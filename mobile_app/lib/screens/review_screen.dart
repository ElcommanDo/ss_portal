import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';
import 'my_timesheets_screen.dart';
import 'timesheet_detail_screen.dart';

/// views.timesheet — "Review Logs" for admins, managers and leaders (leaders see their team only).
class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

enum _Period { all, month, week, day }

class _ReviewScreenState extends State<ReviewScreen> {
  final _listKey = GlobalKey<PagedListState<DaySheet>>();
  bool _scheduled = false;
  UserBrief? _user;
  IdName? _team;
  IdName? _project;
  _Period _period = _Period.month;
  late DateTime _ref;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _ref = DateTime(now.year, now.month, 1);
  }

  Map<String, dynamic> _query(int page) {
    final q = <String, dynamic>{
      'page': page,
      'page_size': 20,
      'scheduled': _scheduled ? '1' : '0',
      'user_pk': _user?.id,
      'team_pk': _team?.id,
      'project_pk': _project?.id,
    };
    switch (_period) {
      case _Period.month:
        q['month_year'] = Fmt.isoMonth(_ref);
        break;
      case _Period.week:
        q['week_start_date'] = Fmt.iso(_ref);
        break;
      case _Period.day:
        q['work_date'] = Fmt.iso(_ref);
        break;
      case _Period.all:
        break;
    }
    return q;
  }

  Future<PageResult<DaySheet>> _fetch(int page) async {
    final data = await context.read<Session>().api.get('/review/timesheets/', query: _query(page));
    return PageResult.parse<DaySheet>(data, DaySheet.fromJson);
  }

  void _refresh() => _listKey.currentState?.refresh();

  String get _periodLabel {
    switch (_period) {
      case _Period.all:
        return 'All dates';
      case _Period.month:
        return Fmt.monthYear(_ref);
      case _Period.week:
        return 'Week of ${Fmt.dayShort(_ref)}';
      case _Period.day:
        return Fmt.date(_ref);
    }
  }

  Future<void> _choosePeriod() async {
    final r = await showOptionsSheet<_Period>(context, title: 'Period', selected: _period, options: const [
      Option(_Period.month, 'A month', icon: Icons.calendar_month_rounded),
      Option(_Period.week, 'A week (Sun → Sat)', icon: Icons.view_week_rounded),
      Option(_Period.day, 'A single day', icon: Icons.today_rounded),
      Option(_Period.all, 'All dates', icon: Icons.all_inclusive_rounded),
    ]);
    if (r == null || !mounted) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (r.value) {
      case _Period.all:
        setState(() => _period = _Period.all);
        break;
      case _Period.month:
        final m = await pickMonth(context, selected: _ref);
        if (m == null) return;
        setState(() {
          _period = _Period.month;
          _ref = m;
        });
        break;
      case _Period.week:
        final d = await pickDate(context, initial: today, first: DateTime(2020), last: today.add(const Duration(days: 365)),
            help: 'Pick any day of the week');
        if (d == null) return;
        setState(() {
          _period = _Period.week;
          _ref = d.subtract(Duration(days: d.weekday % 7)); // back to Sunday
        });
        break;
      case _Period.day:
        final d = await pickDate(context, initial: today, first: DateTime(2020), last: today.add(const Duration(days: 365)));
        if (d == null) return;
        setState(() {
          _period = _Period.day;
          _ref = d;
        });
        break;
    }
    _refresh();
  }

  Future<void> _chooseUser() async {
    try {
      final meta = await context.read<Session>().meta();
      if (!mounted) return;
      final r = await showOptionsSheet<int>(context,
          title: 'Employee',
          searchable: true,
          selected: _user?.id,
          options: [
            for (final u in meta.users)
              Option(u.id, u.fullName, subtitle: [u.username, if (u.team != null) u.team!].join(' • '), icon: Icons.person_rounded),
          ]);
      if (r == null) return;
      setState(() => _user = meta.users.firstWhere((u) => u.id == r.value));
      _refresh();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _chooseTeam() async {
    try {
      final meta = await context.read<Session>().meta();
      if (!mounted) return;
      final r = await showOptionsSheet<int>(context,
          title: 'Team',
          selected: _team?.id,
          options: [for (final t in meta.teams) Option(t.id, t.name.replaceAll('_', ' '), icon: Icons.groups_rounded)]);
      if (r == null) return;
      setState(() => _team = IdName(r.value, r.label));
      _refresh();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _chooseProject() async {
    try {
      final meta = await context.read<Session>().meta();
      if (!mounted) return;
      final r = await showOptionsSheet<int>(context,
          title: 'Project',
          searchable: true,
          selected: _project?.id,
          options: [for (final p in meta.projects) Option(p.id, p.name, icon: Icons.folder_rounded)]);
      if (r == null) return;
      setState(() => _project = IdName(r.value, r.label));
      _refresh();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _open(DaySheet d) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TimesheetDetailScreen(timesheetId: d.id, scheduled: _scheduled)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: canPop,
        title: const Text('Review timesheets'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Logged')),
                ButtonSegment(value: true, label: Text('Planned')),
              ],
              selected: {_scheduled},
              showSelectedIcon: false,
              onSelectionChanged: (s) {
                setState(() => _scheduled = s.first);
                _refresh();
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          FilterBar(children: [
            FilterPill(label: _periodLabel, icon: Icons.date_range_rounded, active: _period != _Period.all, onTap: _choosePeriod,
                onClear: () {
                  setState(() => _period = _Period.all);
                  _refresh();
                }),
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
              label: _team?.name ?? 'Team',
              icon: Icons.groups_rounded,
              active: _team != null,
              onTap: _chooseTeam,
              onClear: () {
                setState(() => _team = null);
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
          ]),
          Expanded(
            child: PagedList<DaySheet>(
              key: _listKey,
              fetch: _fetch,
              headerBuilder: (ctx, first) {
                if (first == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Day sheets',
                          value: '${first.count}',
                          icon: Icons.event_note_rounded,
                          tone: Tone.brand,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          label: _scheduled ? 'Planned hours' : 'Total hours',
                          value: Fmt.hours(asDouble(first.raw['sum_hours'])),
                          icon: Icons.timer_rounded,
                          tone: Tone.info,
                        ),
                      ),
                    ],
                  ),
                );
              },
              itemBuilder: (ctx, d, i) => DaySheetCard(day: d, showUser: true, scheduled: _scheduled, onTap: () => _open(d)),
              empty: const EmptyState(
                icon: Icons.fact_check_outlined,
                title: 'No timesheets match',
                message: 'Try another period or clear the filters.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
