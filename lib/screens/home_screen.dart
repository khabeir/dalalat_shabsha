import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'add_listing_screen.dart';
import 'admin_listings_screen.dart';
import 'auth_screen.dart';
import 'favorites_screen.dart';
import 'listing_details_screen.dart';
import 'my_listings_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _listings = [];

  bool _loading = true;
  bool _isAdmin = false;
  String? _error;
  String _searchQuery = '';
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkAdminStatus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalizeSearchText(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه')
        .replaceAll('ـ', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<Map<String, dynamic>> get _filteredListings {
    final query = _normalizeSearchText(_searchQuery);

    return _listings.where((listing) {
      if (_selectedCategoryId != null &&
          listing['category_id'] != _selectedCategoryId) {
        return false;
      }

      if (query.isEmpty) return true;

      final title =
          _normalizeSearchText(listing['title']?.toString() ?? '');
      final description =
          _normalizeSearchText(listing['description']?.toString() ?? '');
      final area = _normalizeSearchText(listing['area']?.toString() ?? '');

      return title.contains(query) ||
          description.contains(query) ||
          area.contains(query);
    }).toList();
  }

  Future<void> _checkAdminStatus() async {
    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        if (!mounted) return;
        setState(() => _isAdmin = false);
        return;
      }

      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;
      setState(() => _isAdmin = profile?['role'] == 'admin');
    } catch (_) {
      if (!mounted) return;
      setState(() => _isAdmin = false);
    }
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final categoriesResponse = await _supabase
          .from('categories')
          .select('id, name, icon')
          .eq('is_active', true)
          .order('sort_order');

      var listingsQuery = _supabase
          .from('listings')
          .select(
            'id, title, description, price, currency, price_type, '
            'area, category_id, status, created_at',
          )
          .eq('status', 'approved');

      if (_selectedCategoryId != null) {
        listingsQuery =
            listingsQuery.eq('category_id', _selectedCategoryId!);
      }

      final listingsResponse = await listingsQuery.order(
        'created_at',
        ascending: false,
      );

      final listings =
          List<Map<String, dynamic>>.from(listingsResponse);

      // جلب صور الإعلانات وربط أول صورة بكل إعلان.
      if (listings.isNotEmpty) {
        final listingIds = listings
            .map((listing) => listing['id'])
            .where((id) => id != null)
            .toList();

        if (listingIds.isNotEmpty) {
          final imagesResponse = await _supabase
              .from('listing_images')
              .select('listing_id, image_path, sort_order')
              .inFilter('listing_id', listingIds)
              .order('sort_order');

          final images =
              List<Map<String, dynamic>>.from(imagesResponse);

          for (final listing in listings) {
            for (final image in images) {
              if (image['listing_id'] == listing['id']) {
                listing['image_path'] = image['image_path'];
                break;
              }
            }
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _categories =
            List<Map<String, dynamic>>.from(categoriesResponse);
        _listings = listings;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error =
            'تعذر تحميل البيانات. تحقق من اتصال الإنترنت وحاول مجدداً.';
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();

      if (!mounted) return;

      setState(() => _isAdmin = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل الخروج بنجاح')),
      );

      await _loadData();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تسجيل الخروج، حاول مرة أخرى'),
        ),
      );
    }
  }

  Future<bool> _ensureSignedIn() async {
    if (_supabase.auth.currentUser != null) return true;

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );

    if (!mounted) return false;

    if (result == true && _supabase.auth.currentUser != null) {
      await _checkAdminStatus();
      return true;
    }

    return false;
  }

  Future<void> _openProfile() async {
    if (!await _ensureSignedIn()) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );

    if (!mounted) return;

    setState(() {});
    await _checkAdminStatus();
  }

  Future<void> _openAddListing() async {
    if (!await _ensureSignedIn()) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddListingScreen()),
    );

    if (!mounted) return;

    await _loadData();
  }

  Future<void> _openMyListings() async {
    if (!await _ensureSignedIn()) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyListingsScreen()),
    );

    if (!mounted) return;

    await _loadData();
  }

  Future<void> _openFavorites() async {
    if (!await _ensureSignedIn()) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FavoritesScreen()),
    );

    if (!mounted) return;

    setState(() {});
  }

  Future<void> _openAdminPanel() async {
    if (!await _ensureSignedIn()) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminListingsScreen()),
    );

    if (!mounted) return;

    await _checkAdminStatus();
    await _loadData();
  }

  void _openListingDetails(Map<String, dynamic> listing) {
    final listingId = listing['id'];

    if (listingId is! int) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListingDetailsScreen(listingId: listingId),
      ),
    );
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

  String _formatPrice(Map<String, dynamic> listing) {
    final price = listing['price'];
    final currency = listing['currency'] ?? 'SDG';
    final priceType = listing['price_type'];

    if (priceType == 'contact' || price == null) {
      return 'السعر عند التواصل';
    }

    final priceText = price.toString();

    if (priceType == 'negotiable') {
      return '$priceText $currency قابل للتفاوض';
    }

    return '$priceText $currency';
  }

  String? _imageUrl(dynamic imagePath) {
    if (imagePath == null) return null;

    final path = imagePath.toString().trim();

    if (path.isEmpty) return null;

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    return _supabase.storage.from('listing-images').getPublicUrl(path);
  }

  Widget _buildListingImage(
    Map<String, dynamic> listing, {
    double height = 105,
  }) {
    final imageUrl = _imageUrl(listing['image_path']);

    Widget noImage() {
      return Container(
        height: height,
        width: double.infinity,
        color: Colors.grey.shade100,
        child: const Center(
          child: Icon(
            Icons.photo_library_outlined,
            size: 32,
            color: Colors.grey,
          ),
        ),
      );
    }

    if (imageUrl == null) return noImage();

    return Image.network(
      imageUrl,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => noImage(),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;

        return Container(
          height: height,
          width: double.infinity,
          color: Colors.grey.shade100,
          child: const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      },
    );
  }

  Widget _buildAvailableBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: Colors.white, size: 12),
          SizedBox(width: 3),
          Text(
            'متاح',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListingCard(Map<String, dynamic> listing) {
    final rawTitle = listing['title']?.toString().trim() ?? '';
    final title = rawTitle.isEmpty ? 'إعلان بدون عنوان' : rawTitle;
    final area = listing['area']?.toString().trim() ?? '';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
      ),
      child: InkWell(
        onTap: () => _openListingDetails(listing),
        child: SizedBox(
          width: 158,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  _buildListingImage(listing, height: 105),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _buildAvailableBadge(),
                  ),
                ],
              ),
              Padding(
                // تقليل الهامش السفلي داخل بطاقة الإعلان.
                padding: const EdgeInsets.fromLTRB(8, 7, 8, 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _formatPrice(listing),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    if (area.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 13,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              area,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 5),
                    SizedBox(
                      width: double.infinity,
                      height: 28,
                      child: OutlinedButton(
                        onPressed: () => _openListingDetails(listing),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(0, 28),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'عرض الإعلان',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(
    String title, {
    Widget? trailing,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 19,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildHorizontalListings(
    List<Map<String, dynamic>> listings,
  ) {
    return SizedBox(
      height: 260,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: listings.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          return _buildListingCard(listings[index]);
        },
      ),
    );
  }

  Widget _buildCategories() {
    if (_categories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: Text('لا توجد أقسام متاحة حالياً')),
      );
    }

    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final categoryId = category['id'] as int?;
          final categoryName =
              category['name']?.toString() ?? 'بدون اسم';
          final selected = _selectedCategoryId == categoryId;

          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (categoryId == null) return;

              setState(() {
                _selectedCategoryId = selected ? null : categoryId;
              });

              _loadData();
            },
            child: Container(
              width: 76,
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_categoryIcon(categoryName), size: 22),
                  const SizedBox(height: 3),
                  Text(
                    categoryName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 43,
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'ابحث عن إعلان أو منطقة...',
          hintStyle: const TextStyle(fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 21),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                  icon: const Icon(Icons.clear, size: 19),
                  tooltip: 'مسح البحث',
                )
              : null,
          filled: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(11),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = _filteredListings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'نتائج البحث',
          trailing: Text(
            '${results.length} إعلان',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        if (results.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 35),
            child: Column(
              children: [
                Icon(Icons.search_off_outlined, size: 45),
                SizedBox(height: 9),
                Text('لم نجد إعلانات تطابق بحثك'),
              ],
            ),
          )
        else
          ...results.map(
            (listing) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _buildListingCard(listing),
            ),
          ),
      ],
    );
  }

  Widget _buildHomeSections() {
    if (_listings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined, size: 45),
            SizedBox(height: 10),
            Text('لا توجد إعلانات متاحة حالياً'),
          ],
        ),
      );
    }

    // لا يوجد حالياً حقل مؤكد يحدد الإعلانات المميزة في قاعدة البيانات.
    // لذلك تعرض هذه المساحة مجموعة من أحدث الإعلانات مؤقتاً.
    final featuredPreview = _listings.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          'إعلانات مميزة أو تجارية',
          icon: Icons.local_offer_outlined,
        ),
        _buildHorizontalListings(featuredPreview),
        const SizedBox(height: 18),
        _sectionTitle(
          'أحدث الإعلانات',
          icon: Icons.access_time,
        ),
        _buildHorizontalListings(_listings),
        const SizedBox(height: 20),
        _sectionTitle(
          'معروضات الأقسام',
          icon: Icons.grid_view_rounded,
        ),
        ..._categories.map((category) {
          final categoryId = category['id'] as int?;
          final categoryName =
              category['name']?.toString() ?? 'بدون اسم';

          if (categoryId == null) return const SizedBox.shrink();

          final categoryListings = _listings
              .where((listing) => listing['category_id'] == categoryId)
              .take(8)
              .toList();

          if (categoryListings.isEmpty) {
            return const SizedBox.shrink();
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle(
                  categoryName,
                  icon: _categoryIcon(categoryName),
                  trailing: TextButton(
                    onPressed: () {
                      setState(() => _selectedCategoryId = categoryId);
                      _loadData();
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text(
                      'عرض الكل',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ),
                _buildHorizontalListings(categoryListings),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 42),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _loadData,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final searching =
        _searchQuery.trim().isNotEmpty || _selectedCategoryId != null;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(13, 8, 13, 18),
        children: [
          _buildSearchField(),
          const SizedBox(height: 12),
          _sectionTitle(
            'الأقسام',
            trailing: TextButton(
              onPressed: () {
                setState(() {
                  _selectedCategoryId = null;
                  _searchQuery = '';
                  _searchController.clear();
                });
                _loadData();
              },
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 7),
              ),
              child: const Text(
                'عرض الكل',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          _buildCategories(),
          const SizedBox(height: 15),
          if (searching) _buildSearchResults() else _buildHomeSections(),
        ],
      ),
    );
  }

  Widget _buildPostListingButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: FilledButton(
        onPressed: _openAddListing,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 9),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ضع إعلانك',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: 3),
            Icon(Icons.add, size: 17),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileButton() {
    final user = _supabase.auth.currentUser;

    return IconButton(
      tooltip: user == null ? 'تسجيل الدخول' : 'الملف الشخصي',
      onPressed: _openProfile,
      icon: CircleAvatar(
        radius: 15,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          user == null ? Icons.person_outline : Icons.person,
          size: 19,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    final primary = Theme.of(context).colorScheme.primary;

    Widget navItem({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool selected = false,
    }) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: selected ? primary : Colors.grey.shade600,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? primary : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Colors.grey.shade300, width: 0.6),
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            navItem(
              icon: Icons.home_outlined,
              label: 'الرئيسية',
              selected: true,
              onTap: () {
                setState(() {
                  _selectedCategoryId = null;
                  _searchQuery = '';
                  _searchController.clear();
                });
                _loadData();
              },
            ),
            navItem(
              icon: Icons.inventory_2_outlined,
              label: 'إعلاناتي',
              onTap: _openMyListings,
            ),

            // زر إضافة إعلان مميز بلون التطبيق.
            Expanded(
              child: InkWell(
                onTap: _openAddListing,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 43,
                        height: 34,
                        decoration: BoxDecoration(
                          color: primary,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'أضف إعلان',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            navItem(
              icon: Icons.favorite_border,
              label: 'المفضلة',
              onTap: _openFavorites,
            ),
            navItem(
              icon: Icons.person_outline,
              label: 'الملف الشخصي',
              onTap: _openProfile,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final name = user?.userMetadata?['full_name'] as String?;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                UserAccountsDrawerHeader(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  accountName: Text(
                    name == null || name.isEmpty
                        ? 'مرحباً بك في دلالة شبشة'
                        : name,
                  ),
                  accountEmail: user == null ? null : Text(user.email ?? ''),
                  currentAccountPicture: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.onPrimary,
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 31,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    user == null ? 'تسجيل الدخول' : 'الملف الشخصي',
                  ),
                  onTap: () async {
                    Navigator.pop(context);
                    await _openProfile();
                  },
                ),
                if (_isAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.admin_panel_settings_outlined,
                    ),
                    title: const Text('لوحة تحكم الإدارة'),
                    subtitle: const Text('إدارة ومراجعة الإعلانات'),
                    onTap: () async {
                      Navigator.pop(context);
                      await _openAdminPanel();
                    },
                  ),
                const Divider(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Text(
                    'الأقسام',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_categories.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('لا توجد أقسام حالياً'),
                  )
                else
                  ..._categories.map((category) {
                    final categoryId = category['id'] as int?;
                    final categoryName =
                        category['name']?.toString() ?? 'بدون اسم';

                    return ListTile(
                      dense: true,
                      leading: Icon(_categoryIcon(categoryName)),
                      title: Text(categoryName),
                      selected: _selectedCategoryId == categoryId,
                      onTap: () {
                        Navigator.pop(context);

                        if (categoryId == null) return;

                        setState(() {
                          _selectedCategoryId = categoryId;
                          _searchQuery = '';
                          _searchController.clear();
                        });

                        _loadData();
                      },
                    );
                  }),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.favorite_border),
                  title: const Text('المفضلة'),
                  onTap: () {
                    Navigator.pop(context);
                    _openFavorites();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('إعلاناتي'),
                  onTap: () {
                    Navigator.pop(context);
                    _openMyListings();
                  },
                ),
                if (user != null)
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('تسجيل الخروج'),
                    onTap: () {
                      Navigator.pop(context);
                      _signOut();
                    },
                  ),
              ],
            ),
          ),
        ),

        // الشريط العلوي: زر القائمة ثم اسم التطبيق، وبعدهما الأزرار.
        appBar: AppBar(
          centerTitle: false,
          elevation: 0,
          title: Text(
            'دلالة شبشة',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: () {
                _loadData();
                _checkAdminStatus();
              },
              icon: const Icon(Icons.refresh),
            ),
            _buildPostListingButton(),
            _buildProfileButton(),
          ],
        ),

        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 4, 13, 8),
              child: Column(
                children: [
                  Text(
                    'في مكان واحد - تسوق واعلن بسهولة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (user != null &&
                      name != null &&
                      name.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'مرحباً يا $name 👋',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),

        // شريط تنقل سفلي ثابت أثناء تمرير محتوى الصفحة.
        bottomNavigationBar: _buildBottomNavigation(),
      ),
    );
  }
}