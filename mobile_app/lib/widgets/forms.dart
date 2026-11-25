import 'package:flutter/material.dart';

import '../core/theme.dart';

InputDecoration appInput(String label, {IconData? icon, String? hint, String? errorText, Widget? suffix}) {
  OutlineInputBorder border(Color c, [double w = 1.2]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: errorText,
    errorMaxLines: 3,
    prefixIcon: icon == null ? null : Icon(icon, color: AppColors.muted),
    suffixIcon: suffix,
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border(AppColors.border),
    enabledBorder: border(AppColors.border),
    focusedBorder: border(AppColors.indigo, 1.8),
    errorBorder: border(AppColors.danger),
    focusedErrorBorder: border(AppColors.danger, 1.8),
  );
}

/// A read-only field that opens a picker (date, time, list...) when tapped.
class PickerField extends StatelessWidget {
  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback? onTap;
  final String? errorText;
  final String placeholder;
  final VoidCallback? onClear;

  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.errorText,
    this.placeholder = 'Select',
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null && value!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        isEmpty: false,
        decoration: appInput(
          label,
          icon: icon,
          errorText: errorText,
          suffix: hasValue && onClear != null
              ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClear, tooltip: 'Clear')
              : const Icon(Icons.expand_more_rounded, color: AppColors.muted),
        ),
        child: Text(
          hasValue ? value! : placeholder,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15.5,
            color: hasValue ? AppColors.text : AppColors.subtle,
            fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class Option<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  const Option(this.value, this.label, {this.subtitle, this.icon});
}

/// Bottom sheet list with optional search. Returns the chosen option or null.
Future<Option<T>?> showOptionsSheet<T>(
  BuildContext context, {
  required String title,
  required List<Option<T>> options,
  T? selected,
  bool searchable = false,
}) {
  return showModalBottomSheet<Option<T>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => _OptionsSheet<T>(title: title, options: options, selected: selected, searchable: searchable),
  );
}

class _OptionsSheet<T> extends StatefulWidget {
  final String title;
  final List<Option<T>> options;
  final T? selected;
  final bool searchable;

  const _OptionsSheet({super.key, required this.title, required this.options, this.selected, required this.searchable});

  @override
  State<_OptionsSheet<T>> createState() => _OptionsSheetState<T>();
}

class _OptionsSheetState<T> extends State<_OptionsSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final items = q.isEmpty
        ? widget.options
        : widget.options
            .where((o) => o.label.toLowerCase().contains(q) || (o.subtitle ?? '').toLowerCase().contains(q))
            .toList();
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(widget.title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.text)),
            ),
            if (widget.searchable)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: false,
                  decoration: appInput('Search', icon: Icons.search_rounded),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
            Flexible(
              child: items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No matches', textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final o = items[i];
                        final isSelected = widget.selected != null && o.value == widget.selected;
                        return ListTile(
                          leading: o.icon == null ? null : Icon(o.icon, color: AppColors.blue),
                          title: Text(o.label,
                              style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
                          subtitle: o.subtitle == null ? null : Text(o.subtitle!),
                          trailing: isSelected ? const Icon(Icons.check_circle_rounded, color: AppColors.indigo) : null,
                          onTap: () => Navigator.of(ctx).pop(o),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<DateTime?> pickDate(
  BuildContext context, {
  DateTime? initial,
  required DateTime first,
  required DateTime last,
  String? help,
}) {
  var init = initial ?? DateTime.now();
  if (init.isBefore(first)) init = first;
  if (init.isAfter(last)) init = last;
  return showDatePicker(
    context: context,
    initialDate: init,
    firstDate: first,
    lastDate: last,
    helpText: help,
  );
}

Future<TimeOfDay?> pickTime(BuildContext context, {TimeOfDay? initial, String? help}) {
  return showTimePicker(
    context: context,
    initialTime: initial ?? const TimeOfDay(hour: 9, minute: 0),
    helpText: help,
  );
}

/// Pick a month (YYYY-MM) from the last [count] months.
Future<DateTime?> pickMonth(BuildContext context, {DateTime? selected, int count = 24, String title = 'Choose month'}) async {
  final now = DateTime.now();
  final options = <Option<DateTime>>[];
  for (int i = 0; i < count; i++) {
    final d = DateTime(now.year, now.month - i, 1);
    const names = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October',
      'November', 'December'];
    options.add(Option(d, '${names[d.month - 1]} ${d.year}', icon: Icons.calendar_month_rounded));
  }
  DateTime? sel;
  if (selected != null) sel = DateTime(selected.year, selected.month, 1);
  final r = await showOptionsSheet<DateTime>(context, title: title, options: options, selected: sel);
  return r?.value;
}
