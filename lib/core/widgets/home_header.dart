import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'home_decorative_painters.dart';

class HomeHeader extends StatelessWidget {
  // تم تقليل ارتفاع الترويسة قليلًا لتقليل المساحة الرأسية.
  static const headerContentHeight = 160.0;

  static const headerAsset =
      'assets/images/home_header.jpg';

  final double topPadding;
  final bool isDark;
  final Color pageBackground;
  final Color titleColor;
  final TextEditingController searchController;
  final bool isSignedIn;

  final VoidCallback onOpenDrawer;
  final VoidCallback onProfile;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  const HomeHeader({
    super.key,
    required this.topPadding,
    required this.isDark,
    required this.pageBackground,
    required this.titleColor,
    required this.searchController,
    required this.isSignedIn,
    required this.onOpenDrawer,
    required this.onProfile,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    final height =
        topPadding + headerContentHeight;

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // =========================
          // خلفية الترويسة
          // =========================
          Positioned.fill(
            child: Image.asset(
              headerAsset,
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              errorBuilder: (_, __, ___) {
                return const RepaintBoundary(
                  child: CustomPaint(
                    painter:
                        HomeShabshaScenePainter(),
                  ),
                );
              },
            ),
          ),

          // =========================
          // تدرج علوي خفيف
          // =========================
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPadding + 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(
                      alpha: 0.22,
                    ),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // =========================
          // الصف العلوي
          // =========================
          Positioned(
            top: topPadding + 10,
            left: 16,
            right: 16,
            child: _buildTopRow(),
          ),

          // =========================
          // مربع البحث
          // تم رفعه للأعلى ليكون أقرب
          // إلى عنوان التطبيق.
          // =========================
          Positioned(
            left: 16,
            right: 16,
            bottom: 42,
            child: _buildSearchField(context),
          ),

          // =========================
          // الحافة المنحنية
          // أسفل الترويسة
          // =========================
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 30,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: pageBackground,
                borderRadius:
                    const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // الصف العلوي
  // =========================================================
  Widget _buildTopRow() {
    const glow = [
      Shadow(
        color: Colors.white,
        blurRadius: 10,
      ),
      Shadow(
        color: Colors.white,
        blurRadius: 4,
      ),
    ];

    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.center,
      children: [
        // =========================
        // زر القائمة
        // =========================
        Tooltip(
          message: 'القائمة',
          child: InkWell(
            borderRadius:
                BorderRadius.circular(24),
            onTap: onOpenDrawer,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(
                Icons.menu_rounded,
                size: 30,
                color: AppColors.brandDark,
              ),
            ),
          ),
        ),

        const SizedBox(width: 2),

        // =========================
        // الشعار
        // =========================
        _buildLogo(),

        const SizedBox(width: 8),

        // =========================
        // اسم التطبيق
        // =========================
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment:
                    AlignmentDirectional
                        .centerStart,
                child: Text(
                  'دلالة شبشة',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight:
                        FontWeight.w900,
                    height: 1.1,
                    color:
                        AppColors.brandDark,
                    shadows: glow,
                  ),
                ),
              ),

              Text(
                'سوقك المحلي في شبشة',
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight:
                      FontWeight.w700,
                  color:
                      AppColors.brandDark,
                  shadows: glow,
                ),
              ),
            ],
          ),
        ),

        // =========================
        // حساب المستخدم
        // =========================
        Tooltip(
          message: isSignedIn
              ? 'الملف الشخصي'
              : 'تسجيل الدخول',
          child: GestureDetector(
            onTap: onProfile,
            child: Container(
              width: 46,
              height: 46,
              decoration:
                  BoxDecoration(
                color: Colors.white.withValues(
                  alpha: 0.94,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: 0.15,
                    ),
                    blurRadius: 10,
                    offset:
                        const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                isSignedIn
                    ? Icons.person_rounded
                    : Icons.person_outline_rounded,
                size: 26,
                color:
                    AppColors.brandDark,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // شعار دلالة شبشة
  // =========================================================
  Widget _buildLogo() {
    return SizedBox(
      width: 46,
      height: 52,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          // دبوس الموقع
          const Icon(
            Icons.location_on_rounded,
            size: 52,
            color: AppColors.brand,
          ),

          // عربة التسوق
          const Positioned(
            top: 12,
            child: Icon(
              Icons.shopping_cart_rounded,
              size: 17,
              color: Colors.white,
            ),
          ),

          // علامة العرض
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: 15,
              height: 15,
              decoration:
                  const BoxDecoration(
                color: AppColors.gold,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_offer_rounded,
                size: 9,
                color:
                    AppColors.brandDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // مربع البحث
  // =========================================================
  Widget _buildSearchField(
    BuildContext context,
  ) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: isDark
            ? Theme.of(context)
                .colorScheme
                .surfaceContainerHigh
            : Colors.white,
        borderRadius:
            BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(
              alpha: 0.20,
            ),
            blurRadius: 18,
            offset:
                const Offset(0, 6),
          ),
        ],
      ),
      child:
          ValueListenableBuilder<
              TextEditingValue>(
        valueListenable:
            searchController,
        builder: (
          context,
          value,
          _,
        ) {
          return TextField(
            controller:
                searchController,
            textInputAction:
                TextInputAction.search,
            onChanged:
                onSearchChanged,
            style: const TextStyle(
              fontSize: 15,
            ),
            decoration:
                InputDecoration(
              hintText:
                  'ابحث عن إعلان أو منطقة ...',
              hintStyle: TextStyle(
                fontSize: 14.5,
                color: Theme.of(
                  context,
                )
                    .colorScheme
                    .onSurfaceVariant,
              ),

              // أيقونة البحث
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 27,
                color: titleColor,
              ),

              // زر مسح البحث
              suffixIcon:
                  value.text.isNotEmpty
                      ? IconButton(
                          onPressed:
                              onClearSearch,
                          tooltip:
                              'مسح البحث',
                          icon:
                              const Icon(
                            Icons.close_rounded,
                            size: 21,
                          ),
                        )
                      : null,

              filled: false,
              isDense: true,

              border:
                  InputBorder.none,

              enabledBorder:
                  InputBorder.none,

              focusedBorder:
                  InputBorder.none,

              contentPadding:
                  const EdgeInsets.symmetric(
                vertical: 17,
              ),
            ),
          );
        },
      ),
    );
  }
}