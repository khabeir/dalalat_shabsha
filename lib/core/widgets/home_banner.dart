import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class HomeBanner extends StatelessWidget {
  final VoidCallback onAddListing;
  final VoidCallback onBrowseCategories;

  const HomeBanner({
    super.key,
    required this.onAddListing,
    required this.onBrowseCategories,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      height: 172,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: isDark
                    ? [
                        AppColors.brandDark,
                        AppColors.brandDark.withValues(alpha: 0.82),
                      ]
                    : [
                        AppColors.brand,
                        AppColors.brandDark,
                      ],
              ),
            ),
          ),

          Positioned(
            top: -45,
            left: -30,
            child: _DecorativeCircle(
              size: 150,
              opacity: 0.10,
            ),
          ),

          Positioned(
            bottom: -55,
            right: -25,
            child: _DecorativeCircle(
              size: 160,
              opacity: 0.09,
            ),
          ),

          Positioned(
            top: 18,
            right: 18,
            child: Icon(
              Icons.storefront_rounded,
              size: 58,
              color: Colors.white.withValues(alpha: 0.16),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(
              20,
              18,
              20,
              16,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      const Text(
                        'دلالة شبشة',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'اعرض منتجك أو ابحث عما تحتاجه',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(
                            alpha: 0.92,
                          ),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _BannerButton(
                            icon: Icons.add_rounded,
                            label: 'أضف إعلانك',
                            onTap: onAddListing,
                          ),
                          const SizedBox(width: 8),
                          _BannerButton(
                            icon: Icons.grid_view_rounded,
                            label: 'التصنيفات',
                            outlined: true,
                            onTap: onBrowseCategories,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const SizedBox(
                  width: 76,
                  child: Icon(
                    Icons.shopping_bag_rounded,
                    size: 72,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BannerButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool outlined;

  const _BannerButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: outlined
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 38,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 7,
          ),
          decoration: outlined
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(
                      alpha: 0.55,
                    ),
                  ),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: outlined
                    ? Colors.white
                    : AppColors.brandDark,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: outlined
                      ? Colors.white
                      : AppColors.brandDark,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecorativeCircle extends StatelessWidget {
  final double size;
  final double opacity;

  const _DecorativeCircle({
    required this.size,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(
          alpha: opacity,
        ),
      ),
    );
  }
}