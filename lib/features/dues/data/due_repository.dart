import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../../core/database/seed.dart';
import '../../../core/utils/money.dart';
import '../../ledger/data/ledger_service.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/allocation_logic.dart';
import '../../transactions/domain/transaction_models.dart';
import '../domain/due_models.dart';

/// Everything needed to create or edit a due.
class DueDraft {
  const DueDraft({
    this.id,
    required this.title,
    required this.kind,
    this.personId,
    this.sourceId,
    required this.totalAmount,
    required this.accountId,
    required this.dueDate,
    this.reminderAt,
    this.reminderRepeatDays,
    this.note,
    this.allocations,
    this.transactionDate,
    this.periodKey,
  });

  final String? id;
  final String title;
  final DueKind kind;
  final String? personId;
  final String? sourceId;
  final int totalAmount;
  final String accountId;
  final DateTime dueDate;
  final DateTime? reminderAt;
  final int? reminderRepeatDays;
  final String? note;

  /// Whose money is lent (lent) or where borrowed money is tagged (borrowed).
  /// Null = automatic.
  final List<AllocationInput>? allocations;

  /// Date of the lend_out / borrow_in transaction (default today).
  final DateTime? transactionDate;
  final String? periodKey;
}

const _paymentTypes = [
  TransactionType.income,
  TransactionType.repayIn,
  TransactionType.repayOut,
];

class DueRepository {
  DueRepository(this._db) : _txs = TransactionRepository(_db);

  final AppDatabase _db;
  final TransactionRepository _txs;
  static const _uuid = Uuid();

  // ---- reading -------------------------------------------------------------

  static const _viewSql = '''
SELECT d.*, COALESCE(p.paid, 0) AS paid_total, p.last_date AS last_date,
       COALESCE(e.ext, 0) AS ext_count
  FROM dues d
  LEFT JOIN (SELECT due_id, SUM(amount) AS paid, MAX(date) AS last_date
               FROM transactions
              WHERE due_id IS NOT NULL
                AND type IN ('income','repayIn','repayOut')
              GROUP BY due_id) p ON p.due_id = d.id
  LEFT JOIN (SELECT due_id, COUNT(*) AS ext FROM due_events
              WHERE type = 'extended' GROUP BY due_id) e ON e.due_id = d.id
''';

  DueView _viewOf(QueryRow r, DateTime now) {
    final lastRaw = r.readNullable<int>('last_date');
    return DueView.build(
      due: _db.dues.map(r.data),
      paid: r.read<int>('paid_total'),
      extensionCount: r.read<int>('ext_count'),
      lastPaymentAt: lastRaw == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastRaw * 1000),
      now: now,
    );
  }

  Set<TableInfo> get _viewTables => {_db.dues, _db.transactions, _db.dueEvents};

  Stream<List<DueView>> watchViews() => _db
      .customSelect(_viewSql, readsFrom: _viewTables)
      .watch()
      .map((rows) {
        final now = DateTime.now();
        return [for (final r in rows) _viewOf(r, now)];
      });

  Future<DueView?> getView(String id) async {
    final rows = await _db
        .customSelect(
          '$_viewSql WHERE d.id = ?',
          variables: [Variable(id)],
          readsFrom: _viewTables,
        )
        .get();
    return rows.isEmpty ? null : _viewOf(rows.first, DateTime.now());
  }

  Stream<DueView?> watchView(String id) => _db
      .customSelect(
        '$_viewSql WHERE d.id = ?',
        variables: [Variable(id)],
        readsFrom: _viewTables,
      )
      .watch()
      .map((rows) => rows.isEmpty ? null : _viewOf(rows.first, DateTime.now()));

  /// History, newest first (ties: the later event on top).
  Stream<List<DueEvent>> watchEvents(String dueId) => _db
      .customSelect(
        'SELECT * FROM due_events WHERE due_id = ? ORDER BY at DESC, rowid DESC',
        variables: [Variable(dueId)],
        readsFrom: {_db.dueEvents},
      )
      .watch()
      .map((rows) => [for (final r in rows) _db.dueEvents.map(r.data)]);

  Stream<List<Transaction>> watchPayments(String dueId) =>
      (_db.select(_db.transactions)
            ..where(
              (t) => t.dueId.equals(dueId) & t.type.isInValues(_paymentTypes),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.date)]))
          .watch();

  // ---- events --------------------------------------------------------------

  Future<void> _event(
    String dueId,
    DueEventType type, {
    int? amount,
    String? accountId,
    String? transactionId,
    DateTime? oldDate,
    DateTime? newDate,
    String? reason,
    String? note,
  }) => _db
      .into(_db.dueEvents)
      .insert(
        DueEventsCompanion.insert(
          id: _uuid.v4(),
          dueId: dueId,
          type: type,
          at: DateTime.now(),
          amount: Value(amount),
          accountId: Value(accountId),
          transactionId: Value(transactionId),
          oldDate: Value(oldDate),
          newDate: Value(newDate),
          reason: Value(reason),
          note: Value(note),
        ),
      );

  // ---- create / edit -------------------------------------------------------

  Future<List<AllocationInput>> _autoAllocations(
    String accountId,
    int amount,
    DueKind kind,
  ) async {
    if (kind == DueKind.borrowed) {
      return [AllocationInput(otherMoneySourceId, amount)];
    }
    final balances = await LedgerService(_db).sourceBalances();
    final account = await (_db.select(
      _db.accounts,
    )..where((a) => a.id.equals(accountId))).getSingleOrNull();
    final source = autoPickSource(
      balancesInAccount: LedgerService.sourcesInAccount(balances, accountId),
      accountDefaultSourceId: account?.defaultSpendingSourceId,
      fallbackSourceId: otherMoneySourceId,
    );
    return [AllocationInput(source, amount)];
  }

  void _validate(DueDraft d) {
    if (d.title.trim().isEmpty) throw LedgerException('Enter a title.');
    if (d.totalAmount <= 0) throw LedgerException('Amount must be above 0.');
    if (d.kind != DueKind.expectedIncome && d.personId == null) {
      throw LedgerException('Choose a person.');
    }
  }

  /// Creates a due. Lent / borrowed dues also record the matching
  /// lend_out / borrow_in transaction, all in one database transaction.
  Future<String> create(DueDraft d) async {
    _validate(d);
    final id = d.id ?? _uuid.v4();
    final allocations =
        d.allocations ??
        (d.kind == DueKind.expectedIncome
            ? const <AllocationInput>[]
            : await _autoAllocations(d.accountId, d.totalAmount, d.kind));
    await _db.transaction(() async {
      final due = dateOnly(d.dueDate);
      await _db
          .into(_db.dues)
          .insert(
            DuesCompanion.insert(
              id: id,
              title: d.title.trim(),
              kind: d.kind,
              totalAmount: d.totalAmount,
              accountId: d.accountId,
              originalDueDate: due,
              currentDueDate: due,
              createdAt: DateTime.now(),
              personId: Value(d.personId),
              sourceId: Value(d.sourceId),
              reminderAt: Value(d.reminderAt),
              reminderRepeatDays: Value(d.reminderRepeatDays),
              note: Value(d.note),
              periodKey: Value(d.periodKey),
            ),
          );
      if (d.kind != DueKind.expectedIncome) {
        await _txs.save(
          TransactionInput(
            type: d.kind == DueKind.lent
                ? TransactionType.lendOut
                : TransactionType.borrowIn,
            amount: d.totalAmount,
            accountId: d.accountId,
            personId: d.personId,
            dueId: id,
            date: d.transactionDate ?? DateTime.now(),
            note: d.title.trim(),
            allocations: allocations,
          ),
        );
      }
      await _event(id, DueEventType.created, amount: d.totalAmount);
    });
    return id;
  }

  /// Edits a due's details. Changing the amount (or account) of a lent /
  /// borrowed due keeps its creation transaction in sync.
  Future<void> update(DueDraft d) async {
    _validate(d);
    final id = d.id!;
    await _db.transaction(() async {
      final old = await (_db.select(
        _db.dues,
      )..where((x) => x.id.equals(id))).getSingle();
      await (_db.update(_db.dues)..where((x) => x.id.equals(id))).write(
        DuesCompanion(
          title: Value(d.title.trim()),
          personId: Value(d.personId),
          sourceId: Value(d.sourceId),
          totalAmount: Value(d.totalAmount),
          accountId: Value(d.accountId),
          reminderAt: Value(d.reminderAt),
          reminderRepeatDays: Value(d.reminderRepeatDays),
          note: Value(d.note),
        ),
      );
      if (old.kind != DueKind.expectedIncome &&
          (old.totalAmount != d.totalAmount || old.accountId != d.accountId)) {
        final creation = await _creationTx(id);
        if (creation != null) {
          await _txs.save(
            creation.copyWith(
              amount: d.totalAmount,
              accountId: d.accountId,
              allocations: _scale(creation.allocations, d.totalAmount),
            ),
          );
        }
      }
      if (old.totalAmount != d.totalAmount) {
        await _event(
          id,
          DueEventType.amountEdited,
          amount: d.totalAmount,
          note:
              'Amount changed from ${Money.format(old.totalAmount)} to ${Money.format(d.totalAmount)}',
        );
      }
    });
  }

  Future<TransactionInput?> _creationTx(String dueId) async {
    final row =
        await (_db.select(_db.transactions)..where(
              (t) =>
                  t.dueId.equals(dueId) &
                  t.type.isInValues([
                    TransactionType.lendOut,
                    TransactionType.borrowIn,
                  ]),
            ))
            .getSingleOrNull();
    return row == null ? null : _txs.get(row.id);
  }

  /// Re-scales allocations to a new total (last one takes the rounding).
  static List<AllocationInput> _scale(
    List<AllocationInput> allocations,
    int newTotal,
  ) {
    final oldTotal = allocations.fold<int>(0, (s, a) => s + a.amount);
    if (allocations.length == 1 || oldTotal == 0) {
      return [AllocationInput(allocations.first.sourceId, newTotal)];
    }
    var used = 0;
    final out = <AllocationInput>[];
    for (var i = 0; i < allocations.length; i++) {
      final isLast = i == allocations.length - 1;
      final amount = isLast
          ? newTotal - used
          : (allocations[i].amount * newTotal ~/ oldTotal);
      used += amount;
      if (amount > 0) out.add(AllocationInput(allocations[i].sourceId, amount));
    }
    return out;
  }

  // ---- payments ------------------------------------------------------------

  /// Whose money is paid back when a lent due is repaid: the sources the
  /// lent money came from, in proportion to what is still outstanding.
  Future<List<AllocationInput>> _repayInAllocations(
    String dueId,
    int amount,
  ) async {
    final rows = await _db
        .customSelect(
          '''
SELECT a.source_id AS source_id,
  SUM(CASE WHEN t.type = 'lendOut' THEN a.amount
           WHEN t.type = 'repayIn' THEN -a.amount ELSE 0 END) AS outstanding
  FROM transaction_allocations a
  JOIN transactions t ON t.id = a.transaction_id
 WHERE t.due_id = ? GROUP BY a.source_id
''',
          variables: [Variable(dueId)],
          readsFrom: {_db.transactions, _db.transactionAllocations},
        )
        .get();
    final outstanding =
        [
          for (final r in rows)
            if (r.read<int>('outstanding') > 0)
              (r.read<String>('source_id'), r.read<int>('outstanding')),
        ]..sort((a, b) => b.$2.compareTo(a.$2));
    var left = amount;
    final out = <AllocationInput>[];
    for (final (source, owed) in outstanding) {
      if (left <= 0) break;
      final take = owed < left ? owed : left;
      out.add(AllocationInput(source, take));
      left -= take;
    }
    if (left > 0) out.add(AllocationInput(otherMoneySourceId, left));
    return out;
  }

  /// Records a payment received (expected income / lent) or made (borrowed).
  /// Partial payments are fine. Paying more than what remains needs
  /// [allowOverpay] (the UI asks the user to confirm).
  Future<String> recordPayment(
    String dueId, {
    required int amount,
    required String accountId,
    DateTime? date,
    List<AllocationInput>? allocations,
    bool allowOverpay = false,
  }) async {
    if (amount <= 0) throw LedgerException('Amount must be above 0.');
    final view = await getView(dueId);
    if (view == null) throw LedgerException('This due no longer exists.');
    if (view.status == DueStatus.cancelled) {
      throw LedgerException('This due was cancelled.');
    }
    if (amount > view.remaining && !allowOverpay) {
      throw LedgerException(
        'That is more than the ${Money.format(view.remaining)} remaining.',
      );
    }
    final due = view.due;
    final type = switch (due.kind) {
      DueKind.expectedIncome => TransactionType.income,
      DueKind.lent => TransactionType.repayIn,
      DueKind.borrowed => TransactionType.repayOut,
    };
    final alloc =
        allocations ??
        switch (due.kind) {
          DueKind.expectedIncome => [
            AllocationInput(due.sourceId ?? otherMoneySourceId, amount),
          ],
          DueKind.lent => await _repayInAllocations(dueId, amount),
          DueKind.borrowed => await _autoAllocations(
            accountId,
            amount,
            DueKind.lent, // pick from money the account actually holds
          ),
        };
    late String txId;
    await _db.transaction(() async {
      txId = await _txs.save(
        TransactionInput(
          type: type,
          amount: amount,
          accountId: accountId,
          personId: due.personId,
          dueId: dueId,
          date: date ?? DateTime.now(),
          note: due.title,
          allocations: alloc,
        ),
      );
      await _event(
        dueId,
        DueEventType.payment,
        amount: amount,
        accountId: accountId,
        transactionId: txId,
      );
      if (amount >= view.remaining) {
        await _event(dueId, DueEventType.settled);
      }
    });
    return txId;
  }

  /// Changes the amount of a recorded payment (history gets an entry).
  Future<void> editPayment(
    String txId, {
    required int amount,
    DateTime? date,
    String? accountId,
  }) async {
    if (amount <= 0) throw LedgerException('Amount must be above 0.');
    await _db.transaction(() async {
      final t = await _txs.get(txId);
      if (t == null || t.dueId == null) {
        throw LedgerException('Payment not found.');
      }
      await _txs.save(
        t.copyWith(
          amount: amount,
          date: date,
          accountId: accountId,
          allocations: _scale(t.allocations, amount),
        ),
      );
      await _event(
        t.dueId!,
        DueEventType.paymentEdited,
        amount: amount,
        accountId: accountId ?? t.accountId,
        transactionId: txId,
        note: 'Payment changed from ${Money.format(t.amount)} to ${Money.format(amount)}',
      );
    });
  }

  Future<void> deletePayment(String txId) async {
    await _db.transaction(() async {
      final t = await _txs.get(txId);
      if (t == null || t.dueId == null) return;
      // History keeps its entries; only the link to the deleted row is cut.
      await (_db.update(_db.dueEvents)
            ..where((e) => e.transactionId.equals(txId)))
          .write(const DueEventsCompanion(transactionId: Value(null)));
      await _txs.delete(txId);
      await _event(
        t.dueId!,
        DueEventType.paymentDeleted,
        amount: t.amount,
        accountId: t.accountId,
        note: 'Payment of ${Money.format(t.amount)} removed',
      );
    });
  }

  // ---- date, notes, reminder, cancel --------------------------------------

  /// Moves the current due date. The original date is kept forever.
  /// The new date must be after today. Unlimited extensions.
  Future<void> extend(
    String dueId, {
    required DateTime newDate,
    String? reason,
    DateTime? reminderAt,
    DateTime? now,
  }) async {
    final today = dateOnly(now ?? DateTime.now());
    final target = dateOnly(newDate);
    if (!target.isAfter(today)) {
      throw LedgerException('The new date must be after today.');
    }
    await _db.transaction(() async {
      final due = await (_db.select(
        _db.dues,
      )..where((d) => d.id.equals(dueId))).getSingle();
      if (due.cancelledAt != null) {
        throw LedgerException('This due was cancelled.');
      }
      await (_db.update(_db.dues)..where((d) => d.id.equals(dueId))).write(
        DuesCompanion(
          currentDueDate: Value(target),
          reminderAt: Value(reminderAt),
        ),
      );
      await _event(
        dueId,
        DueEventType.extended,
        oldDate: due.currentDueDate,
        newDate: target,
        reason: (reason == null || reason.trim().isEmpty) ? null : reason.trim(),
      );
    });
  }

  Future<void> addNote(String dueId, String note) async {
    if (note.trim().isEmpty) throw LedgerException('Write a note first.');
    await _event(dueId, DueEventType.note, note: note.trim());
  }

  /// Notes are the only history entries that can be edited (marked edited).
  Future<void> editNote(String eventId, String note) async {
    if (note.trim().isEmpty) throw LedgerException('Write a note first.');
    final e = await (_db.select(
      _db.dueEvents,
    )..where((x) => x.id.equals(eventId))).getSingle();
    if (e.type != DueEventType.note) {
      throw LedgerException('Only notes can be edited.');
    }
    await (_db.update(_db.dueEvents)..where((x) => x.id.equals(eventId))).write(
      DueEventsCompanion(
        note: Value(note.trim()),
        editedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Pushes the reminder to [until] (a one-off override).
  Future<void> snooze(String dueId, DateTime until) async {
    await _db.transaction(() async {
      await (_db.update(_db.dues)..where((d) => d.id.equals(dueId))).write(
        DuesCompanion(reminderAt: Value(until)),
      );
      await _event(
        dueId,
        DueEventType.reminderChanged,
        newDate: until,
        note: 'Reminder snoozed',
      );
    });
  }

  Future<void> setReminder(
    String dueId, {
    DateTime? reminderAt,
    int? repeatEveryDays,
  }) async {
    await _db.transaction(() async {
      await (_db.update(_db.dues)..where((d) => d.id.equals(dueId))).write(
        DuesCompanion(
          reminderAt: Value(reminderAt),
          reminderRepeatDays: Value(repeatEveryDays),
        ),
      );
      await _event(
        dueId,
        DueEventType.reminderChanged,
        newDate: reminderAt,
        note: reminderAt == null ? 'Reminder reset to default' : 'Reminder changed',
      );
    });
  }

  /// Closes the due. With [writeOff] the remaining amount is written off.
  Future<void> cancel(String dueId, {required bool writeOff}) async {
    final view = await getView(dueId);
    if (view == null) return;
    await _db.transaction(() async {
      final off = writeOff ? view.remaining : 0;
      await (_db.update(_db.dues)..where((d) => d.id.equals(dueId))).write(
        DuesCompanion(
          cancelledAt: Value(DateTime.now()),
          writtenOffAmount: Value(view.due.writtenOffAmount + off),
        ),
      );
      await _event(
        dueId,
        DueEventType.cancelled,
        amount: off == 0 ? null : off,
        note: off == 0
            ? 'Cancelled'
            : 'Cancelled, ${Money.format(off)} written off',
      );
    });
  }

  /// Deletes a due together with its history and every transaction linked to
  /// it (so balances change). The UI asks for confirmation first.
  Future<void> delete(String dueId) async {
    await _db.transaction(() async {
      final linked = await (_db.select(
        _db.transactions,
      )..where((t) => t.dueId.equals(dueId))).get();
      await (_db.delete(
        _db.dueEvents,
      )..where((e) => e.dueId.equals(dueId))).go();
      for (final t in linked) {
        await _txs.delete(t.id);
      }
      await (_db.delete(_db.dues)..where((d) => d.id.equals(dueId))).go();
    });
  }
}
