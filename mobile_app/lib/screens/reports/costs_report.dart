import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/forms.dart';
import '../../widgets/report_kit.dart';

/// views.reports_project_cost
class CostsReportScreen extends StatefulWidget {
  const CostsReportScreen({super.key});

  @override
  State<CostsReportScreen> createState() => _CostsReportScreenState();
}

class _CostsReportScreenState extends State<CostsReportScreen> {
  final _listKey = GlobalKey<PagedListState<Map<String, dynamic>>>();
  IdName? _project;
  UserBrief? _user;

  Future<PageResult<Map<String, dynamic>>> _fetch(int page) async {
    final data = await context.read<Session>().api.get('/reports/project-costs/', query: {
      'page': page,
      'page_size': 30,
      'project_pk': _project?.id,
      'user_pk': _user?.id,
    });
    return PageResult.parse<Map<String, dynamic>>(data, (m) => m);
  }

  void _refresh() => _listKey.currentState?.refresh();

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Project costs')),
      body: Column(
        children: [
          FilterBar(children: [
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
            FilterPill(
              label: _user?.fullName ?? 'All employees',
              icon: Icons.person_search_rounded,
              active: _user != null,
              onTap: _chooseUser,
              onClear: () {
                setState(() => _user = null);
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
                final byCurrency = asMap(first.raw['totals_by_currency']);
                final primary = asString(first.raw['primary_currency'], 'EGP');
                return ReportSummary(
                  title: 'External project costs',
                  subtitle: 'Totals are per currency (no conversion)',
                  tiles: [
                    StatTile(
                      label: 'Total ($primary)',
                      value: Fmt.money(asDouble(first.raw['total_cost'])),
                      icon: Icons.payments_rounded,
                      tone: Tone.success,
                    ),
                    StatTile(label: 'Cost records', value: '${first.count}', icon: Icons.receipt_long_rounded, tone: Tone.info),
                    for (final e in byCurrency.entries.where((e) => e.key != primary))
                      StatTile(label: 'Total (${e.key})', value: Fmt.money(asDouble(e.value)), icon: Icons.currency_exchange_rounded),
                  ],
                );
              },
              itemBuilder: (ctx, c, i) {
                final project = asMap(c['project']);
                final user = asMap(c['user']);
                final notes = asString(c['notes']).trim();
                return AppCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const IconBadge(Icons.request_quote_rounded, fg: AppColors.info, bg: AppColors.infoBg, size: 42),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(asString(project['name'], '—'),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.text)),
                            const SizedBox(height: 2),
                            Text('${asString(c['cost_type'])} • ${asString(user['full_name'], '—')}',
                                style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                            if (notes.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(notes, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${Fmt.money(asDouble(c['amount']))} ${asString(c['currency'])}',
                          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.success)),
                    ],
                  ),
                );
              },
              empty: const EmptyState(icon: Icons.request_quote_outlined, title: 'No costs recorded'),
            ),
          ),
        ],
      ),
    );
  }
}
