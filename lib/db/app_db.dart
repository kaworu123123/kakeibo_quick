import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class Expense {
  final int id;
  final DateTime date; // date only
  final String category;
  final int amount;
  final String? memo;

  Expense({
    required this.id,
    required this.date,
    required this.category,
    required this.amount,
    required this.memo,
  });
}

class Category {
  final int id;
  final String name;
  final int sortOrder;

  Category({required this.id, required this.name, required this.sortOrder});
}

class CategoryTotal {
  final String category;
  final int total;
  CategoryTotal({required this.category, required this.total});
}

class DayTotal {
  final DateTime day; // date only
  final int total;
  DayTotal({required this.day, required this.total});
}

class MonthTotal {
  final DateTime month; // first day of month
  final int total;
  MonthTotal({required this.month, required this.total});
}

class AppDb {
  Database? _db;
  final StreamController<void> _change = StreamController<void>.broadcast();

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'kakeibo_quick.db');

    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE categories(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            sort_order INTEGER NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE expenses(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            date TEXT NOT NULL,         -- YYYY-MM-DD
            category TEXT NOT NULL,
            amount INTEGER NOT NULL,
            memo TEXT
          );
        ''');

        // 初期カテゴリ
        final init = ['食費', '日用品', '交通', '娯楽', '医療', 'その他'];
        for (int i = 0; i < init.length; i++) {
          await db.insert('categories', {
            'name': init[i],
            'sort_order': i,
          });
        }
      },
    );

    return _db!;
  }

  void _notify() {
    if (!_change.isClosed) _change.add(null);
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<T> _fetch<T>(Future<T> Function(Database db) fn) async {
    final db = await _database;
    return fn(db);
  }

  Stream<T> _watch<T>(Future<T> Function() fetch) async* {
    yield await fetch();
    await for (final _ in _change.stream) {
      yield await fetch();
    }
  }

  /* ===== Categories ===== */

  Stream<List<Category>> watchCategories() => _watch(() async {
    return _fetch((db) async {
      final rows = await db.query('categories', orderBy: 'sort_order ASC, id ASC');
      return rows
          .map((r) => Category(
        id: (r['id'] as int),
        name: (r['name'] as String),
        sortOrder: (r['sort_order'] as int),
      ))
          .toList();
    });
  });

  Future<void> addCategory(String name) async {
    final n = name.trim();
    if (n.isEmpty) return;

    await _fetch((db) async {
      final rows = await db.rawQuery('SELECT MAX(sort_order) as m FROM categories');
      final maxOrder = (rows.first['m'] as int?) ?? -1;
      await db.insert('categories', {'name': n, 'sort_order': maxOrder + 1});
    });

    _notify();
  }

  Future<void> deleteCategoryById(int id) async {
    await _fetch((db) async {
      await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    });
    _notify();
  }

  Future<bool> categoryIsUsed(String categoryName) async {
    return _fetch((db) async {
      final rows = await db.query(
        'expenses',
        columns: ['id'],
        where: 'category = ?',
        whereArgs: [categoryName],
        limit: 1,
      );
      return rows.isNotEmpty;
    });
  }

  Future<void> updateCategoryOrder(List<Category> ordered) async {
    await _fetch((db) async {
      final batch = db.batch();
      for (int i = 0; i < ordered.length; i++) {
        batch.update(
          'categories',
          {'sort_order': i},
          where: 'id = ?',
          whereArgs: [ordered[i].id],
        );
      }
      await batch.commit(noResult: true);
    });
    _notify();
  }

  /* ===== Expenses ===== */

  Future<void> addExpense({
    required DateTime date,
    required String category,
    required int amount,
    String? memo,
  }) async {
    final d = _dateOnly(date);
    await _fetch((db) async {
      await db.insert('expenses', {
        'date': _dateStr(d),
        'category': category,
        'amount': amount,
        'memo': memo,
      });
    });
    _notify();
  }

  Future<void> deleteExpenseById(int id) async {
    await _fetch((db) async {
      await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    });
    _notify();
  }

  Stream<List<Expense>> watchMonthExpenses(DateTime month) => _watch(() async {
    final start = DateTime(month.year, month.month, 1);
    final end = (month.month == 12)
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);

    return _fetch((db) async {
      final rows = await db.query(
        'expenses',
        where: 'date >= ? AND date < ?',
        whereArgs: [_dateStr(start), _dateStr(end)],
        orderBy: 'date DESC, id DESC',
      );
      return rows.map(_rowToExpense).toList();
    });
  });

  Stream<List<Expense>> watchDayExpenses(DateTime day) => _watch(() async {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));

    return _fetch((db) async {
      final rows = await db.query(
        'expenses',
        where: 'date >= ? AND date < ?',
        whereArgs: [_dateStr(start), _dateStr(end)],
        orderBy: 'id DESC',
      );
      return rows.map(_rowToExpense).toList();
    });
  });

  Expense _rowToExpense(Map<String, Object?> r) {
    final ds = (r['date'] as String);
    final parts = ds.split('-');
    final d = DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
    return Expense(
      id: (r['id'] as int),
      date: d,
      category: (r['category'] as String),
      amount: (r['amount'] as int),
      memo: r['memo'] as String?,
    );
  }

  /* ===== Analytics ===== */

  Stream<List<CategoryTotal>> watchMonthCategoryTotals(DateTime month) => _watch(() async {
    final start = DateTime(month.year, month.month, 1);
    final end = (month.month == 12)
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);

    return _fetch((db) async {
      final rows = await db.rawQuery('''
            SELECT category, SUM(amount) AS total
            FROM expenses
            WHERE date >= ? AND date < ?
            GROUP BY category
            ORDER BY total DESC
          ''', [_dateStr(start), _dateStr(end)]);

      return rows
          .map((r) => CategoryTotal(
        category: (r['category'] as String),
        total: (r['total'] as int?) ?? 0,
      ))
          .toList();
    });
  });

  Stream<List<DayTotal>> watchMonthDailyTotals(DateTime month) => _watch(() async {
    final start = DateTime(month.year, month.month, 1);
    final end = (month.month == 12)
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);

    return _fetch((db) async {
      final rows = await db.rawQuery('''
            SELECT date, SUM(amount) AS total
            FROM expenses
            WHERE date >= ? AND date < ?
            GROUP BY date
            ORDER BY date ASC
          ''', [_dateStr(start), _dateStr(end)]);

      return rows.map((r) {
        final ds = (r['date'] as String);
        final p = ds.split('-');
        final d = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
        return DayTotal(day: d, total: (r['total'] as int?) ?? 0);
      }).toList();
    });
  });

  Stream<int> watchMonthTotal(DateTime month) => _watch(() async {
    final start = DateTime(month.year, month.month, 1);
    final end = (month.month == 12)
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);

    return _fetch((db) async {
      final rows = await db.rawQuery('''
            SELECT SUM(amount) AS total
            FROM expenses
            WHERE date >= ? AND date < ?
          ''', [_dateStr(start), _dateStr(end)]);
      return (rows.first['total'] as int?) ?? 0;
    });
  });

  Stream<int> watchTodayTotal() => _watch(() async {
    final d = _dateOnly(DateTime.now());
    final start = d;
    final end = d.add(const Duration(days: 1));

    return _fetch((db) async {
      final rows = await db.rawQuery('''
            SELECT SUM(amount) AS total
            FROM expenses
            WHERE date >= ? AND date < ?
          ''', [_dateStr(start), _dateStr(end)]);
      return (rows.first['total'] as int?) ?? 0;
    });
  });

  // ✅ 新規：直近Nヶ月の月別合計（棒グラフ用）
  Stream<List<MonthTotal>> watchRecentMonthTotals(int months) => _watch(() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month - (months - 1), 1);
    final end = DateTime(now.year, now.month + 1, 1);

    return _fetch((db) async {
      final rows = await db.rawQuery('''
            SELECT strftime('%Y-%m', date) AS ym, SUM(amount) AS total
            FROM expenses
            WHERE date >= ? AND date < ?
            GROUP BY ym
            ORDER BY ym ASC
          ''', [_dateStr(start), _dateStr(end)]);

      final map = <String, int>{};
      for (final r in rows) {
        final ym = (r['ym'] as String?) ?? '';
        final total = (r['total'] as int?) ?? 0;
        map[ym] = total;
      }

      final list = <MonthTotal>[];
      for (int i = 0; i < months; i++) {
        final m = DateTime(start.year, start.month + i, 1);
        final key = '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}';
        list.add(MonthTotal(month: m, total: map[key] ?? 0));
      }
      return list;
    });
  });

  Future<void> close() async {
    await _db?.close();
    _db = null;
    await _change.close();
  }
}
