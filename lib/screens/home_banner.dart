import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

// =============================================================
// بيانات خانة واحدة من البنر (كما يعبّئها الأدمن).
// =============================================================
class BannerSlideData {
  final int slot;
  final String headline;
  final String subtitle;

  const BannerSlideData({
    required this.slot,
    required this.headline,
    required this.subtitle,
  });

  factory BannerSlideData.fromRow(Map<String, dynamic> row) {
    return BannerSlideData(
      slot: row['slot'] is int ? row['slot'] as int : 0,
      headline: row['headline']?.toString() ?? '',
      subtitle: row['subtitle']?.toString() ?? '',
    );
  }

  // الشكل الافتراضي الذي يظهر إن لم يفعّل الأدمن أي خانة بعد.
  static const fallback = BannerSlideData(
    slot: 0,
    headline: 'دلالة شبشة',
    subtitle: 'اعرض منتجك أو ابحث عما تحتاجه',
  );
}

// =============================================================
// البنر: يجلب الخانات المفعّلة من لوحة الأدمن ويعرضها كشرائح
// قابلة للتمرير، وإن لم توجد خانة مفعّلة يعرض الشكل الافتراضي.
// نفس الاستدعاء القديم بلا تغيير: HomeBanner(onAddListing:, onBrowseCategories:).
// =============================================================
class HomeBanner extends StatefulWidget {
  final VoidCallback onAddListing;
  final VoidCallback onBrowseCategories;

  const HomeBanner({
    super.key,
    required this.onAddListing,
    required this.onBrowseCategories,
  });

  @override
  State<HomeBanner> createState() => _HomeBannerState();
}

class _HomeBannerState extends State<HomeBanner> {
  static const _refreshInterval = Duration(minutes: 5);

  final _pageController = PageController();
  final _currentPage = ValueNotifier<int>(0);

  List<BannerSlideData> _slides = const [];
  Timer? _refreshTimer;
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();

    _loadSlides();

    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _loadSlides());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    _currentPage.dispose();
    super.dispose();
  }

  Future<void> _loadSlides() async {
    try {
      final response = await Supabase.instance.client
          .from('home_banner_slides')
          .select('slot, headline, subtitle')
          .eq('is_active', true)
          .order('slot');

      final rows = List<Map<String, dynamic>>.from(response)
          .map(BannerSlideData.fromRow)
          .where((slide) => slide.headline.trim().isNotEmpty)
          .toList();

      if (!mounted) return;

      setState(() => _slides = rows);

      _restartAutoPlay();
    } catch (e) {
      debugPrint('loadBannerSlides error: $e');
      // لا نعطّل الصفحة الرئيسية؛ يبقى الشكل الافتراضي ظاهراً.
    }
  }

  void _restartAutoPlay() {
    _autoPlayTimer?.cancel();

    if (_slides.length < 2) return;

    _autoPlayTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_pageController.hasClients) return;

      _pageController.animateToPage(
        (_currentPage.value + 1) % _slides.length,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides.isEmpty ? const [BannerSlideData.fallback] : _slides;

    return Column(
      children: [
        SizedBox(
          height: 172,
          child: PageView.builder(
            controller: _pageController,
            itemCount: slides.length,
            onPageChanged: (index) => _currentPage.value = index,
            itemBuilder: (context, index) {
              final slide = slides[index];

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: BannerCardContent(
                  headline: slide.headline,
                  subtitle: slide.subtitle,
                  onAddListing: widget.onAddListing,
                  onBrowseCategories: widget.onBrowseCategories,
                ),
              );
            },
          ),
        ),

        if (slides.length > 1) ...[
          const SizedBox(height: 6),
          ValueListenableBuilder<int>(
            valueListenable: _currentPage,
            builder: (context, current, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(slides.length, (index) {
                  final active = index == current;

                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 18 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active
                          ? AppColors.brand
                          : AppColors.brand.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ],
    );
  }
}

// =============================================================
// شكل بطاقة البنر نفسه (بلا تغيير عن التصميم الحالي)، مستقل عن
// مصدر النص حتى تستخدمه شاشة تحكم الأدمن كمعاينة مطابقة تماماً.
// =============================================================
class BannerCardContent extends StatelessWidget {
  final String headline;
  final String subtitle;
  final VoidCallback? onAddListing;
  final VoidCallback? onBrowseCategories;

  const BannerCardContent({
    super.key,
    required this.headline,
    required this.subtitle,
    this.onAddListing,
    this.onBrowseCategories,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
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

          const Positioned(
            top: -45,
            left: -30,
            child: _DecorativeCircle(size: 150, opacity: 0.10),
          ),

          const Positioned(
            bottom: -55,
            right: -25,
            child: _DecorativeCircle(size: 160, opacity: 0.09),
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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        headline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
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
  final VoidCallback? onTap;
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
          constraints: const BoxConstraints(minHeight: 38),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: outlined
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: outlined ? Colors.white : AppColors.brandDark,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: outlined ? Colors.white : AppColors.brandDark,
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
        color: Colors.white.withValues(alpha: opacity),
      ),
    );
  }
}
