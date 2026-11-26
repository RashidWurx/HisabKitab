import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hisaab/core/database/app_database.dart';
import 'package:hisaab/core/database/enums.dart';
import 'package:hisaab/features/accounts/data/account_repository.dart';
import 'package:hisaab/features/home/data/dashboard_service.dart';
import 'package:hisaab/features/ledger/data/ledger_service.dart';
import 'package:hisaab/features/notifications/domain/notification_models.dart';
import 'package:hisaab/features/reminders/data/reminder_repository.dart';
import 'package:hisaab/features/transactions/data/transaction_repository.dart';
import 'package:hisaab/features/transactions/domain/transaction_models.dart';

const rs = 100;

void main() {
  late AppDatabase db;
  late ReminderRepository reminders;
  late String bank;
  final due = DateTime(2026, 12, 23, 9);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    reminders = ReminderRepository(db);
    bank = await AccountRepository(db).save(
      const AccountDraft(
        name: 'Bank',
        type: AccountType.bank,
        openingBalance: 20000 * rs,
        colorValue: 1,
        iconKey: 'bank',
      ),
    );
  });
  tearDown(() => db.close());

  Future<String> plan({
    DateTime? at,
    ReminderRepeat repeat = ReminderRepeat.none,
  }) => reminders.save(
    ReminderDraft(
      title: 'Siblings',
      amount: 5000 * rs,
      categoryId: 'cat_exp_rent',
      accountId: bank,
      remindAt: at ?? due,
      repeat: repeat,
    ),
  );

  TransactionInput expense(DateTime date) => TransactionInput(
    type: TransactionType.expense,
    amount: 5000 * rs,
    accountId: bank,
    categoryId: 'cat_exp_rent',
    date: date,
    allocations: [AllocationInput('other_money', 5000 * rs)],
  );

  Future<int> balance() async => LedgerService.accountTotals(
    await LedgerService(db).sourceBalances(),
  )[bank]!;

  List<PlannedReminder> notifications(
    List<CustomReminder> list,
    DateTime now,
  ) => planReminders(
    PlanInput(
      now: now,
      prefs: NotificationPrefs.defaults,
      reminders: list,
    ),
  );

  test('planning a payment takes no money until it is paid', () async {
    final id = await plan();

    expect(await balance(), 20000 * rs);
    expect(await db.select(db.transactions).get(), isEmpty);

    await reminders.recordPaid(
      id,
      occurrence: due,
      expense: expense(due),
      now: due,
    );

    expect(await balance(), 15000 * rs);
    expect((await reminders.get(id))!.isActive, isFalse);
  });

  test('the same payment cannot be recorded twice', () async {
    final id = await plan();
    await reminders.recordPaid(id, occurrence: due, expense: expense(due));

    await expectLater(
      reminders.recordPaid(id, occurrence: due, expense: expense(due)),
      throwsA(isA<LedgerException>()),
    );
    expect(await balance(), 15000 * rs);
  });

  test('a repeating payment moves on only when paid', () async {
    final id = await plan(repeat: ReminderRepeat.monthly);

    // Long overdue: it must not slide to the next month by itself.
    await reminders.rollForward(now: DateTime(2027, 2, 1));
    expect((await reminders.get(id))!.remindAt, due);
    expect((await reminders.get(id))!.isUnpaid(DateTime(2027, 2, 1)), isTrue);

    await reminders.recordPaid(id, occurrence: due, expense: expense(due));
    final after = (await reminders.get(id))!;
    expect(after.remindAt, DateTime(2027, 1, 23, 9));
    expect(after.isActive, isTrue);

    // A stale form for the old date cannot pay the new one.
    await expectLater(
      reminders.recordPaid(id, occurrence: due, expense: expense(due)),
      throwsA(isA<LedgerException>()),
    );
  });

  test('a failed expense leaves the payment unpaid', () async {
    final id = await plan();

    await expectLater(
      reminders.recordPaid(
        id,
        occurrence: due,
        expense: TransactionInput(
          type: TransactionType.expense,
          amount: 5000 * rs,
          accountId: bank,
          categoryId: 'cat_exp_rent',
          date: due,
          allocations: const [], // does not add up to the amount
        ),
      ),
      throwsA(isA<LedgerException>()),
    );
    expect((await reminders.get(id))!.isActive, isTrue);
  });

  test('asks on the date and keeps asking until paid', () async {
    await plan();
    final list = await db.select(db.customReminders).get();

    final before = notifications(list, DateTime(2026, 12, 1));
    expect(before.first.at, due);
    expect(before.first.payload, startsWith('pay:'));
    expect(before.first.body, contains('Have you paid?'));

    // Two days late and still unpaid.
    final late = notifications(list, DateTime(2026, 12, 25, 12));
    expect(late, isNotEmpty);
    expect(late.first.at, DateTime(2026, 12, 26, 9));
    expect(late.first.body, contains('was due on 23 Dec'));
  });

  test('a repeating payment left unpaid for cycles keeps asking', () async {
    await plan(repeat: ReminderRepeat.monthly);
    var list = await db.select(db.customReminders).get();
    final months = notifications(list, DateTime(2027, 3, 1, 12));
    expect(months.where((r) => r.payload.startsWith('pay:')), isNotEmpty);
    expect(months.first.at, DateTime(2027, 3, 2, 9));

    await db.delete(db.customReminders).go();
    await plan(repeat: ReminderRepeat.daily);
    list = await db.select(db.customReminders).get();
    expect(notifications(list, DateTime(2026, 12, 27, 12)), isNotEmpty);
  });

  test('an unpaid payment stays in Upcoming', () async {
    await plan();
    final items = await DashboardService(
      db,
    ).watchUpcoming(now: DateTime(2027, 1, 20)).first;

    expect(items.single.kind, UpcomingKind.payment);
    expect(items.single.amount, 5000 * rs);
  });

  test('paying fills in the expense and links it back', () async {
    final id = await plan();
    final route = Uri.parse(expenseRouteFor((await reminders.get(id))!));

    expect(route.path, '/transaction/new/expense');
    expect(route.queryParameters['amount'], '${5000 * rs}');
    expect(route.queryParameters['reminder'], id);
    expect(route.queryParameters['occurrence'], '${due.millisecondsSinceEpoch}');
    expect(route.queryParameters['note'], 'Siblings');
  });
}
