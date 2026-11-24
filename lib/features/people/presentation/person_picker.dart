import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../data/person_repository.dart';

const _newPerson = '__new_person__';

/// Pick a person (or add a new one on the spot). Returns null if dismissed;
/// a [PickResult] with a null value means "None".
Future<PickResult<String>?> pickPerson(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
  bool allowNone = false,
}) async {
  final people = ref.read(peopleProvider).value ?? const <PeopleData>[];
  final result = await showItemPicker<String>(
    context,
    title: 'Choose person',
    selected: selectedId,
    noneLabel: allowNone ? 'None' : null,
    items: [
      const PickerItem(
        value: _newPerson,
        title: 'New person',
        iconKey: 'people',
      ),
      for (final p in people)
        if (!p.isArchived)
          PickerItem(
            value: p.id,
            title: p.name,
            subtitle: p.phone,
            iconKey: 'people',
          ),
    ],
  );
  if (result == null || result.value != _newPerson) return result;
  if (!context.mounted) return null;
  final name = await showTextDialog(context, title: 'New person', hint: 'Name', confirmLabel: 'Add', capitalization: TextCapitalization.words);
  if (name == null || name.trim().isEmpty) return null;
  final id = await ref.read(personRepositoryProvider).save(
    PersonDraft(name: name),
  );
  return PickResult(id);
}
