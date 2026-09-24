import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// الصفحة الرئيسية لتطبيق «دلالة شبشة».
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const purple = Color(0xFF4820A5);
  static const darkPurple = Color(0xFF291064);
  static const orange = Color(0xFFFFA900);
  static const cream = Color(0xFFFFFCF5);
  static const muted = Color(0xFF77758C);

  final supabase = Supabase.instance.client;
  final searchController = TextEditingController();

  List<Map<String, dynamic>> categories = [];
  List<Map<String, dynamic>> listings = [];
  bool loading = true;
  String? error;
  String? selectedCategory;
  String searchText = '';

  @override
  void initState() {
    super.initState();
    searchController.addListener(() {
      if (mounted) setState(() => searchText = searchController.text.trim());
    });
    loadData();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await Future.wait([
        supabase.from('categories').select('*'),
        supabase.from('listings').select('*'),
      ]);

      final cats = (data[0] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((e) => e['active'] != false && e['is_active'] != false)
          .toList();

      final ads = (data[1] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where(isPublished)
          .toList()
        ..sort((a, b) => dateOf(b).compareTo(dateOf(a)));

      if (!mounted) return;
      setState(() {
        categories = cats;
        listings = ads;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'تعذّر تحميل الإعلانات. تحقق من اتصال الإنترنت وإعدادات Supabase.';
      });
    }
  }

  bool isPublished(Map<String, dynamic> ad) {
    final s = text(ad['status']).toLowerCase();
    // أضف هنا قيمة الحالة التي تستخدمها قاعدة بياناتك للإعلانات المنشورة.
    return ['approved', 'active', 'published', 'مقبول', 'منشور'].contains(s);
  }

  DateTime dateOf(Map<String, dynamic> row) =>
      DateTime.tryParse(text(row['created_at'])) ??
      DateTime.fromMillisecondsSinceEpoch(0);

  String text(dynamic value, [String fallback = '']) {
    if (value == null || value.toString().trim().isEmpty) return fallback;
    return value.toString().trim();
  }

  String categoryName(Map<String, dynamic> row) =>
      text(row['name'] ?? row['title'] ?? row['label'], 'قسم');

  String adCategory(Map<String, dynamic> ad) {
    final direct = ad['category_name'] ?? ad['category'];
    if (direct is Map) return text(direct['name'] ?? direct['title'], 'إعلانات');
    if (direct != null && direct is! int) return direct.toString();

    final id = text(ad['category_id']);
    for (final cat in categories) {
      if (text(cat['id']) == id) return categoryName(cat);
    }
    return 'إعلانات';
  }

  bool isFeatured(Map<String, dynamic> ad) =>
      ad['is_featured'] == true ||
      ad['is_promoted'] == true ||
      ad['featured'] == true ||
      ad['promotion_active'] == true;

  String? imageOf(Map<String, dynamic> ad) {
    final value = ad['image_url'] ?? ad['image'];
    if (value is String && value.trim().isNotEmpty) return value.trim();

    final images = ad['images'];
    if (images is List && images.isNotEmpty) {
      final first = images.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
      if (first is Map) {
        final url = first['image_url'] ?? first['url'] ?? first['path'];
        if (url != null && url.toString().trim().isNotEmpty) return url.toString();
      }
    }
    return null;
  }

  String priceOf(Map<String, dynamic> ad) {
    final price = ad['price'];
    final type = text(ad['price_type']).toLowerCase();
    if (type == 'contact' || type == 'عند التواصل') return 'السعر عند التواصل';
    if (price == null || price.toString().trim().isEmpty) return 'السعر عند التواصل';
    if (type == 'negotiable' || type == 'قابل للتفاوض') {
      return '${price.toString()} SDG · قابل للتفاوض';
    }
    return '${price.toString()} SDG';
  }

  List<Map<String, dynamic>> get filteredAds {
    final q = searchText.toLowerCase();
    return listings.where((ad) {
      if (selectedCategory != null) {
        final id = text(ad['category_id']);
        final chosen = categories.where((c) => text(c['id']) == selectedCategory);
        if (id != selectedCategory &&
            (chosen.isEmpty || adCategory(ad) != categoryName(chosen.first))) {
          return false;
        }
      }
      if (q.isEmpty) return true;
      final haystack = [
        ad['title'], ad['description'], ad['area'], ad['address'], adCategory(ad)
      ].map((e) => text(e).toLowerCase()).join(' ');
      return haystack.contains(q);
    }).toList();
  }

  IconData categoryIcon(String name) {
    if (name.contains('عقار') || name.contains('سكن') || name.contains('أرض')) {
      return Icons.home_work_rounded;
    }
    if (name.contains('سيار') || name.contains('مركب')) return Icons.directions_car_rounded;
    if (name.contains('أثاث') || name.contains('منزل')) return Icons.weekend_rounded;
    if (name.contains('خدم')) return Icons.handyman_rounded;
    if (name.contains('إلكترون') || name.contains('هاتف')) return Icons.devices_rounded;
    if (name.contains('ملابس')) return Icons.checkroom_rounded;
    return Icons.storefront_rounded;
  }

  void addListing() {
    // اربط هذا الزر بصفحة AddListingScreen في مشروعك.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اربط الزر بصفحة إضافة إعلان الموجودة في مشروعك.')),
    );
  }

  void openAd(Map<String, dynamic> ad) {
    // اربط هذه الدالة بصفحة تفاصيل الإعلان في مشروعك.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('اربط البطاقة بصفحة تفاصيل الإعلان.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = filteredAds;
    final featured = all.where(isFeatured).toList();
    final latest = all.where((e) => !isFeatured(e)).toList();
    final visibleLatest = latest.isNotEmpty ? latest : featured;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: cream,
        body: SafeArea(
          child: RefreshIndicator(
            color: purple,
            onRefresh: loadData,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: header()),
                SliverToBoxAdapter(child: searchBox()),
                SliverToBoxAdapter(child: greeting()),
                SliverToBoxAdapter(child: banner()),
                SliverToBoxAdapter(child: sectionTitle('الأقسام')),
                SliverToBoxAdapter(child: categoryList()),
                if (loading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(35),
                      child: Center(child: CircularProgressIndicator(color: purple)),
                    ),
                  )
                else if (error != null)
                  SliverToBoxAdapter(child: errorWidget())
                else ...[
                  if (featured.isNotEmpty) ...[
                    SliverToBoxAdapter(child: sectionTitle('إعلانات مميزة', icon: Icons.star_rounded)),
                    SliverToBoxAdapter(child: horizontalAds(featured)),
                  ],
                  SliverToBoxAdapter(child: sectionTitle('أحدث الإعلانات', icon: Icons.access_time_rounded)),
                  if (visibleLatest.isEmpty)
                    const SliverToBoxAdapter(child: EmptyAds())
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      sliver: SliverGrid(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => AdCard(
                            ad: visibleLatest[i],
                            imageUrl: imageOf(visibleLatest[i]),
                            category: adCategory(visibleLatest[i]),
                            price: priceOf(visibleLatest[i]),
                            onTap: () => openAd(visibleLatest[i]),
                          ),
                          childCount: visibleLatest.length,
                        ),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 14,
                          childAspectRatio: 0.68,
                        ),
                      ),
                    ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
              ],
            ),
          ),
        ),
        bottomNavigationBar: bottomBar(),
      ),
    );
  }

  Widget header() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
        child: Row(
          children: [
            circleButton(Icons.person_rounded, () {}),
            const Spacer(),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('دلالة شبشة', style: TextStyle(
                  color: darkPurple, fontSize: 28, fontWeight: FontWeight.w900)),
                Text('سوقك المحلي في شبشة',
                    style: TextStyle(color: muted, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.menu_rounded, color: darkPurple, size: 30),
            ),
          ],
        ),
      );

  Widget searchBox() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 3),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF0EDF5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'ابحث عن إعلان أو منطقة...',
              hintStyle: const TextStyle(color: muted, fontSize: 15),
              prefixIcon: const Icon(Icons.search_rounded, color: purple, size: 27),
              suffixIcon: searchText.isEmpty
                  ? null
                  : IconButton(
                      onPressed: searchController.clear,
                      icon: const Icon(Icons.close_rounded, color: muted),
                    ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            ),
          ),
        ),
      );

  Widget greeting() {
    final user = supabase.auth.currentUser;
    final name = text(user?.userMetadata?['full_name'] ?? user?.userMetadata?['name'], 'يا صديقي');
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 14),
      child: Row(children: [
        const Text('👋', style: TextStyle(fontSize: 22)),
        const SizedBox(width: 8),
        Text('مرحباً $name',
            style: const TextStyle(color: darkPurple, fontSize: 17, fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget banner() => Container(
        height: 205,
        margin: const EdgeInsets.fromLTRB(16, 2, 16, 18),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [purple, darkPurple],
          ),
          boxShadow: [BoxShadow(color: purple.withOpacity(.18), blurRadius: 18, offset: const Offset(0, 8))],
        ),
        child: Stack(children: [
          Positioned(
            left: -20, top: -12, bottom: -18,
            child: Icon(Icons.store_mall_directory_rounded, size: 190, color: Colors.white.withOpacity(.12)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 22, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('دلالة شبشة', style: TextStyle(color: Colors.white, fontSize: 29, fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              const Text('كل ما تحتاجه قريب منك', style: TextStyle(color: orange, fontSize: 23, fontWeight: FontWeight.w900)),
              const SizedBox(height: 9),
              const Text('إعلانات محلية  •  بيع وشراء  •  دعم مجتمعنا',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: addListing,
                icon: const Icon(Icons.add_circle_rounded, color: darkPurple),
                label: const Text('أضف إعلانك الآن'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: orange, foregroundColor: darkPurple, elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
            ]),
          ),
          Positioned(
            left: 20, bottom: 12,
            child: Row(children: List.generate(4, (i) => Container(
              width: i == 0 ? 10 : 7, height: i == 0 ? 10 : 7,
              margin: const EdgeInsets.only(left: 7),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == 0 ? orange : Colors.white.withOpacity(.55),
              ),
            ))),
          ),
        ]),
      );

  Widget sectionTitle(String title, {IconData? icon}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, color: purple, size: 23), const SizedBox(width: 7)],
          Text(title, style: const TextStyle(color: darkPurple, fontSize: 22, fontWeight: FontWeight.w900)),
          const Spacer(),
          const Text('عرض الكل', style: TextStyle(color: purple, fontWeight: FontWeight.w700)),
          const Icon(Icons.chevron_left_rounded, color: purple, size: 22),
        ]),
      );

  Widget categoryList() {
    const colors = [
      Color(0xFFF0E7FF), Color(0xFFFFF0D4), Color(0xFFE0F3ED),
      Color(0xFFE8E7FF), Color(0xFFFFE5E9), Color(0xFFE1F0FF),
    ];
    final fallback = [
      {'name': 'عقارات'}, {'name': 'مركبات'}, {'name': 'أثاث وديكور'},
      {'name': 'إلكترونيات'}, {'name': 'خدمات'},
    ];
    final items = categories.isEmpty ? fallback : categories;
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final item = items[i];
          final name = categoryName(item);
          final id = categories.isEmpty ? null : text(item['id']);
          final active = id != null && id == selectedCategory;
          return GestureDetector(
            onTap: () => setState(() => selectedCategory = active ? null : id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 104,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              decoration: BoxDecoration(
                color: active ? purple : colors[i % colors.length],
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: active ? orange : Colors.white, width: active ? 2 : 1.5),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.035), blurRadius: 10, offset: const Offset(0, 4))],
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(categoryIcon(name), color: active ? Colors.white : purple, size: 35),
                const SizedBox(height: 8),
                Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                    style: TextStyle(color: active ? Colors.white : darkPurple, fontSize: 12, fontWeight: FontWeight.w800)),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget horizontalAds(List<Map<String, dynamic>> ads) => SizedBox(
        height: 300,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: ads.length,
          separatorBuilder: (_, __) => const SizedBox(width: 13),
          itemBuilder: (context, i) => SizedBox(
            width: 245,
            child: AdCard(
              ad: ads[i], imageUrl: imageOf(ads[i]), category: adCategory(ads[i]),
              price: priceOf(ads[i]), onTap: () => openAd(ads[i]),
            ),
          ),
        ),
      );

  Widget errorWidget() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Icon(Icons.cloud_off_rounded, size: 42, color: muted),
          const SizedBox(height: 8),
          Text(error!, textAlign: TextAlign.center, style: const TextStyle(color: muted)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: loadData, icon: const Icon(Icons.refresh_rounded), label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(backgroundColor: purple, foregroundColor: Colors.white),
          ),
        ]),
      );

  Widget bottomBar() => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          boxShadow: [BoxShadow(color: purple.withOpacity(.09), blurRadius: 18, offset: const Offset(0, -5))],
        ),
        padding: const EdgeInsets.fromLTRB(8, 9, 8, 7),
        child: SafeArea(
          top: false,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            navItem(Icons.home_rounded, 'الرئيسية', true),
            navItem(Icons.inventory_2_outlined, 'إعلاناتي', false),
            GestureDetector(
              onTap: addListing,
              child: Container(
                width: 62, height: 62,
                decoration: BoxDecoration(
                  color: purple, borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: purple.withOpacity(.25), blurRadius: 12, offset: const Offset(0, 5))],
                ),
                child: const Icon(Icons.add_rounded, color: Colors.white, size: 38),
              ),
            ),
            navItem(Icons.favorite_border_rounded, 'المفضلة', false),
            navItem(Icons.person_outline_rounded, 'الملف الشخصي', false),
          ]),
        ),
      );

  Widget navItem(IconData icon, String label, bool selected) => InkWell(
        onTap: () {},
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: selected ? purple : const Color(0xFF5F5B6F), size: 25),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(
              color: selected ? purple : const Color(0xFF5F5B6F),
              fontSize: 10, fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            )),
          ]),
        ),
      );

  Widget circleButton(IconData icon, VoidCallback onTap) => Material(
        color: const Color(0xFFEDE5FF),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 48, height: 48, child: Icon(icon, color: purple, size: 27)),
        ),
      );
}

class AdCard extends StatelessWidget {
  const AdCard({
    super.key, required this.ad, required this.imageUrl, required this.category,
    required this.price, required this.onTap,
  });

  final Map<String, dynamic> ad;
  final String? imageUrl;
  final String category;
  final String price;
  final VoidCallback onTap;

  static const purple = Color(0xFF4820A5);
  static const darkPurple = Color(0xFF291064);

  String value(dynamic v, [String fallback = '']) =>
      v == null || v.toString().trim().isEmpty ? fallback : v.toString().trim();

  @override
  Widget build(BuildContext context) {
    final title = value(ad['title'], 'إعلان بدون عنوان');
    final location = value(ad['area'] ?? ad['address'] ?? ad['city'], 'شبشة');
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFECE8F2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              flex: 6,
              child: Stack(fit: StackFit.expand, children: [
                if (imageUrl != null)
                  Image.network(imageUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholder())
                else
                  placeholder(),
                Positioned(
                  top: 10, right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: purple, borderRadius: BorderRadius.circular(14)),
                    child: Text(category, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                ),
                Positioned(
                  top: 9, left: 9,
                  child: Container(
                    width: 36, height: 36,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('اربط هذا الزر بميزة المفضلة.')),
                      ),
                      icon: const Icon(Icons.favorite_border_rounded, color: darkPurple, size: 21),
                    ),
                  ),
                ),
              ]),
            ),
            Expanded(
              flex: 5,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: darkPurple, fontSize: 15, fontWeight: FontWeight.w900, height: 1.25)),
                  const SizedBox(height: 7),
                  Text(price, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: purple, fontSize: 14, fontWeight: FontWeight.w900)),
                  const Spacer(),
                  Row(children: [
                    const Icon(Icons.location_on_rounded, color: Color(0xFF77758C), size: 15),
                    const SizedBox(width: 3),
                    Expanded(child: Text(location, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF77758C), fontSize: 11, fontWeight: FontWeight.w600))),
                    const Icon(Icons.access_time_rounded, color: Color(0xFF77758C), size: 14),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget placeholder() => Container(
        color: const Color(0xFFF0EAFB),
        child: const Center(child: Icon(Icons.photo_outlined, color: purple, size: 52)),
      );
}

class EmptyAds extends StatelessWidget {
  const EmptyAds({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(children: [
          Icon(Icons.search_off_rounded, color: Color(0xFF8A80A6), size: 46),
          SizedBox(height: 8),
          Text('لا توجد إعلانات مطابقة حالياً',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF77758C), fontWeight: FontWeight.w700)),
        ]),
      );
}
