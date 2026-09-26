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

  // تم تقليل ارتفاع الصورة قليلًا لتقليل الارتفاع الكلي للبطاقة.
  static const double imageHeight = 116;

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
      errorWidget: (_, __, ___) =>
          placeholder(Icons.broken_image_outlined),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final id = listing['id'] as int?;
    final rawTitle = listing['title']?.toString().trim() ?? '';
    final title =
        rawTitle.isEmpty ? 'إعلان بدون عنوان' : rawTitle;
    final area = listing['area']?.toString().trim() ?? '';

    final meta = [
      if (area.isNotEmpty) area,
      timeAgo,
    ].where((part) => part.isNotEmpty).join(' - ');

    final isNegotiable =
        listing['price_type'] == 'negotiable';

    final isContactPrice =
        formatPrice == 'السعر عند التواصل';

    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
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
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // =========================
                // الصورة
                // =========================
                Stack(
                  children: [
                    _buildImage(context),

                    // القسم
                    if (categoryName.isNotEmpty)
                      Positioned(
                        top: 8,
                        right: 8,
                        left: 46,
                        child: Align(
                          alignment:
                              AlignmentDirectional.centerStart,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.brand,
                              borderRadius:
                                  BorderRadius.circular(15),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  categoryIcon,
                                  size: 13,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    categoryName,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight:
                                          FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // المفضلة
                    if (id != null &&
                        onToggleFavorite != null)
                      Positioned(
                        top: 3,
                        left: 3,
                        child: GestureDetector(
                          behavior:
                              HitTestBehavior.opaque,
                          onTap: onToggleFavorite,
                          child: Padding(
                            padding:
                                const EdgeInsets.all(5),
                            child: Container(
                              width: 33,
                              height: 33,
                              decoration:
                                  BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black
                                        .withValues(
                                      alpha: 0.14,
                                    ),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons
                                        .favorite_border_rounded,
                                size: 19,
                                color: isFavorite
                                    ? Colors.red
                                    : AppColors.brand,
                              ),
                            ),
                          ),
                        ),
                      ),

                    // الإعلان المميز
                    if (isCommercial)
                      Positioned(
                        bottom: 7,
                        right: 8,
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            borderRadius:
                                BorderRadius.circular(11),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: AppColors.brandDark,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'مميز',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight:
                                      FontWeight.w800,
                                  color:
                                      AppColors.brandDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                // =========================
                // معلومات الإعلان
                // =========================
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    11,
                    8,
                    11,
                    8,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      // العنوان
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          height: 1.18,
                          fontWeight: FontWeight.w800,
                          color: titleColor,
                        ),
                      ),

                      const SizedBox(height: 5),

                      // السعر
                      Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? colorScheme.primary
                                  .withValues(alpha: 0.18)
                              : AppColors.brandSoft,
                          borderRadius:
                              BorderRadius.circular(9),
                        ),
                        child: Text(
                          formatPrice,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isContactPrice
                                ? 12
                                : 14,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? colorScheme.primary
                                : AppColors.brand,
                          ),
                        ),
                      ),

                      // الموقع والوقت
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 14,
                              color: AppColors.brand,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                meta,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      // قابل للتفاوض
                      if (isNegotiable) ...[
                        const SizedBox(height: 5),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? colorScheme.primary
                                    .withValues(
                                    alpha: 0.18,
                                  )
                                : AppColors.brandSoft,
                            borderRadius:
                                BorderRadius.circular(12),
                          ),
                          child: Text(
                            'سعر قابل للتفاوض',
                            style: TextStyle(
                              fontSize: 11,
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