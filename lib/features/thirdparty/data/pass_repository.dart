import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/seed.dart';
import '../../../core/utils/money.dart';
import '../../ledger/data/ledger_service.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction_models.dart';
import '../domain/pass_models.dart';

/// Everything needed to create (or edit) a 3rd party record.
class PassDraft {
  const PassDraft({
    this.id,
    required this.fromPersonId,
    required this.forPersonId,
    required this.amount,
    required this.date,
    required this.throughMe,
    this.accountId,
    this.handedOver = true,
    this.collectBy,
    this.returnBy,
    this.note,
  });

  final String? id;

  /// Who lent the money.
  final String fromPersonId;

  /// Who it was borrowed for.
  final String forPersonId;
  final int amount;
  final DateTime date;

  /// True: it came into [accountId]. False: it went straight between them.
  final bool throughMe;
  final String? accountId;

  /// Through me only: it has already been given on.
  final bool handedOver;
  final DateTime? collectBy;
  final DateTime? returnBy;
  final String? note;
}

const _originKinds = {PassEntryKind.takenIn, PassEntryKind.lentDirect};

/// 3rd party money. Movements through an account are real transactions
/// (`passIn` / `passOut`), so balances stay right, but they are never income,
/// expense or the user's own dues.
class PassRepository {
  PassRepository(this._db) : _txs = TransactionRepository(_db);

  final AppDatabase _db;
  final TransactionRepository _txs;
  static const _uuid = Uuid();

  // ---- reading -------------------------------------------------------------

  /// Every record with its history, newest record first.
  Stream<List<PassView>> watchViews() => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.passThroughs,
          _db.passEntries,
          _db.transactions,
          _db.accounts,
        },
      )
      .watch()
      .asyncMap((_) => views());

  Future<List<PassView>> views() async {
    final passes = await (_db.select(
      _db.passThroughs,
    )..orderBy([(p) => OrderingTerm.desc(p.startDate)])).get();
    final entries =
        await (_db.select(_db.passEntries)..orderBy([
              (e) => OrderingTerm.desc(e.date),
              (e) => OrderingTerm.desc(e.createdAt),
            ]))
            .get();
    final held = await _db.customSelect('''
SELECT e.pass_id AS pass_id,
       SUM(CASE WHEN t.type = 'passIn' THEN t.amount ELSE -t.amount END) AS held
  FROM pass_entries e
  JOIN transactions t ON t.id = e.transaction_id
  JOIN accounts a ON a.id = t.account_id
 WHERE a.include_in_total = 1
 GROUP BY e.pass_id
''').get();
    final heldBy = {
      for (final r in held) r.read<String>('pass_id'): r.read<int>('held'),
    };
    return [
      for (final p in passes)
        PassView(
          pass: p,
          entries: [
            for (final e in entries)
              if (e.passId == p.id) e,
          ],
          heldInTotal: heldBy[p.id] ?? 0,
        ),
    ];
  }

  Future<PassView?> view(String id) async =>
      (await views()).where((v) => v.pass.id == id).firstOrNull;

  /// The record a `passIn` / `passOut` transaction belongs to.
  Future<String?> passIdForTransaction(String transactionId) async {
    final e =
        await (_db.select(_db.passEntries)
              ..where((x) => x.transactionId.equals(transactionId)))
            .getSingleOrNull();
    return e?.passId;
  }

  // ---- writing -------------------------------------------------------------

  void _validate(PassDraft d) {
    if (d.amount <= 0) throw LedgerException('Amount must be above 0.');
    if (d.fromPersonId == d.forPersonId) {
      throw LedgerException('Choose two different people.');
    }
    if (d.throughMe && d.accountId == null) {
      throw LedgerException('Choose the account it came into.');
    }
  }

  Future<String> create(PassDraft d) async {
    _validate(d);
    final id = d.id ?? _uuid.v4();
    await _db.transaction(() async {
      await _db
          .into(_db.passThroughs)
          .insert(
            PassThroughsCompanion.insert(
              id: id,
              fromPersonId: d.fromPersonId,
              forPersonId: d.forPersonId,
              amount: d.amount,
              startDate: d.date,
              collectBy: Value(d.collectBy),
              returnBy: Value(d.returnBy),
              note: Value(_clean(d.note)),
              createdAt: DateTime.now(),
            ),
          );
      await _writeOrigin(id, d);
    });
    return id;
  }

  Future<void> _writeOrigin(String id, PassDraft d) async {
    if (!d.throughMe) {
      await _insertEntry(id, PassEntryKind.lentDirect, d.amount, d.date);
      return;
    }
    await _move(id, PassEntryKind.takenIn, d.amount, d.accountId!, d.date);
    if (d.handedOver) {
      await _move(id, PassEntryKind.givenOut, d.amount, d.accountId!, d.date);
    }
  }

  /// Edits a record. People, dates to remember and note can always change. The
  /// amount, date and path can change only before a later step is recorded;
  /// the first entries are then written again.
  Future<void> update(PassDraft d) async {
    _validate(d);
    final id = d.id!;
    await _db.transaction(() async {
      final old = await view(id);
      if (old == null) throw LedgerException('This record no longer exists.');
      if (!old.isRewritable && d.amount != old.amount) {
        throw LedgerException(
          'The amount cannot change after later steps are recorded.',
        );
      }
      var rewrite = false;
      if (old.isRewritable) {
        String? oldAccount;
        for (final e in old.entries) {
          if (e.kind != PassEntryKind.takenIn) continue;
          oldAccount = (await _txs.get(e.transactionId!))?.accountId;
        }
        rewrite =
            d.amount != old.amount ||
            d.date != old.pass.startDate ||
            d.throughMe != old.startedThroughMe ||
            (d.throughMe &&
                (d.handedOver != (old.toHandOver == 0) ||
                    d.accountId != oldAccount));
      }
      await (_db.update(
        _db.passThroughs,
      )..where((p) => p.id.equals(id))).write(
        PassThroughsCompanion(
          fromPersonId: Value(d.fromPersonId),
          forPersonId: Value(d.forPersonId),
          amount: Value(d.amount),
          startDate: Value(old.isRewritable ? d.date : old.pass.startDate),
          collectBy: Value(d.collectBy),
          returnBy: Value(d.returnBy),
          note: Value(_clean(d.note)),
        ),
      );
      if (rewrite) {
        await _deleteEntries(old.entries);
        await _writeOrigin(id, d);
      } else {
        // Keep the account history pointing at the right people.
        for (final e in old.entries) {
          if (e.transactionId == null) continue;
          final t = await _txs.get(e.transactionId!);
          if (t == null) continue;
          await _txs.save(
            TransactionInput(
              id: t.id,
              type: t.type,
              amount: t.amount,
              accountId: t.accountId,
              personId: _personFor(e.kind, d.fromPersonId, d.forPersonId),
              date: t.date,
              note: await _label(d.fromPersonId, d.forPersonId),
              createdAt: t.createdAt,
              allocations: t.allocations,
            ),
          );
        }
      }
    });
  }

  /// Records the next step of a record. [accountId] is required unless the
  /// money went straight between the two people.
  Future<void> record(
    String passId,
    PassAction action, {
    required int amount,
    String? accountId,
    DateTime? date,
    String? note,
  }) => _db.transaction(() async {
    if (amount <= 0) throw LedgerException('Amount must be above 0.');
    final v = await view(passId);
    if (v == null) throw LedgerException('This record no longer exists.');
    final max = v.maxFor(action);
    if (max == 0) {
      throw LedgerException(
        v.toHandOver > 0 && action == PassAction.payBack
            ? 'Record handing the money over first.'
            : 'There is nothing left to record here.',
      );
    }
    if (amount > max) {
      throw LedgerException('The most you can record is ${Money.format(max)}.');
    }
    final at = date ?? DateTime.now();
    if (action == PassAction.direct) {
      await _insertEntry(
        passId,
        PassEntryKind.returnedDirect,
        amount,
        at,
        note: note,
      );
      return;
    }
    if (accountId == null) throw LedgerException('Choose an account.');
    await _move(
      passId,
      switch (action) {
        PassAction.handOver => PassEntryKind.givenOut,
        PassAction.collect => PassEntryKind.collected,
        _ => PassEntryKind.repaid,
      },
      amount,
      accountId,
      at,
      note: note,
    );
  });

  /// Removes one step (to fix a mistake). The first step cannot be removed;
  /// delete the whole record instead.
  Future<void> deleteEntry(String entryId) => _db.transaction(() async {
    final e = await (_db.select(
      _db.passEntries,
    )..where((x) => x.id.equals(entryId))).getSingleOrNull();
    if (e == null) return;
    if (_originKinds.contains(e.kind)) {
      throw LedgerException(
        'This is the start of the record. Delete the whole record instead.',
      );
    }
    await _deleteEntries([e]);
    final v = (await view(e.passId))!;
    final returnedEarly = v.toHandOver > 0 && v.toPayBack < v.amount;
    if (v.toCollect < 0 || returnedEarly) {
      throw LedgerException('Delete the later entries first.');
    }
  });

  /// Deletes the record, its history and its account movements.
  Future<void> delete(String passId) => _db.transaction(() async {
    final entries = await (_db.select(
      _db.passEntries,
    )..where((e) => e.passId.equals(passId))).get();
    await _deleteEntries(entries);
    await (_db.delete(
      _db.passThroughs,
    )..where((p) => p.id.equals(passId))).go();
    await (_db.delete(
      _db.notificationLog,
    )..where((l) => l.payload.equals('pass:$passId'))).go();
  });

  // ---- helpers -------------------------------------------------------------

  static String? _clean(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<void> _deleteEntries(List<PassEntry> entries) async {
    for (final e in entries) {
      await (_db.delete(_db.passEntries)..where((x) => x.id.equals(e.id))).go();
      if (e.transactionId != null) await _txs.delete(e.transactionId!);
    }
  }

  Future<void> _insertEntry(
    String passId,
    PassEntryKind kind,
    int amount,
    DateTime date, {
    String? transactionId,
    String? note,
  }) => _db
      .into(_db.passEntries)
      .insert(
        PassEntriesCompanion.insert(
          id: _uuid.v4(),
          passId: passId,
          kind: kind,
          amount: amount,
          date: date,
          transactionId: Value(transactionId),
          note: Value(_clean(note)),
          createdAt: DateTime.now(),
        ),
      );

  static String _personFor(PassEntryKind kind, String from, String forId) =>
      kind == PassEntryKind.takenIn || kind == PassEntryKind.repaid
      ? from
      : forId;

  Future<String> _label(String fromId, String forId) async {
    Future<String> name(String id) async =>
        (await (_db.select(
          _db.people,
        )..where((p) => p.id.equals(id))).getSingleOrNull())?.name ??
        '?';
    return 'From ${await name(fromId)} for ${await name(forId)}';
  }

  /// A movement through an account: the transaction and its history entry.
  Future<void> _move(
    String passId,
    PassEntryKind kind,
    int amount,
    String accountId,
    DateTime date, {
    String? note,
  }) async {
    final pass = await (_db.select(
      _db.passThroughs,
    )..where((p) => p.id.equals(passId))).getSingle();
    final incoming =
        kind == PassEntryKind.takenIn || kind == PassEntryKind.collected;
    final txId = await _txs.save(
      TransactionInput(
        type: incoming ? TransactionType.passIn : TransactionType.passOut,
        amount: amount,
        accountId: accountId,
        personId: _personFor(kind, pass.fromPersonId, pass.forPersonId),
        date: date,
        note: await _label(pass.fromPersonId, pass.forPersonId),
        allocations: await _allocations(passId, accountId, amount, incoming),
      ),
    );
    await _insertEntry(
      passId,
      kind,
      amount,
      date,
      transactionId: txId,
      note: note,
    );
  }

  /// Which source tags the money. Their money comes in as "Other money" and
  /// leaves from it. When the user's own money covers a payment it comes from
  /// a real source, and goes back to that source once collected.
  Future<List<AllocationInput>> _allocations(
    String passId,
    String accountId,
    int amount,
    bool incoming,
  ) async {
    final rows = await _db
        .customSelect(
          '''
SELECT a.source_id AS source_id,
       SUM(CASE WHEN t.type = 'passIn' THEN a.amount ELSE -a.amount END) AS net
  FROM pass_entries e
  JOIN transactions t ON t.id = e.transaction_id
  JOIN transaction_allocations a ON a.transaction_id = t.id
 WHERE e.pass_id = ? GROUP BY a.source_id
''',
          variables: [Variable(passId)],
        )
        .get();
    // Positive: their money still sitting in that source. Negative: the
    // user's own money from that source has been used.
    final net = {
      for (final r in rows) r.read<String>('source_id'): r.read<int>('net'),
    };
    final out = <String, int>{};
    var left = amount;
    void take(String source, int upTo) {
      final n = upTo < left ? upTo : left;
      if (n <= 0) return;
      out[source] = (out[source] ?? 0) + n;
      left -= n;
    }

    if (incoming) {
      final owed = net.entries.where((e) => e.value < 0).toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      for (final e in owed) {
        take(e.key, -e.value);
      }
      take(otherMoneySourceId, left);
    } else {
      final balances = LedgerService.sourcesInAccount(
        await LedgerService(_db).sourceBalances(),
        accountId,
      );
      // First their money that is in this account.
      for (final e in net.entries) {
        final here = balances[e.key] ?? 0;
        if (e.value <= 0 || here <= 0) continue;
        take(e.key, e.value < here ? e.value : here);
      }
      // Then the user's own, from whichever sources hold the most here.
      final own = balances.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in own) {
        take(e.key, e.value - (out[e.key] ?? 0));
      }
      // Not enough in the account: the rest goes below zero.
      take(otherMoneySourceId, left);
    }
    return [for (final e in out.entries) AllocationInput(e.key, e.value)];
  }
}
