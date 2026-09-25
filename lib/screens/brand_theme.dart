import 'dart:math' as math;

import 'package:flutter/material.dart';

// =============================================================
// هوية دلالة شبشة: الألوان والشعار والخلفية المرسومة، مستخدمة في
// الصفحة الرئيسية وبقية الشاشات حتى يتطابق الشكل بينها كلها.
// =============================================================

class Brand {
  Brand._();

  static const primary = Color(0xFF5B2DB5);
  static const primaryDark = Color(0xFF3B1785);
  static const soft = Color(0xFFEFE9FF);
  static const ink = Color(0xFF241A55);
  static const orange = Color(0xFFFF9F1C);
  static const gold = Color(0xFFFFC93C);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8A5CE6), primary],
  );

  static const bannerGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF3B1785), Color(0xFF5B2DB5), Color(0xFF7A45DA)],
  );

  static const goldGradient = LinearGradient(
    colors: [Color(0xFFFFB02E), Color(0xFFFF8A00)],
  );
}

// شعار دلالة شبشة: دبوس بنفسجي + عربة تسوق بيضاء + وسم عرض ذهبي.
class BrandLogo extends StatelessWidget {
  final double size;

  const BrandLogo({super.key, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final cartSize = size * 0.37;
    final badgeSize = size * 0.32;

    return SizedBox(
      width: size,
      height: size * 1.13,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.location_on_rounded, size: size * 1.13, color: Brand.primary),
          Positioned(
            top: size * 0.26,
            child: Icon(Icons.shopping_cart_rounded, size: cartSize, color: Colors.white),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              decoration: const BoxDecoration(color: Brand.gold, shape: BoxShape.circle),
              child: Icon(Icons.local_offer_rounded, size: badgeSize * 0.55, color: Brand.primaryDark),
            ),
          ),
        ],
      ),
    );
  }
}

// عنوان التطبيق كاملاً (الشعار + الاسم + الشعار الفرعي)، بلون فاتح
// يصلح فوق صورة أو خلفية بنفسجية.
class BrandWordmark extends StatelessWidget {
  final double logoSize;
  final double titleSize;
  final Color color;
  final bool showTagline;

  const BrandWordmark({
    super.key,
    this.logoSize = 46,
    this.titleSize = 26,
    this.color = Colors.white,
    this.showTagline = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandLogo(size: logoSize),
        SizedBox(height: logoSize * 0.18),
        Text(
          'دلالة شبشة',
          style: TextStyle(fontSize: titleSize, fontWeight: FontWeight.w900, color: color),
        ),
        if (showTagline) ...[
          const SizedBox(height: 4),
          Text(
            'سوقك المحلي في شبشة',
            style: TextStyle(
              fontSize: titleSize * 0.46,
              fontWeight: FontWeight.w700,
              color: color.withValues(alpha: 0.9),
            ),
          ),
        ],
      ],
    );
  }
}

// خلفية علوية بنفسجية مع مشهد شبشة المرسوم وحافة سفلية منحنية،
// تُستخدم كترويسة لصفحات مثل تسجيل الدخول.
class BrandHeaderBackground extends StatelessWidget {
  final double height;
  final Widget? child;
  final double curveRadius;

  const BrandHeaderBackground({
    super.key,
    required this.height,
    this.child,
    this.curveRadius = 32,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Positioned.fill(
            child: DecoratedBox(decoration: BoxDecoration(gradient: Brand.bannerGradient)),
          ),
          const Positioned.fill(
            child: Opacity(
              opacity: 0.55,
              child: CustomPaint(painter: ShabshaScenePainter()),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: curveRadius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(curveRadius)),
              ),
            ),
          ),
          if (child != null) Positioned.fill(child: child!),
        ],
      ),
    );
  }
}

// زر بتدرج ذهبي (نفس زر "أضف إعلانك الآن" في بانر الصفحة الرئيسية).
class BrandGoldButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool loading;
  final double height;

  const BrandGoldButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
    this.loading = false,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null || loading;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: disabled && !loading ? 0.6 : 1,
        child: Container(
          height: height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: Brand.goldGradient,
            borderRadius: BorderRadius.circular(height / 2),
            boxShadow: [
              BoxShadow(
                color: Brand.orange.withValues(alpha: 0.45),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (icon != null) ...[
                      const SizedBox(width: 8),
                      Icon(icon, color: Colors.white, size: 22),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

// رسم احتياطي لمشهد شبشة عند الغروب (مباني طينية ونخيل ونهر).
// يظهر إذا لم تضف صورة حقيقية في assets/images.
class ShabshaScenePainter extends CustomPainter {
  const ShabshaScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizon = h * 0.64;

    // السماء
    final skyRect = Rect.fromLTWH(0, 0, w, horizon + 1);

    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF7C9CEB),
            Color(0xFFB6A4E8),
            Color(0xFFF5B5A6),
            Color(0xFFFFCB90),
          ],
          stops: [0.0, 0.38, 0.72, 1.0],
        ).createShader(skyRect),
    );

    // سحب ناعمة
    void cloud(double cx, double cy, double cw, double ch, Color color) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(w * cx, h * cy),
          width: w * cw,
          height: h * ch,
        ),
        Paint()
          ..color = color
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.03),
      );
    }

    cloud(0.20, 0.15, 0.50, 0.10, Colors.white.withValues(alpha: 0.30));
    cloud(0.68, 0.10, 0.44, 0.09, const Color(0xFFFFC2C8).withValues(alpha: 0.45));
    cloud(0.90, 0.26, 0.40, 0.08, Colors.white.withValues(alpha: 0.28));
    cloud(0.42, 0.34, 0.60, 0.08, const Color(0xFFFFB27A).withValues(alpha: 0.40));

    // وهج الشمس عند الأفق
    canvas.drawRect(
      skyRect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x99FFE3AA), Color(0x00FFE3AA)],
        ).createShader(
          Rect.fromCircle(center: Offset(w * 0.72, horizon), radius: w * 0.5),
        ),
    );

    // تلال بعيدة
    final hills = Path()
      ..moveTo(0, horizon)
      ..quadraticBezierTo(w * 0.2, horizon - h * 0.10, w * 0.42, horizon - h * 0.03)
      ..quadraticBezierTo(w * 0.7, horizon - h * 0.12, w, horizon - h * 0.04)
      ..lineTo(w, horizon)
      ..close();

    canvas.drawPath(
      hills,
      Paint()..color = const Color(0xFFD59A78).withValues(alpha: 0.55),
    );

    // المباني الطينية: [x, العرض, الارتفاع] كنسب من الأبعاد.
    const buildings = <List<double>>[
      [0.00, 0.11, 0.20],
      [0.09, 0.10, 0.31],
      [0.18, 0.13, 0.23],
      [0.30, 0.10, 0.34],
      [0.39, 0.10, 0.26],
      [0.49, 0.13, 0.30],
      [0.61, 0.11, 0.22],
      [0.71, 0.12, 0.33],
      [0.82, 0.10, 0.24],
      [0.91, 0.10, 0.30],
    ];

    for (var i = 0; i < buildings.length; i++) {
      final b = buildings[i];
      final bx = w * b[0];
      final bw = w * b[1];
      final bh = h * b[2];
      final top = horizon - bh;

      final tone = i.isEven ? const Color(0xFFB9744A) : const Color(0xFFA5613C);
      final shade = Color.lerp(tone, const Color(0xFF6B3A25), 0.35)!;
      final rect = Rect.fromLTWH(bx, top, bw + 1, bh + 1);

      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [tone, shade],
          ).createShader(rect),
      );

      // شرفات علوية
      final teeth = math.max(3, (bw / (h * 0.045)).floor());
      final toothWidth = bw / (teeth * 2 - 1);
      final toothHeight = h * 0.022;

      for (var t = 0; t < teeth; t++) {
        canvas.drawRect(
          Rect.fromLTWH(
            bx + t * toothWidth * 2,
            top - toothHeight,
            toothWidth,
            toothHeight + 1,
          ),
          Paint()..color = tone,
        );
      }

      // نوافذ صغيرة
      final windowPaint = Paint()
        ..color = const Color(0xFF4A2A1B).withValues(alpha: 0.75);

      final cols = math.max(2, (bw / (h * 0.09)).floor());
      final rows = math.max(1, (bh / (h * 0.12)).floor() - 1);

      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final cx = bx + bw * (c + 0.5) / cols;
          final cy = top + bh * 0.20 + r * (bh * 0.66 / rows);

          canvas.drawRect(
            Rect.fromCenter(
              center: Offset(cx, cy),
              width: h * 0.026,
              height: h * 0.042,
            ),
            windowPaint,
          );
        }
      }
    }

    // البرج
    final towerWidth = w * 0.05;
    final towerX = w * 0.45;
    final towerHeight = h * 0.46;
    final towerTop = horizon - towerHeight;

    canvas.drawRect(
      Rect.fromLTWH(towerX, towerTop, towerWidth, towerHeight + 1),
      Paint()..color = const Color(0xFFB06A42),
    );

    canvas.drawRect(
      Rect.fromLTWH(
        towerX - towerWidth * 0.12,
        towerTop,
        towerWidth * 1.24,
        h * 0.03,
      ),
      Paint()..color = const Color(0xFF8E512F),
    );

    canvas.drawArc(
      Rect.fromLTWH(
        towerX + towerWidth * 0.1,
        towerTop - towerWidth * 0.5,
        towerWidth * 0.8,
        towerWidth,
      ),
      math.pi,
      math.pi,
      true,
      Paint()..color = const Color(0xFF7A4326),
    );

    canvas.drawCircle(
      Offset(towerX + towerWidth / 2, towerTop + h * 0.09),
      towerWidth * 0.22,
      Paint()..color = const Color(0xFFFFE8B0),
    );

    // النهر
    final riverRect = Rect.fromLTWH(0, horizon, w, h - horizon);

    canvas.drawRect(
      riverRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFBE85),
            Color(0xFFC99AB6),
            Color(0xFF5E6FB0),
            Color(0xFF3A3F86),
          ],
          stops: [0.0, 0.35, 0.75, 1.0],
        ).createShader(riverRect),
    );

    // ضفة خضراء
    final bank = Path()
      ..moveTo(0, horizon + h * 0.01)
      ..cubicTo(w * 0.15, horizon - h * 0.05, w * 0.30, horizon + h * 0.02,
          w * 0.50, horizon - h * 0.02)
      ..cubicTo(w * 0.70, horizon - h * 0.06, w * 0.85, horizon, w,
          horizon - h * 0.02)
      ..lineTo(w, horizon + h * 0.05)
      ..lineTo(0, horizon + h * 0.05)
      ..close();

    canvas.drawPath(bank, Paint()..color = const Color(0xFF2E5B34));

    // انعكاسات على الماء
    final streak = Paint()..color = Colors.white.withValues(alpha: 0.22);

    for (var i = 0; i < 6; i++) {
      final y = horizon + h * (0.09 + i * 0.05);
      final streakWidth = w * (0.22 + (i % 3) * 0.10);
      final cx = w * (0.20 + ((i * 0.17) % 0.62));

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, y),
            width: streakWidth,
            height: h * 0.008,
          ),
          const Radius.circular(4),
        ),
        streak,
      );
    }

    // النخيل
    void palm(double bxFraction, double baseY, double height, double lean) {
      final base = Offset(w * bxFraction, baseY);
      final top = Offset(base.dx + lean * w, baseY - height);

      final trunk = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(
          base.dx + lean * w * 0.2,
          baseY - height * 0.5,
          top.dx,
          top.dy,
        );

      canvas.drawPath(
        trunk,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(2.0, h * 0.022)
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF3F2A1A),
      );

      const angles = [-172.0, -150.0, -125.0, -100.0, -80.0, -55.0, -30.0, -8.0];

      for (var i = 0; i < angles.length; i++) {
        final angle = angles[i] * math.pi / 180;
        final direction = Offset(math.cos(angle), math.sin(angle));
        final length = height * 0.55;

        final end = top + direction * length + Offset(0, length * 0.30);
        final control =
            top + direction * length * 0.55 + Offset(0, -length * 0.30);

        final frond = Path()
          ..moveTo(top.dx, top.dy)
          ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

        canvas.drawPath(
          frond,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.6, h * 0.016)
            ..strokeCap = StrokeCap.round
            ..color = i.isEven
                ? const Color(0xFF1F5A2E)
                : const Color(0xFF2E7A3E),
        );
      }
    }

    palm(0.10, horizon + h * 0.03, h * 0.46, 0.015);
    palm(0.27, horizon, h * 0.36, -0.010);
    palm(0.60, horizon + h * 0.02, h * 0.42, 0.010);
    palm(0.78, horizon, h * 0.34, -0.012);
    palm(0.94, horizon + h * 0.03, h * 0.50, -0.020);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
