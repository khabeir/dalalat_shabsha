import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// بطاقة إعلان قابلة لإعادة الاستخدام في الصفحة الرئيسية والأقسام المختلفة.
class ListingCard extends StatelessWidget {
  const ListingCard({
    super.key,
    required this.listing,
    required this.imageUrl,
    required this.width,
    required this.isCommercial,
    required this.isFavorite,
    required this.categoryName,
    required this.isDark,
    required this.cardColor,
    required this.titleColor,
    required this.onTap,
    required this.onToggleFavorite,
    required this.categoryIcon,
    required this.formatPrice,
    required this.timeAgo,
  });

  final Map<String, dynamic> listing;
  final String? imageUrl;
  final double width;
  final bool isCommercial;
  final bool isFavorite;
  final String categoryName;
  final bool isDark;
  final Color cardColor;
  final Color titleColor;
  final VoidCallback onTap;
  final VoidCallback? onToggleFavorite;
  final IconData categoryIcon;
  final String formatPrice;
  final String timeAgo;

  static const double imageHeight = 122;

  Widget _buildImage(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget placeholder([
      IconData icon = Icons.photo_library_outlined,
    ]) {
      return Container(
        height: imageHeight,
        width: double.infinity,
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            icon,
            size: 30,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (imageUrl == null) return placeholder();

    return CachedNetworkImage(
      imageUrl: imageUrl!,
      height: imageHeight,
      width: double.infinity,
      fit: BoxFit.cover,
      memCacheWidth: 400,
      placeholder: (_, __) => placeholder(Icons.image_outlined),
      errorWidget: (_, __, ___) => placeholder(Icons.broken_image_outlined),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final id = listing['id'] as int?;
    final rawTitle = listing['title']?.toString().trim() ?? '';
    final title = rawTitle.isEmpty ? 'إعلان بدون عنوان' : rawTitle;
    final area = listing['area']?.toString().trim() ?? '';

    final meta = [
      if (area.isNotEmpty) area,
      timeAgo,
    ].where((part) => part.isNotEmpty).join(' - ');

    final isNegotiable = listing['price_type'] == 'negotiable';
    final isContactPrice = formatPrice == 'السعر عند التواصل';

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.brand.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    _buildImage(context),
                    if (categoryName.isNotEmpty)
                      Positioned(
                        top: 9,
                        right: 9,
                        left: 48,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.brand,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  categoryIcon,
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    categoryName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (id != null && onToggleFavorite != null)
                      Positioned(
                        top: 3,
                        left: 3,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onToggleFavorite,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.14),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 20,
                                color: isFavorite
                                    ? Colors.red
                                    : AppColors.brand,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (isCommercial)
                      Positioned(
                        bottom: 8,
                        right: 9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: AppColors.brandDark,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'مميز',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? colorScheme.primary.withValues(alpha: 0.18)
                              : AppColors.brandSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          formatPrice,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isContactPrice ? 12.5 : 14.5,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? colorScheme.primary
                                : AppColors.brand,
                          ),
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 15,
                              color: AppColors.brand,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (isNegotiable) ...[
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? colorScheme.primary.withValues(alpha: 0.18)
                                : AppColors.brandSoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'سعر قابل للتفاوض',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? colorScheme.primary
                                  : AppColors.brand,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
