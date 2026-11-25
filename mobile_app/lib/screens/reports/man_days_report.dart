import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../widgets/report_kit.dart';

/// views.reports_daily_man_days (+ export_man_days_pdf)
class ManDaysReportScreen extends StatefulWidget {
  const ManDaysReportScreen({super.key});

  @override
  State<ManDaysReportScreen> createState() => _ManDaysReportScreenState();
}

class _ManDaysReportScreenState extends State<ManDaysReportScreen> {
  final _listKey = GlobalKey<PagedListState<Map<String, dynamic>>>();
  DateTime? _start;
  DateTime? _end;
  UserBrief? _user;
  IdName? _project;
  String _location = '';

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
        'user_pk': _user?.id,
        'project_pk': _project?.id,
        'work_location': _location,
      };

  Future<PageResult<Map<String, dynamic>>> _fetch(int page) async {
    final data = await context.read<Session>().api.get('/reports/man-days/', query: {..._filters, 'page': page, 'page_size': 40});
    return PageResult.parse<Map<String, dynamic>>(data, (m) => m);
  }

  void _refresh() => _listKey.currentState?.refresh();

  Future<void> _chooseRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _start != null && _end != null ? DateTimeRange(start: _start!, end: _end!) : null,
      helpText: 'Report period',
    );
    if (r == null) return;
    setState(() {
      _start = r.start;
      _end = r.end;
    });
    _refresh();
  }

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

  Future<void> _chooseLocation() async {
    final r = await showOptionsSheet<String>(context, title: 'Work location', selected: _location, options: const [
      Option('', 'All locations', icon: Icons.public_rounded),
      Option('abroad', 'Onsite abroad', icon: Icons.flight_takeoff_rounded),
      Option('remote', 'Remotely / office', icon: Icons.home_work_rounded),
    ]);
    if (r == null) return;
    setState(() => _location = r.value);
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final rangeLabel = _start == null ? 'All dates' : '${Fmt.dayShort(_start)} – ${Fmt.date(_end)}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Man-days & overtime'),
        actions: [
          IconButton(
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.danger),
            onPressed: () => downloadAndOpenPdf(context,
                path: '/reports/man-days/pdf/',
                query: _filters,
                fileName: 'Man_Days_Report_${Fmt.iso(DateTime.now())}.pdf'),
          ),
        ],
      ),
      body: Column(
        children: [
          FilterBar(children: [
            FilterPill(
              label: rangeLabel,
              icon: Icons.date_range_rounded,
              active: _start != null,
              onTap: _chooseRange,
              onClear: () {
                setState(() {
                  _start = null;
                  _end = null;
                });
                _refresh();
              },
            ),
            FilterPill(
              label: _user?.fullName ?? 'Employee',
              icon: Icons.person_search_rounded,
              active: _user != null,
              onTap: _chooseUser,
              onClear: () {
                setState(() => _user = null);
                _refresh();
              },
            ),
            FilterPill(
              label: _project?.name ?? 'Project',
              icon: Icons.folder_open_rounded,
              active: _project != null,
              onTap: _chooseProject,
              onClear: () {
                setState(() => _project = null);
                _refresh();
              },
            ),
            FilterPill(
              label: _location == 'abroad' ? 'Abroad' : (_location == 'remote' ? 'Remote / office' : 'Location'),
              icon: Icons.place_rounded,
              active: _location.isNotEmpty,
              onTap: _chooseLocation,
              onClear: () {
                setState(() => _location = '');
                _refresh();
              },
            ),
          ]),
          Expanded(
            child: PagedList<Map<String, dynamic>>(
              key: _listKey,
              fetch: _fetch,
              headerBuilder: (ctx, first) {
                if (first == null) return const SizedBox.shrink();
                final t = asMap(first.raw['totals']);
                return ReportSummary(
                  title: 'Daily man-days',
                  subtitle: '$rangeLabel • excludes study & scheduled',
                  tiles: [
                    StatTile(label: 'Logged hours', value: Fmt.hours(asDouble(t['hours'])), icon: Icons.timer_rounded),
                    StatTile(
                        label: 'Man-days (8h)',
                        value: Fmt.dec(asDouble(t['man_days'])),
                        icon: Icons.badge_rounded,
                        tone: Tone.info,
                        caption: 'Hours before 5 PM ÷ 8'),
                    StatTile(
                        label: 'Overtime after 5 PM',
                        value: Fmt.hours(asDouble(t['ot'])),
                        icon: Icons.nightlight_round,
                        tone: Tone.warning),
                    StatTile(
                        label: 'Onsite abroad',
                        value: Fmt.hours(asDouble(t['abroad'])),
                        icon: Icons.flight_takeoff_rounded,
                        tone: Tone.success),
                  ],
                );
              },
              itemBuilder: (ctx, row, i) => _ManDayRow(row: row),
              empty: const EmptyState(icon: Icons.calendar_view_day_outlined, title: 'No logged work for these filters'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManDayRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ManDayRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final total = asDouble(row['total_hours']);
    final ot = asDouble(row['overtime']);
    final abroad = asDouble(row['abroad_hours']);
    final manDay = asDouble(row['work_hours_for_manday']);
    final projects = asList(row['projects']).map((e) => asMap(e)).toList();
    final date = asDate(row['work_date']);
    final tone = Tone.forPercent(manDay / 8 * 100);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(asString(row['user_full_name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.text, fontSize: 15)),
                    Text(Fmt.day(date), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Fmt.hm(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: AppColors.indigo)),
                  Text('Man-day ${asString(row['man_day_display'])}',
                      style: TextStyle(color: tone.fg, fontSize: 12, fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ProgressLine(value: manDay / 8, color: tone.fg, height: 6),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (ot > 0) StatusChip('OT ${Fmt.hm(ot)}', Tone.warning, dense: true),
              if (abroad > 0)
                StatusChip('Abroad ${Fmt.hm(abroad)}',
                    const Tone(AppColors.indigo, AppColors.indigoBg, Icons.flight_takeoff_rounded),
                    dense: true),
              for (final p in projects)
                StatusChip('${asString(p['name'])} • ${Fmt.hm(asDouble(p['hours']))}', Tone.neutral,
                    dense: true, showIcon: false),
            ],
          ),
        ],
      ),
    );
  }
}
