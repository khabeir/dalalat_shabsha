import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class CategoriesSection extends StatelessWidget {
  final GlobalKey? sectionKey;

  final List<Map<String, dynamic>> categories;

  final int? selectedCategoryId;

  final bool isDark;
  final Color titleColor;

  final IconData Function(String name) categoryIcon;
  final Color Function(String name, int index) categoryColor;

  final VoidCallback? onViewAll;
  final void Function(int categoryId) onSelectCategory;

  const CategoriesSection({
    super.key,
    this.sectionKey,
    required this.categories,
    required this.selectedCategoryId,
    required this.isDark,
    required this.titleColor,
    required this.categoryIcon,
    required this.categoryColor,
    required this.onViewAll,
    required this.onSelectCategory,
  });

  Widget _sectionHeader(
    BuildContext context,
  ) {
    final actionColor = isDark
        ? Theme.of(context).colorScheme.primary
        : AppColors.brand;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(
            Icons.grid_view_rounded,
            size: 24,
            color: AppColors.brand,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'الأقسام',
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
                      'عرض الكل',
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

  Widget _buildCategoryTile(
    BuildContext context,
    Map<String, dynamic> category,
    int index, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final name = category['name']?.toString() ?? 'بدون اسم';
    final tone = categoryColor(name, index);

    // نحافظ على نفس درجات الخلفية الموجودة في HomeScreen.
    final bgTone = _backgroundTone(name, index);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          horizontal: 4,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? tone.withValues(alpha: 0.16)
              : bgTone,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? tone : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: tone.withValues(
                alpha: selected ? 0.28 : 0.12,
              ),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              categoryIcon(name),
              size: 34,
              color: tone,
            ),
            const SizedBox(height: 8),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: titleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _backgroundTone(String name, int index) {
    switch (index % 6) {
      case 0:
        return const Color(0xFFEFE7FF);
      case 1:
        return const Color(0xFFFFF1D1);
      case 2:
        return const Color(0xFFDDF5EA);
      case 3:
        return const Color(0xFFDFEDFF);
      case 4:
        return const Color(0xFFFFE3E9);
      default:
        return const Color(0xFFE9EEF5);
    }
  }

  void _showAllCategories(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                0,
                16,
                16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'كل الأقسام',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      itemCount: categories.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.05,
                      ),
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        final categoryId =
                            category['id'] as int?;

                        return _buildCategoryTile(
                          context,
                          category,
                          index,
                          selected:
                              selectedCategoryId == categoryId,
                          onTap: () {
                            Navigator.pop(sheetContext);

                            if (categoryId != null) {
                              onSelectCategory(categoryId);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: sectionKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(context),

        const SizedBox(height: 10),

        if (categories.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                'لا توجد أقسام متاحة حالياً',
              ),
            ),
          )
        else
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
              ),
              itemCount: categories.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final category = categories[index];
                final categoryId =
                    category['id'] as int?;

                final selected =
                    selectedCategoryId == categoryId;

                return Padding(
                  padding: const EdgeInsets.only(
                    bottom: 14,
                  ),
                  child: SizedBox(
                    width: 88,
                    child: _buildCategoryTile(
                      context,
                      category,
                      index,
                      selected: selected,
                      onTap: () {
                        if (categoryId == null) return;

                        onSelectCategory(
                          selected ? -categoryId : categoryId,
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
