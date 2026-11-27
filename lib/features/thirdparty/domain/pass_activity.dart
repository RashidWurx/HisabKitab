import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../../transactions/data/transaction_repository.dart';
import 'pass_models.dart';

/// Money that went straight between two people. It uses no account, so it has
/// no transaction, but Activity still has to show it.
class DirectMove {
  const DirectMove({
    required this.passId,
    required this.entry,
    required this.from,
    required this.to,
  });

  final String passId;
  final PassEntry entry;
  final String from;
  final String to;
}

/// The direct moves that [filter] lets through, newest first. Filtering by
/// type, account, source or category leaves them out, as they have none.
List<DirectMove> directMoves(
  Iterable<PassView> views,
  List<PeopleData> people,
  TransactionFilter filter,
) {
  if (filter.types.isNotEmpty ||
      filter.accountId != null ||
      filter.sourceId != null ||
      filter.categoryId != null) {
    return const [];
  }
  String name(String id) =>
      people.where((p) => p.id == id).firstOrNull?.name ?? 'Someone';
  final search = filter.search.trim().toLowerCase();
  final out = <DirectMove>[];
  for (final v in views) {
    final lender = v.pass.fromPersonId;
    final receiver = v.pass.forPersonId;
    if (filter.personId != null &&
        filter.personId != lender &&
        filter.personId != receiver) {
      continue;
    }
    for (final e in v.entries) {
      final lent = e.kind == PassEntryKind.lentDirect;
      if (!lent && e.kind != PassEntryKind.returnedDirect) continue;
      if (filter.from != null && e.date.isBefore(filter.from!)) continue;
      if (filter.to != null && !e.date.isBefore(filter.to!)) continue;
      final move = DirectMove(
        passId: v.pass.id,
        entry: e,
        from: name(lent ? lender : receiver),
        to: name(lent ? receiver : lender),
      );
      final text = '${move.from} ${move.to} ${e.note ?? ''}'.toLowerCase();
      if (search.isNotEmpty && !text.contains(search)) continue;
      out.add(move);
    }
  }
  out.sort((a, b) => b.entry.date.compareTo(a.entry.date));
  return out;
}
