import 'home_decorative_painters.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class HomeBottomNavigation extends StatelessWidget {
  final bool isDark;
  final Color cardColor;

  final VoidCallback onHome;
  final VoidCallback onMyListings;
  final VoidCallback onAddListing;
  final VoidCallback onFavorites;
  final VoidCallback onProfile;

  const HomeBottomNavigation({
    super.key,
    required this.isDark,
    required this.cardColor,
    required this.onHome,
    required this.onMyListings,
    required this.onAddListing,
    required this.onFavorites,
    required this.onProfile,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    Widget navItem({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool selected = false,
    }) {
      final color = selected
          ? AppColors.brand
          : colorScheme.onSurfaceVariant;

      return Expanded(
        child: InkWell(
          borderRadius:
              BorderRadius.circular(24),
          onTap: onTap,
          child: Column(
            mainAxisAlignment:
                MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 26,
                color: color,
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              selected
                  ? Container(
                      width: 30,
                      height: 3,
                      decoration:
                          BoxDecoration(
                        color:
                            AppColors.brand,
                        borderRadius:
                            BorderRadius.circular(
                          2,
                        ),
                      ),
                    )
                  : const SizedBox(
                      height: 3,
                    ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 104,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // =================================================
            // الشريط السفلي
            // =================================================
            Positioned(
              left: 14,
              right: 14,
              bottom: 8,
              height: 68,
              child: Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius:
                      BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brand
                          .withValues(
                        alpha: 0.20,
                      ),
                      blurRadius: 24,
                      offset:
                          const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  textDirection:
                      TextDirection.rtl,
                  children: [
                    // الرئيسية
                    navItem(
                      icon:
                          Icons.home_rounded,
                      label: 'الرئيسية',
                      selected: true,
                      onTap: onHome,
                    ),

                    // إعلاناتي
                    navItem(
                      icon:
                          Icons.list_alt_rounded,
                      label: 'إعلاناتي',
                      onTap:
                          onMyListings,
                    ),

                    // مساحة زر إضافة الإعلان
                    Expanded(
                      child: GestureDetector(
                        behavior:
                            HitTestBehavior
                                .opaque,
                        onTap:
                            onAddListing,
                        child: const Align(
                          alignment:
                              Alignment
                                  .bottomCenter,
                          child: Padding(
                            padding:
                                EdgeInsets.only(
                              bottom: 9,
                            ),
                            child: Text(
                              'أضف إعلان',
                              style:
                                  TextStyle(
                                fontSize:
                                    11.5,
                                fontWeight:
                                    FontWeight
                                        .w800,
                                color:
                                    AppColors
                                        .brand,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // المفضلة
                    navItem(
                      icon: Icons
                          .favorite_border_rounded,
                      label: 'المفضلة',
                      onTap:
                          onFavorites,
                    ),

                    // الملف الشخصي
                    navItem(
                      icon: Icons
                          .person_outline_rounded,
                      label:
                          'الملف الشخصي',
                      onTap:
                          onProfile,
                    ),
                  ],
                ),
              ),
            ),

            // =================================================
            // زر إضافة إعلان العائم
            // =================================================
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: onAddListing,
                  child: SizedBox(
                    width: 84,
                    height: 66,
                    child: Stack(
                      alignment:
                          Alignment.center,
                      clipBehavior:
                          Clip.none,
                      children: [
                        const CustomPaint(
                          size: Size(
                            84,
                            66,
                          ),
                          painter:
                              HomeSparklesPainter(),
                        ),

                        Container(
                          width: 60,
                          height: 60,
                          decoration:
                              BoxDecoration(
                            shape:
                                BoxShape.circle,
                            gradient:
                                const LinearGradient(
                              begin:
                                  Alignment
                                      .topLeft,
                              end:
                                  Alignment
                                      .bottomRight,
                              colors: [
                                Color(
                                  0xFF8A5CE6,
                                ),
                                AppColors
                                    .brand,
                              ],
                            ),
                            border:
                                Border.all(
                              color:
                                  Colors.white,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors
                                    .brand
                                    .withValues(
                                  alpha:
                                      0.40,
                                ),
                                blurRadius:
                                    14,
                                offset:
                                    const Offset(
                                  0,
                                  6,
                                ),
                              ),
                            ],
                          ),
                          child:
                              const Icon(
                            Icons.add_rounded,
                            size: 36,
                            color:
                                Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
