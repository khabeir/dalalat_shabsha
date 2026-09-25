import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTextStyles {
  AppTextStyles._();

  static const drawerName = TextStyle(
    color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w900,
  );
  static const drawerContact = TextStyle(
    color: Colors.white70, fontSize: 11.5, fontWeight: FontWeight.w500,
  );
  static const drawerBadge = TextStyle(
    color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w700,
  );
  static const drawerSection = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.ink,
  );
  static const drawerItem = TextStyle(
    fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.ink,
  );
  static const drawerSubtitle = TextStyle(
    fontSize: 10.5, fontWeight: FontWeight.w500,
  );
  static const smallBrand = TextStyle(
    fontSize: 11.5, fontWeight: FontWeight.w900, color: AppColors.ink,
  );
}
