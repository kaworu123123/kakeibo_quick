import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'db/app_db.dart';

void main() {
  runApp(const KakeiboApp());
}

class KakeiboApp extends StatelessWidget {
  const KakeiboApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kakeibo Quick',
      theme: ThemeData(useMaterial3: true),
      home: const HomeShell(),
    );
  }
}

class _AddResult {
  final DateTime savedDate;
  _AddResult(this.savedDate);
}

/* =========================
   HomeShell（分析/一覧 + 中央FAB）
========================= */

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late final AppDb db;

  int _tab = 0; // 0=分析, 1=一覧
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    db = AppDb();
  }

  @override
  void dispose() {
    db.close();
    super.dispose();
  }

  String _monthLabel(DateTime m) => '${m.year}/${m.month.toString().padLeft(2, '0')}';

  void _prevMonth() {
    final m = _selectedMonth;
    final prev = (m.month == 1)
        ? DateTime(m.year - 1, 12, 1)
        : DateTime(m.year, m.month - 1, 1);
    setState(() => _selectedMonth = prev);
  }

  void _nextMonth() {
    final m = _selectedMonth;
    final next = (m.month == 12)
        ? DateTime(m.year + 1, 1, 1)
        : DateTime(m.year, m.month + 1, 1);
    setState(() => _selectedMonth = next);
  }

  void _goThisMonth() {
    final now = DateTime.now();
    setState(() => _selectedMonth = DateTime(now.year, now.month, 1));
  }

  Future<void> _openCategoryEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CategoryEditPage(db: db)),
    );
  }

  // ✅ 中央FABで入力シートを下から表示
  Future<void> _openAddExpense() async {
    final result = await showModalBottomSheet<_AddResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddExpenseSheet(db: db),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedMonth = DateTime(result.savedDate.year, result.savedDate.month, 1);
        _tab = 1; // 保存後は一覧へ
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = _monthLabel(_selectedMonth);

    final pages = <Widget>[
      AnalyticsPage(
        db: db,
        month: _selectedMonth,
        monthLabel: monthLabel,
        onPrevMonth: _prevMonth,
        onNextMonth: _nextMonth,
        onThisMonth: _goThisMonth,
      ),
      ListPage(
        db: db,
        month: _selectedMonth,
        monthLabel: monthLabel,
        onPrevMonth: _prevMonth,
        onNextMonth: _nextMonth,
        onThisMonth: _goThisMonth,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? '分析' : '一覧'),
        actions: [
          IconButton(
            onPressed: _openCategoryEditor,
            icon: const Icon(Icons.settings),
            tooltip: 'カテゴリ編集',
          ),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddExpense,
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), label: '分析'),
          NavigationDestination(icon: Icon(Icons.list_alt), label: '一覧'),
        ],
      ),
    );
  }
}

/* =========================
   入力（ボトムシート）
   - タグ(ChoiceChip)は廃止 → Dropdown
========================= */

class AddExpenseSheet extends StatefulWidget {
  final AppDb db;
  const AddExpenseSheet({super.key, required this.db});

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  DateTime _date = DateTime.now();

  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  String? _selectedCategoryName;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  DateTime _asDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _yen(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idxFromEnd = s.length - i;
      buf.write(s[i]);
      if (idxFromEnd > 1 && idxFromEnd % 3 == 1) buf.write(',');
    }
    return '¥$buf';
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amountCtrl.text.replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('金額を正しく入力してね')),
      );
      return;
    }

    final category = _selectedCategoryName;
    if (category == null || category.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('カテゴリを選んでね')),
      );
      return;
    }

    final memoText = _memoCtrl.text.trim();
    final memoOrNull = memoText.isEmpty ? null : memoText;

    final savedDate = _asDateOnly(_date);

    await widget.db.addExpense(
      date: savedDate,
      category: category,
      amount: amount,
      memo: memoOrNull,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('保存: $category ${_yen(amount)}')),
    );

    if (mounted) Navigator.pop(context, _AddResult(savedDate));
  }

  @override
  Widget build(BuildContext context) {
    final d = _date;
    final dateText =
        '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
        child: StreamBuilder<List<Category>>(
          stream: widget.db.watchCategories(),
          builder: (context, catSnap) {
            final cats = catSnap.data ?? const <Category>[];
            final catNames = cats.map((c) => c.name).toList();

            if (_selectedCategoryName == null && catNames.isNotEmpty) {
              _selectedCategoryName = catNames.first;
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Expanded(
                      child: Text('支出を追加',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('日付', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(dateText)),
                    TextButton(onPressed: _pickDate, child: const Text('変更')),
                  ],
                ),
                const SizedBox(height: 10),
                const Text('カテゴリ', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),

                // ✅ タグ(ChoiceChip)は消える（Dropdown）
                if (catNames.isEmpty)
                  const Text('カテゴリがありません（⚙で追加してね）')
                else
                  DropdownButtonFormField<String>(
                    value: _selectedCategoryName,
                    items: catNames
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCategoryName = v),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),

                const SizedBox(height: 12),
                TextField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '金額（円）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _memoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'メモ（任意）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _save,
                  child: const Text('確定（SQLiteに保存）'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/* =========================
   分析ページ
   - PageViewで「円グラフ+内訳」⇄「カレンダー」
   - 円グラフ横の内訳は高さ240 & スクロール
========================= */

class AnalyticsPage extends StatefulWidget {
  final AppDb db;
  final DateTime month;
  final String monthLabel;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onThisMonth;

  const AnalyticsPage({
    super.key,
    required this.db,
    required this.month,
    required this.monthLabel,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onThisMonth,
  });

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  final _pageCtrl = PageController();
  int _page = 0; // 0=pie, 1=calendar

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  String _yen(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idxFromEnd = s.length - i;
      buf.write(s[i]);
      if (idxFromEnd > 1 && idxFromEnd % 3 == 1) buf.write(',');
    }
    return '¥$buf';
  }

  List<PieChartSectionData> _buildSections(List<CategoryTotal> totals) {
    final sum = totals.fold<int>(0, (a, b) => a + b.total);
    if (sum <= 0) return const [];

    return List.generate(totals.length, (i) {
      final t = totals[i];
      final pct = (t.total / sum) * 100.0;
      final color = Colors.primaries[i % Colors.primaries.length];
      return PieChartSectionData(
        value: t.total.toDouble(),
        title: pct >= 10 ? '${pct.toStringAsFixed(0)}%' : '',
        radius: 58,
        titleStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        color: color,
      );
    });
  }

  Map<DateTime, int> _toMap(List<DayTotal> list) {
    final m = <DateTime, int>{};
    for (final d in list) {
      final key = DateTime(d.day.year, d.day.month, d.day.day);
      m[key] = d.total;
    }
    return m;
  }

  Future<void> _openDayDetail(DateTime day) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DayDetailSheet(db: widget.db, day: day),
    );
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = widget.monthLabel;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(onPressed: widget.onPrevMonth, icon: const Icon(Icons.chevron_left)),
                  Expanded(
                    child: Center(
                      child: Text(
                        monthLabel,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  IconButton(onPressed: widget.onNextMonth, icon: const Icon(Icons.chevron_right)),
                  const SizedBox(width: 8),
                  TextButton(onPressed: widget.onThisMonth, child: const Text('今月へ')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: StreamBuilder<int>(
                      stream: widget.db.watchTodayTotal(),
                      builder: (context, snap) {
                        final v = snap.data ?? 0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('今日の合計', style: TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(_yen(v), style: const TextStyle(fontSize: 18)),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: StreamBuilder<int>(
                      stream: widget.db.watchMonthTotal(widget.month),
                      builder: (context, snap) {
                        final v = snap.data ?? 0;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$monthLabel 合計',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(_yen(v), style: const TextStyle(fontSize: 18)),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _page == 0
                              ? 'カテゴリ別（左右フリックでカレンダー）'
                              : '日別（タップで明細 / 左右フリックで円グラフ）',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Row(
                        children: [
                          _Dot(active: _page == 0),
                          const SizedBox(width: 6),
                          _Dot(active: _page == 1),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  SizedBox(
                    height: 260,
                    child: PageView(
                      controller: _pageCtrl,
                      onPageChanged: (i) => setState(() => _page = i),
                      children: [
                        // ===== ページ0：円グラフ + 右に内訳（高さ240でスクロール） =====
                        StreamBuilder<List<CategoryTotal>>(
                          stream: widget.db.watchMonthCategoryTotals(widget.month),
                          builder: (context, snap) {
                            final totals = snap.data ?? const <CategoryTotal>[];
                            final sum = totals.fold<int>(0, (a, b) => a + b.total);
                            if (sum <= 0) return const Center(child: Text('この月のデータがありません'));

                            return Center(
                              child: SizedBox(
                                height: 240, // ✅ 指定どおり240
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 170,
                                      height: 240,
                                      child: PieChart(
                                        PieChartData(
                                          sections: _buildSections(totals),
                                          centerSpaceRadius: 30,
                                          sectionsSpace: 2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: SizedBox(
                                        height: 240,
                                        child: ListView.separated(
                                          itemCount: totals.length,
                                          separatorBuilder: (_, __) => const Divider(height: 1),
                                          itemBuilder: (context, i) {
                                            final t = totals[i];
                                            final pct = (t.total / sum * 100).toStringAsFixed(0);
                                            return ListTile(
                                              dense: true,
                                              contentPadding:
                                              const EdgeInsets.symmetric(horizontal: 8),
                                              title: Text(
                                                t.category,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              subtitle: Text('$pct%'),
                                              trailing: Text(
                                                _yen(t.total),
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),

                        // ===== ページ1：カレンダー（日別合計） =====
                        StreamBuilder<List<DayTotal>>(
                          stream: widget.db.watchMonthDailyTotals(widget.month),
                          builder: (context, snap) {
                            final list = snap.data ?? const <DayTotal>[];
                            final map = _toMap(list);
                            return MonthCalendar(
                              month: widget.month,
                              dayTotals: map,
                              yen: _yen,
                              onDayTap: _openDayDetail,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 10 : 8,
      height: active ? 10 : 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? Colors.black87 : Colors.black26,
      ),
    );
  }
}

/* =========================
   月カレンダー（タップで日別明細）
========================= */

class MonthCalendar extends StatelessWidget {
  final DateTime month;
  final Map<DateTime, int> dayTotals;
  final String Function(int) yen;
  final Future<void> Function(DateTime day) onDayTap;

  const MonthCalendar({
    super.key,
    required this.month,
    required this.dayTotals,
    required this.yen,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final y = month.year;
    final m = month.month;
    final firstDay = DateTime(y, m, 1);
    final nextMonth = (m == 12) ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1);
    final daysInMonth = nextMonth.subtract(const Duration(days: 1)).day;

    // Dart weekday: Mon=1..Sun=7 → 日曜始まり
    final firstWeekday = firstDay.weekday;
    final leadingBlanks = firstWeekday % 7;

    const weeks = 6;
    final cellCount = weeks * 7;

    const labels = ['日', '月', '火', '水', '木', '金', '土'];

    return Column(
      children: [
        Row(
          children: [
            for (int i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(labels[i], style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cellCount,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 0.85,
            ),
            itemBuilder: (context, index) {
              final dayNum = index - leadingBlanks + 1;
              if (dayNum < 1 || dayNum > daysInMonth) return const SizedBox.shrink();

              final key = DateTime(y, m, dayNum);
              final total = dayTotals[key] ?? 0;

              final isToday = _isSameDate(key, DateTime.now());

              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onDayTap(key),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isToday ? Colors.black54 : Colors.black12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$dayNum', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (total > 0)
                        Text(
                          yen(total),
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isSameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/* =========================
   日別明細シート（削除も可）
========================= */

class DayDetailSheet extends StatelessWidget {
  final AppDb db;
  final DateTime day; // DateTime(y,m,d)

  const DayDetailSheet({super.key, required this.db, required this.day});

  String _title() =>
      '${day.year}/${day.month.toString().padLeft(2, '0')}/${day.day.toString().padLeft(2, '0')}';

  String _yen(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idxFromEnd = s.length - i;
      buf.write(s[i]);
      if (idxFromEnd > 1 && idxFromEnd % 3 == 1) buf.write(',');
    }
    return '¥$buf';
  }

  Future<bool> _confirmDelete(BuildContext context, Expense e) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('削除しますか？'),
        content: Text('${e.category} ${_yen(e.amount)} を削除します'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 12, 16, bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_title()} の明細',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Flexible(
              child: StreamBuilder<List<Expense>>(
                stream: db.watchDayExpenses(day),
                builder: (context, snap) {
                  final items = snap.data ?? const <Expense>[];
                  final sum = items.fold<int>(0, (a, b) => a + b.amount);

                  if (items.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 18),
                      child: Center(child: Text('この日の支出はありません')),
                    );
                  }

                  return Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text('合計 ${_yen(sum)}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: items.length,
                          itemBuilder: (context, i) {
                            final e = items[i];
                            return Dismissible(
                              key: ValueKey('day_${e.id}'),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (_) => _confirmDelete(context, e),
                              onDismissed: (_) async {
                                await db.deleteExpenseById(e.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('削除しました')),
                                  );
                                }
                              },
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                child: const Text('削除'),
                              ),
                              child: ListTile(
                                dense: true,
                                title: Text('${e.category}  ${_yen(e.amount)}'),
                                subtitle: Text(e.memo ?? ''),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* =========================
   一覧ページ（カテゴリ別グループ）
========================= */

class ListPage extends StatelessWidget {
  final AppDb db;
  final DateTime month;
  final String monthLabel;
  final VoidCallback onPrevMonth;
  final VoidCallback onNextMonth;
  final VoidCallback onThisMonth;

  const ListPage({
    super.key,
    required this.db,
    required this.month,
    required this.monthLabel,
    required this.onPrevMonth,
    required this.onNextMonth,
    required this.onThisMonth,
  });

  String _yen(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final idxFromEnd = s.length - i;
      buf.write(s[i]);
      if (idxFromEnd > 1 && idxFromEnd % 3 == 1) buf.write(',');
    }
    return '¥$buf';
  }

  Future<bool> _confirmDelete(BuildContext context, Expense e) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('削除しますか？'),
        content: Text('${e.category} ${_yen(e.amount)} を削除します'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
        ],
      ),
    );
    return result ?? false;
  }

  List<Widget> _buildGrouped({
    required BuildContext context,
    required List<Expense> items,
    required List<String> orderedCategoryNames,
  }) {
    if (items.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('この月の支出がありません')),
        ),
      ];
    }

    final map = <String, List<Expense>>{};
    for (final e in items) {
      map.putIfAbsent(e.category, () => []).add(e);
    }

    final ordered = <String>[
      ...orderedCategoryNames.where(map.containsKey),
      ...map.keys.where((k) => !orderedCategoryNames.contains(k)).toList()..sort(),
    ];

    final widgets = <Widget>[];

    for (final cat in ordered) {
      final list = map[cat]!;
      final catTotal = list.fold<int>(0, (a, b) => a + b.amount);

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(cat,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              Text(_yen(catTotal), style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
      widgets.add(const Divider(height: 1));

      for (final e in list) {
        widgets.add(
          Dismissible(
            key: ValueKey(e.id),
            direction: DismissDirection.endToStart,
            confirmDismiss: (_) => _confirmDelete(context, e),
            onDismissed: (_) async {
              await db.deleteExpenseById(e.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('削除しました')),
                );
              }
            },
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const Text('削除'),
            ),
            child: ListTile(
              dense: true,
              title: Text('${e.category}  ${_yen(e.amount)}'),
              subtitle: Text('${e.date.month}/${e.date.day}  ${e.memo ?? ''}'),
            ),
          ),
        );
      }
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: StreamBuilder<List<Category>>(
        stream: db.watchCategories(),
        builder: (context, catSnap) {
          final cats = catSnap.data ?? const <Category>[];
          final catNames = cats.map((c) => c.name).toList();

          return ListView(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      IconButton(onPressed: onPrevMonth, icon: const Icon(Icons.chevron_left)),
                      Expanded(
                        child: Center(
                          child: Text(
                            monthLabel,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      IconButton(onPressed: onNextMonth, icon: const Icon(Icons.chevron_right)),
                      const SizedBox(width: 8),
                      TextButton(onPressed: onThisMonth, child: const Text('今月へ')),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('$monthLabel の支出（カテゴリ別）',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              StreamBuilder<List<Expense>>(
                stream: db.watchMonthExpenses(month),
                builder: (context, snap) {
                  final items = snap.data ?? const <Expense>[];
                  return Column(
                    children: _buildGrouped(
                      context: context,
                      items: items,
                      orderedCategoryNames: catNames,
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

/* =========================
   カテゴリ編集（追加/削除/並び替え）
========================= */

class CategoryEditPage extends StatefulWidget {
  final AppDb db;
  const CategoryEditPage({super.key, required this.db});

  @override
  State<CategoryEditPage> createState() => _CategoryEditPageState();
}

class _CategoryEditPageState extends State<CategoryEditPage> {
  final _newCtrl = TextEditingController();

  @override
  void dispose() {
    _newCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _newCtrl.text.trim();
    if (name.isEmpty) return;
    await widget.db.addCategory(name);
    _newCtrl.clear();
  }

  Future<void> _delete(Category c) async {
    final used = await widget.db.categoryIsUsed(c.name);
    if (used) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('「${c.name}」は支出に使われているので削除できません')),
      );
      return;
    }

    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('削除しますか？'),
        content: Text('カテゴリ「${c.name}」を削除します'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
        ],
      ),
    );

    if (ok == true) {
      await widget.db.deleteCategoryById(c.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('カテゴリ編集')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newCtrl,
                    decoration: const InputDecoration(
                      labelText: 'カテゴリ名',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _add, child: const Text('追加')),
              ],
            ),
            const SizedBox(height: 12),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('並び替え：長押ししてドラッグ'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<Category>>(
                stream: widget.db.watchCategories(),
                builder: (context, snap) {
                  final items = snap.data ?? const <Category>[];
                  if (items.isEmpty) return const Center(child: Text('カテゴリがありません'));

                  return ReorderableListView.builder(
                    itemCount: items.length,
                    onReorder: (oldIndex, newIndex) async {
                      final list = [...items];
                      if (newIndex > oldIndex) newIndex -= 1;
                      final moved = list.removeAt(oldIndex);
                      list.insert(newIndex, moved);
                      await widget.db.updateCategoryOrder(list);
                    },
                    itemBuilder: (context, index) {
                      final c = items[index];
                      return ListTile(
                        key: ValueKey(c.id),
                        title: Text(c.name),
                        leading: const Icon(Icons.drag_handle),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(c),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
