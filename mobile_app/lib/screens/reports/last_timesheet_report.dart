import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../widgets/report_kit.dart';

/// views.reports_last_timesheet (+ export_last_timesheet_pdf)
class LastTimesheetReportScreen extends StatefulWidget {
  const LastTimesheetReportScreen({super.key});

  @override
  State<LastTimesheetReportScreen> createState() => _LastTimesheetReportScreenState();
}

class _LastTimesheetReportScreenState extends State<LastTimesheetReportScreen> {
  String _weekMode = 'current';
  DateTime? _weekDate;
  String _monthMode = 'current';
  DateTime? _month;
  UserBrief? _user;
  String _sort = 'days';
  int _version = 0;

  Map<String, dynamic> get _filters => {
        'week_mode': _weekMode,
        'week_date': _weekMode == 'custom' && _weekDate != null ? Fmt.iso(_weekDate!) : null,
        'month_mode': _monthMode,
        'month': _monthMode == 'custom' && _month != null ? Fmt.isoMonth(_month!) : null,
        'user_pk': _user?.id,
        'sort': _sort,
      };

  Future<Map<String, dynamic>> _load() async {
    return asMap(await context.read<Session>().api.get('/reports/last-timesheet/', query: {..._filters, 'page_size': 500}));
  }

  void _reload() => setState(() => _version++);

  Future<void> _chooseWeek() async {
    final r = await showOptionsSheet<String>(context, title: 'Week', selected: _weekMode, options: const [
      Option('current', 'Current week', icon: Icons.today_rounded),
      Option('previous', 'Previous week', icon: Icons.history_rounded),
      Option('custom', 'Pick a week…', icon: Icons.edit_calendar_rounded),
    ]);
    if (r == null || !mounted) return;
    if (r.value == 'custom') {
      final now = DateTime.now();
      final d = await pickDate(context, initial: _weekDate ?? now, first: DateTime(2020), last: now, help: 'Any day of the week');
      if (d == null) return;
      _weekDate = d;
    }
    _weekMode = r.value;
    _reload();
  }

  Future<void> _chooseMonth() async {
    final r = await showOptionsSheet<String>(context, title: 'Month', selected: _monthMode, options: const [
      Option('current', 'Current month', icon: Icons.calendar_month_rounded),
      Option('previous', 'Previous month', icon: Icons.history_rounded),
      Option('custom', 'Pick a month…', icon: Icons.edit_calendar_rounded),
    ]);
    if (r == null || !mounted) return;
    if (r.value == 'custom') {
      final m = await pickMonth(context, selected: _month, count: 12);
      if (m == null) return;
      _month = m;
    }
    _monthMode = r.value;
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
    final r = await showOptionsSheet<String>(context, title: 'Sort by', selected: _sort, options: const [
      Option('days', 'Days since last log (most first)', icon: Icons.hourglass_bottom_rounded),
      Option('name', 'Name', icon: Icons.sort_by_alpha_rounded),
      Option('date', 'Last log date (newest first)', icon: Icons.event_rounded),
    ]);
    if (r == null) return;
    _sort = r.value;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final weekLabel = _weekMode == 'previous'
        ? 'Previous week'
        : (_weekMode == 'custom' && _weekDate != null ? 'Week of ${Fmt.dayShort(_weekDate)}' : 'Current week');
    final monthLabel = _monthMode == 'previous'
        ? 'Previous month'
        : (_monthMode == 'custom' && _month != null ? Fmt.monthYear(_month) : 'Current month');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Last timesheet'),
        actions: [
          IconButton(
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.danger),
            onPressed: () => downloadAndOpenPdf(context,
                path: '/reports/last-timesheet/pdf/',
                query: _filters,
                fileName: 'Last_Timesheet_${Fmt.iso(DateTime.now())}.pdf'),
          ),
        ],
      ),
      body: Column(
        children: [
          FilterBar(children: [
            FilterPill(label: weekLabel, icon: Icons.view_week_rounded, active: _weekMode != 'current', onTap: _chooseWeek),
            FilterPill(label: monthLabel, icon: Icons.calendar_month_rounded, active: _monthMode != 'current', onTap: _chooseMonth),
            FilterPill(
              label: _user?.fullName ?? 'Employee',
              icon: Icons.person_search_rounded,
              active: _user != null,
              onTap: _chooseUser,
              onClear: () {
                _user = null;
                _reload();
              },
            ),
            FilterPill(label: 'Sort', icon: Icons.sort_rounded, onTap: _chooseSort),
          ]),
          Expanded(
            child: Loader<Map<String, dynamic>>(
              key: ValueKey('last-ts-$_version'),
              load: _load,
              builder: (context, data, reload) {
                final meta = asMap(data['meta']);
                final rows = asList(data['results']).map((e) => asMap(e)).toList();
                final weeklyTarget = asDouble(meta['weekly_target']) == 0 ? 40.0 : asDouble(meta['weekly_target']);
                final monthlyTarget = asDouble(meta['monthly_target']);
                final lagging = rows.where((r) => asInt(r['days_since_work']) > 2).length;
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
                              title: 'Timesheet compliance',
                              subtitle:
                                  'Week ${Fmt.dayShort(asDate(meta['week_start']))} – ${Fmt.dayShort(asDate(meta['week_end']))} • ${asString(meta['selected_month_label'])}',
                              tiles: [
                                StatTile(
                                    label: 'Employees',
                                    value: '${asInt(meta['total_employees'])}',
                                    icon: Icons.groups_rounded),
                                StatTile(
                                    label: 'No log for 3+ days',
                                    value: '$lagging',
                                    icon: Icons.warning_amber_rounded,
                                    tone: lagging > 0 ? Tone.danger : Tone.success),
                                StatTile(
                                    label: 'Weekly target',
                                    value: Fmt.hours(weeklyTarget),
                                    icon: Icons.view_week_rounded,
                                    tone: Tone.info),
                                StatTile(
                                    label: 'Monthly target',
                                    value: Fmt.hours(monthlyTarget),
                                    icon: Icons.calendar_month_rounded,
                                    tone: Tone.info,
                                    caption: '${asInt(meta['working_days'])} working days × 8h'),
                              ],
                            ),
                            if (rows.isEmpty)
                              const EmptyState(icon: Icons.history_toggle_off_rounded, title: 'No employees found'),
                            for (final r in rows)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ComplianceCard(row: r, weeklyTarget: weeklyTarget, monthlyTarget: monthlyTarget),
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
}

class _ComplianceCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final double weeklyTarget;
  final double monthlyTarget;
  const _ComplianceCard({required this.row, required this.weeklyTarget, required this.monthlyTarget});

  @override
  Widget build(BuildContext context) {
    final user = UserBrief.fromJson(asMap(row['user']));
    final days = asInt(row['days_since_work']);
    final weekPct = asDouble(row['week_pct']);
    final monthPct = asDouble(row['month_pct']);
    final weekVacation = asDouble(row['week_vacation']);
    final daysTone = days <= 1 ? Tone.success : (days <= 3 ? Tone.warning : Tone.danger);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(user.initials, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.text)),
                    Text('Last log: ${Fmt.day(asDate(row['work_date']))}',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              StatusChip(Fmt.relativeDays(days), daysTone, dense: true),
            ],
          ),
          const SizedBox(height: 8),
          Text(asString(row['description'], '—'),
              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 10),
          _metric('Week', asDouble(row['week_total']), weeklyTarget, weekPct,
              extra: weekVacation > 0 ? '(${Fmt.hm(weekVacation)} on Fri/Sat)' : null),
          const SizedBox(height: 8),
          _metric('Month', asDouble(row['month_total']), monthlyTarget, monthPct),
        ],
      ),
    );
  }

  Widget _metric(String label, double value, double target, double pct, {String? extra}) {
    final tone = Tone.forPercent(pct);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 13)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('${Fmt.dec(value)} / ${Fmt.dec(target)} h ${extra ?? ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
            ),
            Text(Fmt.percent(pct), style: TextStyle(fontWeight: FontWeight.w800, color: tone.fg)),
          ],
        ),
        const SizedBox(height: 5),
        ProgressLine(value: pct / 100, color: tone.fg, height: 6),
      ],
    );
  }
}
