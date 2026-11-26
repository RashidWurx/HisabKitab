import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/ledger/data/ledger_service.dart';
import '../database/app_database.dart';
import '../database/enums.dart';
import '../theme/app_theme.dart';
import '../providers.dart';
import '../utils/money.dart';
import 'icon_registry.dart';
import 'widgets.dart';

class PickerItem<T> {
  const PickerItem({
    required this.value,
    required this.title,
    this.subtitle,
    this.iconKey,
    this.color,
    this.trailing,
    this.inactive = false,
  });

  final T value;
  final String title;
  final String? subtitle;
  final String? iconKey;
  final Color? color;
  final Widget? trailing;

  /// Inactive items are hidden unless "Show inactive" is switched on.
  final bool inactive;
}

/// Result wrapper so "None" can be told apart from "dismissed".
class PickResult<T> {
  const PickResult(this.value);
  final T? value;
}

/// Bottom sheet list picker. Returns null if dismissed, or a [PickResult]
/// (whose value is null when "None" was chosen).
Future<PickResult<T>?> showItemPicker<T>(
  BuildContext context, {
  required String title,
  required List<PickerItem<T>> items,
  T? selected,
  String? noneLabel,
}) {
  return showModalBottomSheet<PickResult<T>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      var showInactive = false;
      return StatefulBuilder(
        builder: (ctx, setState) {
          final hasInactive = items.any((i) => i.inactive);
          final visible = items
              .where((i) => !i.inactive || showInactive || i.value == selected)
              .toList();
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (noneLabel != null)
                        ListTile(
                          leading: const Icon(Icons.block),
                          title: Text(noneLabel),
                          onTap: () =>
                              Navigator.pop(ctx, PickResult<T>(null)),
                        ),
                      for (final item in visible)
                        ListTile(
                          leading: item.iconKey == null
                              ? null
                              : IconBox(
                                  iconKey: item.iconKey!,
                                  color: item.color,
                                  size: 40,
                                ),
                          title: Text(
                            item.inactive ? '${item.title} (inactive)' : item.title,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: item.subtitle == null
                              ? null
                              : Text(item.subtitle!),
                          trailing: item.value == selected
                              ? const Icon(Icons.check)
                              : item.trailing,
                          onTap: () =>
                              Navigator.pop(ctx, PickResult<T>(item.value)),
                        ),
                      if (hasInactive)
                        SwitchListTile(
                          title: const Text('Show inactive'),
                          value: showInactive,
                          onChanged: (v) => setState(() => showInactive = v),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

/// Pick an account. Archived accounts are never shown; inactive ones are
/// hidden behind "Show inactive".
Future<PickResult<String>?> pickAccount(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
  String? excludeId,
  String title = 'Choose account',
  bool allowNone = false,
}) {
  final accounts = ref.read(accountsProvider).value ?? const <Account>[];
  final balances = LedgerService.accountTotals(
    ref.read(sourceBalancesProvider).value ?? const {},
  );
  return showItemPicker<String>(
    context,
    title: title,
    selected: selectedId,
    noneLabel: allowNone ? 'None' : null,
    items: [
      for (final a in accounts)
        if (!a.isArchived && a.id != excludeId)
          PickerItem(
            value: a.id,
            title: a.name,
            subtitle: Money.format(balances[a.id] ?? 0),
            iconKey: a.iconKey,
            color: Color(a.colorValue),
            inactive: a.status == ActiveStatus.inactive,
          ),
    ],
  );
}

/// Pick a source. [balances] (source id -> paisa) shows money left in the
/// chosen account next to each source.
Future<PickResult<String>?> pickSource(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
  Map<String, int>? balances,
  String title = 'Choose source',
  bool allowNone = false,
  Set<String> exclude = const {},
}) {
  final sources = ref.read(sourcesProvider).value ?? const <IncomeSource>[];
  return showItemPicker<String>(
    context,
    title: title,
    selected: selectedId,
    noneLabel: allowNone ? 'None' : null,
    items: [
      for (final s in sources)
        if (!s.isArchived && !exclude.contains(s.id))
          PickerItem(
            value: s.id,
            title: s.name,
            subtitle: balances == null
                ? null
                : 'Left here: ${Money.format(balances[s.id] ?? 0)}',
            iconKey: s.iconKey,
            color: Color(s.colorValue),
            inactive: s.status == ActiveStatus.inactive,
          ),
    ],
  );
}

Future<PickResult<String>?> pickCategory(
  BuildContext context,
  WidgetRef ref, {
  required CategoryKind kind,
  String? selectedId,
  String? excludeId,
  String title = 'Choose category',
  bool allowNone = false,
}) {
  final cats = ref.read(categoriesProvider).value ?? const <Category>[];
  return showItemPicker<String>(
    context,
    title: title,
    selected: selectedId,
    noneLabel: allowNone ? 'None' : null,
    items: [
      for (final c in cats)
        if (!c.isArchived && c.kind == kind && c.id != excludeId)
          PickerItem(
            value: c.id,
            title: c.name,
            iconKey: c.iconKey,
            color: Color(c.colorValue),
          ),
    ],
  );
}

/// Icon + colour chooser row used by the account/source/category forms.
class IconColorField extends StatelessWidget {
  const IconColorField({
    super.key,
    required this.iconKey,
    required this.colorValue,
    required this.onChanged,
  });

  final String iconKey;
  final int colorValue;
  final void Function(String iconKey, int colorValue) onChanged;

  @override
  Widget build(BuildContext context) {
    return PickerField(
      label: 'Icon and colour',
      leading: IconBox(
        iconKey: iconKey,
        color: Color(colorValue),
        size: 36,
      ),
      value: 'Tap to change',
      onTap: () async {
        final result = await showModalBottomSheet<(String, int)>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _IconColorSheet(iconKey: iconKey, color: colorValue),
        );
        if (result != null) onChanged(result.$1, result.$2);
      },
    );
  }
}

class _IconColorSheet extends StatefulWidget {
  const _IconColorSheet({required this.iconKey, required this.color});

  final String iconKey;
  final int color;

  @override
  State<_IconColorSheet> createState() => _IconColorSheetState();
}

class _IconColorSheetState extends State<_IconColorSheet> {
  late String icon = widget.iconKey;
  late int color = widget.color;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Icon and colour',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in appPalette)
                GestureDetector(
                  onTap: () => setState(() => color = c),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 3,
                        color: color == c
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final entry in appIcons.entries)
                GestureDetector(
                  onTap: () => setState(() => icon = entry.key),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: icon == entry.key
                          ? context.tone(Color(color))
                          : null,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Icon(
                      entry.value,
                      color: icon == entry.key
                          ? context.onAccent
                          : context.tone(Color(color)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.pop(context, (icon, color)),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
