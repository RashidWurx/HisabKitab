import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../domain/backup_models.dart';
import 'cloud_backup.dart';

/// iCloud Drive backups through the app's own iCloud container, using a small
/// Swift plugin (`ios/Runner/ICloudBackupPlugin.swift`). Needs the iCloud
/// capability in Xcode and a paid Apple Developer account (see README).
///
/// Not testable on Android/Windows: the logic runs on a real iPhone.
class ICloudBackupProvider implements CloudBackupProvider {
  static const _channel = MethodChannel('hisaab/icloud');

  @override
  String get label => 'iCloud';

  @override
  bool get isConfigured => Platform.isIOS;

  @override
  String get setupHint =>
      'iCloud backup needs the iCloud capability in Xcode (see README, "iCloud setup") and iCloud turned on for this iPhone.';

  BackupException _friendly(PlatformException e) {
    switch (e.code) {
      case 'unavailable':
        return BackupException(
          'iCloud is not available. Sign in to iCloud in Settings and turn on iCloud Drive.',
        );
      case 'no_space':
        return BackupException('Not enough iCloud storage.');
      default:
        return BackupException('iCloud error: ${e.message ?? e.code}');
    }
  }

  @override
  Future<void> connect() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable');
      if (ok != true) {
        throw BackupException(
          'iCloud is not available. Sign in to iCloud in Settings and turn on iCloud Drive.',
        );
      }
    } on PlatformException catch (e) {
      throw _friendly(e);
    } on MissingPluginException {
      throw BackupException(setupHint);
    }
  }

  @override
  Future<List<CloudBackup>> list() async {
    try {
      final rows =
          await _channel.invokeListMethod<Map<Object?, Object?>>('list') ??
          const [];
      return [
        for (final r in rows)
          CloudBackup(
            id: r['name'] as String,
            name: r['name'] as String,
            createdAt:
                backupTimeFromName(r['name'] as String) ??
                DateTime.fromMillisecondsSinceEpoch(
                  ((r['modified'] as num?) ?? 0).toInt() * 1000,
                ),
            sizeBytes: ((r['size'] as num?) ?? 0).toInt(),
          ),
      ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } on PlatformException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<CloudBackup> upload(File zip) async {
    try {
      await _channel.invokeMethod<void>('upload', {
        'path': zip.path,
        'name': p.basename(zip.path),
      });
      return CloudBackup(
        id: p.basename(zip.path),
        name: p.basename(zip.path),
        createdAt: backupTimeFromName(p.basename(zip.path)) ?? DateTime.now(),
        sizeBytes: await zip.length(),
      );
    } on PlatformException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<File> download(CloudBackup backup, Directory into) async {
    try {
      await into.create(recursive: true);
      final target = p.join(into.path, backup.name);
      await _channel.invokeMethod<void>('download', {
        'name': backup.name,
        'path': target,
      });
      return File(target);
    } on PlatformException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<void> delete(CloudBackup backup) async {
    try {
      await _channel.invokeMethod<void>('delete', {'name': backup.name});
    } on PlatformException catch (e) {
      throw _friendly(e);
    }
  }

  @override
  Future<void> disconnect() async {}
}
