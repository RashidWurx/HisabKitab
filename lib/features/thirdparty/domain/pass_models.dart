import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../dues/domain/due_models.dart' show dateOnly;

/// "3rd party money": borrowed from one person for another. It passes through
/// (or straight past) the user and is never their income, expense or debt.

/// What the user can record next.
enum PassAction {
  /// Give the money to the person it was borrowed for, from an account.
  handOver,

  /// That person returns money into one of the user's accounts.
  collect,

  /// The user returns money to the lender from an account. If it was not
  /// collected first, the user has covered it from their own money.
  payBack,

  /// That person pays the lender straight; no account is touched.
  direct,
}

/// A record with its history and everything computed from it.
class PassView {
  const PassView({
    required this.pass,
    required this.entries,
    required this.heldInTotal,
  });

  final PassThrough pass;

  /// Newest first.
  final List<PassEntry> entries;

  /// Their money (minus what the user covered) in accounts that count
  /// towards the Home total.
  final int heldInTotal;

  int _sum(Set<PassEntryKind> kinds) => entries
      .where((e) => kinds.contains(e.kind))
      .fold(0, (s, e) => s + e.amount);

  int get amount => pass.amount;

  int get handedOver =>
      _sum({PassEntryKind.givenOut, PassEntryKind.lentDirect});

  /// Taken from the lender but not yet given on.
  int get toHandOver => amount - handedOver;

  /// Still to come back from the person it was borrowed for.
  int get toCollect =>
      handedOver -
      _sum({PassEntryKind.collected, PassEntryKind.returnedDirect});

  /// Still to be returned to the lender.
  int get toPayBack =>
      amount - _sum({PassEntryKind.repaid, PassEntryKind.returnedDirect});

  /// Through the user's accounts: positive = holding their money,
  /// negative = paid from the user's own money.
  int get _through =>
      _sum({PassEntryKind.takenIn, PassEntryKind.collected}) -
      _sum({PassEntryKind.givenOut, PassEntryKind.repaid});

  int get holding => _through > 0 ? _through : 0;
  int get covered => _through < 0 ? -_through : 0;

  /// True when the money went through the user's accounts to begin with.
  bool get startedThroughMe =>
      entries.any((e) => e.kind == PassEntryKind.takenIn);

  /// True while the history holds only what creating the record wrote, so the
  /// amount, date and path can still be corrected. Once a later step has been
  /// recorded, it must not be rewritten.
  bool get isRewritable {
    if (entries.length == 1) {
      return const {
        PassEntryKind.takenIn,
        PassEntryKind.lentDirect,
      }.contains(entries.first.kind);
    }
    if (entries.length != 2 || !startedThroughMe) return false;
    return entries.any(
      (e) =>
          e.kind == PassEntryKind.givenOut &&
          e.amount == amount &&
          e.date == pass.startDate &&
          e.note == null,
    );
  }

  bool get isOpen => toHandOver > 0 || toCollect > 0 || toPayBack > 0;

  /// The most that [action] may record; 0 means it is not available.
  int maxFor(PassAction action) {
    final handed = toHandOver == 0;
    final max = switch (action) {
      PassAction.handOver => toHandOver,
      PassAction.collect => toCollect,
      PassAction.payBack => handed ? toPayBack : 0,
      PassAction.direct => toCollect < toPayBack ? toCollect : toPayBack,
    };
    return max > 0 ? max : 0;
  }

  bool collectOverdue(DateTime now) =>
      toCollect > 0 &&
      pass.collectBy != null &&
      dateOnly(now).isAfter(dateOnly(pass.collectBy!));

  bool payBackOverdue(DateTime now) =>
      toPayBack > 0 &&
      pass.returnBy != null &&
      dateOnly(now).isAfter(dateOnly(pass.returnBy!));
}

/// Totals across all records.
class PassSummary {
  const PassSummary({
    required this.openCount,
    required this.toCollect,
    required this.toPayBack,
    required this.heldInTotal,
  });

  final int openCount;
  final int toCollect;
  final int toPayBack;

  /// Money inside the Home total's accounts that belongs to others. Money the
  /// user covered is NOT netted off here: their total stays lower until it is
  /// collected.
  final int heldInTotal;

  static const empty = PassSummary(
    openCount: 0,
    toCollect: 0,
    toPayBack: 0,
    heldInTotal: 0,
  );

  factory PassSummary.of(Iterable<PassView> views) {
    var open = 0, collect = 0, back = 0, held = 0;
    for (final v in views) {
      if (v.isOpen) open++;
      collect += v.toCollect;
      back += v.toPayBack;
      if (v.heldInTotal > 0) held += v.heldInTotal;
    }
    return PassSummary(
      openCount: open,
      toCollect: collect,
      toPayBack: back,
      heldInTotal: held,
    );
  }
}
