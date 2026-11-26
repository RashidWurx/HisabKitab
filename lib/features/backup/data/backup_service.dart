import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../domain/backup_models.dart';

/// The database file name inside a backup zip.
const _dbEntry = 'hisaab.sqlite';
const _manifestEntry = 'manifest.json';

/// What a restore would do, shown to the user before they confirm.
class RestorePreview {
  const RestorePreview({required this.manifest, required this.sizeBytes});
  final BackupManifest manifest;
  final int sizeBytes;
}

/// Creates and restores backup zips (a clean copy of the SQLite file made
/// with `VACUUM INTO`, plus `manifest.json`). Cloud upload is separate.
class BackupService {
  BackupService({this.deviceName = 'This device'});

  final String deviceName;

  static const _tables = [
    'income_sources',
    'accounts',
    'account_opening_allocations',
    'categories',
    'people',
    'dues',
    'pass_throughs',
    'pass_entries',
    'subscriptions',
    'transactions',
    'transaction_allocations',
    'due_events',
    'custom_reminders',
  ];

  /// How many rows each table has.
  Future<Map<String, int>> recordCounts(AppDatabase db) async {
    final counts = <String, int>{};
    for (final t in _tables) {
      final row = await db.customSelect('SELECT COUNT(*) AS c FROM $t').getSingle();
      counts[t] = row.read<int>('c');
    }
    return counts;
  }

  /// Writes `hisaab_backup_YYYY-MM-DD_HHmm.zip` into [outDir] and returns it.
  Future<File> createBackup(
    AppDatabase db,
    Directory outDir, {
    DateTime? now,
  }) async {
    final when = now ?? DateTime.now();
    await outDir.create(recursive: true);
    final tmp = await Directory.systemTemp.createTemp('hisaab_backup_');
    try {
      final copy = File(p.join(tmp.path, _dbEntry));
      // VACUUM INTO writes a compact, consistent copy even while the app runs.
      final escaped = copy.path.replaceAll("'", "''");
      await db.customStatement("VACUUM INTO '$escaped'");
      final manifest = BackupManifest(
        appVersion: appVersion,
        schemaVersion: db.schemaVersion,
        createdAt: when,
        deviceName: deviceName,
        counts: await recordCounts(db),
      );
      final archive = Archive()
        ..addFile(ArchiveFile.bytes(_manifestEntry, utf8.encode(manifest.toJson())))
        ..addFile(ArchiveFile.bytes(_dbEntry, await copy.readAsBytes()));
      final zipBytes = ZipEncoder().encode(archive);
      final zip = File(p.join(outDir.path, backupFileName(when)));
      await zip.writeAsBytes(zipBytes);
      return zip;
    } finally {
      await tmp.delete(recursive: true);
    }
  }

  /// Opens a backup zip and checks it. Throws [BackupException] with a clear
  /// message if it is damaged, not a Hisaab backup, or from a NEWER app.
  Future<RestorePreview> inspect(File zip, {required int currentSchemaVersion}) async {
    final archive = await _readArchive(zip);
    final manifestFile = archive.findFile(_manifestEntry);
    final dbFile = archive.findFile(_dbEntry);
    if (manifestFile == null || dbFile == null) {
      throw BackupException('This file is not a complete Hisaab backup.');
    }
    final manifest = BackupManifest.fromJson(
      utf8.decode(manifestFile.content as List<int>),
    );
    if (manifest.schemaVersion > currentSchemaVersion) {
      throw BackupException(
        'This backup was made by a newer version of Hisaab (data version ${manifest.schemaVersion}). Update the app, then try again.',
      );
    }
    final bytes = dbFile.content as List<int>;
    // A SQLite file starts with this 16-byte header.
    const header = 'SQLite format 3\u0000';
    if (bytes.length < 100 || utf8.decode(bytes.sublist(0, 16), allowMalformed: true) != header) {
      throw BackupException('The backup is damaged (the data file is unreadable).');
    }
    return RestorePreview(manifest: manifest, sizeBytes: await zip.length());
  }

  Future<Archive> _readArchive(File zip) async {
    try {
      return ZipDecoder().decodeBytes(await zip.readAsBytes());
    } on FileSystemException {
      throw BackupException('The backup file could not be read.');
    } catch (_) {
      throw BackupException('The backup is damaged (it is not a valid zip file).');
    }
  }

  /// Swaps the database file for the one in [zip]. The app database MUST be
  /// closed first. The old file is kept as `.before_restore` until the new
  /// one is in place, so a failure never leaves the user without data.
  /// When the app reopens the file, Drift migrates it if it is from an older
  /// data version.
  Future<void> restoreInto(File zip, File databaseFile, {required int currentSchemaVersion}) async {
    await inspect(zip, currentSchemaVersion: currentSchemaVersion);
    final archive = await _readArchive(zip);
    final bytes = archive.findFile(_dbEntry)!.content as List<int>;
    final backupOfOld = File('${databaseFile.path}.before_restore');
    if (await databaseFile.exists()) {
      await databaseFile.copy(backupOfOld.path);
    }
    try {
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final f = File('${databaseFile.path}$suffix');
        if (await f.exists()) await f.delete();
      }
      await databaseFile.parent.create(recursive: true);
      await databaseFile.writeAsBytes(bytes, flush: true);
      if (await backupOfOld.exists()) await backupOfOld.delete();
    } catch (e) {
      if (await backupOfOld.exists()) {
        await backupOfOld.copy(databaseFile.path);
      }
      throw BackupException('Not enough storage or permission to restore. Nothing was changed.');
    }
  }
}
