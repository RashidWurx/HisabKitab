import 'package:drift/drift.dart';

import 'app_database.dart';
import 'enums.dart';

/// Fixed id of the built-in "Other money" source.
const otherMoneySourceId = 'other_money';

const _expenseSeeds = <(String, String, int)>[
  // name, iconKey, color
  ('Family', 'family', 0xFFE91E63),
  ('Siblings', 'people', 0xFF9C27B0),
  ('Petrol', 'fuel', 0xFFFF5722),
  ('Packages', 'wifi', 0xFF3F51B5),
  ('Food', 'food', 0xFFFF9800),
  ('Bills', 'receipt', 0xFF009688),
  ('Rent', 'home', 0xFF795548),
  ('Shopping', 'shopping', 0xFFE53935),
  ('Health', 'health', 0xFF43A047),
  ('Subscriptions', 'subscriptions', 0xFF5E35B1),
  ('Other', 'category', 0xFF607D8B),
];

const _incomeSeeds = <(String, String, int)>[
  ('Salary', 'work', 0xFF2E7D32),
  ('Freelance', 'laptop', 0xFF00897B),
  ('Sales', 'store', 0xFF1E88E5),
  ('Gift', 'gift', 0xFFD81B60),
  ('Other', 'category', 0xFF607D8B),
];

/// Inserts the built-in source and the starter categories.
/// Runs once, when the database is first created.
Future<void> seedDatabase(AppDatabase db) async {
  await db.batch((b) {
    b.insert(
      db.incomeSources,
      IncomeSourcesCompanion.insert(
        id: otherMoneySourceId,
        name: 'Other money',
        type: const Value(SourceType.other),
        iconKey: const Value('wallet'),
        colorValue: const Value(0xFF607D8B),
        isBuiltIn: const Value(true),
        createdAt: DateTime.now(),
      ),
    );
    var order = 0;
    for (final (name, icon, color) in _expenseSeeds) {
      b.insert(
        db.categories,
        CategoriesCompanion.insert(
          id: 'cat_exp_${name.toLowerCase()}',
          name: name,
          kind: CategoryKind.expense,
          iconKey: Value(icon),
          colorValue: Value(color),
          sortOrder: Value(order++),
        ),
      );
    }
    order = 0;
    for (final (name, icon, color) in _incomeSeeds) {
      b.insert(
        db.categories,
        CategoriesCompanion.insert(
          id: 'cat_inc_${name.toLowerCase()}',
          name: name,
          kind: CategoryKind.income,
          iconKey: Value(icon),
          colorValue: Value(color),
          sortOrder: Value(order++),
        ),
      );
    }
  });
}
