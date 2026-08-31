import 'package:flutter/material.dart';

/// Pushes [page] with no transition animation.
///
/// `MaterialPageRoute`'s default slide+fade is ~300ms of compositing work
/// per navigation, and the TV interface does a lot of navigation — hub to
/// category, category to grid, grid to details, details to player. On the
/// weak GPUs in budget TV boxes that adds up to visible stutter on every
/// single screen change, for a purely decorative animation a remote user
/// gets no benefit from (there's no swipe-back gesture on TV for it to
/// support the sense of). This swaps the destination in instantly instead.
/// Returns the same `Future<T?>` `Navigator.push` does, resolving once
/// [page] is popped — most callers ignore it (fine, a discarded Future is
/// not an error), but a caller that needs to react to returning (e.g.
/// resuming something paused before the push) can await it.
Future<T?> pushTv<T>(BuildContext context, Widget page) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    ),
  );
}
