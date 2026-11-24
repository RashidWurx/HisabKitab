import 'dart:convert';

import 'package:intl/intl.dart';

/// Shown to the user when a backup or restore cannot continue.
class BackupException implements Exception {
  BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The app version written into backups (keep in step with pubspec.yaml).
const appVersion = '1.0.0';

/// What `manifest.json` inside a backup zip says about the backup.
class BackupManifest {
  const BackupManifest({
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAt,
    required this.deviceName,
    required this.counts,
  });

  final String appVersion;
  final int schemaVersion;
  final DateTime createdAt;
  final String deviceName;

  /// Records per table (for the "what will be replaced" summary).
  final Map<String, int> counts;

  int get transactionCount => counts['transactions'] ?? 0;

  String toJson() => const JsonEncoder.withIndent('  ').convert({
    'app': 'hisaab',
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
    'createdAt': createdAt.toIso8601String(),
    'deviceName': deviceName,
    'counts': counts,
  });

  factory BackupManifest.fromJson(String source) {
    try {
      final map = jsonDecode(source) as Map<String, dynamic>;
      if (map['app'] != 'hisaab') {
        throw BackupException('This file is not a Hisaab backup.');
      }
      return BackupManifest(
        appVersion: map['appVersion'] as String? ?? '?',
        schemaVersion: map['schemaVersion'] as int,
        createdAt: DateTime.parse(map['createdAt'] as String),
        deviceName: map['deviceName'] as String? ?? 'Unknown device',
        counts: {
          for (final e in (map['counts'] as Map<String, dynamic>).entries)
            e.key: e.value as int,
        },
      );
    } on BackupException {
      rethrow;
    } catch (_) {
      throw BackupException('The backup is damaged (unreadable manifest).');
    }
  }
}

/// `hisaab_backup_2026-11-25_0930.zip`
String backupFileName(DateTime when) =>
    'hisaab_backup_${DateFormat('yyyy-MM-dd_HHmm').format(when)}.zip';

/// Reads the time back out of a backup file name (null if it does not match).
DateTime? backupTimeFromName(String name) {
  final m = RegExp(
    r'hisaab_backup_(\d{4})-(\d{2})-(\d{2})_(\d{2})(\d{2})\.zip',
  ).firstMatch(name);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
  );
}

/// How many cloud backups are kept; older ones are deleted.
const cloudBackupsToKeep = 10;

/// Which backups to delete so that only the newest [keep] stay.
List<T> backupsToDelete<T>(
  List<T> all,
  DateTime Function(T) createdAt, {
  int keep = cloudBackupsToKeep,
}) {
  final sorted = [...all]..sort((a, b) => createdAt(b).compareTo(createdAt(a)));
  return sorted.length <= keep ? <T>[] : sorted.sublist(keep);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
