import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/entry_tile.dart';
import 'entry_form_screen.dart';

class _DayDetail {
  final DateTime? date;
  final UserBrief? user;
  final double total;
  final double abroad;
  final bool isOwner;
  final List<TimesheetEntry> entries;

  _DayDetail(Map<String, dynamic> j)
      : date = asDate(asMap(j['timesheet'])['date']),
        user = asMap(j['timesheet'])['user'] == null ? null : UserBrief.fromJson(asMap(asMap(j['timesheet'])['user'])),
        total = asDouble(j['total_hours']),
        abroad = asDouble(j['abroad_hours']),
        isOwner = asBool(j['is_owner']),
        entries = asList(j['entries']).map((e) => TimesheetEntry.fromJson(asMap(e))).toList();
}

/// All entries of one day (views.my_timesheet_entries / views.timesheet_entries).
/// The caller refreshes its list when this screen closes.
class TimesheetDetailScreen extends StatefulWidget {
  final int timesheetId;
  final bool scheduled;

  const TimesheetDetailScreen({super.key, required this.timesheetId, this.scheduled = false});

  @override
  State<TimesheetDetailScreen> createState() => _TimesheetDetailScreenState();
}

class _TimesheetDetailScreenState extends State<TimesheetDetailScreen> {
  final _loader = GlobalKey<LoaderState<_DayDetail>>();

  Future<_DayDetail> _load() async {
    final data = await context.read<Session>().api.get('/timesheets/${widget.timesheetId}/entries/',
        query: {'scheduled': widget.scheduled ? '1' : '0'});
    return _DayDetail(asMap(data));
  }

  Future<void> _edit(TimesheetEntry e) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => EntryFormScreen(entry: e)));
    if (saved == true) _loader.currentState?.reload();
  }

  void _showReadOnly(TimesheetEntry e) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(e.project?.name ?? '—',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
            const SizedBox(height: 12),
            InfoRow(Icons.category_rounded, 'Type', taskTypeLabel(e.taskType)),
            InfoRow(Icons.calendar_today_rounded, 'Date', Fmt.day(e.workDate)),
            if (e.timeStart != null)
              InfoRow(Icons.access_time_rounded, 'Time', '${Fmt.time12(e.timeStart)} – ${Fmt.time12(e.timeEnd)}'),
            InfoRow(Icons.hourglass_bottom_rounded, 'Hours', e.isScheduled ? 'Planned' : '${Fmt.hm(e.hours)} (${Fmt.dec(e.hours)} h)'),
            InfoRow(Icons.place_rounded, 'Location', e.onsiteAbroad ? 'Onsite abroad' : (e.onsiteEgypt ? 'Onsite Egypt' : 'Office / remote')),
            InfoRow(Icons.flag_rounded, 'Status', e.statusLabel),
            const Divider(height: 28),
            const Text('Description', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
            const SizedBox(height: 6),
            SelectableText(e.description, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.text)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Scaffold(
        appBar: AppBar(
          title: Text(widget.scheduled ? 'Scheduled day' : 'Day details'),
        ),
        body: Loader<_DayDetail>(
          key: _loader,
          load: _load,
          builder: (context, d, reload) {
            return RefreshIndicator(
              onRefresh: reload,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 32),
                children: [
                  ResponsiveCenter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        GradientBanner(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (d.user != null && !d.isOwner) ...[
                                Row(
                                  children: [
                                    Avatar(d.user!.initials, size: 34, bg: AppColors.overlayWhite20, fg: Colors.white),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(d.user!.fullName,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ],
                              Text(Fmt.weekday(d.date),
                                  style: const TextStyle(color: AppColors.overlayWhite70, fontWeight: FontWeight.w600)),
                              Text(Fmt.date(d.date),
                                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  _pill(Icons.list_alt_rounded, '${d.entries.length} task${d.entries.length == 1 ? '' : 's'}'),
                                  if (!widget.scheduled) _pill(Icons.timer_rounded, Fmt.hm(d.total)),
                                  if (d.abroad > 0) _pill(Icons.flight_takeoff_rounded, 'Abroad ${Fmt.hm(d.abroad)}'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (d.entries.isEmpty)
                          const EmptyState(icon: Icons.inbox_rounded, title: 'No entries for this day')
                        else
                          for (final e in d.entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: EntryTile(
                                entry: e,
                                showDate: false,
                                onTap: () => d.isOwner ? _edit(e) : _showReadOnly(e),
                              ),
                            ),
                        if (d.isOwner && d.entries.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              widget.scheduled
                                  ? 'Tap a planned task to log it as done, or delete it.'
                                  : 'Tap an entry to edit or delete it.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.subtle, fontSize: 12.5),
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
    );
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: AppColors.overlayWhite20, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}
