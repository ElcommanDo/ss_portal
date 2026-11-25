import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';

/// views.missions_list — missions assigned to me and (for managers/leaders) created by me.
class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen> with SingleTickerProviderStateMixin {
  TabController? _tabs;
  final _assignedKey = GlobalKey<PagedListState<Mission>>();
  final _createdKey = GlobalKey<PagedListState<Mission>>();
  String _status = 'open';
  UserBrief? _employee;

  @override
  void initState() {
    super.initState();
    if (context.read<Session>().caps.assignMissions) {
      _tabs = TabController(length: 2, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabs?.dispose();
    super.dispose();
  }

  Future<PageResult<Mission>> _fetch(int page, String box) async {
    final data = await context.read<Session>().api.get('/missions/', query: {
      'box': box,
      'page': page,
      'page_size': 15,
      'status': _status == 'all' ? null : _status,
      'employee': box == 'created' ? _employee?.id : null,
    });
    return PageResult.parse<Mission>(data, Mission.fromJson);
  }

  void _refreshAll() {
    _assignedKey.currentState?.refresh();
    _createdKey.currentState?.refresh();
  }

  Future<void> _chooseStatus() async {
    final r = await showOptionsSheet<String>(context, title: 'Show missions', selected: _status, options: const [
      Option('open', 'Open (not completed)', icon: Icons.radio_button_unchecked_rounded),
      Option('pending', 'Pending', icon: Icons.schedule_rounded),
      Option('in_progress', 'In progress', icon: Icons.autorenew_rounded),
      Option('completed', 'Completed', icon: Icons.check_circle_rounded),
      Option('all', 'All missions', icon: Icons.all_inclusive_rounded),
    ]);
    if (r == null) return;
    setState(() => _status = r.value);
    _refreshAll();
  }

  Future<void> _chooseEmployee() async {
    try {
      final meta = await context.read<Session>().meta();
      if (!mounted) return;
      final r = await showOptionsSheet<int>(context,
          title: 'Assigned to',
          searchable: true,
          selected: _employee?.id,
          options: [
            for (final u in meta.assignableEmployees)
              Option(u.id, u.fullName, subtitle: [u.username, if (u.team != null) u.team!].join(' • '),
                  icon: Icons.person_rounded),
          ]);
      if (r == null) return;
      setState(() => _employee = meta.assignableEmployees.firstWhere((u) => u.id == r.value));
      _createdKey.currentState?.refresh();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const MissionFormScreen()));
    if (created == true) {
      _createdKey.currentState?.refresh();
      _tabs?.animateTo(1);
    }
  }

  Future<void> _open(Mission m, bool mine) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => MissionSheet(mission: m, assignedToMe: mine),
    );
    if (changed == true) _refreshAll();
  }

  Widget _list(String box) {
    final mine = box == 'assigned';
    return PagedList<Mission>(
      key: mine ? _assignedKey : _createdKey,
      fetch: (p) => _fetch(p, box),
      itemBuilder: (ctx, m, i) => MissionCard(mission: m, showEmployee: !mine, onTap: () => _open(m, mine)),
      empty: EmptyState(
        icon: Icons.flag_outlined,
        title: mine ? 'No missions for you' : 'No missions created',
        message: mine ? 'Missions assigned to you will appear here.' : 'Use “New mission” to assign work to your team.',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusLabel = {
      'open': 'Open',
      'pending': 'Pending',
      'in_progress': 'In progress',
      'completed': 'Completed',
      'all': 'All',
    }[_status]!;
    final tabs = _tabs;
    final canPop = Navigator.of(context).canPop();
    final canAssign = context.watch<Session>().caps.assignMissions;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: canPop,
        title: const Text('Missions'),
        bottom: tabs == null
            ? null
            : TabBar(
                controller: tabs,
                labelColor: AppColors.indigo,
                unselectedLabelColor: AppColors.muted,
                indicatorColor: AppColors.indigo,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                onTap: (_) => setState(() {}),
                tabs: const [Tab(text: 'Assigned to me'), Tab(text: 'Created by me')],
              ),
      ),
      floatingActionButton: canAssign
          ? FloatingActionButton.extended(
              heroTag: 'fab-missions',
              onPressed: _create,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('New mission', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      body: Column(
        children: [
          FilterBar(children: [
            FilterPill(label: statusLabel, icon: Icons.filter_list_rounded, active: _status != 'open', onTap: _chooseStatus),
            if (tabs != null)
              AnimatedBuilder(
                animation: tabs,
                builder: (ctx, _) => tabs.index == 1
                    ? FilterPill(
                        label: _employee?.fullName ?? 'Any employee',
                        icon: Icons.person_search_rounded,
                        active: _employee != null,
                        onTap: _chooseEmployee,
                        onClear: () {
                          setState(() => _employee = null);
                          _createdKey.currentState?.refresh();
                        },
                      )
                    : const SizedBox.shrink(),
              ),
          ]),
          Expanded(
            child: tabs == null
                ? _list('assigned')
                : TabBarView(controller: tabs, children: [_list('assigned'), _list('created')]),
          ),
        ],
      ),
    );
  }
}

class MissionCard extends StatelessWidget {
  final Mission mission;
  final bool showEmployee;
  final VoidCallback? onTap;

  const MissionCard({super.key, required this.mission, this.showEmployee = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = mission;
    final person = showEmployee ? m.employee : m.createdBy;
    return AppCard(
      onTap: onTap,
      borderColor: m.isOverdue ? const Color(0xFFFCA5A5) : null,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusChip(Fmt.capitalize(m.priority.isEmpty ? 'normal' : m.priority), Tone.forPriority(m.priority), dense: true),
              const SizedBox(width: 6),
              StatusChip.status(m.status, dense: true),
              const Spacer(),
              if (m.isTask)
                const Tooltip(message: 'Task', child: Icon(Icons.checklist_rounded, size: 18, color: AppColors.subtle)),
            ],
          ),
          const SizedBox(height: 10),
          Text(m.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, height: 1.4, color: AppColors.text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _meta(Icons.folder_open_rounded, m.project?.name ?? 'General'),
              _meta(
                m.isOverdue ? Icons.warning_amber_rounded : Icons.event_rounded,
                m.isOverdue ? 'Overdue • ${Fmt.dateTime(m.deadline)}' : Fmt.dateTime(m.deadline),
                color: m.isOverdue ? AppColors.danger : null,
              ),
              if (person != null) _meta(showEmployee ? Icons.person_rounded : Icons.person_pin_rounded,
                  showEmployee ? person.fullName : 'From ${person.fullName}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color ?? AppColors.subtle),
        const SizedBox(width: 4),
        Flexible(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: color ?? AppColors.muted, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

/// Mission details + actions. Pops `true` if the mission changed.
class MissionSheet extends StatefulWidget {
  final Mission mission;
  final bool assignedToMe;
  const MissionSheet({super.key, required this.mission, required this.assignedToMe});

  @override
  State<MissionSheet> createState() => _MissionSheetState();
}

class _MissionSheetState extends State<MissionSheet> {
  late String _status = widget.mission.status.isEmpty ? 'pending' : widget.mission.status;
  bool _busy = false;
  bool _changed = false;

  Future<void> _run(Future<dynamic> Function() call, {bool closes = false}) async {
    setState(() => _busy = true);
    try {
      final res = asMap(await call());
      if (!mounted) return;
      _changed = true;
      var msg = asString(res['detail'], 'Done');
      if (res.containsKey('email_sent') && res['email_sent'] == false) msg = '$msg (email notification not sent)';
      showSnack(context, msg);
      if (closes) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.mission;
    final api = context.watch<Session>().api;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: ResponsiveCenter(
        maxWidth: 640,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                StatusChip(Fmt.capitalize(m.priority), Tone.forPriority(m.priority)),
                const SizedBox(width: 8),
                StatusChip.status(_status),
                const Spacer(),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(_changed),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(m.body, style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.text)),
            const SizedBox(height: 16),
            InfoRow(Icons.folder_open_rounded, 'Project', m.project?.name ?? 'General'),
            InfoRow(Icons.event_rounded, 'Deadline', Fmt.dateTime(m.deadline)),
            if (m.employee != null) InfoRow(Icons.person_rounded, 'Assigned to', m.employee!.fullName),
            if (m.createdBy != null) InfoRow(Icons.person_pin_rounded, 'Created by', m.createdBy!.fullName),
            InfoRow(Icons.schedule_rounded, 'Created', Fmt.dateTime(m.createdAt)),
            if (m.isOverdue)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.dangerBg, borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.danger),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text('This mission is overdue.',
                          style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            if (widget.assignedToMe) ...[
              const Text('Update status', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'pending', label: Text('Pending')),
                  ButtonSegment(value: 'in_progress', label: Text('In progress')),
                  ButtonSegment(value: 'completed', label: Text('Done')),
                ],
                selected: {_status},
                showSelectedIcon: false,
                onSelectionChanged: _busy
                    ? null
                    : (s) {
                        final v = s.first;
                        if (v == _status) return;
                        _run(() async {
                          final r = await api.post('/missions/${m.id}/status/', {'status': v});
                          if (mounted) setState(() => _status = v);
                          return r;
                        });
                      },
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(() => api.post('/missions/${m.id}/accept/')),
                icon: const Icon(Icons.thumb_up_alt_outlined),
                label: const Text('Accept mission (notify creator)'),
              ),
            ] else if (!m.isCompleted) ...[
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(() => api.post('/missions/${m.id}/remind/')),
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Send reminder email'),
              ),
            ],
            if (_busy) const Padding(padding: EdgeInsets.only(top: 14), child: LinearProgressIndicator()),
          ],
        ),
      ),
    );
  }
}

/// views.missions_list POST — assign a mission to an employee.
class MissionFormScreen extends StatefulWidget {
  const MissionFormScreen({super.key});

  @override
  State<MissionFormScreen> createState() => _MissionFormScreenState();
}

class _MissionFormScreenState extends State<MissionFormScreen> {
  final _body = TextEditingController();
  UserBrief? _employee;
  IdName? _project;
  String _priority = 'medium';
  DateTime? _deadlineDate;
  TimeOfDay _deadlineTime = const TimeOfDay(hour: 17, minute: 0);
  bool _isTask = false;
  bool _saving = false;
  final Map<String, String> _errors = {};

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickEmployee(MetaData meta) async {
    final r = await showOptionsSheet<int>(context,
        title: 'Assign to',
        searchable: true,
        selected: _employee?.id,
        options: [
          for (final u in meta.assignableEmployees)
            Option(u.id, u.fullName, subtitle: [u.username, if (u.team != null) u.team!].join(' • '), icon: Icons.person_rounded),
        ]);
    if (r != null) {
      setState(() {
        _employee = meta.assignableEmployees.firstWhere((u) => u.id == r.value);
        _errors.remove('employee');
      });
    }
  }

  Future<void> _pickProject(MetaData meta) async {
    final r = await showOptionsSheet<int>(context,
        title: 'Project (optional)',
        searchable: true,
        selected: _project?.id,
        options: [for (final p in meta.projects) Option(p.id, p.name, icon: Icons.folder_rounded)]);
    if (r != null) setState(() => _project = IdName(r.value, r.label));
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final d = await pickDate(context,
        initial: _deadlineDate ?? now.add(const Duration(days: 1)),
        first: DateTime(now.year, now.month, now.day),
        last: now.add(const Duration(days: 730)),
        help: 'Deadline date');
    if (d == null || !mounted) return;
    final t = await pickTime(context, initial: _deadlineTime, help: 'Deadline time');
    setState(() {
      _deadlineDate = d;
      if (t != null) _deadlineTime = t;
      _errors.remove('deadline');
    });
  }

  Future<void> _save() async {
    _errors.clear();
    if (_employee == null) _errors['employee'] = 'Select an employee.';
    if (_body.text.trim().isEmpty) _errors['body'] = 'Describe the mission.';
    if (_deadlineDate == null) _errors['deadline'] = 'Choose a deadline.';
    setState(() {});
    if (_errors.isNotEmpty || _saving) return;
    setState(() => _saving = true);
    final d = _deadlineDate!;
    final deadline = '${Fmt.iso(d)}T${Fmt.time(_deadlineTime)}';
    try {
      final res = asMap(await context.read<Session>().api.post('/missions/', {
        'employee': _employee!.id,
        'body': _body.text.trim(),
        'priority': _priority,
        'deadline': deadline,
        'project': _project?.id,
        'is_task': _isTask,
      }));
      if (!mounted) return;
      var msg = asString(res['detail'], 'Mission created');
      if (res['email_sent'] == false) msg = '$msg (email not sent)';
      showSnack(context, msg);
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.field != null) _errors[e.field!] = e.message;
      });
      showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New mission')),
      body: Loader<MetaData>(
        load: () => context.read<Session>().meta(),
        builder: (context, meta, _) => GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(pad, 8, pad, 32),
            children: [
              ResponsiveCenter(
                maxWidth: 640,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PickerField(
                      label: 'Assign to',
                      value: _employee?.fullName,
                      icon: Icons.person_add_alt_1_rounded,
                      placeholder: meta.assignableEmployees.isEmpty ? 'No team members' : 'Select employee',
                      errorText: _errors['employee'],
                      onTap: () => _pickEmployee(meta),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _body,
                      minLines: 4,
                      maxLines: 10,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: appInput('Mission details',
                          icon: Icons.notes_rounded, hint: 'Detailed task instructions…', errorText: _errors['body']),
                    ),
                    const SizedBox(height: 14),
                    PickerField(
                      label: 'Project (optional)',
                      value: _project?.name,
                      icon: Icons.folder_open_rounded,
                      placeholder: 'No specific project',
                      onTap: () => _pickProject(meta),
                      onClear: () => setState(() => _project = null),
                    ),
                    const SizedBox(height: 14),
                    PickerField(
                      label: 'Deadline',
                      value: _deadlineDate == null
                          ? null
                          : '${Fmt.date(_deadlineDate)} • ${Fmt.time12(Fmt.time(_deadlineTime))}',
                      icon: Icons.event_rounded,
                      placeholder: 'Choose date & time',
                      errorText: _errors['deadline'],
                      onTap: _pickDeadline,
                    ),
                    const SizedBox(height: 18),
                    const Text('Priority', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'high', label: Text('High'), icon: Icon(Icons.keyboard_double_arrow_up_rounded)),
                        ButtonSegment(value: 'medium', label: Text('Medium'), icon: Icon(Icons.drag_handle_rounded)),
                        ButtonSegment(value: 'low', label: Text('Low'), icon: Icon(Icons.keyboard_double_arrow_down_rounded)),
                      ],
                      selected: {_priority},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _priority = s.first),
                    ),
                    const SizedBox(height: 12),
                    CheckboxListTile(
                      value: _isTask,
                      onChanged: (v) => setState(() => _isTask = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Mark as task', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                          : const Icon(Icons.send_rounded),
                      label: const Text('Assign mission'),
                    ),
                    const SizedBox(height: 8),
                    const Text('The employee receives an email with the mission details.',
                        textAlign: TextAlign.center, style: TextStyle(color: AppColors.subtle, fontSize: 12.5)),
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
