import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../widgets/report_kit.dart';

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
  'November', 'December'];

/// views.reports_monthly_man_days (+ export_monthly_man_days_pdf)
class MonthlyReportScreen extends StatefulWidget {
  const MonthlyReportScreen({super.key});

  @override
  State<MonthlyReportScreen> createState() => _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends State<MonthlyReportScreen> {
  late int _year;
  late String _month; // "1".."12" or "all"
  UserBrief? _user;
  String _sort = 'pct';
  int _version = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = '${now.month}';
  }

  Map<String, dynamic> get _filters => {'year': _year, 'month': _month, 'user_pk': _user?.id, 'sort': _sort};

  Future<Map<String, dynamic>> _load() async {
    return asMap(await context.read<Session>().api.get('/reports/monthly-man-days/', query: {..._filters, 'page_size': 500}));
  }

  void _reload() => setState(() => _version++);

  Future<void> _chooseYear() async {
    final now = DateTime.now().year;
    final r = await showOptionsSheet<int>(context, title: 'Year', selected: _year, options: [
      for (int y = now; y >= now - 3; y--) Option(y, '$y', icon: Icons.calendar_today_rounded),
    ]);
    if (r == null) return;
    _year = r.value;
    _reload();
  }

  Future<void> _chooseMonth() async {
    final r = await showOptionsSheet<String>(context, title: 'Month', selected: _month, options: [
      const Option('all', 'Full year (pick one employee)', icon: Icons.all_inclusive_rounded),
      for (int m = 1; m <= 12; m++) Option('$m', _monthNames[m - 1], icon: Icons.calendar_month_rounded),
    ]);
    if (r == null) return;
    if (r.value == 'all' && _user == null && mounted) {
      showSnack(context, 'Full-year view shows 12 months for one employee — choose the employee next.');
      _month = 'all';
      await _chooseUser();
      if (_user == null) _month = '${DateTime.now().month}';
      _reload();
      return;
    }
    _month = r.value;
    _reload();
  }

  Future<void> _chooseUser() async {
    final meta = await loadMeta(context);
    if (meta == null || !mounted) return;
    final r = await showOptionsSheet<int>(context, title: 'Employee', searchable: true, selected: _user?.id, options: [
      for (final u in meta.users) Option(u.id, u.fullName, subtitle: u.username, icon: Icons.person_rounded),
    ]);
    if (r == null) return;
    _user = meta.users.firstWhere((u) => u.id == r.value);
    _reload();
  }

  Future<void> _chooseSort() async {
    final r = await showOptionsSheet<String>(context, title: 'Sort by', selected: _sort, options: [
      const Option('pct', 'Achievement %', icon: Icons.percent_rounded),
      const Option('main', 'Main hours', icon: Icons.timer_rounded),
      const Option('name', 'Name', icon: Icons.sort_by_alpha_rounded),
      if (_month == 'all') const Option('month', 'Month order', icon: Icons.calendar_month_rounded),
    ]);
    if (r == null) return;
    _sort = r.value;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final monthLabel = _month == 'all' ? 'Full year' : _monthNames[(int.tryParse(_month) ?? 1) - 1];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monthly man-days'),
        actions: [
          IconButton(
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.danger),
            onPressed: () => downloadAndOpenPdf(context,
                path: '/reports/monthly-man-days/pdf/', query: _filters, fileName: 'Monthly_ManDays_${_year}_$_month.pdf'),
          ),
        ],
      ),
      body: Column(
        children: [
          FilterBar(children: [
            FilterPill(label: '$_year', icon: Icons.calendar_today_rounded, active: true, onTap: _chooseYear),
            FilterPill(label: monthLabel, icon: Icons.calendar_month_rounded, active: true, onTap: _chooseMonth),
            FilterPill(
              label: _user?.fullName ?? 'All employees',
              icon: Icons.person_search_rounded,
              active: _user != null,
              onTap: _chooseUser,
              onClear: () {
                _user = null;
                if (_month == 'all') _month = '${DateTime.now().month}';
                _reload();
              },
            ),
            FilterPill(label: 'Sort', icon: Icons.sort_rounded, onTap: _chooseSort),
          ]),
          Expanded(
            child: Loader<Map<String, dynamic>>(
              key: ValueKey('monthly-$_version'),
              load: _load,
              builder: (context, data, reload) {
                final meta = asMap(data['meta']);
                final rows = asList(data['results']).map((e) => asMap(e)).toList();
                final fullYear = asBool(meta['is_full_year']);
                return RefreshIndicator(
                  onRefresh: reload,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(pad, 4, pad, 32),
                    children: [
                      ResponsiveCenter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ReportSummary(
                              title: fullYear ? '${_user?.fullName ?? ''} — $_year' : '${asString(meta['month_name'])} $_year',
                              subtitle: fullYear
                                  ? 'Main hours = Sun–Thu, extra = Fri–Sat (study excluded)'
                                  : '${asInt(meta['working_days'])} working days • target ${Fmt.hours(asDouble(meta['monthly_target']))}',
                              tiles: [
                                StatTile(
                                  label: 'Average achievement',
                                  value: Fmt.percent(asDouble(meta['avg_percentage'])),
                                  icon: Icons.percent_rounded,
                                  tone: Tone.forPercent(asDouble(meta['avg_percentage'])),
                                ),
                                StatTile(
                                    label: 'Main hours (Sun–Thu)',
                                    value: Fmt.hours(asDouble(meta['total_main'])),
                                    icon: Icons.work_history_rounded),
                                StatTile(
                                    label: 'Extra hours (Fri–Sat)',
                                    value: Fmt.hours(asDouble(meta['total_extra'])),
                                    icon: Icons.weekend_rounded,
                                    tone: Tone.warning),
                                StatTile(
                                    label: fullYear ? 'Months' : 'Employees',
                                    value: '${asInt(meta['total_employees'])}',
                                    icon: fullYear ? Icons.calendar_month_rounded : Icons.groups_rounded,
                                    tone: Tone.info),
                              ],
                            ),
                            AppCard(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              child: rows.isEmpty
                                  ? const EmptyState(icon: Icons.bar_chart_rounded, title: 'No data')
                                  : Column(
                                      children: [
                                        for (int i = 0; i < rows.length; i++) ...[
                                          if (i > 0) const Divider(height: 1),
                                          _monthlyRow(rows[i], fullYear),
                                        ],
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _monthlyRow(Map<String, dynamic> r, bool fullYear) {
    final pct = asDouble(r['percentage']);
    final tone = Tone.forPercent(pct);
    final user = asMap(r['user']);
    final main = asDouble(r['main_hours']);
    final extra = asDouble(r['extra_hours']);
    final target = asDouble(r['target']);
    return BarRow(
      label: fullYear ? asString(r['month_name']) : asString(user['full_name'], '—'),
      sublabel: 'Main ${Fmt.dec(main)}h • Extra ${Fmt.dec(extra)}h • Target ${Fmt.dec(target)}h',
      valueText: Fmt.percent(pct),
      ratio: pct / 100,
      color: tone.fg,
    );
  }
}
