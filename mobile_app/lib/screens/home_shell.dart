import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../core/theme.dart';
import 'dashboard_screen.dart';
import 'missions_screen.dart';
import 'more_screen.dart';
import 'my_timesheets_screen.dart';
import 'reports/reports_hub.dart';
import 'review_screen.dart';
import 'vacations_screen.dart';

class _Tab {
  final String id;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() build;
  const _Tab(this.id, this.label, this.icon, this.selectedIcon, this.build);
}

/// Main navigation. The tabs depend on the user's role (capabilities from the server).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  /// Switch tab from anywhere below the shell, e.g. HomeShell.goTo(context, 'missions').
  static void goTo(BuildContext context, String tabId) {
    context.findAncestorStateOfType<HomeShellState>()?.goTo(tabId);
  }

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final List<_Tab> _tabs;
  late final List<Widget?> _pages;

  @override
  void initState() {
    super.initState();
    final caps = context.read<Session>().caps;
    if (caps.isManager) {
      _tabs = [
        _Tab('home', 'Home', Icons.dashboard_outlined, Icons.dashboard_rounded, () => const DashboardScreen()),
        _Tab('review', 'Review', Icons.fact_check_outlined, Icons.fact_check_rounded, () => const ReviewScreen()),
        _Tab('reports', 'Reports', Icons.insights_outlined, Icons.insights_rounded, () => const ReportsHub()),
        _Tab('missions', 'Missions', Icons.flag_outlined, Icons.flag_rounded, () => const MissionsScreen()),
        _Tab('more', 'More', Icons.grid_view_outlined, Icons.grid_view_rounded, () => const MoreScreen()),
      ];
    } else {
      _tabs = [
        _Tab('home', 'Home', Icons.dashboard_outlined, Icons.dashboard_rounded, () => const DashboardScreen()),
        _Tab('timesheets', 'Timesheets', Icons.event_note_outlined, Icons.event_note_rounded,
            () => const MyTimesheetsScreen()),
        _Tab('missions', 'Missions', Icons.flag_outlined, Icons.flag_rounded, () => const MissionsScreen()),
        _Tab('vacations', 'Leave', Icons.beach_access_outlined, Icons.beach_access_rounded,
            () => const VacationsScreen()),
        _Tab('more', 'More', Icons.grid_view_outlined, Icons.grid_view_rounded, () => const MoreScreen()),
      ];
    }
    // pages are built lazily the first time their tab is opened
    _pages = List<Widget?>.filled(_tabs.length, null);
    _pages[0] = _tabs[0].build();
  }

  void goTo(String tabId) {
    final i = _tabs.indexWhere((t) => t.id == tabId);
    if (i >= 0) {
      _select(i);
    } else {
      // tab not in this role's bar: open the screen full-page instead
      Widget? page;
      switch (tabId) {
        case 'timesheets':
          page = const MyTimesheetsScreen();
          break;
        case 'vacations':
          page = const VacationsScreen();
          break;
        case 'review':
          page = const ReviewScreen();
          break;
        case 'reports':
          page = const ReportsHub();
          break;
      }
      if (page != null) {
        final p = page;
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => p));
      }
    }
  }

  void _select(int i) {
    setState(() {
      _index = i;
      _pages[i] ??= _tabs[i].build();
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final body = IndexedStack(
      index: _index,
      children: [for (int i = 0; i < _tabs.length; i++) _pages[i] ?? const SizedBox.shrink()],
    );

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              backgroundColor: AppColors.surface,
              indicatorColor: AppColors.indigoBg,
              selectedIconTheme: const IconThemeData(color: AppColors.indigo),
              selectedLabelTextStyle: const TextStyle(color: AppColors.indigo, fontWeight: FontWeight.w700),
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Image.asset('assets/images/app_icon.png', width: 44, height: 44),
              ),
              destinations: [
                for (final t in _tabs)
                  NavigationRailDestination(
                    icon: Icon(t.icon),
                    selectedIcon: Icon(t.selectedIcon),
                    label: Text(t.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1, thickness: 1, color: AppColors.border),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.indigoBg,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon, color: AppColors.indigo),
              label: t.label,
            ),
        ],
      ),
    );
  }
}
