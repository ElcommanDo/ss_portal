import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';

/// views.vacation_requests / add_vacations / process_vacation
class VacationsScreen extends StatefulWidget {
  const VacationsScreen({super.key});

  @override
  State<VacationsScreen> createState() => _VacationsScreenState();
}

class _VacationsScreenState extends State<VacationsScreen> {
  final _listKey = GlobalKey<PagedListState<Vacation>>();
  String _status = '';
  late String _scope;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _scope = context.read<Session>().caps.allVacations ? 'all' : 'mine';
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<PageResult<Vacation>> _fetch(int page) async {
    final data = await context.read<Session>().api.get('/vacations/', query: {
      'page': page,
      'page_size': 15,
      'scope': _scope,
      'status': _status,
      'search': _query,
    });
    return PageResult.parse<Vacation>(data, Vacation.fromJson);
  }

  void _refresh() => _listKey.currentState?.refresh();

  Future<void> _chooseStatus() async {
    final r = await showOptionsSheet<String>(context, title: 'Status', selected: _status, options: const [
      Option('', 'All statuses', icon: Icons.all_inclusive_rounded),
      Option('pending', 'Pending', icon: Icons.schedule_rounded),
      Option('approved', 'Approved', icon: Icons.check_circle_rounded),
      Option('rejected', 'Rejected', icon: Icons.cancel_rounded),
      Option('cancelled', 'Cancelled', icon: Icons.block_rounded),
    ]);
    if (r == null) return;
    setState(() => _status = r.value);
    _refresh();
  }

  Future<void> _request() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => const VacationRequestSheet(),
    );
    if (ok == true) _refresh();
  }

  Future<void> _process(Vacation v, String action) async {
    String? reason;
    if (action == 'rejected') {
      reason = await _askRejectReason();
      if (reason == null) return;
    } else {
      final ok = await confirmDialog(context,
          title: 'Approve leave?',
          message: '${v.user?.fullName ?? ''} • ${Fmt.date(v.date)} • ${v.duration} day${v.duration == 1 ? '' : 's'}',
          confirmLabel: 'Approve');
      if (!ok) return;
    }
    if (!mounted) return;
    try {
      final res = asMap(await context.read<Session>().api.post('/vacations/${v.id}/process/', {
        'action': action,
        'reject_reason': reason ?? '',
      }));
      if (!mounted) return;
      var msg = asString(res['detail'], 'Done');
      if (res['email_sent'] == false) msg = '$msg (email not sent)';
      showSnack(context, msg);
      _refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<String?> _askRejectReason() {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reject request'),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 5,
          decoration: appInput('Reason (sent to the employee)', icon: Icons.comment_outlined),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Back')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(Vacation v) async {
    final ok = await confirmDialog(context,
        title: 'Cancel request?', message: 'Your leave request will be cancelled.', confirmLabel: 'Cancel request',
        destructive: true);
    if (!ok || !mounted) return;
    try {
      final res = asMap(await context.read<Session>().api.post('/vacations/${v.id}/cancel/'));
      if (!mounted) return;
      showSnack(context, asString(res['detail'], 'Cancelled'));
      _refresh();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final caps = session.caps;
    final me = session.user?.id;
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: canPop, title: const Text('Leave requests')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-vacations',
        onPressed: _request,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Request leave', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          if (caps.allVacations)
            Padding(
              padding: EdgeInsets.fromLTRB(pagePadding(context), 4, pagePadding(context), 4),
              child: ResponsiveCenter(
                child: TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  decoration: appInput('Search employee or reason', icon: Icons.search_rounded),
                  onSubmitted: (v) {
                    setState(() => _query = v.trim());
                    _refresh();
                  },
                ),
              ),
            ),
          FilterBar(children: [
            if (caps.allVacations)
              FilterPill(
                label: _scope == 'all' ? 'Everyone' : 'Only mine',
                icon: _scope == 'all' ? Icons.groups_rounded : Icons.person_rounded,
                active: _scope == 'mine',
                onTap: () {
                  setState(() => _scope = _scope == 'all' ? 'mine' : 'all');
                  _refresh();
                },
              ),
            FilterPill(
              label: _status.isEmpty ? 'All statuses' : Fmt.capitalize(_status),
              icon: Icons.filter_list_rounded,
              active: _status.isNotEmpty,
              onTap: _chooseStatus,
              onClear: () {
                setState(() => _status = '');
                _refresh();
              },
            ),
          ]),
          Expanded(
            child: PagedList<Vacation>(
              key: _listKey,
              fetch: _fetch,
              headerBuilder: (ctx, first) {
                if (first == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: StatTile(
                          label: 'Pending',
                          value: '${asInt(first.raw['pending_count'])}',
                          icon: Icons.hourglass_top_rounded,
                          tone: Tone.warning,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: StatTile(
                          label: 'This month',
                          value: '${asInt(first.raw['vacations_this_month'])}',
                          icon: Icons.calendar_month_rounded,
                          tone: Tone.brand,
                        ),
                      ),
                    ],
                  ),
                );
              },
              itemBuilder: (ctx, v, i) => _VacationCard(
                vacation: v,
                showUser: v.user?.id != me,
                canProcess: caps.processVacations && v.status == 'pending',
                canCancel: v.user?.id == me && v.status == 'pending',
                onApprove: () => _process(v, 'approved'),
                onReject: () => _process(v, 'rejected'),
                onCancel: () => _cancel(v),
              ),
              empty: const EmptyState(
                icon: Icons.beach_access_outlined,
                title: 'No leave requests',
                message: 'Requests you submit will appear here.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VacationCard extends StatelessWidget {
  final Vacation vacation;
  final bool showUser;
  final bool canProcess;
  final bool canCancel;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onCancel;

  const _VacationCard({
    required this.vacation,
    required this.showUser,
    required this.canProcess,
    required this.canCancel,
    required this.onApprove,
    required this.onReject,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final v = vacation;
    final start = v.date;
    final end = start?.add(Duration(days: v.duration > 0 ? v.duration - 1 : 0));
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showUser && v.user != null) ...[
                Avatar(v.user!.initials, size: 38),
                const SizedBox(width: 10),
              ] else ...[
                const IconBadge(Icons.beach_access_rounded, size: 38, fg: AppColors.blue, bg: AppColors.cyanBg),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showUser && v.user != null ? v.user!.fullName : 'My leave',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.text),
                    ),
                    Text(
                      v.duration <= 1 ? Fmt.day(start) : '${Fmt.dayShort(start)} → ${Fmt.date(end)}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              StatusChip.status(v.status, dense: true),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              StatusChip('${v.duration} day${v.duration == 1 ? '' : 's'}', Tone.brand, dense: true),
              const SizedBox(width: 8),
              Expanded(
                child: Text(v.reason.isEmpty ? '—' : v.reason,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.text)),
              ),
            ],
          ),
          if (canProcess || canCancel) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (canProcess) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size(0, 44)),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onApprove,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, minimumSize: const Size(0, 44)),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve'),
                    ),
                  ),
                ] else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCancel,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      icon: const Icon(Icons.block_rounded, size: 18),
                      label: const Text('Cancel request'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class VacationRequestSheet extends StatefulWidget {
  const VacationRequestSheet({super.key});

  @override
  State<VacationRequestSheet> createState() => _VacationRequestSheetState();
}

class _VacationRequestSheetState extends State<VacationRequestSheet> {
  DateTime? _date;
  int _duration = 1;
  final _reason = TextEditingController();
  bool _saving = false;
  final Map<String, String> _errors = {};

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await pickDate(context,
        initial: _date ?? now, first: DateTime(now.year - 1), last: DateTime(now.year + 2), help: 'First day of leave');
    if (d != null) {
      setState(() {
        _date = d;
        _errors.remove('date');
      });
    }
  }

  Future<void> _submit() async {
    _errors.clear();
    if (_date == null) _errors['date'] = 'Choose the first day.';
    if (_reason.text.trim().isEmpty) _errors['reason'] = 'Please write the reason.';
    setState(() {});
    if (_errors.isNotEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final res = asMap(await context.read<Session>().api.post('/vacations/', {
        'date': Fmt.iso(_date!),
        'duration': _duration,
        'reason': _reason.text.trim(),
      }));
      if (!mounted) return;
      var msg = asString(res['detail'], 'Request sent');
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
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 24 + bottom),
      child: SingleChildScrollView(
        child: ResponsiveCenter(
          maxWidth: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Request leave', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
              const SizedBox(height: 16),
              PickerField(
                label: 'First day',
                value: _date == null ? null : Fmt.day(_date),
                icon: Icons.event_rounded,
                placeholder: 'Choose date',
                errorText: _errors['date'],
                onTap: _pickDate,
              ),
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  children: [
                    const IconBadge(Icons.timelapse_rounded, size: 38),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text('Duration (days)', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
                    ),
                    IconButton.filledTonal(
                      onPressed: _duration > 1 ? () => setState(() => _duration--) : null,
                      icon: const Icon(Icons.remove_rounded),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text('$_duration',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
                    ),
                    IconButton.filledTonal(
                      onPressed: _duration < 60 ? () => setState(() => _duration++) : null,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ),
              if (_errors['duration'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(_errors['duration']!, style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
                ),
              const SizedBox(height: 14),
              TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: appInput('Reason', icon: Icons.comment_outlined, errorText: _errors['reason']),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: const Text('Send request'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
