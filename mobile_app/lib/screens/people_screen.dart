import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';
import 'reports/activity_report.dart';

/// views.users — leaders only see the members of their teams.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _listKey = GlobalKey<PagedListState<AppUser>>();
  final _search = TextEditingController();
  String _query = '';
  String _active = '';
  IdName? _team;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<PageResult<AppUser>> _fetch(int page) async {
    final data = await context.read<Session>().api.get('/users/', query: {
      'page': page,
      'page_size': 30,
      'search': _query,
      'active': _active,
      'team_pk': _team?.id,
    });
    return PageResult.parse<AppUser>(data, AppUser.fromJson);
  }

  void _refresh() => _listKey.currentState?.refresh();

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

  Future<void> _toggle(AppUser u) async {
    final activate = !u.isActive;
    final ok = await confirmDialog(context,
        title: activate ? 'Activate account?' : 'Deactivate account?',
        message: activate
            ? '${u.fullName} will be able to sign in again.'
            : '${u.fullName} will not be able to sign in to the portal or the app.',
        confirmLabel: activate ? 'Activate' : 'Deactivate',
        destructive: !activate);
    if (!ok || !mounted) return;
    try {
      final res = asMap(await context.read<Session>().api.post('/users/${u.id}/toggle-active/', {'active': activate}));
      if (!mounted) return;
      showSnack(context, asString(res['detail'], 'Updated'));
      _refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  void _showUser(AppUser u) {
    final me = context.read<Session>().user?.id;
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Avatar(u.initials, size: 54),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(u.fullName, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.text)),
                      Text('@${u.username}', style: const TextStyle(color: AppColors.muted)),
                    ],
                  ),
                ),
                StatusChip(u.isActive ? 'Active' : 'Inactive', u.isActive ? Tone.success : Tone.danger),
              ],
            ),
            const SizedBox(height: 14),
            InfoRow(Icons.badge_outlined, 'Role', u.roleLabel),
            InfoRow(Icons.groups_outlined, 'Team', (u.team ?? 'No team').replaceAll('_', ' ')),
            InfoRow(Icons.mail_outline_rounded, 'Email', (u.email ?? '').isEmpty ? '—' : u.email!),
            InfoRow(Icons.event_outlined, 'Joined', Fmt.date(u.dateJoined)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => ActivityReportScreen(initialUser: u)));
              },
              icon: const Icon(Icons.query_stats_rounded),
              label: const Text('View activity'),
            ),
            if (u.id != me) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _toggle(u);
                },
                style: OutlinedButton.styleFrom(foregroundColor: u.isActive ? AppColors.danger : AppColors.success),
                icon: Icon(u.isActive ? Icons.person_off_outlined : Icons.person_add_alt_1_outlined),
                label: Text(u.isActive ? 'Deactivate account' : 'Activate account'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 4),
            child: ResponsiveCenter(
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: appInput('Search name or username', icon: Icons.search_rounded),
                onSubmitted: (v) {
                  setState(() => _query = v.trim());
                  _refresh();
                },
              ),
            ),
          ),
          FilterBar(children: [
            FilterPill(
              label: _team?.name ?? 'All teams',
              icon: Icons.groups_rounded,
              active: _team != null,
              onTap: _chooseTeam,
              onClear: () {
                setState(() => _team = null);
                _refresh();
              },
            ),
            FilterPill(
              label: _active == '1' ? 'Active' : (_active == '0' ? 'Inactive' : 'Any status'),
              icon: Icons.toggle_on_outlined,
              active: _active.isNotEmpty,
              onTap: () {
                setState(() => _active = _active == '' ? '1' : (_active == '1' ? '0' : ''));
                _refresh();
              },
            ),
          ]),
          Expanded(
            child: PagedList<AppUser>(
              key: _listKey,
              fetch: _fetch,
              itemSpacing: 8,
              itemBuilder: (ctx, u, i) => AppCard(
                onTap: () => _showUser(u),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Avatar(u.initials,
                        size: 42,
                        bg: u.isActive ? AppColors.indigoBg : AppColors.greyBg,
                        fg: u.isActive ? AppColors.indigo : AppColors.subtle),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(u.fullName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                          Text(
                            [u.roleLabel, if (u.team != null) u.team!.replaceAll('_', ' ')].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    if (!u.isActive) const StatusChip('Inactive', Tone.danger, dense: true),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.subtle),
                  ],
                ),
              ),
              empty: const EmptyState(icon: Icons.person_search_rounded, title: 'No users found'),
            ),
          ),
        ],
      ),
    );
  }
}

/// views.teams
class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Teams')),
      body: Loader<List<Map<String, dynamic>>>(
        load: () async {
          final data = asMap(await context.read<Session>().api.get('/teams/'));
          return asList(data['results']).map((e) => asMap(e)).toList();
        },
        builder: (context, teams, reload) => RefreshIndicator(
          onRefresh: reload,
          child: teams.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.groups_outlined, title: 'No teams')])
              : ListView(
                  padding: EdgeInsets.fromLTRB(pad, 8, pad, 32),
                  children: [
                    ResponsiveCenter(
                      child: TileGrid(
                        minTileWidth: 260,
                        minColumns: 1,
                        children: [
                          for (final t in teams)
                            AppCard(
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => TeamMembersScreen(
                                      teamId: asInt(t['id']), title: asString(t['title']).replaceAll('_', ' ')))),
                              child: Row(
                                children: [
                                  const IconBadge(Icons.groups_rounded, size: 46),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(asString(t['title']).replaceAll('_', ' '),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.text)),
                                        const SizedBox(height: 2),
                                        Text('Lead: ${asString(t['team_lead'], '—')}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                                        const SizedBox(height: 8),
                                        StatusChip('${asInt(t['active_members'])} active / ${asInt(t['members'])} members',
                                            Tone.brand,
                                            dense: true,
                                            showIcon: false),
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
        ),
      ),
    );
  }
}

class TeamMembersScreen extends StatelessWidget {
  final int teamId;
  final String title;
  const TeamMembersScreen({super.key, required this.teamId, required this.title});

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Loader<List<AppUser>>(
        load: () async {
          final data = asMap(await context.read<Session>().api.get('/teams/$teamId/members/'));
          return asList(data['results']).map((e) => AppUser.fromJson(asMap(e))).toList();
        },
        builder: (context, users, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 32),
            children: [
              if (users.isEmpty) const EmptyState(icon: Icons.person_off_outlined, title: 'No members'),
              for (final u in users)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ResponsiveCenter(
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => ActivityReportScreen(initialUser: u))),
                      child: Row(
                        children: [
                          Avatar(u.initials, size: 40),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(u.fullName,
                                    style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                                Text(u.roleLabel, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                              ],
                            ),
                          ),
                          StatusChip(u.isActive ? 'Active' : 'Inactive', u.isActive ? Tone.success : Tone.danger,
                              dense: true),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
