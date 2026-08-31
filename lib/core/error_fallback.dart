import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Replaces Flutter's default build-error placeholder — a plain grey box
/// with no text in release mode (by design, to avoid leaking stack traces
/// to end users) — with something that at least reads as "something broke,
/// go back" instead of an unexplained blank/white panel a viewer might not
/// even realize is an error state rather than a stuck loading screen.
///
/// Doesn't (can't) offer an in-place "go back" button — `ErrorWidget.builder`
/// only receives [FlutterErrorDetails], no [BuildContext] to call
/// `Navigator.of(context)` with — but it does still leave the physical/
/// remote back key working exactly as before (this only replaces the failed
/// subtree's own painted output, not the surrounding Navigator/route), so
/// spelling that out explicitly turns a dead end into a recoverable one.
///
/// Call once, before `runApp()`, from every entry point (see main.dart /
/// main_tv.dart).
void installErrorFallback() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kDebugMode) {
      // Keep the normal red debug screen (full exception text) while
      // developing — this fallback is only for what end users see.
      return ErrorWidget(details.exception);
    }
    return Container(
      color: const Color(0xFF0B0B0F),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.error_outline_rounded, color: Colors.white54, size: 40),
          SizedBox(height: 16),
          Text(
            "Something went wrong loading this screen.\nPress Back to return.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 15),
          ),
        ],
      ),
    );
  };
}
