import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// The single app database. Closed when the provider is disposed.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});
