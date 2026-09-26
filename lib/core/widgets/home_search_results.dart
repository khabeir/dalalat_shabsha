import 'package:flutter/material.dart';

import 'home_empty_state.dart';
import 'home_loading.dart';

/// عرض نتائج البحث أو نتائج القسم أو القوائم الكاملة.
///
/// يعتمد هذا المكوّن على callbacks بسيطة حتى يبقى منطق Supabase
/// والتنقل والمفضلة داخل HomeScreen.
class HomeSearchResults extends StatelessWidget {
  const HomeSearchResults({
    super.key,
    required this.results,
    required this.promotedIds,
    required this.title,
    required this.titleColor,
    required this.isSearching,
    required this.isLoading,
    required this.searchPoolLoading,
    required this.loadingMore,
    required this.onClearFilters,
    required this.buildListingCard,
  });

  static const _cardHeight = 272.0;

  final List<Map<String, dynamic>> results;
  final Set<dynamic> promotedIds;
  final String title;
  final Color titleColor;
  final bool isSearching;
  final bool isLoading;
  final bool searchPoolLoading;
  final bool loadingMore;
  final VoidCallback onClearFilters;
  final Widget Function(
    Map<String, dynamic> listing,
    bool isCommercial,
  ) buildListingCard;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showSpinner = isLoading || (isSearching && searchPoolLoading);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
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
              Text(
                '${results.length} إعلان',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: onClearFilters,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 17,
                ),
                label: const Text(
                  'إلغاء التصفية',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (showSpinner && results.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: HomeLoading(),
          )
        else if (results.isEmpty)
          HomeEmptyState(
            message: isSearching
                ? 'لم نجد إعلانات تطابق بحثك'
                : 'لا توجد إعلانات هنا حالياً',
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: results.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                mainAxisExtent: _cardHeight,
              ),
              itemBuilder: (context, index) {
                final listing = results[index];
                final isCommercial = promotedIds.contains(listing['id']);

                return buildListingCard(listing, isCommercial);
              },
            ),
          ),
        if (loadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: HomeLoading(),
          ),
      ],
    );
  }
}
