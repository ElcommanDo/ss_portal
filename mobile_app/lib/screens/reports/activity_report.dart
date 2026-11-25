import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/entry_tile.dart';
import '../../widgets/forms.dart';
import '../../widgets/report_kit.dart';

/// views.reports_employee_activity
class ActivityReportScreen extends StatefulWidget {
  final UserBrief? initialUser;
  const ActivityReportScreen({super.key, this.initialUser});

  @override
  State<ActivityReportScreen> createState() => _ActivityReportScreenState();
}

class _ActivityReportScreenState extends State<ActivityReportScreen> {
  final _listKey = GlobalKey<PagedListState<Map<String, dynamic>>>();
  UserBrief? _user;
  IdName? _project;
  String _period = 'month';
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    _user = widget.initialUser;
    if (_user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _chooseUser();
      });
    }
  }

  Map<String, dynamic> get _filters => {
        'user_pk': _user?.id,
        'project_pk': _project?.id,
        'period': _period,
        'start_date': _period == 'custom' && _start != null ? Fmt.iso(_start!) : null,
        'end_date': _period == 'custom' && _end != null ? Fmt.iso(_end!) : null,
      };

  Future<PageResult<Map<String, dynamic>>> _fetch(int page) async {
    final data = await context.read<Session>().api.get('/reports/employee-activity/',
        query: {..._filters, 'page': page, 'page_size': 30});
    return PageResult.parse<Map<String, dynamic>>(data, (m) => m);
  }

  void _refresh() => _listKey.currentState?.refresh();

  Future<void> _chooseUser() async {
    final meta = await loadMeta(context);
    if (meta == null || !mounted) return;
    final r = await showOptionsSheet<int>(context, title: 'Employee', searchable: true, selected: _user?.id, options: [
      for (final u in meta.users) Option(u.id, u.fullName, subtitle: u.username, icon: Icons.person_rounded),
    ]);
    if (r == null) return;
    setState(() => _user = meta.users.firstWhere((u) => u.id == r.value));
    _refresh();
  }

  Future<void> _chooseProject() async {
    final meta = await loadMeta(context);
    if (meta == null || !mounted) return;
    final r = await showOptionsSheet<int>(context, title: 'Project', searchable: true, selected: _project?.id, options: [
      for (final p in meta.projects) Option(p.id, p.name, icon: Icons.folder_rounded),
    ]);
    if (r == null) return;
    setState(() => _project = IdName(r.value, r.label));
    _refresh();
  }

  Future<void> _choosePeriod() async {
    final r = await showOptionsSheet<String>(context, title: 'Period', selected: _period, options: const [
      Option('month', 'This month', icon: Icons.calendar_month_rounded),
      Option('quarter', 'This quarter', icon: Icons.view_quilt_rounded),
      Option('year', 'This year', icon: Icons.calendar_today_rounded),
      Option('custom', 'Custom range…', icon: Icons.date_range_rounded),
      Option('all', 'All time', icon: Icons.all_inclusive_rounded),
    ]);
    if (r == null || !mounted) return;
    if (r.value == 'custom') {
      final now = DateTime.now();
      final range = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime(now.year + 1, 12, 31),
        initialDateRange: _start != null && _end != null ? DateTimeRange(start: _start!, end: _end!) : null,
      );
      if (range == null) return;
      _start = range.start;
      _end = range.end;
    }
    setState(() => _period = r.value);
    _refresh();
  }

  String get _periodLabel {
    switch (_period) {
      case 'month':
        return 'This month';
      case 'quarter':
        return 'This quarter';
      case 'year':
        return 'This year';
      case 'custom':
        return _start == null ? 'Custom' : '${Fmt.dayShort(_start)} – ${Fmt.date(_end)}';
      default:
        return 'All time';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Employee activity')),
      body: Column(
        children: [
          FilterBar(children: [
            FilterPill(
                label: _user?.fullName ?? 'Choose employee',
                icon: Icons.person_search_rounded,
                active: _user != null,
                onTap: _chooseUser),
            FilterPill(label: _periodLabel, icon: Icons.date_range_rounded, active: true, onTap: _choosePeriod),
            FilterPill(
              label: _project?.name ?? 'All projects',
              icon: Icons.folder_open_rounded,
              active: _project != null,
              onTap: _chooseProject,
              onClear: () {
                setState(() => _project = null);
                _refresh();
              },
            ),
          ]),
          Expanded(
            child: _user == null
                ? EmptyState(
                    icon: Icons.person_search_rounded,
                    title: 'Choose an employee',
                    message: 'See their hours, projects and entries for any period.',
                    actionLabel: 'Choose employee',
                    onAction: _chooseUser,
                  )
                : PagedList<Map<String, dynamic>>(
                    key: _listKey,
                    fetch: _fetch,
                    headerBuilder: (ctx, first) {
                      if (first == null) return const SizedBox.shrink();
                      final raw = first.raw;
                      final total = asDouble(raw['total_logged_hours']);
                      final types = asList(raw['task_type_hours']).map((e) => asMap(e)).toList();
                      final s = asDate(raw['start_date']);
                      final e = asDate(raw['end_date']);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ReportSummary(
                            title: _user!.fullName,
                            subtitle: s == null ? 'All time' : '${Fmt.date(s)} – ${Fmt.date(e)}',
                            tiles: [
                              StatTile(label: 'Logged hours', value: Fmt.hours(total), icon: Icons.timer_rounded),
                              StatTile(
                                  label: 'Entries',
                                  value: '${asInt(raw['total_entries'])}',
                                  icon: Icons.list_alt_rounded,
                                  tone: Tone.info),
                              StatTile(
                                  label: 'Projects',
                                  value: '${asInt(raw['distinct_project_count'])}',
                                  icon: Icons.folder_rounded,
                                  tone: Tone.warning),
                              StatTile(
                                  label: 'Approved',
                                  value: Fmt.percent(asDouble(raw['approved_percent'])),
                                  icon: Icons.verified_rounded,
                                  tone: Tone.success),
                            ],
                          ),
                          if (types.isNotEmpty)
                            AppCard(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              child: Column(
                                children: [
                                  for (final t in types)
                                    BarRow(
                                      label: taskTypeLabel(asString(t['type'])),
                                      valueText: Fmt.hours(asDouble(t['hours'])),
                                      ratio: total > 0 ? asDouble(t['hours']) / total : 0,
                                      color: taskTypeTone(asString(t['type'])).fg,
                                    ),
                                ],
                              ),
                            ),
                          const SectionTitle('Entries'),
                        ],
                      );
                    },
                    itemBuilder: (ctx, r, i) => EntryTile(
                      entry: TimesheetEntry.fromJson({
                        ...r,
                        'project': {'id': 0, 'name': r['project_name']},
                      }),
                    ),
                    empty: const EmptyState(icon: Icons.inbox_rounded, title: 'No entries in this period'),
                  ),
          ),
        ],
      ),
    );
  }
}
