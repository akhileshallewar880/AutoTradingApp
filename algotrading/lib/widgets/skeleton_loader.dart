import '../theme/vt_color_scheme.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Shimmer skeleton placeholder — used while async data loads.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.radius = Rad.sm,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.vt.surface2,
      highlightColor: context.vt.surface3,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.vt.surface2,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

/// Full card skeleton — mimics a VtCard loading state.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 120});
  final double height;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.vt.surface2,
      highlightColor: context.vt.surface3,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: context.vt.surface1,
          borderRadius: BorderRadius.circular(Rad.lg),
          border: Border.all(color: context.vt.divider),
        ),
        padding: const EdgeInsets.all(Sp.base),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _box(context, 80, 14),
                const Spacer(),
                _box(context, 50, 14),
              ],
            ),
            const SizedBox(height: Sp.md),
            _box(context, double.infinity, 12),
            const SizedBox(height: Sp.sm),
            _box(context, 200, 12),
          ],
        ),
      ),
    );
  }

  Widget _box(BuildContext context, double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: context.vt.surface2,
          borderRadius: BorderRadius.circular(Rad.sm),
        ),
      );
}

/// List tile skeleton — mimics a single-row list item.
class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: context.vt.surface2,
      highlightColor: context.vt.surface3,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: Sp.sm, horizontal: Sp.base),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.vt.surface2,
                borderRadius: BorderRadius.circular(Rad.sm),
              ),
            ),
            SizedBox(width: Sp.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: 120,
                    decoration: BoxDecoration(
                      color: context.vt.surface2,
                      borderRadius: BorderRadius.circular(Rad.sm),
                    ),
                  ),
                  SizedBox(height: Sp.xs),
                  Container(
                    height: 12,
                    width: 80,
                    decoration: BoxDecoration(
                      color: context.vt.surface2,
                      borderRadius: BorderRadius.circular(Rad.sm),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 14,
              width: 60,
              decoration: BoxDecoration(
                color: context.vt.surface2,
                borderRadius: BorderRadius.circular(Rad.sm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders N skeleton list tiles — convenience wrapper.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 4});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(count, (_) => const SkeletonListTile()),
    );
  }
}
