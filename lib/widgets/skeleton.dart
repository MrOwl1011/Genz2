import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Loading placeholders that match the layout they stand in for.
///
/// A spinner says "something is happening". A skeleton says "this is what is
/// coming", and because the shapes match the real content it also prevents the
/// layout shift on arrival that makes an app feel cheap.
///
/// Hand-rolled rather than pulling in `shimmer`: the sweep is one
/// [AnimationController] and a [ShaderMask], it avoids a dependency, and it
/// lets the highlight carry the brand hue instead of the package's grey.
///
/// Wrap a whole row rather than each card, so the sweep travels across the row
/// the way light actually would — per-card animation looks like several
/// unrelated things blinking.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Travels from fully off the leading edge to fully off the trailing
        // one, so there is a beat with no highlight rather than a band that
        // teleports back to the start.
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(-1.6 + 3.2 * t, 0),
            end: Alignment(-0.6 + 3.2 * t, 0),
            colors: [
              colors.surfaceElevated,
              Color.alphaBlend(
                colors.brandPrimary.withValues(alpha: 0.12),
                colors.surfaceElevated,
              ),
              colors.surfaceElevated,
            ],
          ).createShader(rect),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// One blank shape inside a [Skeleton]. Radius defaults to the poster value,
/// since that is what most placeholders stand in for.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = 4,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.colors.surfaceElevated,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// A stand-in for one horizontal content row: header bar plus poster cards.
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({
    super.key,
    this.posterWidth = 116,
    this.posterHeight = 174,
    this.count = 5,
  });

  final double posterWidth;
  final double posterHeight;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: SkeletonBox(width: 140, height: 16, radius: 3),
          ),
          SizedBox(
            height: posterHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, _) =>
                  SkeletonBox(width: posterWidth, height: posterHeight),
            ),
          ),
        ],
      ),
    );
  }
}
