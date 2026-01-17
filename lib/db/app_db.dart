import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_db.g.dart';

class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();

  // 日付（その日の0:00として保持）
  DateTimeColumn get date => dateTime()();

  TextColumn get category => text()();

  IntColumn get amount => integer()();

  TextColumn get memo => text().nullable()();

  // 作成時刻（並び順用）
  DateTimeColumn get createdAt => dateTime()();
}

class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  // 表示順（小さいほど上）
  IntColumn get sortOrder => integer()();

  @override
  List<Set<Column>>? get uniqueKeys => [
    {name},
  ];
}

class CategoryTotal {
  final String category;
  final int total;
  const CategoryTotal(this.category, this.total);
}

class DayTotal {
  final DateTime day; // その日の0:00
  final int total;
  const DayTotal(this.day, this.total);
}

@DriftDatabase(tables: [Expenses, Categories])
class AppDb extends _$AppDb {
  AppDb() : super(_openConnection());

  @override
  int get schemaVersion => 2;

  static const List<String> defaultCategoryNames = [
    '食費',
    '日用品',
    '交通',
    '娯楽',
    '医療',
    'その他',
  ];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedDefaultCategoriesIfEmpty();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(categories);
        await _seedDefaultCategoriesIfEmpty();
      }
    },
  );

  Future<void> _seedDefaultCategoriesIfEmpty() async {
    final countRow = await customSelect(
      'SELECT COUNT(*) AS c FROM categories',
      readsFrom: {categories},
    ).getSingle();

    final count = countRow.data['c'] as int? ?? 0;
    if (count > 0) return;

    await batch((b) {
      for (int i = 0; i < defaultCategoryNames.length; i++) {
        b.insert(
          categories,
          CategoriesCompanion.insert(
            name: defaultCategoryNames[i],
            sortOrder: i,
          ),
        );
      }
    });
  }

  // ---- カテゴリ ----
  Stream<List<Category>> watchCategories() {
    final q = select(categories)..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return q.watch();
  }

  Future<void> addCategory(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final maxRow = await customSelect(
      'SELECT COALESCE(MAX(sort_order), -1) AS m FROM categories',
      readsFrom: {categories},
    ).getSingle();
    final maxSort = maxRow.data['m'] as int? ?? -1;

    await into(categories).insert(
      CategoriesCompanion.insert(
        name: trimmed,
        sortOrder: maxSort + 1,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<bool> categoryIsUsed(String name) async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM expenses WHERE category = ?',
      variables: [Variable<String>(name)],
      readsFrom: {expenses},
    ).getSingle();
    final c = row.data['c'] as int? ?? 0;
    return c > 0;
  }

  Future<void> deleteCategoryById(int id) async {
    await (delete(categories)..where((t) => t.id.equals(id))).go();
  }

  Future<void> updateCategoryOrder(List<Category> ordered) async {
    await batch((b) {
      for (int i = 0; i < ordered.length; i++) {
        b.update(
          categories,
          CategoriesCompanion(sortOrder: Value(i)),
          where: (t) => t.id.equals(ordered[i].id),
        );
      }
    });
  }

  // ---- 支出 ----
  Future<int> addExpense({
    required DateTime date,
    required String category,
    required int amount,
    String? memo,
  }) {
    return into(expenses).insert(
      ExpensesCompanion.insert(
        date: DateTime(date.year, date.month, date.day),
        category: category,
        amount: amount,
        memo: Value(memo),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<int> deleteExpenseById(int id) {
    return (delete(expenses)..where((t) => t.id.equals(id))).go();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  // ---- 一覧（月指定）----
  Stream<List<Expense>> watchMonthExpenses(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final nextMonth = (month.month == 12)
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);

    final q = select(expenses)
      ..where((t) =>
      t.date.isBiggerOrEqualValue(start) & t.date.isSmallerThanValue(nextMonth))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);

    return q.watch();
  }

  // ✅ 明細（日指定）←今回追加
  Stream<List<Expense>> watchDayExpenses(DateTime day) {
    final d = _dateOnly(day);
    final q = select(expenses)
      ..where((t) => t.date.equals(d))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return q.watch();
  }

  // ---- 集計（今日） ----
  Stream<int> watchTodayTotal() {
    final today = _dateOnly(DateTime.now());
    final sumExpr = expenses.amount.sum();

    final q = selectOnly(expenses)
      ..addColumns([sumExpr])
      ..where(expenses.date.equals(today));

    return q.watchSingle().map((row) => row.read(sumExpr) ?? 0);
  }

  // ---- 集計（月指定：合計） ----
  Stream<int> watchMonthTotal(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final nextMonth = (month.month == 12)
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);

    final sumExpr = expenses.amount.sum();

    final q = selectOnly(expenses)
      ..addColumns([sumExpr])
      ..where(expenses.date.isBiggerOrEqualValue(start) &
      expenses.date.isSmallerThanValue(nextMonth));

    return q.watchSingle().map((row) => row.read(sumExpr) ?? 0);
  }

  // ---- 集計（月指定：カテゴリ別） ----
  Stream<List<CategoryTotal>> watchMonthCategoryTotals(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final nextMonth = (month.month == 12)
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);

    final totalExpr = expenses.amount.sum();

    final q = selectOnly(expenses)
      ..addColumns([expenses.category, totalExpr])
      ..where(expenses.date.isBiggerOrEqualValue(start) &
      expenses.date.isSmallerThanValue(nextMonth))
      ..groupBy([expenses.category]);

    return q.watch().map((rows) {
      return rows
          .map((r) {
        final cat = r.read(expenses.category)!;
        final total = r.read(totalExpr) ?? 0;
        return CategoryTotal(cat, total);
      })
          .toList()
        ..sort((a, b) => b.total.compareTo(a.total));
    });
  }

  // ---- 集計（月指定：日別合計） ----
  Stream<List<DayTotal>> watchMonthDailyTotals(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final nextMonth = (month.month == 12)
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);

    final sumExpr = expenses.amount.sum();

    final q = selectOnly(expenses)
      ..addColumns([expenses.date, sumExpr])
      ..where(expenses.date.isBiggerOrEqualValue(start) &
      expenses.date.isSmallerThanValue(nextMonth))
      ..groupBy([expenses.date])
      ..orderBy([OrderingTerm.asc(expenses.date)]);

    return q.watch().map((rows) {
      return rows.map((r) {
        final day = r.read(expenses.date)!;
        final total = r.read(sumExpr) ?? 0;
        return DayTotal(day, total);
      }).toList();
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'kakeibo.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
