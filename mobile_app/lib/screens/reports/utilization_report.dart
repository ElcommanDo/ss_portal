import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../widgets/report_kit.dart';

/// views.utilization_report / employee_utilization_detail
/// Expected hours = working days (Sun–Thu) − approved leave days, × 8.
class UtilizationReportScreen extends StatefulWidget {
  const UtilizationReportScreen({super.key});

  @override
  State<UtilizationReportScreen> createState() => _UtilizationReportScreenState();
}

class _UtilizationReportScreenState extends State<UtilizationReportScreen> {
  DateTime? _start;
  DateTime? _end;
  IdName? _team;
  String _sort = 'util';
  int _version = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = DateTime(now.year, now.month, now.day);
  }

  Map<String, dynamic> get _filters => {
        'start_date': _start == null ? null : Fmt.iso(_start!),
        'end_date': _end == null ? null : Fmt.iso(_end!),
        'team_pk': _team?.id,
        'sort': _sort,
      };

  Future<Map<String, dynamic>> _load() async =>
      asMap(await context.read<Session>().api.get('/reports/utilization/', query: _filters));

  void _reload() => setState(() => _version++);

  Future<void> _chooseRange() async {
    final r = await showOptionsSheet<String>(context, title: 'Period', options: const [
      Option('month', 'This month', icon: Icons.calendar_month_rounded),
      Option('last', 'Last month', icon: Icons.history_rounded),
      Option('year', 'This year', icon: Icons.calendar_today_rounded),
      Option('custom', 'Custom range…', icon: Icons.date_range_rounded),
      Option('all', 'All data (like the portal)', icon: Icons.all_inclusive_rounded),
    ]);
    if (r == null || !mounted) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (r.value) {
      case 'month':
        _start = DateTime(now.year, now.month, 1);
        _end = today;
        break;
      case 'last':
        _start = DateTime(now.year, now.month - 1, 1);
        _end = DateTime(now.year, now.month, 0);
        break;
      case 'year':
        _start = DateTime(now.year, 1, 1);
        _end = today;
        break;
      case 'all':
        _start = null;
        _end = null;
        break;
      case 'custom':
        final range = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: DateTime(now.year + 1, 12, 31),
          initialDateRange: _start != null && _end != null ? DateTimeRange(start: _start!, end: _end!) : null,
        );
        if (range == null) return;
        _start = range.start;
        _end = range.end;
        break;
    }
    _reload();
  }

  Future<void> _chooseTeam() async {
    final meta = await loadMeta(context);
    if (meta == null || !mounted) return;
    final r = await showOptionsSheet<int>(context, title: 'Team', selected: _team?.id, options: [
      for (final t in meta.teams) Option(t.id, t.name.replaceAll('_', ' '), icon: Icons.groups_rounded),
    ]);
    if (r == null) return;
    _team = IdName(r.value, r.label);
    _reload();
  }

  void _openDetail(Map<String, dynamic> row, String start, String end) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _UtilDetail(
          employeeId: asInt(row['id']),
          start: start,
          end: end,
          scroll: scroll,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final rangeLabel = _start == null ? 'All data' : '${Fmt.dayShort(_start)} – ${Fmt.date(_end)}';
    return Scaffold(
      appBar: AppBar(title: const Text('Utilization')),
      body: Column(
        children: [
          FilterBar(children: [
            FilterPill(label: rangeLabel, icon: Icons.date_range_rounded, active: true, onTap: _chooseRange),
            FilterPill(
              label: _team?.name ?? 'All teams',
              icon: Icons.groups_rounded,
              active: _team != null,
              onTap: _chooseTeam,
              onClear: () {
                _team = null;
                _reload();
              },
            ),
            FilterPill(
              label: _sort == 'util' ? 'Sort: utilization' : 'Sort: name',
              icon: Icons.sort_rounded,
              onTap: () {
                _sort = _sort == 'util' ? 'name' : 'util';
                _reload();
              },
            ),
          ]),
          Expanded(
            child: Loader<Map<String, dynamic>>(
              key: ValueKey('util-$_version'),
              load: _load,
              builder: (context, data, reload) {
                final rows = asList(data['results']).map((e) => asMap(e)).toList();
                final avg = asDouble(data['avg_utilization']);
                final start = asString(data['start_date']);
                final end = asString(data['end_date']);
                final totalHours = rows.fold<double>(0, (s, r) => s + asDouble(r['total_hours']));
                final under = rows.where((r) => asDouble(r['utilization']) < 70).length;
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
                              title: 'Team utilization',
                              subtitle: '${Fmt.date(asDate(start))} – ${Fmt.date(asDate(end))}',
                              tiles: [
                                StatTile(
                                    label: 'Average utilization',
                                    value: Fmt.percent(avg),
                                    icon: Icons.speed_rounded,
                                    tone: Tone.forPercent(avg)),
                                StatTile(
                                    label: 'Employees',
                                    value: '${asInt(data['total_employees'])}',
                                    icon: Icons.groups_rounded,
                                    tone: Tone.info),
                                StatTile(label: 'Logged hours', value: Fmt.hours(totalHours), icon: Icons.timer_rounded),
                                StatTile(
                                    label: 'Below 70%',
                                    value: '$under',
                                    icon: Icons.trending_down_rounded,
                                    tone: under > 0 ? Tone.danger : Tone.success),
                              ],
                            ),
                            AppCard(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              child: rows.isEmpty
                                  ? const EmptyState(icon: Icons.speed_rounded, title: 'No employees')
                                  : Column(
                                      children: [
                                        for (int i = 0; i < rows.length; i++) ...[
                                          if (i > 0) const Divider(height: 1),
                                          BarRow(
                                            leading: Avatar(
                                                UserBrief.fromJson({'full_name': rows[i]['full_name']}).initials,
                                                size: 34),
                                            label: asString(rows[i]['full_name']),
                                            sublabel:
                                                '${asString(rows[i]['team']).replaceAll('_', ' ')} • ${Fmt.dec(asDouble(rows[i]['total_hours']))} / ${Fmt.dec(asDouble(rows[i]['expected_hours']))} h',
                                            valueText: Fmt.percent(asDouble(rows[i]['utilization'])),
                                            ratio: asDouble(rows[i]['utilization']) / 100,
                                            color: Tone.forPercent(asDouble(rows[i]['utilization'])).fg,
                                            onTap: () => _openDetail(rows[i], start, end),
                                          ),
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
}

class _UtilDetail extends StatelessWidget {
  final int employeeId;
  final String start;
  final String end;
  final ScrollController scroll;

  const _UtilDetail({required this.employeeId, required this.start, required this.end, required this.scroll});

  @override
  Widget build(BuildContext context) {
    return Loader<Map<String, dynamic>>(
      load: () async => asMap(await context
          .read<Session>()
          .api
          .get('/reports/utilization/$employeeId/', query: {'start_date': start, 'end_date': end})),
      builder: (context, d, _) {
        final util = asDouble(d['utilization']);
        final projects = asList(d['project_data']).map((e) => asMap(e)).toList();
        final types = asList(d['task_data']).map((e) => asMap(e)).toList();
        final entries = asList(d['entries']).map((e) => asMap(e)).toList();
        final total = asDouble(d['total_hours']);
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text(asString(d['employee_name']),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
            Text('${Fmt.date(asDate(d['start_date']))} – ${Fmt.date(asDate(d['end_date']))}',
                style: const TextStyle(color: AppColors.muted)),
            const SizedBox(height: 14),
            TileGrid(minTileWidth: 140, children: [
              StatTile(label: 'Utilization', value: Fmt.percent(util), icon: Icons.speed_rounded, tone: Tone.forPercent(util)),
              StatTile(
                  label: 'Logged / expected',
                  value: '${Fmt.dec(total)} / ${Fmt.dec(asDouble(d['expected_hours']))}',
                  icon: Icons.timer_rounded,
                  caption: '${asInt(d['workdays'])} workdays after approved leave'),
            ]),
            const SectionTitle('By project'),
            for (final p in projects)
              BarRow(
                label: asString(p['project']),
                valueText: Fmt.hours(asDouble(p['hours'])),
                ratio: total > 0 ? asDouble(p['hours']) / total : 0,
                color: AppColors.indigo,
              ),
            const SectionTitle('By task type'),
            for (final t in types)
              BarRow(
                label: asString(t['type']),
                valueText: Fmt.hours(asDouble(t['hours'])),
                ratio: total > 0 ? asDouble(t['hours']) / total : 0,
                color: AppColors.blue,
              ),
            SectionTitle('Entries (${entries.length})'),
            for (final e in entries.take(100))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(asString(e['project']), style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('${Fmt.date(asDate(e['work_date']))} • ${asString(e['task_type'])}\n${asString(e['task_description'])}',
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                isThreeLine: true,
                trailing: Text(Fmt.hm(asDouble(e['hours'])),
                    style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.indigo)),
              ),
          ],
        );
      },
    );
  }
}
