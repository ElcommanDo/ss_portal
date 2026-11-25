import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';

/// views.MyKPIView — my quarterly KPI scores.
class KpiScreen extends StatefulWidget {
  const KpiScreen({super.key});

  @override
  State<KpiScreen> createState() => _KpiScreenState();
}

class _KpiScreenState extends State<KpiScreen> {
  late int _year;
  late int _quarterMonth;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _quarterMonth = ((now.month - 1) ~/ 3 + 1) * 3;
  }

  Future<Map<String, dynamic>> _load() async {
    return asMap(await context.read<Session>().api.get('/kpi/my/', query: {'year': _year, 'quarter_month': _quarterMonth}));
  }

  Future<void> _chooseYear() async {
    final now = DateTime.now().year;
    final r = await showOptionsSheet<int>(context, title: 'Year', selected: _year, options: [
      for (int y = now; y >= now - 3; y--) Option(y, '$y', icon: Icons.calendar_today_rounded),
    ]);
    if (r != null) {
      setState(() {
        _year = r.value;
        _version++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Scaffold(
      appBar: AppBar(title: const Text('My KPIs')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
            child: ResponsiveCenter(
              child: Row(
                children: [
                  FilterPill(label: '$_year', icon: Icons.calendar_today_rounded, active: true, onTap: _chooseYear),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 3, label: Text('Q1')),
                        ButtonSegment(value: 6, label: Text('Q2')),
                        ButtonSegment(value: 9, label: Text('Q3')),
                        ButtonSegment(value: 12, label: Text('Q4')),
                      ],
                      selected: {_quarterMonth},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() {
                        _quarterMonth = s.first;
                        _version++;
                      }),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Loader<Map<String, dynamic>>(
              key: ValueKey('kpi-$_year-$_quarterMonth-$_version'),
              load: _load,
              builder: (context, data, reload) {
                final rows = asList(data['kpis']).map((e) => asMap(e)).toList();
                final total = asDouble(data['total_score']);
                final groups = <String, List<Map<String, dynamic>>>{};
                for (final r in rows) {
                  groups.putIfAbsent(asString(r['category'], 'General'), () => []).add(r);
                }
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
                            _ScoreBanner(total: total, label: asString(data['quarter_label']), year: _year),
                            if (rows.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: EmptyState(
                                  icon: Icons.emoji_events_outlined,
                                  title: 'No KPIs for this period yet',
                                  message: 'Your manager has not evaluated this quarter.',
                                ),
                              ),
                            for (final entry in groups.entries) ...[
                              SectionTitle(entry.key),
                              for (final r in entry.value)
                                Padding(padding: const EdgeInsets.only(bottom: 10), child: _KpiTile(row: r)),
                            ],
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

class _ScoreBanner extends StatelessWidget {
  final double total;
  final String label;
  final int year;
  const _ScoreBanner({required this.total, required this.label, required this.year});

  String get _level {
    if (total >= 90) return 'Outstanding Performance';
    if (total >= 80) return 'Excellent Achievement';
    if (total >= 70) return 'Good Progress';
    if (total <= 0) return 'Not evaluated';
    return 'Improvement Required';
  }

  @override
  Widget build(BuildContext context) {
    return GradientBanner(
      child: Row(
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: CircularProgressIndicator(
                    value: (total / 100).clamp(0.0, 1.0).toDouble(),
                    strokeWidth: 9,
                    backgroundColor: AppColors.overlayWhite20,
                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                Text(Fmt.dec(total, decimals: 1),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Period ending $label $year',
                    style: const TextStyle(color: AppColors.overlayWhite70, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                const Text('Total score',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 20)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: AppColors.overlayWhite20, borderRadius: BorderRadius.circular(20)),
                  child: Text(_level, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final Map<String, dynamic> row;
  const _KpiTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final weight = asDouble(row['weight']);
    final score = asDouble(row['score']);
    final grade = asDouble(row['grade']);
    final maxGrade = asDouble(row['max_grade']) == 0 ? 10.0 : asDouble(row['max_grade']);
    final ratio = weight > 0 ? score / weight : 0.0;
    final tone = Tone.forPercent(ratio * 100);
    final notes = asString(row['notes']).trim();
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(asString(row['description']),
              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, height: 1.35)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: ProgressLine(value: ratio, color: tone.fg)),
              const SizedBox(width: 12),
              Text('${Fmt.dec(score)} / ${Fmt.dec(weight)}',
                  style: TextStyle(fontWeight: FontWeight.w800, color: tone.fg)),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusChip('Grade ${Fmt.dec(grade)} / ${Fmt.dec(maxGrade)}', tone, dense: true, showIcon: false),
              StatusChip('Weight ${Fmt.dec(weight)}%', Tone.neutral, dense: true, showIcon: false),
            ],
          ),
          if (asString(row['way_of_measure']).trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(asString(row['way_of_measure']), style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppColors.greyBg, borderRadius: BorderRadius.circular(10)),
              child: Text(notes, style: const TextStyle(color: AppColors.text, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }
}
