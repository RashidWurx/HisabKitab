import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/ui/pickers.dart';
import '../../../core/ui/widgets.dart';
import '../../transactions/data/transaction_repository.dart';
import '../data/category_repository.dart';

class CategoryFormPage extends ConsumerStatefulWidget {
  const CategoryFormPage({super.key, this.categoryId, this.kind});

  final String? categoryId;
  final CategoryKind? kind;

  @override
  ConsumerState<CategoryFormPage> createState() => _CategoryFormPageState();
}

class _CategoryFormPageState extends ConsumerState<CategoryFormPage> {
  final _name = TextEditingController();
  late CategoryKind _kind = widget.kind ?? CategoryKind.expense;
  String _iconKey = 'category';
  int _color = 0xFF607D8B;
  String? _accountId;
  String? _sourceId;
  bool _loaded = false;
  bool _saving = false;

  bool get _isEdit => widget.categoryId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      _loaded = true;
    }
  }

  void _load() {
    final cats = ref.read(categoriesProvider).value ?? const [];
    for (final c in cats) {
      if (c.id == widget.categoryId) {
        setState(() {
          _name.text = c.name;
          _kind = c.kind;
          _iconKey = c.iconKey;
          _color = c.colorValue;
          _accountId = c.defaultAccountId;
          _sourceId = c.defaultSourceId;
          _loaded = true;
        });
        return;
      }
    }
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(categoryRepositoryProvider)
          .save(
            CategoryDraft(
              id: widget.categoryId,
              name: _name.text,
              kind: _kind,
              colorValue: _color,
              iconKey: _iconKey,
              defaultAccountId: _accountId,
              defaultSourceId: _sourceId,
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
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final sources = ref.watch(sourcesProvider).value ?? const [];
    String? accountName() {
      for (final a in accounts) {
        if (a.id == _accountId) return a.name;
      }
      return null;
    }

    String? sourceName() {
      for (final s in sources) {
        if (s.id == _sourceId) return s.name;
      }
      return null;
    }

    if (!_loaded) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit category' : 'New category'),
      ),
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
          SegmentedButton<CategoryKind>(
            segments: const [
              ButtonSegment(value: CategoryKind.expense, label: Text('Expense')),
              ButtonSegment(value: CategoryKind.income, label: Text('Income')),
            ],
            selected: {_kind},
            onSelectionChanged: _isEdit
                ? null
                : (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          IconColorField(
            iconKey: _iconKey,
            colorValue: _color,
            onChanged: (i, c) => setState(() {
              _iconKey = i;
              _color = c;
            }),
          ),
          if (_kind == CategoryKind.expense) ...[
            const SizedBox(height: 16),
            const Text(
              'When you add an expense in this category, these are picked for you (you can still change them).',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            PickerField(
              label: 'Default account (optional)',
              value: accountName(),
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
            const SizedBox(height: 12),
            PickerField(
              label: 'Default source (optional)',
              value: sourceName(),
              placeholder: 'None',
              onTap: () async {
                final r = await pickSource(
                  context,
                  ref,
                  selectedId: _sourceId,
                  allowNone: true,
                );
                if (r != null) setState(() => _sourceId = r.value);
              },
            ),
          ],
        ],
      ),
      bottomNavigationBar: SaveBar(
        onPressed: _saving ? null : _save,
        label: _isEdit ? 'Save changes' : 'Add category',
      ),
    );
  }
}
