import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ListingSection extends StatelessWidget {
  final bool loading;

  final List<Map<String, dynamic>> promotedListings;
  final List<Map<String, dynamic>> listings;
  final List<Map<String, dynamic>> categories;

  final bool isDark;
  final Color titleColor;
  final double cardHeight;

  final Widget Function(
    Map<String, dynamic> listing, {
    bool isCommercial,
  }) buildListingCard;

  final IconData Function(String name) categoryIcon;
  final Color Function(String name, int index) categoryColor;

  final VoidCallback onShowFeatured;
  final VoidCallback onShowLatest;
  final void Function(int categoryId) onSelectCategory;

  const ListingSection({
    super.key,
    required this.loading,
    required this.promotedListings,
    required this.listings,
    required this.categories,
    required this.isDark,
    required this.titleColor,
    required this.cardHeight,
    required this.buildListingCard,
    required this.categoryIcon,
    required this.categoryColor,
    required this.onShowFeatured,
    required this.onShowLatest,
    required this.onSelectCategory,
  });

  Widget _sectionHeader(
    BuildContext context,
    String title, {
    IconData? icon,
    Color? iconColor,
    VoidCallback? onViewAll,
  }) {
    final actionColor = isDark
        ? Theme.of(context).colorScheme.primary
        : AppColors.brand;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 24,
              color: iconColor ?? AppColors.brand,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: titleColor,
              ),
            ),
          ),
          if (onViewAll != null)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onViewAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '⁄—÷ «·ﬂ·',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: actionColor,
                      ),
                    ),
                    Icon(
                      Icons.chevron_left_rounded,
                      size: 22,
                      color: actionColor,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalListings(
    List<Map<String, dynamic>> items, {
    bool commercial = false,
  }) {
    return SizedBox(
      height: cardHeight + 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: buildListingCard(
              items[index],
              isCommercial: commercial,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final promoted = promotedListings;

    if (listings.isEmpty && promoted.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 48,
            ),
            SizedBox(height: 10),
            Text('·«  ÊÃœ ≈⁄·«‰«  „ «Õ… Õ«·Ì«'),
          ],
        ),
      );
    }

    final promotedIds = promoted
        .map((listing) => listing['id'])
        .toSet();

    final latestListings = listings
        .where(
          (listing) => !promotedIds.contains(listing['id']),
        )
        .take(10)
        .toList();

    final categoryRows = <Widget>[];

    for (var i = 0; i < categories.length; i++) {
      final category = categories[i];
      final categoryId = category['id'] as int?;

      if (categoryId == null) continue;

      final items = listings
          .where(
            (listing) => listing['category_id'] == categoryId,
          )
          .take(8)
          .toList();

      if (items.isEmpty) continue;

      final name =
          category['name']?.toString() ?? '»œÊ‰ «”„';

      categoryRows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader(
                context,
                name,
                icon: categoryIcon(name),
                iconColor: categoryColor(name, i),
                onViewAll: () => onSelectCategory(categoryId),
              ),
              const SizedBox(height: 12),
              _buildHorizontalListings(items),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (promoted.isNotEmpty) ...[
          _sectionHeader(
            context,
            '≈⁄·«‰«  „„Ì“…',
            icon: Icons.local_fire_department_rounded,
            iconColor: const Color(0xFFFF6A1A),
            onViewAll: onShowFeatured,
          ),
          const SizedBox(height: 12),

          // ‰Õ«›Ÿ ⁄·Ï «·”·Êﬂ «·”«»ﬁ:
          // «·≈⁄·«‰ «·„„Ì“ ›Ì «·’›Õ… «·—∆Ì”Ì…
          // ·« Ìı⁄«„· ﬂ≈⁄·«‰  Ã«—Ì.
          _buildHorizontalListings(promoted),

          const SizedBox(height: 14),
        ],

        if (latestListings.isNotEmpty) ...[
          _sectionHeader(
            context,
            '√ÕœÀ «·≈⁄·«‰« ',
            icon: Icons.schedule_rounded,
            onViewAll: onShowLatest,
          ),
          const SizedBox(height: 12),
          _buildHorizontalListings(latestListings),
          const SizedBox(height: 14),
        ],

        ...categoryRows,
      ],
    );
  }
}