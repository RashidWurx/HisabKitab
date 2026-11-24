import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../../core/ui/widgets.dart';
import '../../transactions/data/transaction_repository.dart';
import '../domain/due_models.dart';
import 'due_widgets.dart';

/// "Extend date": moves the current due date (the original is kept forever).
/// Returns true if the date was extended.
Future<bool> showExtendSheet(
  BuildContext context,
  WidgetRef ref,
  DueView view,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ExtendSheet(view: view),
  );
  return saved ?? false;
}

class _ExtendSheet extends ConsumerStatefulWidget {
  const _ExtendSheet({required this.view});

  final DueView view;

  @override
  ConsumerState<_ExtendSheet> createState() => _ExtendSheetState();
}

class _ExtendSheetState extends ConsumerState<_ExtendSheet> {
  final _reason = TextEditingController();
  late DateTime _newDate = _suggest();
  bool _customReminder = false;
  DateTime? _reminderAt;
  bool _saving = false;

  /// A week after the current date, but never today or earlier.
  DateTime _suggest() {
    final today = dateOnly(DateTime.now());
    final plusWeek = dateOnly(widget.view.due.currentDueDate).add(
      const Duration(days: 7),
    );
    final tomorrow = today.add(const Duration(days: 1));
    return plusWeek.isAfter(today) ? plusWeek : tomorrow;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickReminder() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _reminderAt ?? _newDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null) return;
    setState(
      () => _reminderAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(dueRepositoryProvider)
          .extend(
            widget.view.due.id,
            newDate: _newDate,
            reason: _reason.text,
            reminderAt: _customReminder ? _reminderAt : null,
          );
      if (mounted) Navigator.pop(context, true);
    } on LedgerException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.view.due;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Extend date',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context, false),
                ),
              ],
            ),
            InfoRow('Original due date', formatDateShort(d.originalDueDate)),
            InfoRow('Current due date', formatDateShort(d.currentDueDate)),
            const SizedBox(height: 8),
            PickerField(
              label: 'New date',
              leading: const Icon(Icons.calendar_today_outlined),
              value: formatDate(_newDate),
              onTap: () async {
                final today = dateOnly(DateTime.now());
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _newDate,
                  firstDate: today.add(const Duration(days: 1)),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _newDate = picked);
              },
            ),
            const SizedBox(height: 14),
            const Text(
              'Reason (optional)',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _reason,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Why is it late? e.g. invoice is still in processing',
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Reminder',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('1 day before & on date'),
                ),
                ButtonSegment(value: true, label: Text('Custom')),
              ],
              selected: {_customReminder},
              onSelectionChanged: (s) async {
                setState(() => _customReminder = s.first);
                if (s.first && _reminderAt == null) await _pickReminder();
              },
            ),
            if (_customReminder)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: PickerField(
                  label: '',
                  leading: const Icon(Icons.notifications_none),
                  value: _reminderAt == null ? null : formatDateTime(_reminderAt!),
                  placeholder: 'Choose date and time',
                  onTap: _pickReminder,
                ),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('Save new date'),
            ),
          ],
        ),
      ),
    );
  }
}
