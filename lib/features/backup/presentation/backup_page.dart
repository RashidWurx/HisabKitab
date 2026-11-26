import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/widgets.dart';
import '../application/backup_controller.dart';
import '../data/cloud_backup.dart';
import '../data/backup_service.dart';
import '../domain/backup_models.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  List<CloudBackup>? _cloud;
  String? _cloudError;
  bool _loadingCloud = false;
  bool _working = false;

  BackupController get _c => ref.read(backupControllerProvider);

  @override
  void initState() {
    super.initState();
    if (_c.cloud.isConfigured) _loadCloud();
  }

  Future<void> _loadCloud() async {
    setState(() {
      _loadingCloud = true;
      _cloudError = null;
    });
    try {
      await _c.cloud.connect();
      final list = await _c.cloud.list();
      if (mounted) setState(() => _cloud = list);
    } on BackupException catch (e) {
      if (mounted) setState(() => _cloudError = e.message);
    } finally {
      if (mounted) setState(() => _loadingCloud = false);
    }
  }

  Future<void> _run(Future<void> Function() job, {String? success}) async {
    setState(() => _working = true);
    try {
      await job();
      if (success != null && mounted) showMessage(context, success);
    } on BackupException catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) showMessage(context, 'Something went wrong. Nothing was changed.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _backUpNow() => _run(() async {
    await _c.backUpNow();
    await _loadCloud();
  }, success: 'Backup saved to ${_c.cloud.label}');

  Future<void> _export() => _run(_c.exportFile);

  Future<void> _import() async {
    final file = await _c.pickFile();
    if (file == null || !mounted) return;
    await _confirmAndRestore(file);
  }

  Future<void> _restoreFromCloud(CloudBackup b) async {
    File? file;
    await _run(() async => file = await _c.downloadFromCloud(b));
    if (file != null && mounted) await _confirmAndRestore(file!);
  }

  /// Shows what will be replaced, asks to confirm, then restores.
  Future<void> _confirmAndRestore(File file) async {
    RestorePreview preview;
    try {
      preview = await _c.inspect(file);
    } on BackupException catch (e) {
      if (mounted) showMessage(context, e.message);
      return;
    }
    if (!mounted) return;
    final m = preview.manifest;
    final when = DateFormat('d MMM y, h:mm a').format(m.createdAt);
    final c = m.counts;
    final ok = await confirmDialog(
      context,
      title: 'Replace all data?',
      message:
          'Everything on this phone will be REPLACED by the backup from $when (${m.deviceName}).\n\n'
          'The backup has ${c['accounts'] ?? 0} accounts, ${c['income_sources'] ?? 0} sources, '
          '${m.transactionCount} transactions, ${c['dues'] ?? 0} dues and ${c['subscriptions'] ?? 0} subscriptions.\n\n'
          'Your current data will be lost. This cannot be undone.',
      confirmLabel: 'Replace',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
      () => _c.restore(file),
      success: 'Restored. Your data is back.',
    );
    if (mounted && _c.cloud.isConfigured) await _loadCloud();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value;
    final lastAtRaw = int.tryParse(settings?.raw(BackupKeys.lastAt) ?? '');
    final lastAt = lastAtRaw == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(lastAtRaw);
    final lastSize = int.tryParse(settings?.raw(BackupKeys.lastSize) ?? '') ?? 0;
    final lastTarget = settings?.raw(BackupKeys.lastTarget);
    final cloud = _c.cloud;
    final scheme = Theme.of(context).colorScheme;
    final fmt = DateFormat('d MMM y \'at\' HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.smartphone_outlined, size: 30),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your data stays on this device',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'Backups are only a safety copy.',
                                style: TextStyle(color: scheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    Text(
                      'Last backup',
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      lastAt == null
                          ? 'No backup yet'
                          : '${fmt.format(lastAt)} · ${formatBytes(lastSize)}${lastTarget == null ? '' : ' · $lastTarget'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: context.accentFill,
                  foregroundColor: context.onAccent,
                ),
                onPressed: _working ? null : _backUpNow,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Back up now'),
              ),
              if (!cloud.isConfigured)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    cloud.setupHint,
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ),
              SectionTitle(
                '${cloud.label} backups',
                trailing: IconButton(
                  onPressed: cloud.isConfigured && !_loadingCloud ? _loadCloud : null,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              if (_loadingCloud)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_cloudError != null)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _cloudError!,
                        style: TextStyle(color: context.appColors.negative),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                        onPressed: _loadCloud,
                        child: Text('Connect ${cloud.label}'),
                      ),
                    ],
                  ),
                )
              else if (!cloud.isConfigured)
                const AppCard(child: Text('Not set up yet.'))
              else if (_cloud == null || _cloud!.isEmpty)
                const AppCard(child: Text('No cloud backups yet. Tap "Back up now".'))
              else
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (var i = 0; i < _cloud!.length; i++) ...[
                        if (i > 0) const Divider(),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.cloud_outlined, size: 28),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      DateFormat('d MMM y \'at\' HH:mm').format(_cloud![i].createdAt),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      formatBytes(_cloud![i].sizeBytes),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 40),
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                ),
                                onPressed: _working ? null : () => _restoreFromCloud(_cloud![i]),
                                child: const Text('Restore'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.file_download_outlined),
                      title: const Text(
                        'Export backup file',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('Save or share the backup as a file'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _working ? null : _export,
                    ),
                    const Divider(),
                    ListTile(
                      leading: const Icon(Icons.file_upload_outlined),
                      title: const Text(
                        'Import backup file',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: const Text('Restore from a backup file'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _working ? null : _import,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_working)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
