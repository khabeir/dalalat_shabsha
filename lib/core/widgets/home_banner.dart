import 'dart:async';
import 'package:flutter/material.dart';
import 'home_decorative_painters.dart';
import '../theme/app_colors.dart';

class HomeBanner extends StatefulWidget {
  const HomeBanner({
    super.key,
    required this.onAddListing,
    required this.onBrowseCategories,
  });

  final VoidCallback onAddListing;
  final VoidCallback onBrowseCategories;

  @override
  State<HomeBanner> createState() => _HomeBannerState();
}

enum _BannerAction { addListing, browseCategories }

class _BannerSlide {
  const _BannerSlide(
    this.line1,
    this.line2,
    this.bullets,
    this.cta,
    this.action,
  );

  final String line1;
  final String line2;
  final List<String> bullets;
  final String cta;
  final _BannerAction action;
}

class _HomeBannerState extends State<HomeBanner> {
  static const _asset = 'assets/images/home_banner.jpg';
  static const _slides = <_BannerSlide>[
    _BannerSlide('كل ما تحتاجه', 'في مكان واحد', ['إعلانات مميزة', 'بيع وشراء محلي', 'انتشار واسع'], 'أضف إعلانك الآن', _BannerAction.addListing),
    _BannerSlide('بيع أسرع', 'بصور واضحة', ['صوّر بالكاميرا', 'حتى 6 صور', 'سعر واضح'], 'أضف إعلانك الآن', _BannerAction.addListing),
    _BannerSlide('تسوق بثقة', 'من أهل شبشة', ['عاين قبل الدفع', 'قابل البائع في مكان عام'], 'تصفح الأقسام', _BannerAction.browseCategories),
    _BannerSlide('ابحث بسهولة', 'عن أي شيء', ['أقسام منظمة', 'بحث سريع', 'الأحدث أولاً'], 'تصفح الأقسام', _BannerAction.browseCategories),
  ];

  final _controller = PageController();
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        (_index + 1) % _slides.length,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onAction(_BannerAction action) {
    if (action == _BannerAction.addListing) {
      widget.onAddListing();
    } else {
      widget.onBrowseCategories();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 170,
          child: PageView.builder(
            controller: _controller,
            itemCount: _slides.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _buildSlide(_slides[index]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_slides.length, (index) {
            final active = index == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: active ? 20 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: active ? AppColors.brand : AppColors.brand.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSlide(_BannerSlide slide) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final photoWidth = constraints.maxWidth * 0.48;
          return Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight, end: Alignment.centerLeft,
                      colors: [AppColors.brandDark, AppColors.brand, Color(0xFF7A45DA)],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0, top: 0, bottom: 0, width: photoWidth,
                child: ClipPath(
                  clipper: const HomePhotoClipper(),
                  child: Image.asset(
                    _asset, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white24,
                      child: const Icon(Icons.directions_car, color: Colors.white, size: 48),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0, top: 0, bottom: 0, width: photoWidth,
                child: const IgnorePointer(child: CustomPaint(painter: HomeSwooshPainter())),
              ),
              Positioned(
                left: 16, top: 12, bottom: 12, right: photoWidth - 10,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(slide.line1, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, height: 1.1)),
                    Text(slide.line2, style: const TextStyle(color: AppColors.gold, fontSize: 20, fontWeight: FontWeight.w900, height: 1.1)),
                    const SizedBox(height: 6),
                    ...slide.bullets.map((bullet) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)),
                        const SizedBox(width: 5),
                        Text(bullet, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w600)),
                      ]),
                    )),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _onAction(slide.action),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFFB02E), Color(0xFFFF8A00)]),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(slide.action == _BannerAction.addListing ? Icons.add_circle_outline_rounded : Icons.grid_view_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 5),
                          Text(slide.cta, style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
