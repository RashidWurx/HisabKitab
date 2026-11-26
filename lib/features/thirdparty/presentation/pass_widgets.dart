import '../../../core/database/app_database.dart';
import '../../../core/database/enums.dart';
import '../domain/pass_models.dart';

/// Wording shared by the 3rd party screens.
class PassNames {
  const PassNames(this.lender, this.receiver);

  final String lender;
  final String receiver;

  factory PassNames.of(PassView v, List<PeopleData> people) {
    String name(String id) =>
        people.where((p) => p.id == id).firstOrNull?.name ?? 'Someone';
    return PassNames(name(v.pass.fromPersonId), name(v.pass.forPersonId));
  }

  String actionLabel(PassAction a) => switch (a) {
    PassAction.handOver => 'Give to $receiver',
    PassAction.collect => '$receiver paid me',
    PassAction.payBack => 'I paid $lender',
    PassAction.direct => '$receiver paid $lender directly',
  };

  String entryLabel(PassEntryKind k) => switch (k) {
    PassEntryKind.takenIn => 'Received from $lender',
    PassEntryKind.givenOut => 'Given to $receiver',
    PassEntryKind.lentDirect => '$lender gave it to $receiver directly',
    PassEntryKind.collected => '$receiver paid me back',
    PassEntryKind.repaid => 'I returned it to $lender',
    PassEntryKind.returnedDirect => '$receiver returned it to $lender directly',
  };
}
