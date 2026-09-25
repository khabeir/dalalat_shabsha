import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

/// القائمة الجانبية الخاصة بالصفحة الرئيسية.
///
/// تم فصلها عن HomeScreen حتى يمكن إعادة استخدام مكونات الهوية والتصميم
/// لاحقاً في صفحات أخرى دون تضخيم ملف الصفحة الرئيسية.
class HomeDrawer extends StatelessWidget {
  const HomeDrawer({
    super.key,
    required this.user,
    required this.name,
    required this.isAdmin,
    required this.categories,
    required this.selectedCategoryId,
    required this.onProfile,
    required this.onAddListing,
    required this.onAdminPanel,
    required this.onSelectCategory,
    required this.onFavorites,
    required this.onMyListings,
    required this.onSignOut,
  });

  final User? user;
  final String? name;
  final bool isAdmin;
  final List<Map<String, dynamic>> categories;
  final int? selectedCategoryId;

  final Future<void> Function() onProfile;
  final Future<void> Function() onAddListing;
  final Future<void> Function() onAdminPanel;
  final void Function(int categoryId) onSelectCategory;
  final VoidCallback onFavorites;
  final VoidCallback onMyListings;
  final Future<void> Function() onSignOut;

  IconData _iconForCategory(Map<String, dynamic> category) {
    const iconMap = <String, IconData>{
      'car': Icons.directions_car_outlined,
      'cars': Icons.directions_car_outlined,
      'real_estate': Icons.home_work_outlined,
      'home': Icons.home_work_outlined,
      'phone': Icons.phone_android_outlined,
      'electronics': Icons.devices_other_outlined,
      'electric': Icons.electrical_services_outlined,
      'clothes': Icons.checkroom_outlined,
      'furniture': Icons.weekend_outlined,
      'animals': Icons.pets_outlined,
      'crops': Icons.agriculture_outlined,
      'food': Icons.restaurant_outlined,
      'tools': Icons.build_outlined,
      'services': Icons.handyman_outlined,
      'jobs': Icons.work_outline,
      'other': Icons.more_horiz_outlined,
    };

    return iconMap[category['icon']?.toString().trim()] ??
        _categoryIcon(category['name']?.toString() ?? '');
  }

  IconData _categoryIcon(String name) {
    switch (name.trim()) {
      case 'سيارات ومركبات':
        return Icons.directions_car_outlined;
      case 'عقارات':
        return Icons.home_work_outlined;
      case 'موبايلات وإلكترونيات':
        return Icons.phone_android_outlined;
      case 'أجهزة كهربائية':
        return Icons.electrical_services_outlined;
      case 'ملابس وأحذية':
        return Icons.checkroom_outlined;
      case 'أثاث ومستلزمات منزلية':
        return Icons.weekend_outlined;
      case 'مواشي وحيوانات':
        return Icons.pets_outlined;
      case 'محاصيل زراعية':
        return Icons.agriculture_outlined;
      case 'مواد غذائية':
        return Icons.restaurant_outlined;
      case 'أدوات ومعدات':
        return Icons.build_outlined;
      case 'خدمات':
        return Icons.handyman_outlined;
      case 'وظائف':
        return Icons.work_outline;
      case 'أخرى':
        return Icons.more_horiz_outlined;
      default:
        return Icons.category_outlined;
    }
  }

  Widget _buildHeader() {
    final displayName = name != null && name!.trim().isNotEmpty
        ? name!.trim()
        : user == null
            ? 'مرحباً بك'
            : 'مستخدم دلالة شبشة';

    final authPhone = user?.phone?.trim() ?? '';
    final email = user?.email?.trim() ?? '';
    final metadataPhone =
        user?.userMetadata?['phone']?.toString().trim() ?? '';
    final phone = authPhone.isNotEmpty ? authPhone : metadataPhone;

    final contact = phone.isNotEmpty
        ? phone
        : email.isNotEmpty
            ? email
            : user == null
                ? 'سوقك المحلي في شبشة'
                : 'حسابك في دلالة شبشة';

    return Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.brandDark, AppColors.brand, Color(0xFF7548D1)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.brand.withValues(alpha: 0.22),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            left: -22,
            top: -28,
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            right: -32,
            bottom: -40,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.gold.withValues(alpha: 0.08),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 15, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.65),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    user == null
                        ? Icons.person_outline_rounded
                        : Icons.storefront_rounded,
                    size: 28,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        contact,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'دلالة شبشة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(7, 9, 7, 6),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: AppColors.brand),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
          ),
          Container(
            width: 34,
            height: 2,
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    bool selected = false,
    bool isDestructive = false,
    bool emphasized = false,
  }) {
    final itemColor = isDestructive
        ? Colors.red.shade700
        : selected || emphasized
            ? AppColors.brand
            : Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected
            ? AppColors.brandSoft
            : emphasized
                ? AppColors.brand.withValues(alpha: 0.055)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: selected
                  ? Border.all(
                      color: AppColors.brand.withValues(alpha: 0.14),
                      width: 1,
                    )
                  : emphasized
                      ? Border.all(
                          color: AppColors.brand.withValues(alpha: 0.08),
                          width: 1,
                        )
                      : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 37,
                  height: 37,
                  decoration: BoxDecoration(
                    gradient: selected || emphasized
                        ? const LinearGradient(
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                            colors: [AppColors.brand, AppColors.brandDark],
                          )
                        : null,
                    color: selected || emphasized
                        ? null
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: selected || emphasized ? Colors.white : itemColor,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: itemColor,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.chevron_left_rounded,
                    size: 21,
                    color: AppColors.brand,
                  )
                else if (emphasized)
                  const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    size: 13,
                    color: AppColors.brand,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _closeAndRun(Future<void> Function() action) async {
    Navigator.of(context).pop();
    await action();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
      width: 300,
      elevation: 8,
      backgroundColor: const Color(0xFFFCFAFF),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
                children: [
                  _buildSectionTitle('الوصول السريع', Icons.bolt_rounded),
                  _buildItem(context,
                    icon: user == null
                        ? Icons.login_rounded
                        : Icons.person_outline_rounded,
                    title: user == null ? 'تسجيل الدخول' : 'الملف الشخصي',
                    subtitle: user == null ? 'ادخل إلى حسابك' : 'إدارة حسابك',
                    onTap: () => _closeAndRun(onProfile),
                  ),
                  _buildItem(context,
                    icon: Icons.add_circle_outline_rounded,
                    title: 'إضافة إعلان',
                    subtitle: 'اعرض ما تريد بيعه في شبشة',
                    emphasized: true,
                    onTap: () => _closeAndRun(onAddListing),
                  ),
                  if (isAdmin) ...[
                    _buildSectionTitle(
                      'الإدارة',
                      Icons.admin_panel_settings_outlined,
                    ),
                    _buildItem(context,
                      icon: Icons.admin_panel_settings_rounded,
                      title: 'لوحة تحكم الإدارة',
                      subtitle: 'إدارة ومراجعة الإعلانات',
                      emphasized: true,
                      onTap: () => _closeAndRun(onAdminPanel),
                    ),
                  ],
                  _buildSectionTitle('الأقسام', Icons.grid_view_rounded),
                  if (categories.isEmpty)
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.brandSoft.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.category_outlined,
                            size: 28,
                            color: AppColors.brand,
                          ),
                          SizedBox(height: 6),
                          Text(
                            'لا توجد أقسام حالياً',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...categories.map((category) {
                      final categoryId = category['id'] as int?;
                      final categoryName =
                          category['name']?.toString() ?? 'بدون اسم';
                      final selected = selectedCategoryId == categoryId;

                      return _buildItem(context,
                        icon: _iconForCategory(category),
                        title: categoryName,
                        selected: selected,
                        onTap: () {
                          Navigator.of(context).pop();
                          if (categoryId == null) return;
                          onSelectCategory(categoryId);
                        },
                      );
                    }),
                  _buildSectionTitle(
                    'حسابي',
                    Icons.account_circle_outlined,
                  ),
                  _buildItem(context,
                    icon: Icons.favorite_border_rounded,
                    title: 'المفضلة',
                    subtitle: 'الإعلانات التي حفظتها',
                    onTap: () {
                      Navigator.of(context).pop();
                      onFavorites();
                    },
                  ),
                  _buildItem(context,
                    icon: Icons.inventory_2_outlined,
                    title: 'إعلاناتي',
                    subtitle: 'متابعة إعلاناتك',
                    onTap: () {
                      Navigator.of(context).pop();
                      onMyListings();
                    },
                  ),
                  if (user != null)
                    _buildItem(context,
                      icon: Icons.logout_rounded,
                      title: 'تسجيل الخروج',
                      subtitle: 'الخروج من الحساب الحالي',
                      isDestructive: true,
                      onTap: () => _closeAndRun(onSignOut),
                    ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.storefront_rounded,
                    size: 16,
                    color: AppColors.brand,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'دلالة شبشة',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: AppColors.gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'سوقك المحلي',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
