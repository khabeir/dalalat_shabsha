import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class HomeLoading extends StatelessWidget {
  final String message;

  const HomeLoading({
    super.key,
    this.message = 'جاري التحميل...',
  });

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 32,
          horizontal: 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(
                  alpha: isDark ? 0.18 : 0.10,
                ),
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(15),
              child: const CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
