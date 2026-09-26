import 'package:flutter/material.dart';

import 'categories_section.dart';
import 'home_error_state.dart';
import 'home_greeting.dart';
import 'home_loading.dart';
import 'home_search_results.dart';
import 'listing_section.dart';

class HomeBody extends StatelessWidget {
  final double topPadding;
  final bool loading;
  final String? error;
  final bool isFiltering;
  final String? userName;

  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> promotedListings;
  final List<Map<String, dynamic>> listings;

  final int? selectedCategoryId;
  final bool isDark;
  final Color titleColor;
  final double cardHeight;

  final GlobalKey categoriesKey;

  final Widget Function(double topPadding) buildHeader;
  final Widget Function(Map<String, dynamic> listing, {bool isCommercial})
      buildListingCard;

  final Widget banner;
  final Widget searchResults;

  final IconData Function(String categoryName) categoryIcon;
  final Color Function(String categoryName, int index) categoryColor;

  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final Future<void> Function(int? id, {bool clearSearch}) onSelectCategory;
  final VoidCallback onShowFeatured;
  final VoidCallback onShowLatest;

  final bool listingsLoading;

  const HomeBody({
    super.key,
    required this.topPadding,
    required this.loading,
    required this.error,
    required this.isFiltering,
    required this.userName,
    required this.categories,
    required this.promotedListings,
    required this.listings,
    required this.selectedCategoryId,
    required this.isDark,
    required this.titleColor,
    required this.cardHeight,
    required this.categoriesKey,
    required this.buildHeader,
    required this.buildListingCard,
    required this.banner,
    required this.searchResults,
    required this.categoryIcon,
    required this.categoryColor,
    required this.onRetry,
    required this.onRefresh,
    required this.onSelectCategory,
    required this.onShowFeatured,
    required this.onShowLatest,
    required this.listingsLoading,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final Widget content;

    if (loading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 90),
        child: HomeLoading(),
      );
    } else if (error != null) {
      content = HomeErrorState(
        message: error!,
        onRetry: onRetry,
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isFiltering) ...[
            if (userName != null && userName!.isNotEmpty)
              HomeGreeting(name: userName!),
            banner,
            const SizedBox(height: 16),
          ],
          CategoriesSection(
            sectionKey: categoriesKey,
            categories: categories,
            selectedCategoryId: selectedCategoryId,
            isDark: isDark,
            titleColor: titleColor,
            categoryIcon: categoryIcon,
            categoryColor: categoryColor,
            onSelectCategory: (categoryId) {
              if (categoryId < 0) {
                onSelectCategory(null);
              } else {
                onSelectCategory(
                  categoryId,
                  clearSearch: true,
                );
              }
            },
          ),
          const SizedBox(height: 8),
          if (isFiltering)
            searchResults
          else
            ListingSection(
              loading: listingsLoading,
              promotedListings: promotedListings,
              listings: listings,
              categories: categories,
              isDark: isDark,
              titleColor: titleColor,
              cardHeight: cardHeight,
              buildListingCard: buildListingCard,
              categoryIcon: categoryIcon,
              categoryColor: categoryColor,
              onShowFeatured: onShowFeatured,
              onShowLatest: onShowLatest,
              onSelectCategory: (categoryId) {
                onSelectCategory(categoryId);
              },
            ),
        ],
      );
    }

    return RefreshIndicator(
      displacement: topPadding + 50,
      onRefresh: onRefresh,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: 112 + bottomInset),
        children: [
          buildHeader(topPadding),
          content,
        ],
      ),
    );
  }
}
