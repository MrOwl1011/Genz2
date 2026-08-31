import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

/// A D-pad-safe search field: stays read-only (no on-screen keyboard) until
/// explicitly selected, exactly like the TV login screen's fields — see
/// login_screen.dart's `_activeEditingNode` for the full rationale. Android
/// auto-opens the on-screen keyboard the instant a text field gains focus,
/// even from mere D-pad navigation, and that keyboard then swallows every
/// further D-pad press for moving between its own keys rather than
/// navigating the rest of the screen.
///
/// A wrapping `Focus(onKeyEvent: ...)` can't catch the select/OK press
/// needed to opt in, either — `EditableText` binds arrow/select keys via
/// its own `Shortcuts` *inside* the field, closer to the focused leaf than
/// anything wrapping it, so it claims the event first. A
/// `HardwareKeyboard` handler sits one level below all of that and sees
/// every key press application-wide regardless of the focus tree, which is
/// the only layer left that can react to select while this field merely
/// has D-pad focus.
class TvSearchField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hint;
  final VoidCallback? onClose;
  // Fires on the IME's submit/done action, in addition to onChanged already
  // firing per-keystroke — for a screen where live-filtering an already
  // in-memory list isn't feasible (a cross-category search that needs a
  // real query first), this is the hook to act once the user's actually
  // finished typing, rather than on every character.
  final ValueChanged<String>? onSubmit;
  // This field typically only *appears* in response to selecting a search
  // icon elsewhere on the screen — that icon is then removed from the
  // tree, which leaves D-pad focus at null rather than moving it here on
  // its own. Without requesting focus explicitly, the very next D-pad
  // press has nothing to land on.
  final bool autofocus;

  const TvSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hint,
    this.onClose,
    this.onSubmit,
    this.autofocus = false,
  });

  @override
  State<TvSearchField> createState() => _TvSearchFieldState();
}

class _TvSearchFieldState extends State<TvSearchField> {
  final _focusNode = FocusNode();
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    HardwareKeyboard.instance.addHandler(_handleKey);
    if (widget.autofocus) {
      // Not the TextField's own `autofocus` prop — this field typically
      // appears by replacing a search-icon button that was itself focused
      // (see the class doc comment), and removing a focused widget makes
      // Flutter's FocusManager fall back to reassigning focus to whatever
      // else is nearby *as part of that same frame*, which can beat a
      // declarative `autofocus` to the punch and leave it stuck on, say,
      // the back button instead. Requesting focus in a post-frame callback
      // runs after that automatic reassignment has already settled, so it
      // reliably wins instead of racing it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _editing) {
      setState(() => _editing = false);
    }
  }

  /// Leaves edit mode: closes the on-screen keyboard and, when given a
  /// direction, hands focus on to whatever is next that way.
  void _stopEditing({TraversalDirection? move}) {
    setState(() => _editing = false);
    // Closing the IME explicitly rather than relying on readOnly flipping
    // back — the keyboard is a platform surface and does not reliably
    // dismiss itself just because the field stopped accepting input.
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    if (move != null) {
      // After this frame, so focus moves once the field has actually
      // rebuilt as read-only.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.focusInDirection(move);
      });
    }
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (FocusManager.instance.primaryFocus != _focusNode) return false;
    final key = event.logicalKey;

    // While typing, every D-pad press belongs to the keyboard — which is
    // what left the user stuck in here: the only way out was the IME's
    // submit action, so anyone who typed and then tried to simply navigate
    // away (down to the results, or back) found nothing responded. These
    // are the escape hatches. Handled here rather than in a wrapping
    // Focus for the same reason select is (see the class doc comment):
    // EditableText's own Shortcuts sit closer to the focused leaf and
    // would claim these first.
    if (_editing) {
      if (key == LogicalKeyboardKey.escape ||
          key == LogicalKeyboardKey.goBack) {
        // Stay on the field, just stop editing — a second back then
        // leaves the screen, which is what a user expects.
        _stopEditing();
        return true;
      }
      if (key == LogicalKeyboardKey.arrowDown) {
        _stopEditing(move: TraversalDirection.down);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        _stopEditing(move: TraversalDirection.up);
        return true;
      }
      return false;
    }

    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.gameButtonA) {
      setState(() => _editing = true);
      return true;
    }
    // Even read-only (not _editing), EditableText still binds left/right
    // for cursor movement within existing text — the same "closer to the
    // focused leaf, claims it first" problem the class doc comment already
    // describes for select/up/down, just for these two as well. Without
    // this, left/right silently moved a cursor nobody can see instead of
    // ever reaching the sidebar or anything else beside this field.
    if (key == LogicalKeyboardKey.arrowLeft) {
      _focusNode.focusInDirection(TraversalDirection.left);
      return true;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _focusNode.focusInDirection(TraversalDirection.right);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return ListenableBuilder(
      listenable: _focusNode,
      builder: (context, child) {
        final focused = _focusNode.hasFocus;
        return Container(
          height: 50,
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused
                  ? colors.brandAccent
                  : colors.ink.withValues(alpha: 0.1),
              width: focused ? 2 : 1,
            ),
          ),
          child: child,
        );
      },
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        readOnly: !_editing,
        // A remote has a Select key to opt into editing (see _handleKey) —
        // a touch device (iPad running the TV UI, see build_flavor.dart)
        // has no such key, so tapping the field directly is that same
        // explicit "yes, I want to type here" signal. This never fires from
        // mere D-pad navigational focus landing here (only from an actual
        // tap/click), so it doesn't reintroduce the auto-keyboard-on-focus
        // problem the class doc comment describes for Android TV.
        onTap: () {
          if (!_editing) setState(() => _editing = true);
        },
        onChanged: widget.onChanged,
        onSubmitted: (value) {
          setState(() => _editing = false);
          widget.onSubmit?.call(value);
        },
        style: GoogleFonts.outfit(color: colors.ink),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: GoogleFonts.outfit(
            color: colors.ink.withValues(alpha: 0.38),
          ),
          prefixIcon: Icon(
            Icons.search,
            color: colors.ink.withValues(alpha: 0.7),
          ),
          suffixIcon: widget.onClose == null
              ? null
              : IconButton(
                  icon: Icon(
                    Icons.close,
                    color: colors.ink.withValues(alpha: 0.7),
                  ),
                  onPressed: widget.onClose,
                ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }
}
