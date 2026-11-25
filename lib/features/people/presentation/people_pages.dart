import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers.dart';
import '../../../core/ui/manager_list.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../accounts/data/account_repository.dart';
import '../../dues/domain/due_models.dart';
import '../../dues/presentation/due_widgets.dart';
import '../../transactions/data/transaction_repository.dart';
import '../data/person_repository.dart';

class PeoplePage extends ConsumerWidget {
  const PeoplePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(peopleProvider).value ?? const <PeopleData>[];
    final views = ref.watch(dueViewsProvider).value ?? const <DueView>[];
    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/people/new'),
        child: const Icon(Icons.add),
      ),
      body: ManagedList(
        items: [
          for (final p in people)
            () {
              final net = personNet(views, p.id);
              return ManagedItem(
                id: p.id,
                title: p.name,
                subtitle: net == 0
                    ? (p.phone ?? 'All settled')
                    : (net > 0 ? 'Owes you' : 'You owe'),
                iconKey: 'people',
                color: const Color(0xFF2A4E76),
                archived: p.isArchived,
                trailing: net == 0
                    ? null
                    : MoneyText(
                        net,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              );
            }(),
        ],
        emptyTitle: 'No people yet',
        emptyMessage:
            'Add the people you lend to, borrow from, or expect money from.',
        addLabel: 'Add person',
        onAdd: () => context.push('/people/new'),
        onOpen: (id) => context.push('/people/$id'),
        onReorder: ref.read(personRepositoryProvider).reorder,
        onAction: (id, action) async {
          final repo = ref.read(personRepositoryProvider);
          switch (action) {
            case ManagedAction.edit:
              context.push('/people/$id/edit');
            case ManagedAction.archive:
              await repo.setArchived(id, true);
            case ManagedAction.unarchive:
              await repo.setArchived(id, false);
            case ManagedAction.delete:
              final ok = await confirmDialog(
                context,
                title: 'Delete person?',
                message: 'This cannot be undone.',
                confirmLabel: 'Delete',
                destructive: true,
              );
              if (!ok) return;
              try {
                await repo.delete(id);
              } on BlockedDeleteException catch (e) {
                if (!context.mounted) return;
                final archive = await confirmDialog(
                  context,
                  title: 'Cannot delete',
                  message: e.message,
                  confirmLabel: 'Archive',
                );
                if (archive) await repo.setArchived(id, true);
              }
          }
        },
      ),
    );
  }
}

class PersonFormPage extends ConsumerStatefulWidget {
  const PersonFormPage({super.key, this.personId});

  final String? personId;

  @override
  ConsumerState<PersonFormPage> createState() => _PersonFormPageState();
}

class _PersonFormPageState extends ConsumerState<PersonFormPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  String? _accountId;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.personId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _load();
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final p = await ref.read(personRepositoryProvider).get(widget.personId!);
    if (p == null || !mounted) return;
    setState(() {
      _name.text = p.name;
      _phone.text = p.phone ?? '';
      _note.text = p.note ?? '';
      _accountId = p.defaultAccountId;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(personRepositoryProvider)
          .save(
            PersonDraft(
              id: widget.personId,
              name: _name.text,
              phone: _phone.text,
              note: _note.text,
              defaultAccountId: _accountId,
            ),
          );
      if (mounted) context.pop();
    } on LedgerException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit person' : 'New person')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: 16),
          PickerField(
            label: 'Default account for receiving money (optional)',
            value: account?.name,
            placeholder: 'None',
            onTap: () async {
              final r = await pickAccount(
                context,
                ref,
                selectedId: _accountId,
                allowNone: true,
              );
              if (r != null) setState(() => _accountId = r.value);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_isEdit ? 'Save changes' : 'Add person'),
          ),
        ],
      ),
    );
  }
}

/// Everything about one person: what they owe, what you owe, net, track
/// record and the full history of dues.
class PersonDetailPage extends ConsumerWidget {
  const PersonDetailPage({super.key, required this.personId});

  final String personId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final person = (ref.watch(peopleProvider).value ?? const <PeopleData>[])
        .where((p) => p.id == personId)
        .firstOrNull;
    if (person == null) {
      return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    }
    final all = ref.watch(dueViewsProvider).value ?? const <DueView>[];
    final mine = all.where((v) => v.due.personId == personId).toList();
    final people = {person.id: person};
    final sources = {
      for (final s in ref.watch(sourcesProvider).value ?? const <IncomeSource>[])
        s.id: s,
    };
    final owesYou = mine
        .where((v) => v.isOpen && v.isReceivable)
        .fold<int>(0, (s, v) => s + v.remaining);
    final youOwe = mine
        .where((v) => v.isOpen && !v.isReceivable)
        .fold<int>(0, (s, v) => s + v.remaining);
    final net = personNet(all, personId);
    final record = trackRecordFor(mine);
    final open = sortDues(mine.where((v) => v.isOpen));
    final closed = sortDues(mine.where((v) => !v.isOpen)).reversed;

    Widget tile(DueView v) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DueTile(
        view: v,
        people: people,
        sources: sources,
        onTap: () => context.push('/dues/${v.due.id}'),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => context.push('/people/$personId/edit'),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Row(
            children: [
              const IconBox(iconKey: 'people', size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (person.phone != null) Text(person.phone!),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                InfoRow(
                  'They owe you',
                  null,
                  valueWidget: MoneyText(
                    owesYou,
                    neutral: owesYou == 0,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                const Divider(),
                InfoRow(
                  'You owe them',
                  null,
                  valueWidget: MoneyText(
                    -youOwe,
                    neutral: youOwe == 0,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                const Divider(),
                InfoRow(
                  'Net',
                  null,
                  valueWidget: MoneyText(
                    net,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => context.push('/dues/new/lent?person=$personId'),
                  child: const Text('Lend'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      context.push('/dues/new/borrowed?person=$personId'),
                  child: const Text('Borrow'),
                ),
              ),
            ],
          ),
          const SectionTitle('Track record'),
          TrackRecordCard(record: record),
          if (open.isNotEmpty) ...[
            const SectionTitle('Open'),
            for (final v in open) tile(v),
          ],
          const SectionTitle('History'),
          if (closed.isEmpty)
            const InlineEmpty(Icons.history, 'Settled and cancelled dues will show here.')
          else
            for (final v in closed) tile(v),
        ],
      ),
    );
  }
}

/// "Paid on time vs late" summary for a person or a source.
class TrackRecordCard extends StatelessWidget {
  const TrackRecordCard({super.key, required this.record});

  final TrackRecord record;

  @override
  Widget build(BuildContext context) {
    if (record.total == 0) {
      return const AppCard(child: Text('No settled dues yet.'));
    }
    final days = record.averageDaysLate;
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: _cell(context, 'On time', '${record.onTime}',
                statusColor(context, DueStatus.settled)),
          ),
          Expanded(
            child: _cell(context, 'Late', '${record.late}',
                statusColor(context, DueStatus.overdue)),
          ),
          Expanded(
            child: _cell(
              context,
              'Avg days late',
              record.late == 0 ? '-' : days.toStringAsFixed(days % 1 == 0 ? 0 : 1),
              null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, String label, String value, Color? color) =>
      Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      );
}
