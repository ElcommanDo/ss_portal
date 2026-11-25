import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/entry_tile.dart';
import '../widgets/forms.dart';

/// Create a timesheet entry (log work / schedule), edit one, or log a scheduled one as done.
/// Pops `true` when something was saved or deleted.
class EntryFormScreen extends StatefulWidget {
  final TimesheetEntry? entry;
  final bool scheduled;
  final DateTime? initialDate;

  const EntryFormScreen({super.key, this.entry, this.scheduled = false, this.initialDate});

  @override
  State<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends State<EntryFormScreen> {
  final _description = TextEditingController();
  late bool _scheduled;
  IdName? _project;
  String _taskType = 'Delivery';
  late DateTime _date;
  TimeOfDay? _start;
  TimeOfDay? _end;
  bool _abroad = false;
  bool _saving = false;
  final Map<String, String> _errors = {};
  MetaData? _meta;
  Object? _metaError;

  bool get _isEdit => widget.entry != null;

  /// Editing a planned task means "it's done now": it becomes logged work.
  bool get _isLoggingPlanned => _isEdit && widget.entry!.isScheduled;

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    if (e != null) {
      _scheduled = false;
      _project = e.project;
      _taskType = e.taskType;
      _description.text = e.description;
      final d = e.workDate ?? _today;
      _date = d.isAfter(_today) ? _today : DateTime(d.year, d.month, d.day);
      _start = Fmt.parseTime(e.timeStart);
      _end = Fmt.parseTime(e.timeEnd);
      _abroad = e.onsiteAbroad;
    } else {
      _scheduled = widget.scheduled;
      _date = widget.initialDate ?? (_scheduled ? _today.add(const Duration(days: 1)) : _today);
    }
    _loadMeta();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadMeta() async {
    setState(() => _metaError = null);
    try {
      final m = await context.read<Session>().meta();
      if (!mounted) return;
      setState(() {
        _meta = m;
        if (!m.taskTypes.any((t) => t.value == _taskType) && !_isEdit && m.taskTypes.isNotEmpty) {
          _taskType = m.taskTypes.first.value;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _metaError = e);
    }
  }

  double? get _duration {
    final s = _start;
    final e = _end;
    if (s == null || e == null) return null;
    final minutes = (e.hour * 60 + e.minute) - (s.hour * 60 + s.minute);
    return minutes / 60.0;
  }

  void _switchMode(bool scheduled) {
    setState(() {
      _scheduled = scheduled;
      _errors.clear();
      if (scheduled && !_date.isAfter(_today)) _date = _today.add(const Duration(days: 1));
      if (!scheduled && _date.isAfter(_today)) _date = _today;
    });
  }

  Future<void> _pickProject() async {
    final meta = _meta;
    if (meta == null) return;
    final options = [for (final p in meta.entryProjects) Option<int>(p.id, p.name, icon: Icons.folder_rounded)];
    final current = _project;
    if (current != null && !options.any((o) => o.value == current.id)) {
      options.insert(0, Option<int>(current.id, current.name, subtitle: 'Current project', icon: Icons.folder_rounded));
    }
    final picked = await showOptionsSheet<int>(context,
        title: 'Project', options: options, selected: _project?.id, searchable: options.length > 6);
    if (picked != null) {
      setState(() {
        _project = IdName(picked.value, picked.label);
        _errors.remove('project');
      });
    }
  }

  Future<void> _pickDate() async {
    final first = _scheduled ? _today.add(const Duration(days: 1)) : DateTime(2020);
    final last = _scheduled ? _today.add(const Duration(days: 365)) : _today;
    final d = await pickDate(context, initial: _date, first: first, last: last,
        help: _scheduled ? 'Scheduled date' : 'Work date');
    if (d != null) {
      setState(() {
        _date = d;
        _errors.remove('work_date');
      });
    }
  }

  Future<void> _pickTime(bool start) async {
    final t = await pickTime(context,
        initial: start ? (_start ?? const TimeOfDay(hour: 9, minute: 0)) : (_end ?? _suggestEnd()),
        help: start ? 'Start time' : 'End time');
    if (t == null) return;
    setState(() {
      if (start) {
        _start = t;
        _errors.remove('start_time');
      } else {
        _end = t;
        _errors.remove('end_time');
      }
      _errors.remove('end_time');
    });
  }

  TimeOfDay _suggestEnd() {
    final s = _start;
    if (s == null) return const TimeOfDay(hour: 17, minute: 0);
    final h = (s.hour + 1).clamp(0, 23).toInt();
    return TimeOfDay(hour: h, minute: s.minute);
  }

  bool _validate() {
    _errors.clear();
    if (_project == null) _errors['project'] = 'Please select a project.';
    if (_description.text.trim().isEmpty) _errors['task_description'] = 'Describe what you worked on.';
    if (_scheduled) {
      if (!_date.isAfter(_today)) _errors['work_date'] = 'A scheduled task must be on a future date.';
    } else {
      if (_date.isAfter(_today)) _errors['work_date'] = 'You cannot log work on a future date.';
      if (_start == null) _errors['start_time'] = 'Required';
      if (_end == null) _errors['end_time'] = 'Required';
      final d = _duration;
      if (d != null && d <= 0) _errors['end_time'] = 'End time must be after start time.';
    }
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _save() async {
    if (_saving || !_validate()) return;
    setState(() => _saving = true);
    final api = context.read<Session>().api;
    final body = <String, dynamic>{
      'project': _project!.id,
      'task_type': _taskType,
      'task_description': _description.text.trim(),
      'work_date': Fmt.iso(_date),
      'location': _abroad ? 'abroad' : (widget.entry?.onsiteEgypt == true ? 'egypt' : ''),
    };
    if (!_scheduled) {
      body['start_time'] = Fmt.time(_start!);
      body['end_time'] = Fmt.time(_end!);
    }
    try {
      Map<String, dynamic> res;
      if (_isEdit) {
        if (_isLoggingPlanned) body['mark_logged'] = true;
        // legacy task types typed on the web (e.g. "Self Study") are kept unless the user changes them
        if (_taskType == widget.entry!.taskType) body.remove('task_type');
        res = asMap(await api.put('/entries/${widget.entry!.id}/', body));
      } else {
        body['is_scheduled'] = _scheduled;
        res = asMap(await api.post('/entries/', body));
      }
      if (!mounted) return;
      showSnack(context, asString(res['detail'], 'Saved'));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.field != null) _errors[e.field!] = e.message;
      });
      showSnack(context, e.message, error: true);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context,
        title: 'Delete entry?',
        message: 'This timesheet entry will be permanently deleted.',
        confirmLabel: 'Delete',
        destructive: true);
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      final res = asMap(await context.read<Session>().api.delete('/entries/${widget.entry!.id}/'));
      if (!mounted) return;
      showSnack(context, asString(res['detail'], 'Deleted'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        showSnack(context, errorText(e), error: true);
        setState(() => _saving = false);
      }
    }
  }

  String get _title {
    if (_isLoggingPlanned) return 'Log planned task';
    if (_isEdit) return 'Edit entry';
    return _scheduled ? 'Schedule a task' : 'Log work';
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final duration = _duration;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
            ),
        ],
      ),
      body: _meta == null
          ? (_metaError != null ? ErrorState(message: errorText(_metaError!), onRetry: _loadMeta) : const LoadingView())
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: ListView(
                padding: EdgeInsets.fromLTRB(pad, 8, pad, 32),
                children: [
                  ResponsiveCenter(
                    maxWidth: 640,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!_isEdit) ...[
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, icon: Icon(Icons.timer_rounded), label: Text('Log work')),
                              ButtonSegment(value: true, icon: Icon(Icons.event_rounded), label: Text('Schedule')),
                            ],
                            selected: {_scheduled},
                            showSelectedIcon: false,
                            onSelectionChanged: (s) => _switchMode(s.first),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _scheduled
                                ? 'Plan a task for a future date. Hours are logged later when it is done.'
                                : 'Record work you have already done, with start and end time.',
                            style: const TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                          const SizedBox(height: 18),
                        ],
                        if (_isLoggingPlanned) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: AppColors.infoBg, borderRadius: BorderRadius.circular(14)),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: AppColors.info),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'This task was planned. Set the real date and times to log it as done.',
                                    style: TextStyle(color: AppColors.info, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        PickerField(
                          label: 'Project',
                          value: _project?.name,
                          icon: Icons.folder_open_rounded,
                          placeholder: 'Select a project',
                          errorText: _errors['project'],
                          onTap: _pickProject,
                        ),
                        if (_meta!.entryProjects.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 6, left: 4),
                            child: Text('No active projects are available to you. Ask your manager to make one public.',
                                style: TextStyle(color: AppColors.warning, fontSize: 12.5)),
                          ),
                        const SizedBox(height: 18),
                        const Text('Task type',
                            style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 14)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final t in _taskTypeOptions())
                              ChoiceChip(
                                label: Text(t.label),
                                avatar: Icon(taskTypeTone(t.value).icon, size: 18,
                                    color: _taskType == t.value ? Colors.white : taskTypeTone(t.value).fg),
                                selected: _taskType == t.value,
                                showCheckmark: false,
                                selectedColor: AppColors.indigo,
                                backgroundColor: AppColors.surface,
                                side: BorderSide(color: _taskType == t.value ? AppColors.indigo : AppColors.border),
                                labelStyle: TextStyle(
                                  color: _taskType == t.value ? Colors.white : AppColors.text,
                                  fontWeight: FontWeight.w600,
                                ),
                                onSelected: (_) => setState(() => _taskType = t.value),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _description,
                          minLines: 3,
                          maxLines: 8,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: appInput('Task description',
                              icon: Icons.notes_rounded,
                              hint: 'What did you work on?',
                              errorText: _errors['task_description']),
                          onChanged: (_) {
                            if (_errors.containsKey('task_description')) {
                              setState(() => _errors.remove('task_description'));
                            }
                          },
                        ),
                        const SizedBox(height: 18),
                        PickerField(
                          label: _scheduled ? 'Scheduled date' : 'Work date',
                          value: '${Fmt.weekday(_date)}, ${Fmt.date(_date)}',
                          icon: Icons.calendar_today_rounded,
                          errorText: _errors['work_date'],
                          onTap: _pickDate,
                        ),
                        if (!_scheduled) ...[
                          const SizedBox(height: 14),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: PickerField(
                                  label: 'Start',
                                  value: _start == null ? null : Fmt.time12(Fmt.time(_start!)),
                                  icon: Icons.play_circle_outline_rounded,
                                  placeholder: '--:--',
                                  errorText: _errors['start_time'],
                                  onTap: () => _pickTime(true),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: PickerField(
                                  label: 'End',
                                  value: _end == null ? null : Fmt.time12(Fmt.time(_end!)),
                                  icon: Icons.stop_circle_outlined,
                                  placeholder: '--:--',
                                  errorText: _errors['end_time'],
                                  onTap: () => _pickTime(false),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _DurationPreview(hours: duration),
                        ],
                        const SizedBox(height: 14),
                        AppCard(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: SwitchListTile(
                            value: _abroad,
                            onChanged: (v) => setState(() => _abroad = v),
                            secondary: const IconBadge(Icons.flight_takeoff_rounded, size: 38),
                            title: const Text('Onsite abroad', style: TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: const Text('International travel / client site outside Egypt'),
                          ),
                        ),
                        const SizedBox(height: 26),
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _save,
                          icon: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                              : const Icon(Icons.check_rounded),
                          label: Text(_isEdit ? 'Save changes' : (_scheduled ? 'Schedule task' : 'Save entry')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  List<ValueLabel> _taskTypeOptions() {
    final list = List<ValueLabel>.from(_meta?.taskTypes ?? <ValueLabel>[]);
    if (list.isEmpty) {
      list.addAll([ValueLabel('Delivery', 'Delivery'), ValueLabel('Pre-Sale', 'Pre-Sale'), ValueLabel('study', 'Study / Training')]);
    }
    // keep a legacy value (e.g. "Self Study" typed on the web) selectable when editing
    if (!list.any((t) => t.value == _taskType)) list.add(ValueLabel(_taskType, _taskType));
    return list;
  }
}

class _DurationPreview extends StatelessWidget {
  final double? hours;
  const _DurationPreview({required this.hours});

  @override
  Widget build(BuildContext context) {
    final h = hours;
    final valid = h != null && h > 0;
    final tone = h == null ? Tone.neutral : (valid ? Tone.brand : Tone.danger);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(Icons.hourglass_bottom_rounded, color: tone.fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              h == null
                  ? 'Pick start and end time'
                  : (valid ? 'Duration: ${Fmt.hm(h)}  (${Fmt.dec(h)} h)' : 'End time must be after start time'),
              style: TextStyle(color: tone.fg, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
