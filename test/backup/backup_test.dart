import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/backup/data/backup_service.dart';
import 'package:hisaab/features/backup/domain/backup_models.dart';
import 'package:hisaab/features/dues/data/due_repository.dart';
import 'package:hisaab/features/ledger/data/ledger_service.dart';
import 'package:hisaab/features/people/data/person_repository.dart';
import 'package:hisaab/features/sources/data/source_repository.dart';
import 'package:hisaab/features/transactions/data/transaction_repository.dart';
import 'package:hisaab/features/transactions/domain/transaction_models.dart';
import 'package:path/path.dart' as p;

const rs = 100;

void main() {
  late Directory dir;
  late File dbFile;
  late AppDatabase db;
  final service = BackupService(deviceName: 'Test phone');

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('hisaab_test_');
    dbFile = File(p.join(dir.path, 'hisaab.sqlite'));
    db = AppDatabase(NativeDatabase(dbFile));
  });

  tearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    await dir.delete(recursive: true);
  });

  Future<void> fillWithData() async {
    final job = await SourceRepository(db).save(
      const SourceDraft(name: 'Job 1', colorValue: 1, iconKey: 'work'),
    );
    final meezan = await AccountRepository(db).save(
      AccountDraft(
        name: 'Meezan',
        type: AccountType.bank,
        openingBalance: 50000 * rs,
        openingSplit: [AllocationInput(job, 30000 * rs)],
        colorValue: 1,
        iconKey: 'bank',
      ),
    );
    final ali = await PersonRepository(db).save(const PersonDraft(name: 'Ali'));
    final txs = TransactionRepository(db);
    await txs.save(
      TransactionInput(
        type: TransactionType.income,
        amount: 40000 * rs,
        accountId: meezan,
        categoryId: 'cat_inc_salary',
        date: DateTime(2026, 11, 5),
        allocations: [AllocationInput(job, 40000 * rs)],
      ),
    );
    await txs.save(
      TransactionInput(
        type: TransactionType.expense,
        amount: 10000 * rs,
        accountId: meezan,
        categoryId: 'cat_exp_rent',
        date: DateTime(2026, 11, 6),
        allocations: [AllocationInput(job, 10000 * rs)],
      ),
    );
    final dues = DueRepository(db);
    final due = await dues.create(
      DueDraft(
        title: 'Lent to Ali',
        kind: DueKind.lent,
        personId: ali,
        totalAmount: 5000 * rs,
        accountId: meezan,
        dueDate: DateTime(2026, 12, 20),
        allocations: [AllocationInput(job, 5000 * rs)],
      ),
    );
    await dues.recordPayment(due, amount: 2000 * rs, accountId: meezan);
    await dues.extend(due, newDate: DateTime.now().add(const Duration(days: 30)), reason: 'later');
  }

  test('backup, wipe, restore: record counts and balances match', () async {
    await fillWithData();
    final ledger = LedgerService(db);
    final balancesBefore = await ledger.sourceBalances();
    final countsBefore = await service.recordCounts(db);
    expect(countsBefore['transactions'], greaterThan(3));

    final out = Directory(p.join(dir.path, 'out'));
    final zip = await service.createBackup(
      db,
      out,
      now: DateTime(2026, 11, 25, 9, 30),
    );
    expect(p.basename(zip.path), 'hisaab_backup_2026-11-25_0930.zip');

    // Wipe: close and delete the database file entirely.
    await db.close();
    for (final f in dir.listSync()) {
      if (f is File && f.path.contains('hisaab.sqlite')) await f.delete();
    }
    expect(await dbFile.exists(), isFalse);

    // Restore into a fresh app database.
    final preview = await service.inspect(zip, currentSchemaVersion: 3);
    expect(preview.manifest.deviceName, 'Test phone');
    expect(preview.manifest.schemaVersion, 3);
    expect(preview.manifest.counts, countsBefore);

    await service.restoreInto(zip, dbFile, currentSchemaVersion: 3);
    final restored = AppDatabase(NativeDatabase(dbFile));
    addTearDown(restored.close);

    expect(await service.recordCounts(restored), countsBefore);
    final restoredLedger = LedgerService(restored);
    expect(await restoredLedger.sourceBalances(), balancesBefore);
    // History survived too.
    final events = await restored.select(restored.dueEvents).get();
    expect(events.map((e) => e.type), contains(DueEventType.extended));
    // And money still adds up: source balances = account balances.
    final bySource = LedgerService.accountTotals(await restoredLedger.sourceBalances());
    final independent = await restoredLedger.accountBalancesFromTransactions();
    for (final id in independent.keys) {
      expect(bySource[id] ?? 0, independent[id]);
    }
  });

  test('a backup from a NEWER data version is refused with a clear message',
      () async {
    final out = Directory(p.join(dir.path, 'out'));
    final zip = await service.createBackup(db, out);
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    final manifest = jsonDecode(utf8.decode(archive.findFile('manifest.json')!.content as List<int>))
        as Map<String, dynamic>;
    manifest['schemaVersion'] = 99;
    final forged = Archive()
      ..addFile(ArchiveFile.bytes('manifest.json', utf8.encode(jsonEncode(manifest))))
      ..addFile(ArchiveFile.bytes('hisaab.sqlite', archive.findFile('hisaab.sqlite')!.content as List<int>));
    final newer = File(p.join(dir.path, 'newer.zip'))
      ..writeAsBytesSync(ZipEncoder().encode(forged));
    expect(
      () => service.inspect(newer, currentSchemaVersion: 3),
      throwsA(
        isA<BackupException>().having((e) => e.message, 'message', contains('newer version')),
      ),
    );
  });

  test('damaged files give clear errors and never touch the database', () async {
    await fillWithData();
    final before = await service.recordCounts(db);

    final garbage = File(p.join(dir.path, 'garbage.zip'))..writeAsBytesSync([1, 2, 3, 4]);
    expect(
      () => service.inspect(garbage, currentSchemaVersion: 3),
      throwsA(isA<BackupException>()),
    );

    final noManifest = File(p.join(dir.path, 'nomanifest.zip'))
      ..writeAsBytesSync(
        ZipEncoder().encode(Archive()..addFile(ArchiveFile.bytes('other.txt', [1, 2, 3]))),
      );
    expect(
      () => service.inspect(noManifest, currentSchemaVersion: 3),
      throwsA(isA<BackupException>()),
    );

    final badDb = File(p.join(dir.path, 'baddb.zip'))
      ..writeAsBytesSync(
        ZipEncoder().encode(
          Archive()
            ..addFile(
              ArchiveFile.bytes(
                'manifest.json',
                utf8.encode(
                  BackupManifest(
                    appVersion: '1',
                    schemaVersion: 2,
                    createdAt: DateTime(2026),
                    deviceName: 'x',
                    counts: const {},
                  ).toJson(),
                ),
              ),
            )
            ..addFile(ArchiveFile.bytes('hisaab.sqlite', List.filled(200, 7))),
        ),
      );
    expect(
      () => service.restoreInto(badDb, dbFile, currentSchemaVersion: 3),
      throwsA(isA<BackupException>()),
    );
    expect(await service.recordCounts(db), before); // untouched
  });

  group('file names and cleanup', () {
    test('name format and parsing', () {
      final t = DateTime(2026, 11, 25, 9, 5);
      expect(backupFileName(t), 'hisaab_backup_2026-11-25_0905.zip');
      expect(backupTimeFromName('hisaab_backup_2026-11-25_0905.zip'), t);
      expect(backupTimeFromName('photo.zip'), isNull);
    });

    test('keeps the newest 10 and lists older ones for deletion', () {
      final all = [
        for (var i = 0; i < 13; i++) DateTime(2026, 11, 1).add(Duration(days: i)),
      ];
      final doomed = backupsToDelete<DateTime>(all, (d) => d);
      expect(doomed.length, 3);
      expect(doomed.every((d) => d.isBefore(DateTime(2026, 11, 4))), isTrue);
      expect(backupsToDelete<DateTime>(all.take(10).toList(), (d) => d), isEmpty);
    });

    test('byte sizes', () {
      expect(formatBytes(500), '500 B');
      expect(formatBytes(460 * 1024), '460 KB');
      expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
    });
  });
}
