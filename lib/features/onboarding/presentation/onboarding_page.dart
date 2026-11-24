import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/database/enums.dart';
import '../../../core/providers.dart';
import '../../../core/ui/widgets.dart';
import '../../accounts/data/account_repository.dart';
import '../../notifications/data/notification_coordinator.dart';
import '../../settings/data/settings_repository.dart';
import '../../sources/data/source_repository.dart';
import '../../transactions/data/transaction_repository.dart';

/// Three quick, skippable steps: accounts, income sources, categories.
/// (Notification permission is requested later, in the notifications phase.)
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  int _step = 0;

  // Step 1
  final _accName = TextEditingController();
  final _accBalance = TextEditingController();
  AccountType _accType = AccountType.bank;
  // Step 2
  final _srcName = TextEditingController();
  SourceType _srcType = SourceType.job;
  String? _srcAccountId;
  // Step 3
  final _unselected = <String>{};
  bool _categoriesInit = false;

  @override
  void dispose() {
    _accName.dispose();
    _accBalance.dispose();
    _srcName.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final catRepo = ref.read(categoryRepositoryProvider);
    for (final id in _unselected) {
      await catRepo.setArchived(id, true);
    }
    await ref
        .read(settingsRepositoryProvider)
        .setBool(SettingKeys.onboardingDone, true);
    // Last step: ask for notification permission (Android 13+ / iOS).
    try {
      await ref.read(reminderSchedulerProvider).requestPermission();
      await ref.read(notificationCoordinatorProvider).reschedule();
    } catch (_) {
      // Never block setup on notifications.
    }
    if (mounted) context.go('/home');
  }

  void _next() {
    if (_step == 2) {
      _finish();
    } else {
      setState(() => _step++);
    }
  }

  Future<void> _addAccount() async {
    final balance = _accBalance.text.trim().isEmpty
        ? 0
        : parseAmount(_accBalance.text);
    if (_accName.text.trim().isEmpty || balance == null) {
      showMessage(context, 'Enter a name and a valid balance.');
      return;
    }
    try {
      await ref
          .read(accountRepositoryProvider)
          .save(
            AccountDraft(
              name: _accName.text,
              type: _accType,
              openingBalance: balance,
              colorValue: 0xFF112E4E,
              iconKey: switch (_accType) {
                AccountType.bank => 'bank',
                AccountType.mobileWallet => 'phone',
                AccountType.cash => 'cash',
                AccountType.onlineWallet => 'card',
                AccountType.savings => 'savings',
                AccountType.other => 'wallet',
              },
            ),
          );
      _accName.clear();
      _accBalance.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } on LedgerException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _addSource() async {
    if (_srcName.text.trim().isEmpty) {
      showMessage(context, 'Enter a name.');
      return;
    }
    try {
      await ref
          .read(sourceRepositoryProvider)
          .save(
            SourceDraft(
              name: _srcName.text,
              type: _srcType,
              linkedAccountId: _srcAccountId,
              colorValue: 0xFF2A4E76,
              iconKey: switch (_srcType) {
                SourceType.job => 'work',
                SourceType.freelance => 'laptop',
                SourceType.business => 'store',
                SourceType.other => 'wallet',
              },
            ),
          );
      _srcName.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } on LedgerException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titles = [
      'Your accounts',
      'Your income sources',
      'Your categories',
    ];
    final hints = [
      'Add the places your money sits, with what is in them right now.',
      'Add where your money comes from and which account it lands in.',
      'Keep the categories you will use. You can change these any time.',
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Step ${_step + 1} of 3'),
        actions: [
          TextButton(onPressed: _next, child: const Text('Skip')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(
            titles[_step],
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(hints[_step]),
          const SizedBox(height: 20),
          if (_step == 0) ..._accountsStep(),
          if (_step == 1) ..._sourcesStep(),
          if (_step == 2) ..._categoriesStep(),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _next,
            child: Text(_step == 2 ? 'Get started' : 'Next'),
          ),
        ],
      ),
    );
  }

  List<Widget> _accountsStep() {
    final accounts = ref.watch(accountsProvider).value ?? const [];
    return [
      for (final a in accounts)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: IconBox(iconKey: a.iconKey, size: 40),
          title: Text(a.name),
          trailing: MoneyText(a.openingBalance, neutral: true),
        ),
      const SizedBox(height: 8),
      AppCard(
        child: Column(
          children: [
            TextField(
              controller: _accName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Account name',
                hintText: 'Meezan Bank, JazzCash, Cash',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _accBalance,
              keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: amountFormatters,
              decoration: const InputDecoration(
                labelText: 'Current balance',
                prefixText: 'Rs ',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in AccountType.values)
                  ChoiceChip(
                    label: Text(_accTypeLabel(t)),
                    selected: _accType == t,
                    onSelected: (_) => setState(() => _accType = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addAccount,
              icon: const Icon(Icons.add),
              label: const Text('Add account'),
            ),
          ],
        ),
      ),
    ];
  }

  String _accTypeLabel(AccountType t) => switch (t) {
    AccountType.bank => 'Bank',
    AccountType.mobileWallet => 'Wallet',
    AccountType.cash => 'Cash',
    AccountType.onlineWallet => 'Online',
    AccountType.savings => 'Savings',
    AccountType.other => 'Other',
  };

  List<Widget> _sourcesStep() {
    final sources = ref
        .watch(sourcesProvider)
        .value
        ?.where((s) => !s.isBuiltIn)
        .toList() ?? const [];
    final accounts = ref.watch(accountsProvider).value ?? const [];
    String? accountName() {
      for (final a in accounts) {
        if (a.id == _srcAccountId) return a.name;
      }
      return null;
    }

    return [
      for (final s in sources)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: IconBox(iconKey: s.iconKey, size: 40),
          title: Text(s.name),
          subtitle: Text(
            accounts.where((a) => a.id == s.linkedAccountId).firstOrNull?.name ??
                'No linked account',
          ),
        ),
      const SizedBox(height: 8),
      AppCard(
        child: Column(
          children: [
            TextField(
              controller: _srcName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Source name',
                hintText: 'Job 1, Freelancing',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in SourceType.values)
                  ChoiceChip(
                    label: Text(t.name[0].toUpperCase() + t.name.substring(1)),
                    selected: _srcType == t,
                    onSelected: (_) => setState(() => _srcType = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _srcAccountId,
              decoration: const InputDecoration(labelText: 'Pays into'),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(value: a.id, child: Text(a.name)),
              ],
              onChanged: (v) => setState(() => _srcAccountId = v),
              hint: Text(accountName() ?? 'Choose account'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _addSource,
              icon: const Icon(Icons.add),
              label: const Text('Add source'),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _categoriesStep() {
    final cats = ref.watch(categoriesProvider).value ?? const [];
    if (!_categoriesInit && cats.isNotEmpty) {
      _categoriesInit = true;
      _unselected.addAll(cats.where((c) => c.isArchived).map((c) => c.id));
    }
    Widget group(String title, CategoryKind kind) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in cats.where((c) => c.kind == kind))
              FilterChip(
                label: Text(c.name),
                selected: !_unselected.contains(c.id),
                onSelected: (on) => setState(
                  () => on ? _unselected.remove(c.id) : _unselected.add(c.id),
                ),
              ),
          ],
        ),
      ],
    );
    return [
      group('Expenses', CategoryKind.expense),
      const SizedBox(height: 16),
      group('Income', CategoryKind.income),
    ];
  }
}
