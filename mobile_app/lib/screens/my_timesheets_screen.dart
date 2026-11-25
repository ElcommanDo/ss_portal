import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';
import 'entry_form_screen.dart';
import 'timesheet_detail_screen.dart';

/// views.user_timesheets — my days (logged work) and my scheduled plans.
class MyTimesheetsScreen extends StatefulWidget {
  const MyTimesheetsScreen({super.key});

  @override
  State<MyTimesheetsScreen> createState() => _MyTimesheetsScreenState();
}

class _MyTimesheetsScreenState extends State<MyTimesheetsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final _loggedKey = GlobalKey<PagedListState<DaySheet>>();
  final _scheduledKey = GlobalKey<PagedListState<DaySheet>>();
  DateTime? _month;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<PageResult<DaySheet>> _fetch(int page, bool scheduled) async {
    final api = context.read<Session>().api;
    final data = await api.get('/my/timesheets/', query: {
      'scheduled': scheduled ? '1' : '0',
      'page': page,
      'page_size': 20,
      'month': _month == null ? null : Fmt.isoMonth(_month!),
    });
    return PageResult.parse<DaySheet>(data, DaySheet.fromJson);
  }

  void _refreshAll() {
    _loggedKey.currentState?.refresh();
    _scheduledKey.currentState?.refresh();
  }

  Future<void> _newEntry() async {
    final scheduled = _tabs.index == 1;
    final saved = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => EntryFormScreen(scheduled: scheduled)));
    if (saved == true) _refreshAll();
  }

  Future<void> _open(DaySheet d, bool scheduled) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => TimesheetDetailScreen(timesheetId: d.id, scheduled: scheduled)),
    );
    if (mounted) _refreshAll();
  }

  Future<void> _chooseMonth() async {
    final m = await pickMonth(context, selected: _month);
    if (m == null) return;
    setState(() => _month = m);
    _refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: canPop,
        title: const Text('My timesheets'),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.indigo,
          unselectedLabelColor: AppColors.muted,
          indicatorColor: AppColors.indigo,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Logged work', icon: Icon(Icons.task_alt_rounded, size: 20)),
            Tab(text: 'Scheduled', icon: Icon(Icons.event_rounded, size: 20)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-my-timesheets',
        tooltip: 'New entry',
        onPressed: _newEntry,
        child: const Icon(Icons.add_rounded),
      ),
      body: Column(
        children: [
          FilterBar(children: [
            FilterPill(
              label: _month == null ? 'All months' : Fmt.monthYear(_month),
              icon: Icons.calendar_month_rounded,
              active: _month != null,
              onTap: _chooseMonth,
              onClear: () {
                setState(() => _month = null);
                _refreshAll();
              },
            ),
          ]),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                PagedList<DaySheet>(
                  key: _loggedKey,
                  fetch: (p) => _fetch(p, false),
                  itemBuilder: (ctx, d, i) => DaySheetCard(day: d, onTap: () => _open(d, false)),
                  empty: EmptyState(
                    icon: Icons.task_alt_rounded,
                    title: 'No logged work',
                    message: _month == null ? 'Your logged days will appear here.' : 'Nothing logged in this month.',
                    actionLabel: 'Log work',
                    onAction: _newEntry,
                  ),
                ),
                PagedList<DaySheet>(
                  key: _scheduledKey,
                  fetch: (p) => _fetch(p, true),
                  itemBuilder: (ctx, d, i) => DaySheetCard(day: d, scheduled: true, onTap: () => _open(d, true)),
                  empty: const EmptyState(
                    icon: Icons.event_available_rounded,
                    title: 'No scheduled tasks',
                    message: 'Plan upcoming work with the + button.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One day card (used by "My timesheets" and "Review").
class DaySheetCard extends StatelessWidget {
  final DaySheet day;
  final VoidCallback? onTap;
  final bool scheduled;
  final bool showUser;

  const DaySheetCard({super.key, required this.day, this.onTap, this.scheduled = false, this.showUser = false});

  @override
  Widget build(BuildContext context) {
    final d = day.date;
    final tone = scheduled ? Tone.info : Tone.forPercent(day.totalHours / 8 * 100);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: scheduled ? AppColors.cyanBg : AppColors.indigoBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(Fmt.weekdayShort(d).toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: scheduled ? AppColors.blue : AppColors.indigo,
                        letterSpacing: 1)),
                Text(d == null ? '—' : '${d.day}',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text)),
                Text(d == null ? '' : Fmt.monthYear(d).substring(0, 3),
                    style: const TextStyle(fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showUser && day.user != null) ...[
                  Text(day.user!.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text)),
                  const SizedBox(height: 2),
                ],
                Text(
                  scheduled ? 'Planned tasks' : Fmt.hm(day.totalHours),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: showUser ? 14 : 18,
                    color: showUser ? AppColors.indigo : AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  day.projects.isNotEmpty
                      ? day.projects.join(' • ')
                      : '${day.tasksCount} task${day.tasksCount == 1 ? '' : 's'} • ${Fmt.date(d)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                if (!scheduled) ...[
                  const SizedBox(height: 8),
                  ProgressLine(value: day.totalHours / 8, color: tone.fg, height: 6),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (day.abroadHours > 0)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Icon(Icons.flight_takeoff_rounded, size: 18, color: AppColors.indigo),
                ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.subtle),
            ],
          ),
        ],
      ),
    );
  }
}
