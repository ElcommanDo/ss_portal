import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';
import 'common.dart';

Tone taskTypeTone(String type) {
  final t = type.toLowerCase();
  if (t.contains('pre')) return const Tone(AppColors.warning, AppColors.warningBg, Icons.handshake_rounded);
  if (t.contains('stud') || t.contains('train')) {
    return const Tone(AppColors.success, AppColors.successBg, Icons.school_rounded);
  }
  return const Tone(AppColors.info, AppColors.infoBg, Icons.work_rounded);
}

String taskTypeLabel(String type) {
  if (type == 'study') return 'Study / Training';
  return type;
}

class EntryTile extends StatelessWidget {
  final TimesheetEntry entry;
  final VoidCallback? onTap;
  final bool showDate;
  final bool showUser;

  const EntryTile({super.key, required this.entry, this.onTap, this.showDate = true, this.showUser = false});

  @override
  Widget build(BuildContext context) {
    final tone = taskTypeTone(entry.taskType);
    final hasTimes = entry.timeStart != null && entry.timeEnd != null;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(tone.icon, fg: tone.fg, bg: tone.bg, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.project?.name ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.isScheduled ? 'Planned' : Fmt.hm(entry.hours),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: entry.isScheduled ? AppColors.blue : AppColors.indigo,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  entry.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 13.5, height: 1.3),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusChip(taskTypeLabel(entry.taskType), tone, dense: true, showIcon: false),
                    if (showDate && entry.workDate != null)
                      _meta(Icons.calendar_today_rounded, Fmt.dayShort(entry.workDate)),
                    if (hasTimes) _meta(Icons.access_time_rounded, '${Fmt.time12(entry.timeStart)} – ${Fmt.time12(entry.timeEnd)}'),
                    if (entry.onsiteAbroad)
                      const StatusChip('Abroad', Tone(AppColors.indigo, AppColors.indigoBg, Icons.flight_takeoff_rounded),
                          dense: true),
                    if (entry.onsiteEgypt)
                      const StatusChip('Onsite EG', Tone(AppColors.indigo, AppColors.indigoBg, Icons.apartment_rounded),
                          dense: true),
                    if (showUser && entry.user != null) _meta(Icons.person_rounded, entry.user!.fullName),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.subtle),
        const SizedBox(width: 3),
        Text(text, style: const TextStyle(fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
