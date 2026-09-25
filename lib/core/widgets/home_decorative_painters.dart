import 'package:flutter/material.dart';

class HomePhotoClipper extends CustomClipper<Path> {
  const HomePhotoClipper();

  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width * 0.25, 0);
    path.quadraticBezierTo(
      0,
      size.height * 0.5,
      size.width * 0.35,
      size.height,
    );
    path.lineTo(size.width, size.height);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class HomeSwooshPainter extends CustomPainter {
  const HomeSwooshPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final path = Path();
    path.moveTo(size.width * 0.23, 0);
    path.quadraticBezierTo(
      -2,
      size.height * 0.5,
      size.width * 0.33,
      size.height,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HomeSparklesPainter extends CustomPainter {
  const HomeSparklesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final paint = Paint()
      ..color = const Color(0xFFFFB02E)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round;

    for (final degrees in const [-150.0, -90.0, -30.0]) {
      final angle = degrees * math.pi / 180;
      final direction = Offset(math.cos(angle), math.sin(angle));

      canvas.drawLine(
        center + direction * 34,
        center + direction * 41,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// رسم احتياطي لمشهد شبشة عند الغروب (مباني طينية ونخيل ونهر).
// يظهر إذا لم تضف صورة حقيقية في assets/images.
class HomeShabshaScenePainter extends CustomPainter {
  const HomeShabshaScenePainter();

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
