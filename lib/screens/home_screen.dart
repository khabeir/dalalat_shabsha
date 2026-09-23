import 'dart:async';

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
  List<Map<String, dynamic>> _promotedListings = [];

  bool _loading = true;
  bool _isAdmin = false;
  String? _error;
  String _searchQuery = '';
  int? _selectedCategoryId;

  Timer? _promotedRefreshTimer;

  @override
void initState() {
  super.initState();

  _loadData();
  _checkAdminStatus();

  // تحديث حالة الإعلانات التجارية كل دقيقة.
  _promotedRefreshTimer = Timer.periodic(
    const Duration(minutes: 1),
    (_) => _loadPromotedListings(),
  );
}

  @override
void dispose() {
  _promotedRefreshTimer?.cancel();
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
      final area =
          _normalizeSearchText(listing['area']?.toString() ?? '');

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
  
  Future<void> _loadPromotedListings() async {
  try {
    final now = DateTime.now().toUtc().toIso8601String();

    final promotedResponse = await _supabase
        .from('promoted_listings')
        .select(
          'id, listing_id, start_at, end_at, is_active, created_by',
        )
        .eq('is_active', true)
        .lte('start_at', now)
        .gt('end_at', now)
        .order('start_at', ascending: false);

    final promotedRows =
        List<Map<String, dynamic>>.from(
      promotedResponse,
    );

    if (promotedRows.isEmpty) {
      if (!mounted) return;

      setState(() {
        _promotedListings = [];
      });

      return;
    }

    final listingIds = promotedRows
        .map((item) => item['listing_id'])
        .where((id) => id != null)
        .toList();

    if (listingIds.isEmpty) {
      if (!mounted) return;

      setState(() {
        _promotedListings = [];
      });

      return;
    }

    // لا نعرض الإعلان التجاري إلا إذا كان الإعلان نفسه approved.
    final listingsResponse = await _supabase
        .from('listings')
        .select(
          'id, title, description, price, currency, price_type, '
          'area, category_id, status, created_at',
        )
        .inFilter('id', listingIds)
        .eq('status', 'approved');

    final approvedListings =
        List<Map<String, dynamic>>.from(
      listingsResponse,
    );

    final listingsById = <dynamic, Map<String, dynamic>>{};

    for (final listing in approvedListings) {
      listingsById[listing['id']] = listing;
    }

    final result = <Map<String, dynamic>>[];

    // نحافظ على ترتيب start_at القادم من promoted_listings.
    for (final promoted in promotedRows) {
      final listingId = promoted['listing_id'];

      final listing = listingsById[listingId];

      if (listing == null) continue;

      final item = Map<String, dynamic>.from(
        listing,
      );

      item['promoted_listing_id'] =
          promoted['id'];

      item['promotion_start_at'] =
          promoted['start_at'];

      item['promotion_end_at'] =
          promoted['end_at'];

      item['promotion_is_active'] =
          promoted['is_active'];

      item['is_commercial'] = true;

      result.add(item);
    }

    // جلب أول صورة لكل إعلان تجاري.
    if (result.isNotEmpty) {
      final resultIds = result
          .map((listing) => listing['id'])
          .where((id) => id != null)
          .toList();

      if (resultIds.isNotEmpty) {
        final imagesResponse = await _supabase
            .from('listing_images')
            .select(
              'listing_id, image_path, sort_order',
            )
            .inFilter(
              'listing_id',
              resultIds,
            )
            .order('sort_order');

        final images =
            List<Map<String, dynamic>>.from(
          imagesResponse,
        );

        for (final listing in result) {
          for (final image in images) {
            if (image['listing_id'] ==
                listing['id']) {
              listing['image_path'] =
                  image['image_path'];
              break;
            }
          }
        }
      }
    }

    if (!mounted) return;

    setState(() {
      _promotedListings = result;
    });
  } catch (_) {
    // لا نوقف الصفحة الرئيسية إذا فشل تحميل
    // الإعلانات التجارية.
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

// تحميل الإعلانات التجارية بشكل مستقل.
await _loadPromotedListings();
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
        const SnackBar(
          content: Text('تم تسجيل الخروج بنجاح'),
        ),
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
      MaterialPageRoute(
        builder: (_) => const AuthScreen(),
      ),
    );

    if (!mounted) return false;

    if (result == true &&
        _supabase.auth.currentUser != null) {
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
      MaterialPageRoute(
        builder: (_) => const ProfileScreen(),
      ),
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
      MaterialPageRoute(
        builder: (_) => const AddListingScreen(),
      ),
    );

    if (!mounted) return;

    await _loadData();
  }

  Future<void> _openMyListings() async {
    if (!await _ensureSignedIn()) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MyListingsScreen(),
      ),
    );

    if (!mounted) return;

    await _loadData();
  }

  Future<void> _openFavorites() async {
    if (!await _ensureSignedIn()) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FavoritesScreen(),
      ),
    );

    if (!mounted) return;

    setState(() {});
  }

  Future<void> _openAdminPanel() async {
    if (!await _ensureSignedIn()) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AdminListingsScreen(),
      ),
    );

    if (!mounted) return;

    await _checkAdminStatus();
    await _loadData();
  }

  void _openListingDetails(
    Map<String, dynamic> listing,
  ) {
    final listingId = listing['id'];

    if (listingId is! int) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListingDetailsScreen(
          listingId: listingId,
        ),
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

  final currency =
      listing['currency']?.toString().trim().isNotEmpty == true
          ? listing['currency'].toString().trim()
          : 'SDG';

  final priceType =
      listing['price_type']?.toString().trim() ?? '';

  if (priceType == 'contact' || price == null) {
    return 'السعر عند التواصل';
  }

  final number = num.tryParse(price.toString());

  if (number == null) {
    return '$price $currency';
  }

  // تحويل السعر إلى نص، مع الاحتفاظ بالكسور عند وجودها.
  String raw = number.toString();

  // حذف .0 من الأرقام الصحيحة مثل 10000.0
  if (number == number.truncateToDouble()) {
    raw = number.toInt().toString();
  }

  final parts = raw.split('.');
  final integerPart = parts[0];
  final decimalPart = parts.length > 1 ? parts[1] : '';

  // إضافة فواصل الآلاف من اليمين إلى اليسار.
  final buffer = StringBuffer();

  for (int i = 0; i < integerPart.length; i++) {
    buffer.write(integerPart[i]);

    final remaining = integerPart.length - i - 1;

    if (remaining > 0 && remaining % 3 == 0) {
      buffer.write(',');
    }
  }

  String formatted = buffer.toString();

  // إضافة الجزء العشري إذا كان موجوداً وغير صفري.
  if (decimalPart.isNotEmpty &&
      int.tryParse(decimalPart) != 0) {
    formatted = '$formatted.$decimalPart';
  }

  return '$formatted $currency';
}

  String? _imageUrl(dynamic imagePath) {
    if (imagePath == null) return null;

    final path = imagePath.toString().trim();

    if (path.isEmpty) return null;

    if (path.startsWith('http://') ||
        path.startsWith('https://')) {
      return path;
    }

    return _supabase.storage
        .from('listing-images')
        .getPublicUrl(path);
  }

  Widget _buildListingImage(
    Map<String, dynamic> listing, {
    double height = 105,
  }) {
    final imageUrl = _imageUrl(
      listing['image_path'],
    );

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
      loadingBuilder: (
        context,
        child,
        progress,
      ) {
        if (progress == null) return child;

        return Container(
          height: height,
          width: double.infinity,
          color: Colors.grey.shade100,
          child: const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
            ),
          ),
        );
      },
    );
  }

  Widget _buildAvailableBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle,
            color: Colors.white,
            size: 12,
          ),
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

  // التعديل الأول:
  // تحسين شكل بطاقة الإعلان فقط.
  // لم يتم تغيير طريقة تحميل الصور أو روابط Supabase.
Widget _buildListingCard(
  Map<String, dynamic> listing, {
  bool isCommercial = false,
  double width = 158,
}) {
  final rawTitle =
      listing['title']?.toString().trim() ?? '';

  final title = rawTitle.isEmpty
      ? 'إعلان بدون عنوان'
      : rawTitle;

  final area =
      listing['area']?.toString().trim() ?? '';

  final priceText = _formatPrice(listing);

  final isNegotiable =
      listing['price_type'] == 'negotiable';

  final categoryId =
      listing['category_id'] as int?;

  String categoryName = '';

  if (categoryId != null) {
    for (final category in _categories) {
      if (category['id'] == categoryId) {
        categoryName =
            category['name']?.toString().trim() ?? '';
        break;
      }
    }
  }

  final createdAt =
      listing['created_at']?.toString();

  String dateText = '';

  if (createdAt != null &&
      createdAt.trim().isNotEmpty) {
    final date = DateTime.tryParse(createdAt);

    if (date != null) {
      final localDate = date.toLocal();

      final day =
          localDate.day.toString().padLeft(2, '0');

      final month =
          localDate.month.toString().padLeft(2, '0');

      dateText = '$day/$month/${localDate.year}';
    }
  }

  return Card(
    margin: EdgeInsets.zero,
    elevation: 2,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: Theme.of(context)
            .colorScheme
            .outlineVariant
            .withValues(alpha: 0.35),
      ),
    ),
    child: InkWell(
      onTap: () => _openListingDetails(listing),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            // =========================
            // صورة الإعلان
            // =========================
            Stack(
              children: [
                _buildListingImage(
                  listing,
                  height: 112,
                ),

                // متاح
                Positioned(
                  top: 7,
                  right: 7,
                  child: _buildAvailableBadge(),
                ),

                // إعلان تجاري
                if (isCommercial)
                  Positioned(
                    top: 7,
                    left: 7,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary,
                        borderRadius:
                            BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_offer,
                            color: Colors.white,
                            size: 11,
                          ),
                          SizedBox(width: 3),
                          Text(
                            'إعلان تجاري',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            // =========================
            // معلومات الإعلان
            // =========================
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  9,
                  7,
                  9,
                  6,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    // العنوان
                    Text(
                      title,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            FontWeight.w800,
                        height: 1.18,
                      ),
                    ),

                    const SizedBox(height: 5),

                    // السعر
                    Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(8),
                      ),
                      child: Text(
                        priceText,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              FontWeight.w900,
                          height: 1.1,
                          color: Theme.of(context)
                              .colorScheme
                              .primary,
                        ),
                      ),
                    ),

                    // قابل للتفاوض
                    if (isNegotiable)
                      Padding(
                        padding:
                            const EdgeInsets.only(
                          top: 2,
                        ),
                        child: Text(
                          'قابل للتفاوض',
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight:
                                FontWeight.w600,
                            color:
                                Colors.grey.shade600,
                          ),
                        ),
                      ),

                    const SizedBox(height: 3),

                    // المنطقة
                    if (area.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color:
                                Colors.grey.shade600,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              area,
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color:
                                    Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),

                    // القسم
                    if (categoryName.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(
                          top: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _categoryIcon(
                                categoryName,
                              ),
                              size: 12,
                              color:
                                  Colors.grey.shade600,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                categoryName,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  color:
                                      Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // التاريخ
                    if (dateText.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(
                          top: 2,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons
                                  .calendar_today_outlined,
                              size: 11,
                              color:
                                  Colors.grey.shade500,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              dateText,
                              style: TextStyle(
                                fontSize: 9.5,
                                color:
                                    Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),

                    const Spacer(),

                    // زر عرض الإعلان
                    SizedBox(
                      width: double.infinity,
                      height: 29,
                      child: OutlinedButton(
                        onPressed: () =>
                            _openListingDetails(
                          listing,
                        ),
                        style:
                            OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity:
                              VisualDensity.compact,
                          minimumSize:
                              const Size(0, 29),
                          tapTargetSize:
                              MaterialTapTargetSize
                                  .shrinkWrap,
                          side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(
                                  alpha: 0.65,
                                ),
                          ),
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                              8,
                            ),
                          ),
                        ),
                        child: Text(
                          'عرض الإعلان',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                FontWeight.w700,
                            color: Theme.of(context)
                                .colorScheme
                                .primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  8,
                  7,
                  8,
                  3,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    // اسم الإعلان
                    Text(
                      title,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        height: 1.18,
                      ),
                    ),

                    const SizedBox(height: 3),

                    // السعر
                    Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(7),
                      ),
                      child: Text(
                        priceText,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              FontWeight.w800,
                          height: 1.1,
                          color: Theme.of(context)
                              .colorScheme
                              .primary,
                        ),
                      ),
                    ),

                    if (isNegotiable)
                      Padding(
                        padding:
                            const EdgeInsets.only(
                          top: 2,
                        ),
                        child: Text(
                          'قابل للتفاوض',
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight:
                                FontWeight.w600,
                            color:
                                Colors.grey.shade600,
                          ),
                        ),
                      ),

                    // المنطقة
                    if (area.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color:
                                Colors.grey.shade600,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              area,
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],

                    const Spacer(),

                    // زر عرض الإعلان
                    SizedBox(
                      width: double.infinity,
                      height: 28,
                      child: OutlinedButton(
                        onPressed: () =>
                            _openListingDetails(
                          listing,
                        ),
                        style:
                            OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          visualDensity:
                              VisualDensity.compact,
                          minimumSize:
                              const Size(0, 28),
                          tapTargetSize:
                              MaterialTapTargetSize
                                  .shrinkWrap,
                          side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .primary
                                .withValues(
                                  alpha: 0.65,
                                ),
                          ),
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                              8,
                            ),
                          ),
                        ),
                        child: Text(
                          'عرض الإعلان',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                FontWeight.w600,
                            color: Theme.of(context)
                                .colorScheme
                                .primary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
      padding: const EdgeInsets.only(
        bottom: 9,
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 19,
              color: Theme.of(context)
                  .colorScheme
                  .primary,
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
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: listings.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: 9),
        itemBuilder: (context, index) {
          return _buildListingCard(
            listings[index],
          );
        },
      ),
    );
  }

  Widget _buildCategories() {
    if (_categories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          vertical: 12,
        ),
        child: Center(
          child: Text(
            'لا توجد أقسام متاحة حالياً',
          ),
        ),
      );
    }

    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final category = _categories[index];

          final categoryId =
              category['id'] as int?;

          final categoryName =
              category['name']?.toString() ??
                  'بدون اسم';

          final selected =
              _selectedCategoryId == categoryId;

          return InkWell(
            borderRadius:
                BorderRadius.circular(10),
            onTap: () {
              if (categoryId == null) return;

              setState(() {
                _selectedCategoryId =
                    selected ? null : categoryId;
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
                    ? Theme.of(context)
                        .colorScheme
                        .primaryContainer
                    : Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
                borderRadius:
                    BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                      : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: [
                  Icon(
                    _categoryIcon(
                      categoryName,
                    ),
                    size: 22,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    categoryName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
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
        textInputAction:
            TextInputAction.search,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText:
              'ابحث عن إعلان أو منطقة...',
          hintStyle: const TextStyle(
            fontSize: 13,
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 21,
          ),
          suffixIcon:
              _searchQuery.isNotEmpty
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(
                        Icons.clear,
                        size: 19,
                      ),
                      tooltip: 'مسح البحث',
                    )
                  : null,
          filled: true,
          contentPadding:
              const EdgeInsets.symmetric(
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(11),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = _filteredListings;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
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
            padding: EdgeInsets.symmetric(
              vertical: 35,
            ),
            child: Column(
              children: [
                Icon(
                  Icons.search_off_outlined,
                  size: 45,
                ),
                SizedBox(height: 9),
                Text(
                  'لم نجد إعلانات تطابق بحثك',
                ),
              ],
            ),
          )
        else
          ...results.map(
            (listing) => Padding(
              padding: const EdgeInsets.only(
                bottom: 10,
              ),
              child: SizedBox(
  height: 255,
  child: _buildListingCard(
    listing,
    width: double.infinity,
  ),
),
            ),
          ),
      ],
    );
  }

  Widget _buildHomeSections() {
    if (_listings.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(
          vertical: 32,
        ),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 45,
            ),
            SizedBox(height: 10),
            Text(
              'لا توجد إعلانات متاحة حالياً',
            ),
          ],
        ),
      );
    }

    // فصل الإعلانات التجارية عن الإعلانات العادية.
    final promotedIds = _promotedListings
    .map((listing) => listing['id'])
    .toSet();

final latestListings = _listings
    .where(
      (listing) =>
          !promotedIds.contains(listing['id']),
    )
    .take(10)
    .toList();

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        if (_promotedListings.isNotEmpty) ...[
  _sectionTitle(
    'إعلانات تجارية',
    icon: Icons.local_offer_outlined,
  ),

  SizedBox(
    height: 230,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: _promotedListings.length,
      separatorBuilder: (_, __) =>
          const SizedBox(width: 9),
      itemBuilder: (context, index) {
        return _buildListingCard(
          _promotedListings[index],
          isCommercial: true,
        );
      },
    ),
  ),

  const SizedBox(height: 18),
],

        const SizedBox(height: 18),

        _sectionTitle(
          'أحدث الإعلانات',
          icon: Icons.access_time,
        ),

        _buildHorizontalListings(
  latestListings,
),

        const SizedBox(height: 20),

        _sectionTitle(
          'معروضات الأقسام',
          icon: Icons.grid_view_rounded,
        ),

        ..._categories.map((category) {
          final categoryId =
              category['id'] as int?;

          final categoryName =
              category['name']?.toString() ??
                  'بدون اسم';

          if (categoryId == null) {
            return const SizedBox.shrink();
          }

          final categoryListings =
              _listings
                  .where(
                    (listing) =>
                        listing['category_id'] ==
                        categoryId,
                  )
                  .take(8)
                  .toList();

          if (categoryListings.isEmpty) {
            return const SizedBox.shrink();
          }

          return Padding(
            padding: const EdgeInsets.only(
              bottom: 18,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                _sectionTitle(
                  categoryName,
                  icon: _categoryIcon(
                    categoryName,
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedCategoryId =
                            categoryId;
                      });

                      _loadData();
                    },
                    style: TextButton.styleFrom(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 7,
                      ),
                      visualDensity:
                          VisualDensity.compact,
                    ),
                    child: const Text(
                      'عرض الكل',
                      style: TextStyle(
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),

                _buildHorizontalListings(
                  categoryListings,
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              const Icon(
                Icons.wifi_off,
                size: 42,
              ),
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _loadData,
                child: const Text(
                  'إعادة المحاولة',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final searching =
        _searchQuery.trim().isNotEmpty ||
            _selectedCategoryId != null;

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          13,
          8,
          13,
          18,
        ),
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
                visualDensity:
                    VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 7,
                ),
              ),
              child: const Text(
                'عرض الكل',
                style: TextStyle(
                  fontSize: 12,
                ),
              ),
            ),
          ),

          _buildCategories(),

          const SizedBox(height: 15),

          if (searching)
            _buildSearchResults()
          else
            _buildHomeSections(),
        ],
      ),
    );
  }

  Widget _buildPostListingButton() {
    return Padding(
      padding:
          const EdgeInsets.symmetric(vertical: 7),
      child: FilledButton(
        onPressed: _openAddListing,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding:
              const EdgeInsets.symmetric(
            horizontal: 9,
          ),
          visualDensity:
              VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(9),
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
            Icon(
              Icons.add,
              size: 17,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileButton() {
    final user =
        _supabase.auth.currentUser;

    return IconButton(
      tooltip: user == null
          ? 'تسجيل الدخول'
          : 'الملف الشخصي',
      onPressed: _openProfile,
      icon: CircleAvatar(
        radius: 15,
        backgroundColor:
            Theme.of(context)
                .colorScheme
                .primaryContainer,
        child: Icon(
          user == null
              ? Icons.person_outline
              : Icons.person,
          size: 19,
          color:
              Theme.of(context)
                  .colorScheme
                  .onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    final primary =
        Theme.of(context)
            .colorScheme
            .primary;

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
            padding:
                const EdgeInsets.symmetric(
              vertical: 7,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: selected
                      ? primary
                      : Colors.grey.shade600,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: selected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: selected
                        ? primary
                        : Colors.grey.shade700,
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
          color: Theme.of(context)
              .colorScheme
              .surface,
          border: Border(
            top: BorderSide(
              color: Colors.grey.shade300,
              width: 0.6,
            ),
          ),
        ),
        child: Row(
          textDirection:
              TextDirection.rtl,
          children: [
            navItem(
              icon: Icons.home_outlined,
              label: 'الرئيسية',
              selected: true,
              onTap: () {
                setState(() {
                  _selectedCategoryId =
                      null;
                  _searchQuery = '';
                  _searchController.clear();
                });

                _loadData();
              },
            ),

            navItem(
              icon:
                  Icons.inventory_2_outlined,
              label: 'إعلاناتي',
              onTap: _openMyListings,
            ),

            // زر إضافة إعلان مميز بلون التطبيق.
            Expanded(
              child: InkWell(
                onTap: _openAddListing,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Container(
                        width: 43,
                        height: 34,
                        decoration:
                            BoxDecoration(
                          color: primary,
                          borderRadius:
                              BorderRadius.circular(
                            11,
                          ),
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
                        overflow:
                            TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              FontWeight.bold,
                          color: primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            navItem(
              icon:
                  Icons.favorite_border,
              label: 'المفضلة',
              onTap: _openFavorites,
            ),

            navItem(
              icon:
                  Icons.person_outline,
              label: 'الملف الشخصي',
              onTap: _openProfile,
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // رأس القائمة
  // =========================
  Widget _buildDrawerHeader(
    User? user,
    String? name,
  ) {
    final primary =
        Theme.of(context).colorScheme.primary;

    final displayName =
        name != null && name.trim().isNotEmpty
            ? name.trim()
            : user == null
                ? 'مرحباً بك'
                : 'مستخدم دلالة شبشة';

    // رقم الهاتف الحقيقي لحسابات الهاتف.
    final authPhone =
        user?.phone?.trim() ?? '';

    // البريد الإلكتروني لحسابات البريد.
    final email =
        user?.email?.trim() ?? '';

    // رقم الهاتف الذي حفظناه في metadata
    // عند إنشاء الحساب، كخيار احتياطي.
    final metadataPhone =
        user?.userMetadata?['phone']
                ?.toString()
                .trim() ??
            '';

    // إذا كان الحساب مرتبطاً برقم هاتف،
    // نعرض الهاتف أولاً ولا نعرض البريد التلقائي.
    final phone = authPhone.isNotEmpty
        ? authPhone
        : metadataPhone;

    final contact = phone.isNotEmpty
        ? phone
        : email.isNotEmpty
            ? email
            : user == null
                ? 'تصفح الإعلانات بسهولة'
                : 'حسابك في دلالة شبشة';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        14,
      ),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(18),
        ),
      ),
      child: Row(
        children: [
          // صورة الحساب
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.circular(15),
            ),
            child: Icon(
              user == null
                  ? Icons.person_outline
                  : Icons.storefront_rounded,
              size: 28,
              color: primary,
            ),
          ),

          const SizedBox(width: 12),

          // الاسم + الهاتف أو البريد
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  contact,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white
                        .withValues(alpha: 0.82),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // عنوان مجموعة
  // =========================
  Widget _buildDrawerSectionTitle(
    String title,
    IconData icon,
  ) {
    final primary =
        Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        9,
        5,
        9,
        4,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: primary,
          ),
          const SizedBox(width: 7),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: primary,
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // عنصر القائمة
  // =========================
  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    bool selected = false,
    bool isDestructive = false,
  }) {
    final colorScheme =
        Theme.of(context).colorScheme;

    final itemColor = isDestructive
        ? Colors.red.shade700
        : selected
            ? colorScheme.primary
            : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 2,
      ),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer
                .withValues(alpha: 0.65)
            : Colors.transparent,
        borderRadius:
            BorderRadius.circular(11),
        child: InkWell(
          borderRadius:
              BorderRadius.circular(11),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primary
                            .withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(9),
                  ),
                  child: Icon(
                    icon,
                    size: 21,
                    color: itemColor,
                  ),
                ),

                const SizedBox(width: 9),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight:
                              FontWeight.w700,
                          color: itemColor,
                        ),
                      ),

                      if (subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors
                                .grey
                                .shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                if (selected)
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 19,
                    color: colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

    @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;

    final name =
        user?.userMetadata?['full_name'] as String?;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // =========================
        // القائمة الجانبية
        // =========================
        drawer: Drawer(
          width: 220,
          elevation: 3,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // =========================
                // رأس القائمة / الحساب
                // =========================
                _buildDrawerHeader(user, name),

                const SizedBox(height: 5),

                // =========================
                // محتوى القائمة
                // =========================
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 2,
                    ),
                    children: [
                      // الملف الشخصي / تسجيل الدخول
                      _buildDrawerItem(
                        icon: user == null
                            ? Icons.login_outlined
                            : Icons.person_outline,
                        title: user == null
                            ? 'تسجيل الدخول'
                            : 'الملف الشخصي',
                        onTap: () async {
                          Navigator.pop(context);
                          await _openProfile();
                        },
                      ),

                      // إضافة إعلان
                      _buildDrawerItem(
                        icon: Icons.add_circle_outline,
                        title: 'إضافة إعلان',
                        onTap: () async {
                          Navigator.pop(context);
                          await _openAddListing();
                        },
                      ),

                      const SizedBox(height: 5),

                      // =========================
                      // الإدارة
                      // =========================
                      if (_isAdmin) ...[
                        _buildDrawerItem(
                          icon:
                              Icons.admin_panel_settings_outlined,
                          title: 'لوحة تحكم الإدارة',
                          subtitle:
                              'إدارة ومراجعة الإعلانات',
                          onTap: () async {
                            Navigator.pop(context);
                            await _openAdminPanel();
                          },
                        ),

                        const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Divider(height: 1),
                        ),
                      ],

                      // =========================
                      // الأقسام
                      // =========================
                      _buildDrawerSectionTitle(
                        'الأقسام',
                        Icons.grid_view_rounded,
                      ),

                      if (_categories.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                            'لا توجد أقسام حالياً',
                            style: TextStyle(
                              fontSize: 13,
                            ),
                          ),
                        )
                      else
                        ..._categories.map(
                          (category) {
                            final categoryId =
                                category['id'] as int?;

                            final categoryName =
                                category['name']?.toString() ??
                                    'بدون اسم';

                            final selected =
                                _selectedCategoryId ==
                                    categoryId;

                            return _buildDrawerItem(
                              icon: _categoryIcon(
                                categoryName,
                              ),
                              title: categoryName,
                              selected: selected,
                              onTap: () {
                                Navigator.pop(context);

                                if (categoryId == null) {
                                  return;
                                }

                                setState(() {
                                  _selectedCategoryId =
                                      categoryId;
                                  _searchQuery = '';
                                  _searchController.clear();
                                });

                                _loadData();
                              },
                            );
                          },
                        ),

                      const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Divider(height: 1),
                      ),

                      // =========================
                      // نشاط المستخدم
                      // =========================
                      _buildDrawerSectionTitle(
                        'حسابي',
                        Icons.account_circle_outlined,
                      ),

                      _buildDrawerItem(
                        icon: Icons.favorite_border,
                        title: 'المفضلة',
                        onTap: () {
                          Navigator.pop(context);
                          _openFavorites();
                        },
                      ),

                      _buildDrawerItem(
                        icon: Icons.inventory_2_outlined,
                        title: 'إعلاناتي',
                        onTap: () {
                          Navigator.pop(context);
                          _openMyListings();
                        },
                      ),

                      const SizedBox(height: 6),

                      // =========================
                      // تسجيل الخروج
                      // =========================
                      if (user != null)
                        _buildDrawerItem(
                          icon: Icons.logout,
                          title: 'تسجيل الخروج',
                          isDestructive: true,
                          onTap: () {
                            Navigator.pop(context);
                            _signOut();
                          },
                        ),
                    ],
                  ),
                ),

                // =========================
                // أسفل القائمة
                // =========================
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    12,
                  ),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: Colors.grey.shade300,
                        width: 0.6,
                      ),
                    ),
                  ),
                  child: Text(
                    'دلالة شبشة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // =========================
        // AppBar
        // =========================
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 0,
          elevation: 0,
          title: Text(
            'دلالة شبشة',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color:
                  Theme.of(context).colorScheme.primary,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: () {
                _loadData();
                _checkAdminStatus();
              },
              icon: const Icon(
                Icons.refresh,
              ),
            ),
            _buildPostListingButton(),
            _buildProfileButton(),
          ],
        ),

        // =========================
        // محتوى الصفحة
        // =========================
        body: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                13,
                4,
                13,
                8,
              ),
              child: Column(
                children: [
                  Text(
                    'في مكان واحد - تسوق واعلن بسهولة',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context)
                          .colorScheme
                          .primary,
                    ),
                  ),

                  if (user != null &&
                      name != null &&
                      name.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 3,
                      ),
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

            Expanded(
              child: _buildBody(),
            ),
          ],
        ),

        // =========================
        // شريط التنقل السفلي
        // =========================
        bottomNavigationBar:
            _buildBottomNavigation(),
      ),
    );
  }
}