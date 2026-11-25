import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import '../widgets/common.dart';
import '../widgets/forms.dart';

/// views.projects / project_create / add_project_cost
class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _listKey = GlobalKey<PagedListState<ProjectInfo>>();
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<PageResult<ProjectInfo>> _fetch(int page) async {
    final data = await context.read<Session>().api.get('/projects/', query: {'page': page, 'page_size': 30, 'search': _query});
    return PageResult.parse<ProjectInfo>(data, ProjectInfo.fromJson);
  }

  Future<void> _create() async {
    final ok = await _sheet(const _ProjectFormSheet());
    if (ok == true) {
      _listKey.currentState?.refresh();
      if (mounted) await context.read<Session>().meta(force: true);
    }
  }

  Future<void> _addCost(ProjectInfo p) async {
    await _sheet(_CostFormSheet(project: p));
  }

  Future<bool?> _sheet(Widget child) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final caps = context.watch<Session>().caps;
    final pad = pagePadding(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Projects')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-projects',
        onPressed: _create,
        icon: const Icon(Icons.create_new_folder_rounded),
        label: const Text('New project', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
            child: ResponsiveCenter(
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: appInput('Search projects', icon: Icons.search_rounded),
                onSubmitted: (v) {
                  setState(() => _query = v.trim());
                  _listKey.currentState?.refresh();
                },
              ),
            ),
          ),
          Expanded(
            child: PagedList<ProjectInfo>(
              key: _listKey,
              fetch: _fetch,
              itemBuilder: (ctx, p, i) => AppCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconBadge(Icons.folder_rounded,
                            size: 40,
                            fg: p.isActive ? AppColors.indigo : AppColors.subtle,
                            bg: p.isActive ? AppColors.indigoBg : AppColors.greyBg),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppColors.text)),
                        ),
                        if (caps.addProjectCost)
                          IconButton(
                            tooltip: 'Add cost',
                            onPressed: () => _addCost(p),
                            icon: const Icon(Icons.request_quote_outlined, color: AppColors.blue),
                          ),
                      ],
                    ),
                    if (p.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(p.description,
                          maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.muted)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        StatusChip(p.isActive ? 'Active' : 'Inactive', p.isActive ? Tone.success : Tone.neutral, dense: true),
                        StatusChip(p.isPublic ? 'Public' : 'Private',
                            p.isPublic ? Tone.info : const Tone(AppColors.muted, AppColors.greyBg, Icons.lock_rounded),
                            dense: true),
                        StatusChip('${Fmt.hours(p.loggedHours)} logged', Tone.brand, dense: true, showIcon: false),
                        StatusChip('${p.contributors} contributor${p.contributors == 1 ? '' : 's'}', Tone.neutral,
                            dense: true, showIcon: false),
                      ],
                    ),
                    if (p.createdBy != null) ...[
                      const SizedBox(height: 8),
                      Text('Created by ${p.createdBy}', style: const TextStyle(color: AppColors.subtle, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              empty: const EmptyState(icon: Icons.folder_off_outlined, title: 'No projects'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectFormSheet extends StatefulWidget {
  const _ProjectFormSheet();

  @override
  State<_ProjectFormSheet> createState() => _ProjectFormSheetState();
}

class _ProjectFormSheetState extends State<_ProjectFormSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  bool _active = true;
  bool _public = false;
  bool _busy = false;
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Project name is required.');
      return;
    }
    setState(() {
      _busy = true;
      _nameError = null;
    });
    try {
      final res = asMap(await context.read<Session>().api.post('/projects/', {
        'name': _name.text.trim(),
        'description': _desc.text.trim(),
        'is_active': _active,
        'is_public': _public,
      }));
      if (!mounted) return;
      showSnack(context, asString(res['detail'], 'Project created'));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _nameError = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
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
              const Text('New project', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                decoration: appInput('Project name', icon: Icons.folder_rounded, errorText: _nameError),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                minLines: 2,
                maxLines: 5,
                decoration: appInput('Description', icon: Icons.notes_rounded),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: const Text('Active', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Only active projects can receive timesheet entries'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _public,
                onChanged: (v) => setState(() => _public = v),
                title: const Text('Public', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Everyone can log time on a public project'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Create project'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CostFormSheet extends StatefulWidget {
  final ProjectInfo project;
  const _CostFormSheet({required this.project});

  @override
  State<_CostFormSheet> createState() => _CostFormSheetState();
}

class _CostFormSheetState extends State<_CostFormSheet> {
  static const _types = ['Travel', 'Visa Extraction', 'Other']; // same choices as projects.html
  static const _currencies = ['EGP', 'SAR', 'USD', 'EUR'];

  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _otherType = TextEditingController();
  String _type = 'Travel';
  String _currency = 'EGP';
  UserBrief? _employee;
  bool _busy = false;
  final Map<String, String> _errors = {};

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    _otherType.dispose();
    super.dispose();
  }

  Future<void> _pickEmployee() async {
    try {
      final meta = await context.read<Session>().meta();
      if (!mounted) return;
      final r = await showOptionsSheet<int>(context,
          title: 'Employee',
          searchable: true,
          selected: _employee?.id,
          options: [for (final u in meta.users) Option(u.id, u.fullName, subtitle: u.username, icon: Icons.person_rounded)]);
      if (r == null) return;
      setState(() {
        _employee = meta.users.firstWhere((u) => u.id == r.value);
        _errors.remove('employee');
      });
    } catch (e) {
      if (mounted) showSnack(context, errorText(e), error: true);
    }
  }

  Future<void> _submit() async {
    _errors.clear();
    final amount = double.tryParse(_amount.text.trim().replaceAll(',', ''));
    if (_employee == null) _errors['employee'] = 'Select the employee.';
    if (amount == null || amount <= 0) _errors['amount'] = 'Enter an amount greater than zero.';
    final costType = _type == 'Other' ? _otherType.text.trim() : _type;
    if (costType.isEmpty) _errors['cost_type'] = 'Describe the cost type.';
    setState(() {});
    if (_errors.isNotEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final res = asMap(await context.read<Session>().api.post('/projects/${widget.project.id}/costs/', {
        'employee': _employee!.id,
        'amount': _amount.text.trim().replaceAll(',', ''),
        'currency': _currency,
        'cost_type': costType,
        'notes': _notes.text.trim(),
      }));
      if (!mounted) return;
      showSnack(context, asString(res['detail'], 'Cost added'));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errors[e.field ?? 'amount'] = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
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
              const Text('Add project cost', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.text)),
              Text(widget.project.name, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              PickerField(
                label: 'Employee',
                value: _employee?.fullName,
                icon: Icons.person_rounded,
                errorText: _errors['employee'],
                onTap: _pickEmployee,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: appInput('Amount', icon: Icons.payments_outlined, errorText: _errors['amount']),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: PickerField(
                      label: 'Currency',
                      value: _currency,
                      icon: Icons.currency_exchange_rounded,
                      onTap: () async {
                        final r = await showOptionsSheet<String>(context,
                            title: 'Currency',
                            selected: _currency,
                            options: [for (final c in _currencies) Option(c, c)]);
                        if (r != null) setState(() => _currency = r.value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Cost type', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.text)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _types)
                    ChoiceChip(
                      label: Text(t),
                      selected: _type == t,
                      showCheckmark: false,
                      selectedColor: AppColors.indigo,
                      labelStyle: TextStyle(color: _type == t ? Colors.white : AppColors.text, fontWeight: FontWeight.w600),
                      onSelected: (_) => setState(() => _type = t),
                    ),
                ],
              ),
              if (_type == 'Other') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _otherType,
                  decoration: appInput('Other cost type', icon: Icons.edit_note_rounded, errorText: _errors['cost_type']),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                minLines: 2,
                maxLines: 4,
                decoration: appInput('Notes', icon: Icons.notes_rounded),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Add cost'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
