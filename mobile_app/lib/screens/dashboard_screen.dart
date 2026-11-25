import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/entry_tile.dart';
import 'entry_form_screen.dart';
import 'home_shell.dart';
import 'kpi_screen.dart';

class DashboardData {
  final Map<String, dynamic> raw;
  final DateTime? today;
  final double weeklyHours;
  final double weeklyTarget;
  final double todayHours;
  final double monthHours;
  final List<MapEntry<DateTime, double>> weekDays;
  final String wisdom;
  final int openMissions;
  final int pendingVacations;
  final List<TimesheetEntry> recent;
  final List<TimesheetEntry> upcoming;

  DashboardData(this.raw)
      : today = asDate(raw['today']),
        weeklyHours = asDouble(raw['weekly_hours']),
        weeklyTarget = asDouble(raw['weekly_target']) == 0 ? 40 : asDouble(raw['weekly_target']),
        todayHours = asDouble(raw['today_hours']),
        monthHours = asDouble(raw['month_hours']),
        weekDays = asList(raw['week_days'])
            .map((e) => asMap(e))
            .where((m) => asDate(m['date']) != null)
            .map((m) => MapEntry(asDate(m['date'])!, asDouble(m['hours'])))
            .toList(),
        wisdom = asString(raw['daily_wisdom']),
        openMissions = asInt(raw['open_missions']),
        pendingVacations = asInt(raw['pending_vacations']),
        recent = asList(raw['recent_entries']).map((e) => TimesheetEntry.fromJson(asMap(e))).toList(),
        upcoming = asList(raw['upcoming_scheduled']).map((e) => TimesheetEntry.fromJson(asMap(e))).toList();
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _loaderKey = GlobalKey<LoaderState<DashboardData>>();

  Future<DashboardData> _load() async {
    final api = context.read<Session>().api;
    return DashboardData(asMap(await api.get('/dashboard/')));
  }

  Future<void> _openForm({TimesheetEntry? entry, bool scheduled = false}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => EntryFormScreen(entry: entry, scheduled: scheduled)),
    );
    if (saved == true) _loaderKey.currentState?.reload();
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    final firstName = (user?.fullName ?? '').trim().split(RegExp(r'\s+')).first;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-dashboard',
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Log time', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        bottom: false,
        child: Loader<DashboardData>(
          key: _loaderKey,
          load: _load,
          builder: (context, d, reload) {
            final pad = pagePadding(context);
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(pad, 12, pad, 110),
                children: [
                  ResponsiveCenter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TopBar(name: user?.fullName ?? '', initials: user?.initials ?? '?', role: user?.roleLabel ?? ''),
                        const SizedBox(height: 16),
                        _WeekBanner(
                          greeting: '${_greeting()}${firstName.isEmpty ? '' : ', $firstName'}',
                          data: d,
                          onLog: () => _openForm(),
                          onSchedule: () => _openForm(scheduled: true),
                        ),
                        const SizedBox(height: 16),
                        TileGrid(
                          minTileWidth: 150,
                          children: session.caps.staffDashboard ? _staffTiles(context, d) : _employeeTiles(context, d),
                        ),
                        if (d.wisdom.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          _WisdomCard(text: d.wisdom),
                        ],
                        if (d.upcoming.isNotEmpty) ...[
                          SectionTitle('Upcoming scheduled',
                              actionLabel: 'All', onAction: () => HomeShell.goTo(context, 'timesheets')),
                          for (final e in d.upcoming)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: EntryTile(
                                entry: e,
                                onTap: () => _openForm(entry: e),
                              ),
                            ),
                        ],
                        SectionTitle('Recent activity',
                            actionLabel: 'History', onAction: () => HomeShell.goTo(context, 'timesheets')),
                        if (d.recent.isEmpty)
                          AppCard(
                            child: EmptyState(
                              icon: Icons.timer_outlined,
                              title: 'No work logged yet',
                              message: 'Tap “Log time” to add your first entry.',
                              actionLabel: 'Log time',
                              onAction: () => _openForm(),
                            ),
                          )
                        else
                          for (final e in d.recent)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: EntryTile(entry: e, onTap: () => _openForm(entry: e)),
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
    );
  }

  List<Widget> _employeeTiles(BuildContext context, DashboardData d) {
    return [
      StatTile(
        label: 'Logged today',
        value: Fmt.hm(d.todayHours),
        icon: Icons.today_rounded,
        tone: Tone.info,
        onTap: () => HomeShell.goTo(context, 'timesheets'),
      ),
      StatTile(
        label: 'This month',
        value: Fmt.hours(d.monthHours),
        icon: Icons.calendar_month_rounded,
        tone: Tone.brand,
        onTap: () => HomeShell.goTo(context, 'timesheets'),
      ),
      StatTile(
        label: 'Open missions',
        value: '${d.openMissions}',
        icon: Icons.flag_rounded,
        tone: d.openMissions > 0 ? Tone.warning : Tone.success,
        onTap: () => HomeShell.goTo(context, 'missions'),
      ),
      StatTile(
        label: 'My KPIs',
        value: 'View',
        icon: Icons.emoji_events_rounded,
        tone: Tone.success,
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const KpiScreen())),
      ),
    ];
  }

  List<Widget> _staffTiles(BuildContext context, DashboardData d) {
    final caps = context.watch<Session>().caps;
    return [
      StatTile(
        label: 'Entries today (all)',
        value: '${asInt(d.raw['entries_today_count'])}',
        icon: Icons.playlist_add_check_rounded,
        tone: Tone.info,
        onTap: caps.reviewTimesheets ? () => HomeShell.goTo(context, 'review') : null,
      ),
      StatTile(
        label: 'Active users',
        value: '${asInt(d.raw['active_users_count'])}',
        icon: Icons.groups_rounded,
        tone: Tone.brand,
      ),
      StatTile(
        label: 'Missions I assigned (open)',
        value: '${asInt(d.raw['missions_created_open'])}',
        icon: Icons.flag_rounded,
        tone: Tone.warning,
        onTap: () => HomeShell.goTo(context, 'missions'),
      ),
      StatTile(
        label: 'Leave requests waiting',
        value: '${asInt(d.raw['vacations_waiting'])}',
        icon: Icons.beach_access_rounded,
        tone: asInt(d.raw['vacations_waiting']) > 0 ? Tone.danger : Tone.success,
        onTap: () => HomeShell.goTo(context, 'vacations'),
      ),
    ];
  }
}

class _TopBar extends StatelessWidget {
  final String name;
  final String initials;
  final String role;
  const _TopBar({required this.name, required this.initials, required this.role});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170, maxHeight: 40),
              child: Image.asset('assets/images/logo.png', fit: BoxFit.contain),
            ),
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: () => HomeShell.goTo(context, 'more'),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Avatar(initials, size: 42, bg: AppColors.indigo, fg: Colors.white),
          ),
        ),
      ],
    );
  }
}

class _WeekBanner extends StatelessWidget {
  final String greeting;
  final DashboardData data;
  final VoidCallback onLog;
  final VoidCallback onSchedule;

  const _WeekBanner({required this.greeting, required this.data, required this.onLog, required this.onSchedule});

  @override
  Widget build(BuildContext context) {
    final pct = data.weeklyTarget > 0 ? data.weeklyHours / data.weeklyTarget : 0.0;
    final maxDay = data.weekDays.fold<double>(8, (m, e) => e.value > m ? e.value : m);
    final today = data.today;
    return GradientBanner(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(greeting,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(Fmt.day(today ?? DateTime.now()), style: const TextStyle(color: AppColors.overlayWhite70, fontSize: 13)),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('THIS WEEK',
                        style: TextStyle(
                            color: AppColors.overlayWhite70, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: Fmt.dec(data.weeklyHours),
                              style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800),
                            ),
                            TextSpan(
                              text: ' / ${Fmt.dec(data.weeklyTarget)} h',
                              style: const TextStyle(color: AppColors.overlayWhite70, fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.overlayWhite20, borderRadius: BorderRadius.circular(20)),
                child: Text('${(pct * 100).clamp(0, 999).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0).toDouble(),
              minHeight: 8,
              backgroundColor: AppColors.overlayWhite20,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          if (data.weekDays.length == 7) ...[
            const SizedBox(height: 18),
            SizedBox(
              height: 78,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final day in data.weekDays)
                    Expanded(
                      child: _DayBar(
                        label: Fmt.weekdayShort(day.key).substring(0, 1),
                        hours: day.value,
                        ratio: maxDay > 0 ? day.value / maxDay : 0,
                        isToday: today != null &&
                            day.key.year == today.year &&
                            day.key.month == today.month &&
                            day.key.day == today.day,
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onLog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.indigo,
                    minimumSize: const Size(0, 46),
                  ),
                  icon: const Icon(Icons.timer_rounded, size: 20),
                  label: const Text('Log work'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSchedule,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.overlayWhite70, width: 1.4),
                    minimumSize: const Size(0, 46),
                  ),
                  icon: const Icon(Icons.event_available_rounded, size: 20),
                  label: const Text('Schedule'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayBar extends StatelessWidget {
  final String label;
  final double hours;
  final double ratio;
  final bool isToday;

  const _DayBar({required this.label, required this.hours, required this.ratio, required this.isToday});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: Fmt.hm(hours),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: ratio <= 0 ? 0.06 : ratio.clamp(0.06, 1.0).toDouble(),
                child: Container(
                  width: 14,
                  decoration: BoxDecoration(
                    color: isToday ? Colors.white : (hours > 0 ? AppColors.overlayWhite70 : AppColors.overlayWhite20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                color: isToday ? Colors.white : AppColors.overlayWhite70,
                fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12,
              )),
        ],
      ),
    );
  }
}

class _WisdomCard extends StatelessWidget {
  final String text;
  const _WisdomCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const IconBadge(Icons.format_quote_rounded, fg: AppColors.blue, bg: AppColors.cyanBg, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Daily wisdom',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.muted, letterSpacing: .5)),
                const SizedBox(height: 6),
                Text(
                  text,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 15.5, height: 1.6, color: AppColors.text, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
