import 'dart:io';

/// One backup stored in the cloud.
class CloudBackup {
  const CloudBackup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.sizeBytes,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final int sizeBytes;
}

/// Where cloud backups go: Google Drive (Android) or iCloud (iPhone).
/// Backups are only ever sent when the user taps "Back up now".
abstract class CloudBackupProvider {
  /// "Google Drive" or "iCloud".
  String get label;

  /// False when the platform setup (OAuth client / iCloud container) is
  /// missing; [setupHint] then explains what to do.
  bool get isConfigured;
  String get setupHint;

  /// Signs in if needed (may show a system dialog). Throws BackupException
  /// with a clear message if it fails or the user cancels.
  Future<void> connect();

  Future<List<CloudBackup>> list();
  Future<CloudBackup> upload(File zip);
  Future<File> download(CloudBackup backup, Directory into);
  Future<void> delete(CloudBackup backup);
  Future<void> disconnect();
}
