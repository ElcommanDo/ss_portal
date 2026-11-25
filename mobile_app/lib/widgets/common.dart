import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../core/theme.dart';

// --------------------------------------------------------------------------
// Layout
// --------------------------------------------------------------------------

/// Keeps content readable on tablets / landscape: centred with a max width.
class ResponsiveCenter extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  const ResponsiveCenter({super.key, required this.child, this.maxWidth = 760, this.padding = EdgeInsets.zero});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Horizontal page padding that grows a little on bigger phones / tablets.
double pagePadding(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= 600) return 24;
  if (w >= 380) return 16;
  return 12;
}

/// Number of grid columns for tiles at the given available width.
int gridColumns(double width, {double minTileWidth = 160, int minColumns = 2, int maxColumns = 4}) {
  final c = (width / minTileWidth).floor();
  if (c < minColumns) return minColumns;
  if (c > maxColumns) return maxColumns;
  return c;
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color color;
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color = AppColors.surface,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? AppColors.border),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry padding;

  const SectionTitle(this.title,
      {super.key, this.actionLabel, this.onAction, this.padding = const EdgeInsets.fromLTRB(4, 20, 4, 10)});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text),
            ),
          ),
          if (actionLabel != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String label;
  final Tone tone;
  final bool showIcon;
  final bool dense;

  const StatusChip(this.label, this.tone, {super.key, this.showIcon = true, this.dense = false});

  factory StatusChip.status(String status, {Key? key, bool dense = false}) =>
      StatusChip(Fmt.capitalize(status.toLowerCase()), Tone.forStatus(status), key: key, dense: dense);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(30)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(tone.icon, size: dense ? 12 : 14, color: tone.fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(color: tone.fg, fontSize: dense ? 11 : 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color fg;
  final Color bg;
  final double size;

  const IconBadge(this.icon, {super.key, this.fg = AppColors.indigo, this.bg = AppColors.indigoBg, this.size = 42});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.32)),
      child: Icon(icon, color: fg, size: size * 0.52),
    );
  }
}

class Avatar extends StatelessWidget {
  final String initials;
  final double size;
  final Color bg;
  final Color fg;

  const Avatar(this.initials, {super.key, this.size = 40, this.bg = AppColors.indigoBg, this.fg = AppColors.indigo});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        initials,
        style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: size * 0.38),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Tone tone;
  final String? caption;
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = Tone.brand,
    this.caption,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBadge(icon, fg: tone.fg, bg: tone.bg, size: 36),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.text),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, color: AppColors.muted, fontWeight: FontWeight.w600),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.subtle)),
          ],
        ],
      ),
    );
  }
}

/// Grid of equally sized tiles that adapts its column count to the width.
class TileGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final double spacing;
  final int minColumns;

  const TileGrid({super.key, required this.children, this.minTileWidth = 160, this.spacing = 12, this.minColumns = 2});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cols = gridColumns(constraints.maxWidth, minTileWidth: minTileWidth, minColumns: minColumns);
      final tileWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final c in children) SizedBox(width: tileWidth, child: c)],
      );
    });
  }
}

class ProgressLine extends StatelessWidget {
  final double value; // 0..1 (clamped)
  final Color color;
  final double height;

  const ProgressLine({super.key, required this.value, this.color = AppColors.indigo, this.height = 8});

  @override
  Widget build(BuildContext context) {
    final double v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0).toDouble();
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: LinearProgressIndicator(
        value: v,
        minHeight: height,
        backgroundColor: AppColors.greyBg,
        valueColor: AlwaysStoppedAnimation<Color>(color),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoRow(this.icon, this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 10),
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------------
// States
// --------------------------------------------------------------------------

class LoadingView extends StatelessWidget {
  final String? message;
  const LoadingView({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 3)),
            if (message != null) ...[
              const SizedBox(height: 14),
              Text(message!, style: const TextStyle(color: AppColors.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(icon, size: 72, fg: AppColors.blue, bg: AppColors.cyanBg),
            const SizedBox(height: 18),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const ErrorState({super.key, required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconBadge(Icons.cloud_off_rounded, size: 72, fg: AppColors.danger, bg: AppColors.dangerBg),
            const SizedBox(height: 18),
            const Text('Something went wrong',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.text)),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String errorText(Object error) {
  if (error is ApiException) return error.message;
  return 'Unexpected error: $error';
}

/// Loads data once, shows loading / error / content, supports pull-to-refresh.
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  const Loader({super.key, required this.load, required this.builder});

  @override
  State<Loader<T>> createState() => LoaderState<T>();
}

class LoaderState<T> extends State<Loader<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (_loading && data == null) return const LoadingView();
    if (_error != null && data == null) {
      return ErrorState(message: errorText(_error!), onRetry: reload);
    }
    if (data == null) return const LoadingView();
    return widget.builder(context, data, reload);
  }
}

/// Infinite-scroll list for paginated endpoints, with pull-to-refresh.
class PagedList<T> extends StatefulWidget {
  final Future<PageResult<T>> Function(int page) fetch;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final Widget Function(BuildContext context, PageResult<T>? first)? headerBuilder;
  final Widget? empty;
  final EdgeInsetsGeometry? padding;
  final double itemSpacing;

  const PagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.headerBuilder,
    this.empty,
    this.padding,
    this.itemSpacing = 10,
  });

  @override
  State<PagedList<T>> createState() => PagedListState<T>();
}

class PagedListState<T> extends State<PagedList<T>> {
  final List<T> _items = [];
  final ScrollController _scroll = ScrollController();
  PageResult<T>? _first;
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> refresh() async {
    _generation++;
    setState(() {
      _items.clear();
      _first = null;
      _page = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final gen = _generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.fetch(_page + 1);
      if (!mounted || gen != _generation) return;
      setState(() {
        _first ??= result;
        _items.addAll(result.results);
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pad = widget.padding ?? EdgeInsets.fromLTRB(pagePadding(context), 8, pagePadding(context), 96);
    final header = widget.headerBuilder?.call(context, _first);
    final showInitialError = _error != null && _items.isEmpty;
    final showEmpty = !_loading && _error == null && _items.isEmpty;

    final children = <Widget>[];
    if (header != null) children.add(header);
    if (_loading && _items.isEmpty) {
      children.add(const Padding(padding: EdgeInsets.only(top: 40), child: LoadingView()));
    } else if (showInitialError) {
      children.add(ErrorState(message: errorText(_error!), onRetry: refresh));
    } else if (showEmpty) {
      children.add(widget.empty ?? const EmptyState(icon: Icons.inbox_rounded, title: 'Nothing here yet'));
    }

    final itemCount = _items.length;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        itemCount: children.length + itemCount + 1,
        itemBuilder: (context, index) {
          if (index < children.length) {
            return ResponsiveCenter(child: children[index]);
          }
          final i = index - children.length;
          if (i < itemCount) {
            return ResponsiveCenter(
              child: Padding(
                padding: EdgeInsets.only(bottom: widget.itemSpacing),
                child: widget.itemBuilder(context, _items[i], i),
              ),
            );
          }
          // footer
          if (_items.isEmpty) return const SizedBox.shrink();
          if (_loading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
            );
          }
          if (_error != null) {
            return Center(
              child: TextButton.icon(
                onPressed: _loadMore,
                icon: const Icon(Icons.refresh_rounded),
                label: Text('Could not load more — ${errorText(_error!)}'),
              ),
            );
          }
          if (!_hasMore && itemCount > 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  '${_first?.count ?? itemCount} item${(_first?.count ?? itemCount) == 1 ? '' : 's'}',
                  style: const TextStyle(color: AppColors.subtle, fontSize: 12),
                ),
              ),
            );
          }
          return const SizedBox(height: 40);
        },
      ),
    );
  }
}

// --------------------------------------------------------------------------
// Feedback helpers
// --------------------------------------------------------------------------

void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      backgroundColor: error ? AppColors.danger : AppColors.navy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: Duration(seconds: error ? 5 : 3),
    ),
  );
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
        ElevatedButton(
          style: destructive ? ElevatedButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Brand gradient banner used at the top of the dashboards.
class GradientBanner extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GradientBanner({super.key, required this.child, this.padding = const EdgeInsets.all(20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x332E3192), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: const BoxDecoration(color: AppColors.overlayWhite12, shape: BoxShape.circle),
            ),
          ),
          Positioned(
            right: 50,
            bottom: -60,
            child: Container(
              width: 120,
              height: 120,
              decoration: const BoxDecoration(color: AppColors.overlayWhite12, shape: BoxShape.circle),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// Small rounded "filter" chip used in filter bars.
class FilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const FilterPill({super.key, required this.label, required this.icon, required this.onTap, this.active = false, this.onClear});

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AppColors.text;
    return Material(
      color: active ? AppColors.indigo : AppColors.surface,
      shape: StadiumBorder(side: BorderSide(color: active ? AppColors.indigo : AppColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13)),
              ),
              if (active && onClear != null) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: onClear,
                  child: const Icon(Icons.close_rounded, size: 16, color: Colors.white),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class FilterBar extends StatelessWidget {
  final List<Widget> children;
  const FilterBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(horizontal: pagePadding(context), vertical: 6),
      child: Row(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}
