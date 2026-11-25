import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/theme.dart';
import 'common.dart';

/// Downloads a PDF produced by the portal (same WeasyPrint templates as the web) and opens it.
Future<void> downloadAndOpenPdf(
  BuildContext context, {
  required String path,
  required Map<String, dynamic> query,
  required String fileName,
}) async {
  final api = context.read<Session>().api;
  showSnack(context, 'Preparing PDF…');
  try {
    final bytes = await api.getBytes(path, query: query);
    final dir = await getTemporaryDirectory();
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9_\-.]'), '_');
    final file = File('${dir.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    final result = await OpenFilex.open(file.path, type: 'application/pdf');
    if (!context.mounted) return;
    if (result.type != ResultType.done) {
      showSnack(context, 'PDF saved, but no app could open it: ${result.message}', error: true);
    } else {
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
  } catch (e) {
    if (context.mounted) showSnack(context, errorText(e), error: true);
  }
}

/// A labelled horizontal bar (used for utilisation / monthly / breakdowns).
class BarRow extends StatelessWidget {
  final String label;
  final String? sublabel;
  final String valueText;
  final double ratio;
  final Color color;
  final VoidCallback? onTap;
  final Widget? leading;

  const BarRow({
    super.key,
    required this.label,
    required this.valueText,
    required this.ratio,
    this.sublabel,
    this.color = AppColors.indigo,
    this.onTap,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.text, fontSize: 14)),
                      ),
                      const SizedBox(width: 8),
                      Text(valueText, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 14)),
                    ],
                  ),
                  if (sublabel != null) ...[
                    const SizedBox(height: 2),
                    Text(sublabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ],
                  const SizedBox(height: 6),
                  ProgressLine(value: ratio, color: color, height: 7),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right_rounded, color: AppColors.subtle),
          ],
        ),
      ),
    );
  }
}

/// Header block of a report: title, subtitle and a row of summary tiles.
class ReportSummary extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> tiles;

  const ReportSummary({super.key, required this.title, required this.subtitle, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GradientBanner(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: AppColors.overlayWhite70, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TileGrid(minTileWidth: 150, children: tiles),
        const SizedBox(height: 8),
      ],
    );
  }
}

String pctText(double v) => Fmt.percent(v);

/// Cached lookup lists (users, projects, teams). Shows a message and returns null on failure.
Future<MetaData?> loadMeta(BuildContext context) async {
  try {
    return await context.read<Session>().meta();
  } catch (e) {
    if (context.mounted) showSnack(context, errorText(e), error: true);
    return null;
  }
}
