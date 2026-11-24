import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_database.dart';

/// Where the database file lives (`hisaab.sqlite` in the app's documents
/// folder, the same place `drift_flutter` uses by default).
Future<File> hisaabDatabaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, 'hisaab.sqlite'));
}

/// The single app database. Closed when the provider is disposed (this also
/// happens during a restore, which swaps the file and then re-creates it).
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(() {
    // The restore flow may already have closed it.
    db.close().catchError((_) {});
  });
  return db;
});
