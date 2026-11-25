import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../widgets/common.dart';
import 'activity_report.dart';
import 'costs_report.dart';
import 'last_timesheet_report.dart';
import 'man_days_report.dart';
import 'monthly_report.dart';
import 'utilization_report.dart';

class _ReportDef {
  final String title;
  final String description;
  final IconData icon;
  final Color fg;
  final Color bg;
  final Widget Function() page;
  const _ReportDef(this.title, this.description, this.icon, this.fg, this.bg, this.page);
}

/// Same six reports as the portal's reports.html hub.
class ReportsHub extends StatelessWidget {
  const ReportsHub({super.key});

  @override
  Widget build(BuildContext context) {
    final reports = <_ReportDef>[
      _ReportDef('Man-days & overtime', 'Daily hours per employee, overtime after 5 PM, onsite abroad',
          Icons.calendar_view_day_rounded, AppColors.indigo, AppColors.indigoBg, () => const ManDaysReportScreen()),
      _ReportDef('Last timesheet', 'Who logged recently, weekly 40h and monthly target compliance',
          Icons.history_toggle_off_rounded, AppColors.danger, AppColors.dangerBg, () => const LastTimesheetReportScreen()),
      _ReportDef('Monthly man-days', 'Main (Sun–Thu) vs extra (Fri–Sat) hours against the monthly target',
          Icons.calendar_month_rounded, AppColors.blue, AppColors.cyanBg, () => const MonthlyReportScreen()),
      _ReportDef('Utilization', 'Logged vs expected hours (approved leave excluded)', Icons.speed_rounded,
          AppColors.success, AppColors.successBg, () => const UtilizationReportScreen()),
      _ReportDef('Employee activity', 'One employee’s entries, projects and task types', Icons.query_stats_rounded,
          AppColors.warning, AppColors.warningBg, () => const ActivityReportScreen()),
      _ReportDef('Project costs', 'External costs recorded on projects', Icons.request_quote_rounded, AppColors.info,
          AppColors.infoBg, () => const CostsReportScreen()),
    ];
    final pad = pagePadding(context);
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: canPop, title: const Text('Reports')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, 4, pad, 32),
        children: [
          ResponsiveCenter(
            maxWidth: 980,
            child: TileGrid(
              minTileWidth: 300,
              minColumns: 1,
              children: [
                for (final r in reports)
                  AppCard(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => r.page())),
                    child: Row(
                      children: [
                        IconBadge(r.icon, fg: r.fg, bg: r.bg, size: 52),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.title,
                                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.text)),
                              const SizedBox(height: 4),
                              Text(r.description,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.muted, fontSize: 13, height: 1.35)),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: AppColors.subtle),
                      ],
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
