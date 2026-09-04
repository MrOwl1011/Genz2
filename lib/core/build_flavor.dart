import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

/// Whether this binary was built as the dedicated Android TV flavor.
///
/// A *compile-time* constant — set via `--dart-define=IS_TV=true` when
/// building the `tv` Android product flavor from `main_tv.dart` — rather
/// than a runtime device check, for exactly the reason [kIsTv]'s own doc
/// comment used to give: with a compile-time constant, `if (kIsTv) { ... }`
/// is provably unreachable in the `phone` flavor's build, so Dart's compiler
/// deletes that code entirely. Android keeps that guarantee unchanged for
/// both its flavors — see [kIsTv] for why it no longer holds for iOS.
const bool _kIsTvFlavor = bool.fromEnvironment('IS_TV', defaultValue: false);

/// Whether the TV-style UI should be shown: true for the Android TV flavor
/// (as before), or — new — at runtime, when this iOS binary happens to be
/// running on an iPad. iOS has no product-flavor mechanism the way Android
/// does, so there is no separate "iPad" build; instead [main.dart] (the one
/// entry point shared by Android's phone flavor and all of iOS) calls
/// [initIsTv] once at startup, and everywhere in the app that already
/// branched on [kIsTv] for Android TV now also gets the TV UI on iPad, with
/// zero code changes needed at any of those call sites.
///
/// Deliberately a plain mutable global rather than a getter recomputed from
/// `MediaQuery` — several call sites (e.g. exoplayer_backend.dart) have no
/// `BuildContext` to read it from, exactly like the old compile-time
/// constant needed none.
///
/// Cost of this: since [kIsTv] is no longer a compile-time constant, `if
/// (kIsTv) { ... }` is no longer provably unreachable anywhere, including
/// Android's `phone` flavor — that TV code is still unreachable *at
/// runtime* there (see [initIsTv]: it only ever touches this on iOS), but
/// it is no longer eliminated from the compiled binary, so the phone
/// flavor's APK carries a small amount of dead weight it didn't before.
/// Behavior is unaffected on both Android flavors and on iPhone.
bool kIsTv = _kIsTvFlavor;

/// True only where input really is a D-pad remote with no pointer — which
/// is exactly the Android TV flavor and nothing else.
///
/// [kIsTv] alone cannot answer "is there a pointer", now that it's also
/// true on iPad (touch) and desktop (mouse). Several call sites that used
/// to check [kIsTv] to strip out pointer-only controls — brightness/volume
/// swipe gestures, the lock button, the on-screen skip/rewind/forward row,
/// the focus ring (see player_screen.dart, tv_focus.dart, tv_focusable.dart)
/// — were really asking this. Use this for input questions; keep using
/// [kIsTv] for which *layout* to show, since the TV layout is correct on
/// all three.
bool get kIsTvRemote => _kIsTvFlavor;

/// Call once, very early in `main()` (after `WidgetsFlutterBinding.
/// ensureInitialized()`, before anything reads [kIsTv]) — decides whether
/// this run should use the TV UI.
///
/// Android: a no-op. [kIsTv] already reflects the compile-time flavor via
/// [_kIsTvFlavor] and this function never changes it there, so Android's
/// two flavors behave exactly as they always have.
///
/// iOS: there is no iPad-specific build, so this detects the device at
/// runtime instead, via screen size — the same shortest-side-≥600 heuristic
/// Flutter's own Material breakpoints use to distinguish phone from tablet.
/// No native/platform-channel round trip needed: `physicalSize` is
/// available synchronously off the platform dispatcher's first view as soon
/// as the binding is initialized.
void initIsTv() {
  if (_kIsTvFlavor) return;

  // Desktop is always the TV layout. These are large, far-ish, landscape
  // screens driven by keyboard and mouse — the sidebar layout suits them
  // for the same reasons it suits a TV, and the phone layout would just be
  // a stretched column. Unlike iOS there's no small-screen variant of a
  // desktop window worth branching on.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    kIsTv = true;
    return;
  }

  if (!Platform.isIOS) return;
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final shortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;
  kIsTv = shortestSide >= 600;
}
