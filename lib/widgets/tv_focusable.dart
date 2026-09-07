import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/build_flavor.dart' show kIsTv, kIsTvRemote;

/// Wraps [child] so it's properly navigable with a D-pad/TV remote: joins
/// focus traversal (so DPAD up/down/left/right can reach it at all) and
/// shows a clear highlight whenever it's the currently focused item.
///
/// This matters specifically for TV: there's no cursor or touch equivalent,
/// so without an obvious highlight a user navigating by remote has no way
/// to tell what's currently selected. [onTap] fires on DPAD_CENTER/Enter/
/// gamepad-A as well as a plain tap, so the exact same widget works
/// identically whether driven by a remote or a touchscreen — nothing about
/// existing touch behavior changes.
///
/// The highlight is deliberately a clean white rim plus a lift-and-shadow,
/// rather than a saturated accent glow: on a large panel viewed from across
/// a room a neon ring reads as harsh and cheap, while a bright rim with real
/// elevation is what mainstream TV interfaces use and stays legible over
/// arbitrary poster art of any colour.
class TvFocusable extends StatefulWidget {
  /// Width of the focus ring, which is painted at all times — transparent
  /// when unfocused — so a card never changes size as focus moves.
  ///
  /// It is therefore permanent padding around every child: a card inside one
  /// of these occupies its own height plus [focusInset]. Any row or grid
  /// sizing a TvFocusable child has to include that, or the child overflows
  /// by exactly this much. See _PosterCard.totalHeight and friends.
  static const double focusBorderWidth = 3;

  /// Total vertical (and horizontal) space the ring adds to a child.
  static const double focusInset = focusBorderWidth * 2;

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadiusGeometry borderRadius;
  final bool autofocus;

  /// Only ever supplied by a screen restoring a remembered focus position
  /// (e.g. TvMediaGridScreen/TvFavoritesScreen returning from a detail
  /// screen) — every ordinary use leaves this null and lets the internal
  /// `Focus` create/own its own node, same as before.
  final FocusNode? focusNode;

  const TvFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.autofocus = false,
    this.focusNode,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;
  Timer? _activationCooldown;

  @override
  void dispose() {
    _activationCooldown?.cancel();
    super.dispose();
  }

  /// Some Android TV devices surface a single DPAD_CENTER/Enter press as
  /// both a raw key event (below) and a synthesized accessibility tap on
  /// the focused widget (landing on GestureDetector.onTap) for the same
  /// physical press — without a guard, [widget.onTap] fires twice for one
  /// press. See TvFocusScope's identical fix for the full reasoning (same
  /// underlying issue, same shape here since this widget wires both paths
  /// the same way).
  void _activate() {
    if (_activationCooldown?.isActive ?? false) return;
    _activationCooldown = Timer(const Duration(milliseconds: 300), () {});
    widget.onTap?.call();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // On TV this fires on every single D-pad move across a grid full of
    // these — a real (if short) animation on each one is exactly the kind
    // of per-frame compositing cost that adds up to visible stutter on
    // budget TV hardware. Phone/tablet keep the animation: there it's an
    // occasional tap, not a rapid-fire navigation signal, and the motion is
    // worth the polish there.
    final animate = !kIsTv;
    final duration = animate
        ? const Duration(milliseconds: 180)
        : Duration.zero;
    // Real focus state still drives traversal/activation regardless of
    // platform (Focus/onKeyEvent below are untouched) — this only affects
    // what gets *painted*. Suppressed specifically for "showing the TV UI
    // but no actual D-pad" (iPad, kIsTv true and kIsTvRemote false): the
    // ring/scale/glow exists to answer "what will OK activate", which has
    // no meaning without a remote, and would otherwise show a lingering
    // highlight on whatever autofocused when the screen built even before
    // any touch happened. Plain phone (kIsTv false) is unaffected either
    // way, since this widget is shared with several non-TV screens too.
    final showFocusVisuals = _focused && (!kIsTv || kIsTvRemote);
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (focused == _focused) return;
        setState(() => _focused = focused);
      },
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: _activate,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          // Scale is a GPU transform — effectively free even on the weak
          // GPUs in budget TV boxes, unlike animating layout or blur.
          scale: showFocusVisuals ? 1.07 : 1.0,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              // Always a 3px border, transparent when unfocused, so the
              // child never changes size as focus moves — a border that
              // appears from nothing would reflow the whole grid row.
              border: Border.all(
                color: showFocusVisuals ? Colors.white : Colors.transparent,
                width: TvFocusable.focusBorderWidth,
              ),
              boxShadow: showFocusVisuals
                  ? const [
                      BoxShadow(
                        color: Color(0x99000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
