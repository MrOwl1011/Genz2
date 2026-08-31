import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/build_flavor.dart' show kIsTvRemote;

/// Joins D-pad focus traversal and rebuilds [builder] whenever focus enters
/// or leaves, so each TV control can render its *own* focused appearance.
///
/// This is the difference from [TvFocusable], which paints one fixed
/// highlight (accent border + glow) around an arbitrary child: the TV UI
/// needs controls that change their fill and content colours when focused,
/// which can only be done by the control itself. Both coexist — the phone
/// screens keep using [TvFocusable].
///
/// DPAD_CENTER / Enter / gamepad-A activate the control, exactly as a tap
/// does, so the same widget is driveable by remote or touchscreen.
class TvFocusScope extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Notified whenever D-pad focus enters or leaves this control — for
  /// controls where something besides the control's own appearance needs to
  /// react to focus moving across them (e.g. a channel list updating a live
  /// preview pane as focus passes over each row), distinct from [onTap]
  /// which only fires on an actual select/Enter press.
  final ValueChanged<bool>? onFocusChange;

  const TvFocusScope({
    super.key,
    required this.builder,
    this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
  });

  @override
  State<TvFocusScope> createState() => _TvFocusScopeState();
}

class _TvFocusScopeState extends State<TvFocusScope> {
  bool _focused = false;
  Timer? _activationCooldown;

  @override
  void dispose() {
    _activationCooldown?.cancel();
    super.dispose();
  }

  /// Some Android TV devices surface a single DPAD_CENTER/Enter press as
  /// *both* a raw key event (handled below via onKeyEvent) *and* a
  /// synthesized accessibility tap on the focused widget's semantics node
  /// — which lands on GestureDetector.onTap for the exact same physical
  /// press. Without a guard, [widget.onTap] then fires twice back to back;
  /// several call sites (see TvSidebar's callers) compose a pop-then-push
  /// in that callback, so a double-fire pops/pushes twice — sometimes
  /// netting out to nothing visible, sometimes landing one screen deeper
  /// than intended on unrelated content. This is the fix for both of
  /// those: only the first activation within a short window actually
  /// calls through.
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
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        widget.onFocusChange?.call(focused);
      },
      onKeyEvent: _handleKey,
      child: GestureDetector(
        onTap: _activate,
        behavior: HitTestBehavior.opaque,
        // Real D-pad focus state still drives everything functional above
        // (traversal, activation, widget.onFocusChange) — only what gets
        // *painted* is suppressed on iPad. The whole point of a focus ring/
        // scale/glow is answering "what will OK activate", which is
        // meaningless without a D-pad: on a touchscreen, tapping directly
        // is the activation, and a highlight nobody asked for (e.g. sitting
        // on whichever poster/tile happened to autofocus when the screen
        // first built) reads as a stray, unexplained selection instead.
        child: widget.builder(context, _focused && kIsTvRemote),
      ),
    );
  }
}
