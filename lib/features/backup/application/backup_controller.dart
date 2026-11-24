import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/providers.dart';
import '../../notifications/data/notification_coordinator.dart';
import '../../settings/data/settings_repository.dart';
import '../data/backup_service.dart';
import '../data/cloud_backup.dart';
import '../data/google_drive_backup.dart';
import '../data/icloud_backup.dart';
import '../domain/backup_models.dart';

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    deviceName: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
        .split('\n')
        .first
        .trim(),
  ),
);

/// Google Drive on Android, iCloud on iPhone.
final cloudBackupProvider = Provider<CloudBackupProvider>(
  (ref) => Platform.isIOS ? ICloudBackupProvider() : GoogleDriveBackupProvider(),
);

/// Keys for the "last backup" line.
abstract final class BackupKeys {
  static const lastAt = 'backup.last_at'; // epoch millis
  static const lastSize = 'backup.last_size';
  static const lastTarget = 'backup.last_target';
}

class BackupController {
  BackupController(this._ref);

  final Ref _ref;

  BackupService get _service => _ref.read(backupServiceProvider);
  CloudBackupProvider get cloud => _ref.read(cloudBackupProvider);

  Future<Directory> _workDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'hisaab_backups'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _createZip() async {
    try {
      return await _service.createBackup(
        _ref.read(databaseProvider),
        await _workDir(),
      );
    } on FileSystemException {
      throw BackupException('Not enough storage on this phone to make a backup.');
    }
  }

  Future<void> _recordBackup(File zip, String target) async {
    final settings = _ref.read(settingsRepositoryProvider);
    final now = DateTime.now().millisecondsSinceEpoch;
    await settings.set(BackupKeys.lastAt, '$now');
    await settings.set(BackupKeys.lastSize, '${await zip.length()}');
    await settings.set(BackupKeys.lastTarget, target);
    // A fresh backup restarts the "no backup for N days" reminder.
    await settings.set(SettingKeys.backupAnchor, '$now');
  }

  /// "Back up now": zip, upload to the cloud, keep the latest 10.
  Future<CloudBackup> backUpNow() async {
    final cloud = this.cloud;
    if (!cloud.isConfigured) throw BackupException(cloud.setupHint);
    await cloud.connect();
    final zip = await _createZip();
    try {
      final uploaded = await cloud.upload(zip);
      await _recordBackup(zip, cloud.label);
      await _pruneOld();
      return uploaded;
    } finally {
      if (await zip.exists()) await zip.delete();
    }
  }

  Future<void> _pruneOld() async {
    final all = await cloud.list();
    for (final old in backupsToDelete<CloudBackup>(all, (b) => b.createdAt)) {
      await cloud.delete(old);
    }
  }

  /// "Export backup file": makes a zip and opens the share sheet.
  Future<void> exportFile() async {
    final zip = await _createZip();
    await _recordBackup(zip, 'File');
    await SharePlus.instance.share(
      ShareParams(files: [XFile(zip.path)], subject: p.basename(zip.path)),
    );
  }

  /// "Import backup file": picks a zip. Null if the user cancelled.
  Future<File?> pickFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = picked.isEmpty ? null : picked.first.path;
    return path == null ? null : File(path);
  }

  Future<RestorePreview> inspect(File zip) => _service.inspect(
    zip,
    currentSchemaVersion: _ref.read(databaseProvider).schemaVersion,
  );

  Future<File> downloadFromCloud(CloudBackup backup) async =>
      cloud.download(backup, await _workDir());

  /// Replaces ALL data with the backup. The caller has already asked the
  /// user to confirm. Steps: close the database, swap the file, reopen (Drift
  /// migrates older data), then rebuild reminders.
  Future<void> restore(File zip) async {
    final db = _ref.read(databaseProvider);
    final schema = db.schemaVersion;
    // Check first, while the app still works normally.
    await _service.inspect(zip, currentSchemaVersion: schema);
    final file = await hisaabDatabaseFile();
    await db.close();
    try {
      await _service.restoreInto(zip, file, currentSchemaVersion: schema);
    } finally {
      // Reopen whatever is on disk (the restored file, or the old one if the
      // restore failed and was rolled back).
      _ref.invalidate(databaseProvider);
      await _ref.read(databaseProvider).customSelect('SELECT 1').get();
    }
    await _ref.read(notificationCoordinatorProvider).reschedule();
  }
}

final backupControllerProvider = Provider<BackupController>(
  (ref) => BackupController(ref),
);
