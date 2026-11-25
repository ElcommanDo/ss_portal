import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'theme.dart';

class Fmt {
  static final DateFormat _day = DateFormat('EEE, d MMM yyyy');
  static final DateFormat _dayShort = DateFormat('d MMM');
  static final DateFormat _dayMonthYear = DateFormat('d MMM yyyy');
  static final DateFormat _weekday = DateFormat('EEEE');
  static final DateFormat _weekdayShort = DateFormat('EEE');
  static final DateFormat _monthYear = DateFormat('MMMM yyyy');
  static final DateFormat _dateTime = DateFormat('d MMM yyyy, hh:mm a');
  static final DateFormat _iso = DateFormat('yyyy-MM-dd');
  static final DateFormat _isoMonth = DateFormat('yyyy-MM');

  static String day(DateTime? d) => d == null ? '—' : _day.format(d);
  static String dayShort(DateTime? d) => d == null ? '—' : _dayShort.format(d);
  static String date(DateTime? d) => d == null ? '—' : _dayMonthYear.format(d);
  static String weekday(DateTime? d) => d == null ? '' : _weekday.format(d);
  static String weekdayShort(DateTime? d) => d == null ? '' : _weekdayShort.format(d);
  static String monthYear(DateTime? d) => d == null ? '' : _monthYear.format(d);
  static String dateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d);
  static String iso(DateTime d) => _iso.format(d);
  static String isoMonth(DateTime d) => _isoMonth.format(d);

  static String time(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay? parseTime(String? s) {
    if (s == null || s.length < 4) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  /// 12h label for a "HH:MM" string.
  static String time12(String? s) {
    final t = parseTime(s);
    if (t == null) return '—';
    final h = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final suffix = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$h:${t.minute.toString().padLeft(2, '0')} $suffix';
  }

  /// 7.5 -> "7.5", 8 -> "8", 2.3333 -> "2.33"
  static String dec(double v, {int decimals = 2}) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    var s = v.toStringAsFixed(decimals);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static String hours(double v) => '${dec(v)}h';

  /// 2.3333 -> "2h 20m"
  static String hm(double hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  static String percent(double v) => '${v.toStringAsFixed(v >= 100 || v == v.roundToDouble() ? 0 : 1)}%';

  static String money(double v) => NumberFormat('#,##0.##').format(v);

  static String capitalize(String s) =>
      s.isEmpty ? s : s.split(RegExp(r'[_\s]+')).map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  static String relativeDays(int days) {
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    return '$days days ago';
  }
}

/// Colour pairs for status chips — colour is never the only signal (labels/icons are always shown).
class Tone {
  final Color fg;
  final Color bg;
  final IconData icon;
  const Tone(this.fg, this.bg, this.icon);

  static const Tone success = Tone(AppColors.success, AppColors.successBg, Icons.check_circle_rounded);
  static const Tone warning = Tone(AppColors.warning, AppColors.warningBg, Icons.schedule_rounded);
  static const Tone danger = Tone(AppColors.danger, AppColors.dangerBg, Icons.error_rounded);
  static const Tone info = Tone(AppColors.info, AppColors.infoBg, Icons.autorenew_rounded);
  static const Tone neutral = Tone(AppColors.muted, AppColors.greyBg, Icons.circle_outlined);
  static const Tone brand = Tone(AppColors.indigo, AppColors.indigoBg, Icons.bolt_rounded);

  static Tone forStatus(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
      case 'completed':
        return success;
      case 'rejected':
      case 'cancelled':
        return danger;
      case 'in_progress':
      case 'inprogress':
        return info;
      case 'pending':
      case 'draft':
        return warning;
      default:
        return neutral;
    }
  }

  static Tone forPriority(String p) {
    switch (p.toLowerCase()) {
      case 'high':
        return const Tone(AppColors.danger, AppColors.dangerBg, Icons.keyboard_double_arrow_up_rounded);
      case 'medium':
        return const Tone(AppColors.warning, AppColors.warningBg, Icons.drag_handle_rounded);
      case 'low':
        return const Tone(AppColors.success, AppColors.successBg, Icons.keyboard_double_arrow_down_rounded);
      default:
        return neutral;
    }
  }

  /// Utilisation / compliance percentage bands.
  static Tone forPercent(double pct) {
    if (pct >= 90) return success;
    if (pct >= 70) return info;
    if (pct >= 50) return warning;
    return danger;
  }
}
