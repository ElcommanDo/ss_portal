import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/config.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';
import 'kpi_screen.dart';
import 'my_timesheets_screen.dart';
import 'people_screen.dart';
import 'projects_screen.dart';
import 'vacations_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  void _push(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final user = session.user;
    final caps = session.caps;
    final pad = pagePadding(context);
    final host = Uri.tryParse(session.baseUrl)?.host ?? session.baseUrl;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, 4, pad, 32),
        children: [
          ResponsiveCenter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GradientBanner(
                  child: Row(
                    children: [
                      Avatar(user?.initials ?? '?', size: 60, bg: AppColors.overlayWhite20, fg: Colors.white),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user?.fullName ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text('@${user?.username ?? ''}',
                                style: const TextStyle(color: AppColors.overlayWhite70, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _chip(user?.roleLabel ?? ''),
                                if (user?.team != null) _chip(user!.team!.replaceAll('_', ' ')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if ((user?.email ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10, left: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.mail_outline_rounded, size: 16, color: AppColors.muted),
                        const SizedBox(width: 6),
                        Expanded(child: Text(user!.email!, style: const TextStyle(color: AppColors.muted))),
                      ],
                    ),
                  ),
                const SectionTitle('My work'),
                _MenuGroup(items: [
                  if (caps.isManager)
                    _MenuItem(Icons.event_note_rounded, 'My timesheets', 'Logged work and scheduled tasks',
                        () => _push(context, const MyTimesheetsScreen())),
                  if (caps.isManager)
                    _MenuItem(Icons.beach_access_rounded, 'Leave requests',
                        caps.processVacations ? 'Request leave and review the team' : 'Request and track leave',
                        () => _push(context, const VacationsScreen())),
                  _MenuItem(Icons.emoji_events_rounded, 'My KPIs', 'Quarterly performance score',
                      () => _push(context, const KpiScreen())),
                  _MenuItem(Icons.folder_open_rounded, 'Projects', 'Projects you created and public projects',
                      () => _push(context, const ProjectsScreen())),
                ]),
                if (caps.manageUsers || caps.manageTeams) ...[
                  const SectionTitle('Management'),
                  _MenuGroup(items: [
                    if (caps.manageUsers)
                      _MenuItem(Icons.manage_accounts_rounded, 'Users', 'Search, view and activate accounts',
                          () => _push(context, const UsersScreen())),
                    if (caps.manageTeams)
                      _MenuItem(Icons.groups_rounded, 'Teams', 'Teams and their members', () => _push(context, const TeamsScreen())),
                  ]),
                ],
                const SectionTitle('Account'),
                _MenuGroup(items: [
                  _MenuItem(Icons.lock_reset_rounded, 'Change password', 'Signs you in again on this device',
                      () => _changePassword(context)),
                  _MenuItem(Icons.dns_outlined, 'Server', host, null),
                  _MenuItem(Icons.logout_rounded, 'Sign out', null, () => _signOut(context), danger: true),
                ]),
                const SizedBox(height: 24),
                Center(
                  child: Opacity(
                    opacity: 0.85,
                    child: Image.asset('assets/images/logo.png', height: 34),
                  ),
                ),
                const SizedBox(height: 6),
                const Text('${AppConfig.appName} • v1.0.0',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.subtle, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.overlayWhite20, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await confirmDialog(context,
        title: 'Sign out?', message: 'You will need your password to sign in again.', confirmLabel: 'Sign out');
    if (ok && context.mounted) await context.read<Session>().logout();
  }

  Future<void> _changePassword(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const _ChangePasswordSheet(),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;
  _MenuItem(this.icon, this.title, this.subtitle, this.onTap, {this.danger = false});
}

class _MenuGroup extends StatelessWidget {
  final List<_MenuItem> items;
  const _MenuGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 68),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: IconBadge(items[i].icon,
                  size: 40,
                  fg: items[i].danger ? AppColors.danger : AppColors.indigo,
                  bg: items[i].danger ? AppColors.dangerBg : AppColors.indigoBg),
              title: Text(items[i].title,
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: items[i].danger ? AppColors.danger : AppColors.text)),
              subtitle: items[i].subtitle == null ? null : Text(items[i].subtitle!),
              trailing: items[i].onTap == null ? null : const Icon(Icons.chevron_right_rounded, color: AppColors.subtle),
              onTap: items[i].onTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  final Map<String, String> _errors = {};

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    _errors.clear();
    if (_old.text.isEmpty) _errors['old_password'] = 'Enter your current password.';
    if (_new.text.length < 6) _errors['new_password'] = 'At least 6 characters.';
    if (_new.text != _confirm.text) _errors['confirm'] = 'Passwords do not match.';
    setState(() {});
    if (_errors.isNotEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await context.read<Session>().changePassword(_old.text, _new.text);
      if (!mounted) return;
      showSnack(context, 'Password changed successfully');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors[e.field ?? 'old_password'] = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final toggle = IconButton(
      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      onPressed: () => setState(() => _obscure = !_obscure),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottom),
      child: SingleChildScrollView(
        child: ResponsiveCenter(
          maxWidth: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Change password',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
              const SizedBox(height: 16),
              TextField(
                controller: _old,
                obscureText: _obscure,
                decoration: appInput('Current password',
                    icon: Icons.lock_outline_rounded, errorText: _errors['old_password'], suffix: toggle),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _new,
                obscureText: _obscure,
                decoration: appInput('New password', icon: Icons.lock_reset_rounded, errorText: _errors['new_password']),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirm,
                obscureText: _obscure,
                decoration: appInput('Confirm new password', icon: Icons.lock_rounded, errorText: _errors['confirm']),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Update password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
