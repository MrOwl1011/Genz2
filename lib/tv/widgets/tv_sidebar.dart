import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/app_colors.dart';
import '../tv_metrics.dart';
import 'tv_focus.dart';
import 'tv_nav_bar.dart' show TvSection;

/// The five permanent destinations of the TV app, top to bottom.
enum TvSidebarItem { search, movies, series, live, settings }

/// The persistent left-side navigation rail — replaces the old top
/// `TvNavBar`.
///
/// A vertical list reads more naturally on a remote than a horizontal one:
/// Up/Down moves between destinations, Left/Right moves in and out of it,
/// which is the same axis pair D-pad users already use to move between
/// posters within a content row. Staying icon-only until focus actually
/// arrives keeps almost the whole screen free for artwork, which a fixed
/// top bar never gave back.
///
/// Purely an overlay: expanding never changes surrounding layout by itself
/// — it just draws further over the first ~150px of whatever's underneath.
/// Callers (TvHomeScreen, TvLiveScreen) reserve a fixed
/// `TvMetrics.sidebarCollapsedWidth` left inset for the resting icon rail;
/// nothing needs to know this widget's expanded/collapsed state to lay out
/// correctly, so there's no layout jank while the user navigates in and out
/// of it.
class TvSidebar extends StatefulWidget {
  /// Which persistent section (Movies/Series/Live) is currently "shown"
  /// behind/before this rail — null if none should highlight (not
  /// currently used by either caller, but keeps this honest about Search/
  /// Settings never having one).
  final TvSection? active;

  /// Which item Left should land on when the D-pad arrives at this rail
  /// from content — "current page" in the sense that matters for
  /// navigation, not just [active]'s narrower "does this get the gradient
  /// highlight" question (Search and Settings are a `currentItem` each,
  /// but never an [active] TvSection). Every caller has exactly one
  /// unambiguous answer: TvHomeScreen tracks whichever of movies/series is
  /// showing, TvLiveScreen is always `.live`, TvSearchScreen is always
  /// `.search`, TvSettingsScreen is always `.settings`.
  final TvSidebarItem currentItem;

  final ValueChanged<TvSidebarItem> onSelect;
  final bool isArabic;

  /// Fired every time focus lands anywhere in the sidebar (not just once
  /// per expand) — lets the caller do things like re-sync its own
  /// content's scroll position, the way arriving at the old top nav bar
  /// used to.
  final VoidCallback? onFocusEnter;

  /// Fired when Right is pressed while focus is anywhere in the sidebar,
  /// *instead of* falling through to Flutter's default directional
  /// traversal. Left is already fully owned (see [currentItem]'s doc
  /// comment) — this is the same fix applied to the other direction: the
  /// default nearest-rect heuristic has no reason to prefer "the item that
  /// was focused before I came here" over "whatever's geometrically
  /// closest to wherever I am in the sidebar right now", which is exactly
  /// why leaving via Right could land on a different poster than the one
  /// the user actually left. A caller that supplies this is expected to
  /// restore focus to something real itself; a caller that doesn't gets
  /// the previous (default traversal) behavior unchanged.
  final VoidCallback? onExitRight;

  const TvSidebar({
    super.key,
    required this.active,
    required this.currentItem,
    required this.onSelect,
    required this.isArabic,
    this.onFocusEnter,
    this.onExitRight,
  });

  @override
  State<TvSidebar> createState() => _TvSidebarState();
}

class _TvSidebarState extends State<TvSidebar> {
  bool _expanded = false;

  // One persistent FocusNode per item (not anonymous ones TvFocusScope
  // would otherwise create internally) — owning them here is what makes
  // _handleFocusChange able to explicitly redirect to a *specific* item
  // below, rather than accepting whatever Flutter's default geometric
  // traversal happened to land on.
  late final Map<TvSidebarItem, FocusNode> _itemNodes = {
    for (final item in TvSidebarItem.values)
      item: FocusNode(debugLabel: 'sidebar-${item.name}'),
  };

  @override
  void dispose() {
    for (final node in _itemNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleFocusChange(bool hasFocus) {
    if (hasFocus) {
      widget.onFocusEnter?.call();
      // Default directional traversal already ran and landed on whichever
      // item was geometrically nearest to wherever focus came from — which
      // is exactly the wrong idea here (see currentItem's doc comment):
      // Left from deep in a Movies row landing on Search just because
      // Search happens to sit at that row's height reads as broken, not
      // helpful. Runs after that default landing (post-frame) and
      // overrides it to the one item that's actually correct for "where
      // the user currently is" — but only on the false→true transition, so
      // deliberate Up/Down movement *within* an already-focused sidebar is
      // never fought.
      final target = _itemNodes[widget.currentItem];
      if (target != null && !target.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) target.requestFocus();
        });
      }
    }
    if (hasFocus == _expanded) return;
    setState(() => _expanded = hasFocus);
  }

  /// Takes Up/Down over completely while focus is anywhere inside this
  /// rail, instead of leaving them to Flutter's default directional
  /// traversal. That default picks whichever focusable node is
  /// geometrically nearest in the given direction across the *whole*
  /// screen — including the page content behind this overlay — so moving
  /// Up from the bottom item could land on a settings tile instead of the
  /// sidebar item directly above it. Explicitly walking [_itemNodes] in
  /// order guarantees Up/Down only ever move between sidebar items, and
  /// simply stop (rather than escaping into content) at the top/bottom
  /// ends — matching how Left is the only way in and Right/select the only
  /// way back out.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight && widget.onExitRight != null) {
      widget.onExitRight!();
      return KeyEventResult.handled;
    }
    if (key != LogicalKeyboardKey.arrowUp && key != LogicalKeyboardKey.arrowDown) {
      return KeyEventResult.ignored;
    }
    // Reaching this handler at all means the currently focused node is a
    // descendant of this rail (key events bubble from the focused leaf up
    // through its ancestors' onKeyEvent, in order) — so from here on every
    // outcome is KeyEventResult.handled, never ignored. Falling through to
    // ignored would hand the key back to Flutter's default directional
    // traversal, which is the exact geometric-nearest-node behavior this
    // whole handler exists to override; swallowing it and doing nothing on
    // an unresolved lookup is strictly safer than risking that escape.
    final items = TvSidebarItem.values;
    final currentIndex = items.indexWhere((item) => _itemNodes[item]!.hasFocus);
    if (currentIndex != -1) {
      final nextIndex = currentIndex + (key == LogicalKeyboardKey.arrowUp ? -1 : 1);
      if (nextIndex >= 0 && nextIndex < items.length) {
        _itemNodes[items[nextIndex]]!.requestFocus();
      }
    }
    return KeyEventResult.handled;
  }

  String _label(TvSidebarItem item) {
    switch (item) {
      case TvSidebarItem.search:
        return widget.isArabic ? 'بحث' : 'Search';
      case TvSidebarItem.movies:
        return widget.isArabic ? 'أفلام' : 'Movies';
      case TvSidebarItem.series:
        return widget.isArabic ? 'مسلسلات' : 'Series';
      case TvSidebarItem.live:
        return widget.isArabic ? 'مباشر' : 'Live TV';
      case TvSidebarItem.settings:
        return widget.isArabic ? 'الإعدادات' : 'Settings';
    }
  }

  IconData _icon(TvSidebarItem item) {
    switch (item) {
      case TvSidebarItem.search:
        return Icons.search_rounded;
      case TvSidebarItem.movies:
        return Icons.movie_rounded;
      case TvSidebarItem.series:
        return Icons.video_library_rounded;
      case TvSidebarItem.live:
        return Icons.live_tv_rounded;
      case TvSidebarItem.settings:
        return Icons.settings_rounded;
    }
  }

  /// Search and Settings are one-shot actions (push a route, hand control
  /// straight back) rather than a persistent "you are here" body the way
  /// Movies/Series/Live are, so they never show the selected treatment —
  /// matching how the old nav bar's action icons never did either.
  bool _isActive(TvSidebarItem item) {
    switch (item) {
      case TvSidebarItem.movies:
        return widget.active == TvSection.movies;
      case TvSidebarItem.series:
        return widget.active == TvSection.series;
      case TvSidebarItem.live:
        return widget.active == TvSection.live;
      case TvSidebarItem.search:
      case TvSidebarItem.settings:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Focus(
      // Not focusable itself and skipped by traversal — purely an observer
      // for "is focus somewhere inside this subtree right now", which is
      // what drives the expand/collapse animation.
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _handleFocusChange,
      onKeyEvent: _handleKeyEvent,
      child: AnimatedContainer(
        duration: TvMetrics.sidebarAnim,
        curve: Curves.easeOut,
        width: _expanded
            ? TvMetrics.sidebarExpandedWidth
            : TvMetrics.sidebarCollapsedWidth,
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: _expanded ? 0.97 : 0),
          boxShadow: _expanded
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(10, 0),
                  ),
                ]
              : null,
        ),
        // No SafeArea of its own — both callers already wrap their whole
        // body in one, and this sits inside that same safe region; a
        // second SafeArea here would double up the top/left inset.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            // Centered rather than top-anchored — five items pinned to the
            // top of a full-height rail reads as "stuck near the header"
            // on a TV screen; centering them makes the rail feel like a
            // deliberate, balanced piece of the layout instead.
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final item in TvSidebarItem.values) ...[
                _SidebarItemTile(
                  focusNode: _itemNodes[item]!,
                  icon: _icon(item),
                  label: _label(item),
                  expanded: _expanded,
                  active: _isActive(item),
                  onTap: () => widget.onSelect(item),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItemTile extends StatelessWidget {
  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final bool expanded;
  final bool active;
  final VoidCallback onTap;

  const _SidebarItemTile({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.expanded,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return TvFocusScope(
      focusNode: focusNode,
      onTap: onTap,
      builder: (context, focused) {
        return AnimatedContainer(
          duration: TvMetrics.focusAnim,
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: active
                ? LinearGradient(colors: colors.brandGradient)
                : null,
            color: active
                ? null
                : (focused ? colors.surfaceElevated : Colors.transparent),
            border: Border.all(
              color: focused ? colors.ink : Colors.transparent,
              width: 1.5,
            ),
          ),
          // Belt-and-suspenders against the label ever peeking past this
          // tile's own bounds mid-animation (see the duration note below) —
          // clips instead of letting a stray pixel trigger a RenderFlex
          // overflow warning in debug builds (invisible either way in
          // release, but the underlying transient mismatch is real either
          // build).
          child: ClipRect(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Fixed-width slot so every item's icon lines up on the same
                // left edge regardless of that particular glyph's own
                // intrinsic bounding-box width (Icons.movie_rounded and
                // Icons.settings_rounded, for instance, aren't the same
                // visual width at the same `size`).
                SizedBox(
                  width: 24,
                  child: Icon(
                    icon,
                    size: 22,
                    color: active || focused
                        ? Colors.white
                        : colors.ink.withValues(alpha: 0.75),
                  ),
                ),
                AnimatedAlign(
                  // Matches the rail's own width animation exactly (not
                  // focusAnim, which is faster) — the label's reveal must
                  // never outpace how wide the rail has actually grown, or
                  // it demands more width than exists yet for a few frames.
                  duration: TvMetrics.sidebarAnim,
                  curve: Curves.easeOut,
                  alignment: Alignment.centerLeft,
                  widthFactor: expanded ? 1 : 0,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: AnimatedOpacity(
                      duration: TvMetrics.sidebarAnim,
                      opacity: expanded ? 1 : 0,
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        softWrap: false,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: active ? Colors.white : colors.ink,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
