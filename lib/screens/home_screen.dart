// =============================================================
// الصفحة الرئيسية لتطبيق دلالة شبشة (نسخة محسّنة ومدموجة)
//
// الحزم المطلوبة في pubspec.yaml:
//   intl: ^0.19.0
//   cached_network_image: ^3.3.1
//
// يعتمد الكود على الافتراضات التالية، عدّلها إن اختلفت عندك:
//   1) جدول المفضلة: أسماؤه في الثوابت _favoritesTable وما بعده.
//   2) علاقة (foreign key) بين listing_images.listing_id و listings.id.
//      إن لم توجد يعمل الكود تلقائياً بالطريقة القديمة (طلب منفصل للصور).
//   3) عمود icon في جدول categories (اختياري): مفاتيح مثل car, home, phone.
//      إن كان فارغاً تُستخدم الأيقونة حسب اسم القسم كما كان سابقاً.
// =============================================================

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  // =========================
  // ثوابت
  // =========================
  static const _homePageSize = 60;
  static const _categoryPageSize = 30;
  static const _searchPoolSize = 500;

  static const _cardWidth = 158.0;
  static const _cardHeight = 225.0;

  static const _listingColumns =
      'id, title, description, price, currency, price_type, '
      'area, category_id, status, created_at';

  // جدول المفضلة (عدّل الأسماء حسب مشروعك).
  static const _favoritesTable = 'favorites';
  static const _favUserColumn = 'user_id';
  static const _favListingColumn = 'listing_id';

  static final _numberFormat = NumberFormat('#,##0.##', 'en');

  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  // =========================
  // الحالة
  // =========================
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _listings = [];
  List<Map<String, dynamic>> _promotedListings = [];
  List<Map<String, dynamic>>? _searchPool;
  Set<int> _favoriteIds = {};

  bool _loading = true; // أول تحميل للصفحة فقط
  bool _listingsLoading = false; // عند تغيير القسم
  bool _loadingMore = false;
  bool _searchPoolLoading = false;
  bool _hasMore = true;
  bool _isAdmin = false;

  String? _error;
  String _searchQuery = '';
  int? _selectedCategoryId;
  int _page = 0;
  int _listingsRequestId = 0;

  Timer? _debounce;
  Timer? _promotedRefreshTimer;

  bool get _isSearching => _searchQuery.trim().isNotEmpty;
  bool get _isFiltering => _isSearching || _selectedCategoryId != null;

  // =========================
  // الدورة الحياتية
  // =========================
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);

    _loadAll(showSpinner: false);
    _checkAdminStatus();

    // تحديث الإعلانات التجارية كل 5 دقائق (وتتوقف مع dispose).
    _promotedRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _loadPromotedListings(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promotedRefreshTimer?.cancel();
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // عند رجوع المستخدم للتطبيق نحدّث الإعلانات التجارية فقط.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPromotedListings();
    }
  }

  // التحميل التلقائي للمزيد عند نهاية القائمة (داخل القسم فقط).
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_selectedCategoryId == null || _isSearching) return;

    final position = _scrollController.position;

    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadListings(reset: false);
    }
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;

    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // =========================
  // البحث
  // =========================
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

  void _onSearchChanged(String value) {
    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;

      setState(() => _searchQuery = value);

      if (value.trim().isNotEmpty) {
        _ensureSearchPool();
      }
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

  // نتائج البحث/القسم. البحث يعمل على مجموعة أكبر (حتى 500 إعلان)
  // تُحمّل مرة واحدة عند أول بحث، ثم يُبحث فيها محلياً بالتطبيع العربي.
  List<Map<String, dynamic>> get _visibleResults {
    final query = _normalizeSearchText(_searchQuery);
    final source = query.isEmpty ? _listings : (_searchPool ?? _listings);

    return source.where((listing) {
      if (_selectedCategoryId != null &&
          listing['category_id'] != _selectedCategoryId) {
        return false;
      }

      if (query.isEmpty) return true;

      return (listing['_search'] as String? ?? '').contains(query);
    }).toList();
  }

  Future<void> _ensureSearchPool() async {
    if (_searchPool != null || _searchPoolLoading) return;

    setState(() => _searchPoolLoading = true);

    try {
      final rows = await _fetchListings(
        from: 0,
        to: _searchPoolSize - 1,
      );

      if (!mounted) return;

      setState(() {
        _searchPool = rows;
        _searchPoolLoading = false;
      });
    } catch (e) {
      debugPrint('searchPool error: $e');

      if (!mounted) return;

      // إن فشل التحميل نبحث في الإعلانات المحمّلة حالياً.
      setState(() => _searchPoolLoading = false);
    }
  }

  // الإعلانات التجارية تنتهي محلياً بدون انتظار المؤقّت.
  List<Map<String, dynamic>> get _activePromoted {
    final now = DateTime.now().toUtc();

    return _promotedListings.where((listing) {
      final end = DateTime.tryParse('${listing['promotion_end_at']}');
      return end == null || end.toUtc().isAfter(now);
    }).toList();
  }

  // =========================
  // تحميل البيانات
  // =========================
  Future<void> _loadAll({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    // نجعل مجموعة البحث تُحمّل من جديد عند الحاجة.
    _searchPool = null;

    try {
      await Future.wait([
        _loadCategories(),
        _loadListings(),
        _loadPromotedListings(),
        _loadFavorites(),
      ]);

      if (mounted) setState(() => _error = null);
    } catch (e) {
      debugPrint('loadAll error: $e');

      if (mounted) {
        if (_listings.isEmpty) {
          setState(() {
            _error =
                'تعذر تحميل البيانات. تحقق من اتصال الإنترنت وحاول مجدداً.';
          });
        } else {
          _showSnack('تعذر تحديث البيانات، تحقق من اتصال الإنترنت');
        }
      }
    }

    if (!mounted) return;

    setState(() => _loading = false);

    if (_isSearching) {
      unawaited(_ensureSearchPool());
    }
  }

  Future<void> _loadCategories() async {
    final response = await _supabase
        .from('categories')
        .select('id, name, icon')
        .eq('is_active', true)
        .order('sort_order');

    if (!mounted) return;

    setState(() {
      _categories = List<Map<String, dynamic>>.from(response);
    });
  }

  int _pageSizeFor(int? categoryId) {
    return categoryId == null ? _homePageSize : _categoryPageSize;
  }

  Future<void> _loadListings({bool reset = true}) async {
    if (!reset && (_loadingMore || !_hasMore || _listingsLoading)) return;

    // رقم الطلب يمنع نتيجة قديمة من الكتابة فوق نتيجة أحدث.
    final requestId = reset ? ++_listingsRequestId : _listingsRequestId;
    final categoryId = _selectedCategoryId;
    final pageSize = _pageSizeFor(categoryId);
    final page = reset ? 0 : _page;

    if (!reset && mounted) {
      setState(() => _loadingMore = true);
    }

    try {
      final rows = await _fetchListings(
        from: page * pageSize,
        to: page * pageSize + pageSize - 1,
        categoryId: categoryId,
      );

      if (!mounted || requestId != _listingsRequestId) return;

      setState(() {
        _listings = reset ? rows : [..._listings, ...rows];
        _page = page + 1;
        _hasMore = rows.length == pageSize;
        _loadingMore = false;
        _listingsLoading = false;
      });
    } catch (e) {
      debugPrint('loadListings error: $e');

      if (!mounted || requestId != _listingsRequestId) return;

      setState(() {
        _loadingMore = false;
        _listingsLoading = false;
      });

      if (reset) rethrow;
    }
  }

  // جلب الإعلانات مع أول صورة لكل إعلان في طلب واحد.
  // إن فشل الطلب المدمج نعود للطريقة القديمة (طلب منفصل للصور).
  Future<List<Map<String, dynamic>>> _fetchListings({
    required int from,
    required int to,
    int? categoryId,
  }) async {
    try {
      var query = _supabase
          .from('listings')
          .select(
            '$_listingColumns, listing_images(image_path, sort_order)',
          )
          .eq('status', 'approved');

      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .order('sort_order', referencedTable: 'listing_images')
          .limit(1, referencedTable: 'listing_images')
          .range(from, to);

      return List<Map<String, dynamic>>.from(response)
          .map(_prepareListing)
          .toList();
    } catch (e) {
      debugPrint('embedded images query failed, using fallback: $e');

      var query = _supabase
          .from('listings')
          .select(_listingColumns)
          .eq('status', 'approved');

      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(from, to);

      final rows = List<Map<String, dynamic>>.from(response);

      await _attachCoverImages(rows);

      return rows.map(_prepareListing).toList();
    }
  }

  // استخراج غلاف الإعلان وتجهيز نص البحث المطبّع مرة واحدة.
  Map<String, dynamic> _prepareListing(Map<String, dynamic> row) {
    final images = row['listing_images'];

    if (images is List && images.isNotEmpty && images.first is Map) {
      row['image_path'] = (images.first as Map)['image_path'];
    }

    row['_search'] = _normalizeSearchText(
      '${row['title'] ?? ''} '
      '${row['description'] ?? ''} '
      '${row['area'] ?? ''}',
    );

    return row;
  }

  // جلب أول صورة لكل إعلان بطلب منفصل (وسيلة احتياطية + الإعلانات التجارية).
  Future<void> _attachCoverImages(List<Map<String, dynamic>> rows) async {
    final ids = rows
        .map((row) => row['id'])
        .where((id) => id != null)
        .toList();

    if (ids.isEmpty) return;

    final response = await _supabase
        .from('listing_images')
        .select('listing_id, image_path, sort_order')
        .inFilter('listing_id', ids)
        .order('sort_order');

    final covers = <dynamic, dynamic>{};

    for (final image in List<Map<String, dynamic>>.from(response)) {
      covers.putIfAbsent(image['listing_id'], () => image['image_path']);
    }

    for (final row in rows) {
      final path = covers[row['id']];
      if (path != null) row['image_path'] = path;
    }
  }

  Future<void> _loadPromotedListings() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      final promotedResponse = await _supabase
          .from('promoted_listings')
          .select('id, listing_id, start_at, end_at, is_active, created_by')
          .eq('is_active', true)
          .lte('start_at', now)
          .gt('end_at', now)
          .order('start_at', ascending: false);

      final promotedRows = List<Map<String, dynamic>>.from(promotedResponse);

      final listingIds = promotedRows
          .map((item) => item['listing_id'])
          .where((id) => id != null)
          .toList();

      if (listingIds.isEmpty) {
        if (mounted) setState(() => _promotedListings = []);
        return;
      }

      // لا نعرض الإعلان التجاري إلا إذا كان الإعلان نفسه approved.
      final listingsResponse = await _supabase
          .from('listings')
          .select(_listingColumns)
          .inFilter('id', listingIds)
          .eq('status', 'approved');

      final listingsById = <dynamic, Map<String, dynamic>>{};

      for (final listing
          in List<Map<String, dynamic>>.from(listingsResponse)) {
        listingsById[listing['id']] = listing;
      }

      final result = <Map<String, dynamic>>[];

      // نحافظ على ترتيب start_at القادم من promoted_listings.
      for (final promoted in promotedRows) {
        final listing = listingsById[promoted['listing_id']];

        if (listing == null) continue;

        final item = Map<String, dynamic>.from(listing);

        item['promoted_listing_id'] = promoted['id'];
        item['promotion_start_at'] = promoted['start_at'];
        item['promotion_end_at'] = promoted['end_at'];
        item['promotion_is_active'] = promoted['is_active'];
        item['is_commercial'] = true;

        result.add(item);
      }

      await _attachCoverImages(result);

      if (!mounted) return;

      setState(() => _promotedListings = result);
    } catch (e) {
      // لا نوقف الصفحة الرئيسية إذا فشل تحميل الإعلانات التجارية.
      debugPrint('loadPromoted error: $e');
    }
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

  // =========================
  // الفلاتر والأقسام
  // =========================
  Future<void> _selectCategory(
    int? id, {
    bool clearSearch = false,
  }) async {
    _debounce?.cancel();

    if (clearSearch) _searchController.clear();

    setState(() {
      _selectedCategoryId = id;
      _listingsLoading = true;
      if (clearSearch) _searchQuery = '';
    });

    _scrollToTop();

    try {
      await _loadListings();
    } catch (_) {
      _showSnack('تعذر تحميل الإعلانات، حاول مرة أخرى');
    }
  }

  Future<void> _clearFilters() async {
    final hadCategory = _selectedCategoryId != null;

    _debounce?.cancel();
    _searchController.clear();

    setState(() {
      _searchQuery = '';
      _selectedCategoryId = null;
      if (hadCategory) _listingsLoading = true;
    });

    _scrollToTop();

    if (!hadCategory) return;

    try {
      await _loadListings();
    } catch (_) {
      _showSnack('تعذر تحميل الإعلانات، حاول مرة أخرى');
    }
  }

  String? get _selectedCategoryName {
    for (final category in _categories) {
      if (category['id'] == _selectedCategoryId) {
        return category['name']?.toString();
      }
    }
    return null;
  }

  // =========================
  // المفضلة
  // =========================
  Future<void> _loadFavorites() async {
    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        if (mounted) setState(() => _favoriteIds = {});
        return;
      }

      final rows = await _supabase
          .from(_favoritesTable)
          .select(_favListingColumn)
          .eq(_favUserColumn, user.id);

      final ids = <int>{};

      for (final row in rows) {
        final value = row[_favListingColumn];
        if (value is num) ids.add(value.toInt());
      }

      if (!mounted) return;

      setState(() => _favoriteIds = ids);
    } catch (e) {
      debugPrint('loadFavorites error: $e');
    }
  }

  Future<void> _toggleFavorite(int listingId) async {
    if (!await _ensureSignedIn()) return;

    final user = _supabase.auth.currentUser;

    if (user == null) return;

    final wasFavorite = _favoriteIds.contains(listingId);

    // تحديث فوري للواجهة ثم مزامنة مع الخادم.
    setState(() {
      if (wasFavorite) {
        _favoriteIds.remove(listingId);
      } else {
        _favoriteIds.add(listingId);
      }
    });

    try {
      if (wasFavorite) {
        await _supabase
            .from(_favoritesTable)
            .delete()
            .eq(_favUserColumn, user.id)
            .eq(_favListingColumn, listingId);
      } else {
        await _supabase.from(_favoritesTable).insert({
          _favUserColumn: user.id,
          _favListingColumn: listingId,
        });
      }
    } catch (e) {
      debugPrint('toggleFavorite error: $e');

      if (!mounted) return;

      // نتراجع عن التحديث الفوري.
      setState(() {
        if (wasFavorite) {
          _favoriteIds.add(listingId);
        } else {
          _favoriteIds.remove(listingId);
        }
      });

      _showSnack('تعذر تحديث المفضلة، حاول مرة أخرى');
    }
  }

  // =========================
  // التنقل والحساب
  // =========================
  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();

      if (!mounted) return;

      setState(() {
        _isAdmin = false;
        _favoriteIds = {};
      });

      _showSnack('تم تسجيل الخروج بنجاح');

      await _loadAll(showSpinner: false);
    } catch (_) {
      _showSnack('تعذر تسجيل الخروج، حاول مرة أخرى');
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

    if (result == true && _supabase.auth.currentUser != null) {
      await _checkAdminStatus();
      await _loadFavorites();
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

    await _loadAll(showSpinner: false);
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

    await _loadAll(showSpinner: false);
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

    await _loadFavorites();
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
    await _loadAll(showSpinner: false);
  }

  Future<void> _openListingDetails(Map<String, dynamic> listing) async {
    final listingId = listing['id'];

    if (listingId is! int) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListingDetailsScreen(
          listingId: listingId,
        ),
      ),
    );

    if (!mounted) return;

    // قد يكون المستخدم أضاف/أزال المفضلة من صفحة التفاصيل.
    await _loadFavorites();
  }

  // =========================
  // أيقونات الأقسام
  // =========================
  static const _iconMap = <String, IconData>{
    'car': Icons.directions_car_outlined,
    'home': Icons.home_work_outlined,
    'phone': Icons.phone_android_outlined,
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

  // الأولوية لعمود icon في قاعدة البيانات، ثم اسم القسم.
  IconData _iconForCategory(Map<String, dynamic> category) {
    return _iconMap[category['icon']?.toString().trim()] ??
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

  // =========================
  // تنسيق السعر والوقت
  // =========================
  String _formatPrice(Map<String, dynamic> listing) {
    final price = listing['price'];

    final currency =
        (listing['currency']?.toString().trim().isNotEmpty ?? false)
            ? listing['currency'].toString().trim()
            : 'SDG';

    final priceType = listing['price_type']?.toString().trim() ?? '';

    if (priceType == 'contact' || price == null) {
      return 'السعر عند التواصل';
    }

    final number = num.tryParse(price.toString());

    if (number == null) return '$price $currency';

    return '${_numberFormat.format(number)} $currency';
  }

  String _timeAgo(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();

    if (date == null) return '';

    final diff = DateTime.now().difference(date);

    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';

    return 'قبل ${diff.inDays ~/ 30} شهر';
  }

  // =========================
  // الصور
  // =========================
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
    double height = 110,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageUrl = _imageUrl(listing['image_path']);

    Widget placeholder([
      IconData icon = Icons.photo_library_outlined,
    ]) {
      return Container(
        height: height,
        width: double.infinity,
        color: colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            icon,
            size: 30,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (imageUrl == null) return placeholder();

    return CachedNetworkImage(
      imageUrl: imageUrl,
      height: height,
      width: double.infinity,
      fit: BoxFit.cover,
      memCacheWidth: 400,
      placeholder: (_, __) => placeholder(Icons.image_outlined),
      errorWidget: (_, __, ___) => placeholder(Icons.broken_image_outlined),
    );
  }

  // =========================
  // بطاقة الإعلان
  // =========================
  Widget _buildListingCard(
    Map<String, dynamic> listing, {
    bool isCommercial = false,
    bool fillWidth = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final id = listing['id'] as int?;

    final rawTitle = listing['title']?.toString().trim() ?? '';
    final title = rawTitle.isEmpty ? 'إعلان بدون عنوان' : rawTitle;

    final area = listing['area']?.toString().trim() ?? '';

    final meta = [
      if (area.isNotEmpty) area,
      _timeAgo(listing['created_at']),
    ].where((part) => part.isNotEmpty).join(' · ');

    final isFavorite = id != null && _favoriteIds.contains(id);
    final isNegotiable = listing['price_type'] == 'negotiable';

    return SizedBox(
      width: fillWidth ? double.infinity : _cardWidth,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: InkWell(
          onTap: () => _openListingDetails(listing),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  _buildListingImage(listing, height: 110),

                  if (isCommercial)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.local_offer,
                              color: colorScheme.onPrimary,
                              size: 11,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'إعلان تجاري',
                              style: TextStyle(
                                color: colorScheme.onPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  if (id != null)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Material(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _toggleFavorite(id),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              isFavorite
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              size: 18,
                              color: isFavorite
                                  ? Colors.red
                                  : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _formatPrice(listing),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),

                    if (isNegotiable)
                      Text(
                        'قابل للتفاوض',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),

                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              meta,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================
  // مكوّنات الصفحة
  // =========================
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
    List<Map<String, dynamic>> listings, {
    bool commercial = false,
  }) {
    return SizedBox(
      height: _cardHeight,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: listings.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          return _buildListingCard(
            listings[index],
            isCommercial: commercial,
          );
        },
      ),
    );
  }

  // بانر ترحيبي يحلّ محل الجملة الدعائية وزر "ضع إعلانك" في الـ AppBar.
  Widget _buildPromoBanner() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'عندك شيء للبيع؟',
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'في مكان واحد - تسوق واعلن بسهولة',
                  style: TextStyle(
                    color: colorScheme.onPrimary.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _openAddListing,
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.onPrimary,
                    foregroundColor: colorScheme.primary,
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'أضف إعلانك الآن',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.campaign_outlined,
            size: 52,
            color: colorScheme.onPrimary.withValues(alpha: 0.9),
          ),
        ],
      ),
    );
  }

  Widget _buildCategories() {
    if (_categories.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text('لا توجد أقسام متاحة حالياً'),
        ),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final category = _categories[index];

          final categoryId = category['id'] as int?;
          final categoryName = category['name']?.toString() ?? 'بدون اسم';
          final selected = _selectedCategoryId == categoryId;

          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (categoryId == null) return;

              _selectCategory(selected ? null : categoryId);
            },
            child: Container(
              width: 80,
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? colorScheme.primary : Colors.transparent,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _iconForCategory(category),
                    size: 22,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    categoryName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
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
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) {
          return TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'ابحث عن إعلان أو منطقة...',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(
                Icons.search,
                size: 21,
              ),
              suffixIcon: value.text.isNotEmpty
                  ? IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: _clearSearch,
                      icon: const Icon(
                        Icons.clear,
                        size: 19,
                      ),
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
          );
        },
      ),
    );
  }

  // نتائج البحث أو القسم: شبكة من عمودين.
  Widget _buildSearchResults() {
    final colorScheme = Theme.of(context).colorScheme;
    final results = _visibleResults;
    final promotedIds =
        _activePromoted.map((listing) => listing['id']).toSet();

    final showSpinner =
        _listingsLoading || (_isSearching && _searchPoolLoading);

    final title = _isSearching
        ? 'نتائج البحث'
        : (_selectedCategoryName ?? 'إعلانات القسم');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(
          title,
          trailing: Text(
            '${results.length} إعلان',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),

        if (showSpinner && results.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 35),
            child: Column(
              children: [
                const Icon(
                  Icons.search_off_outlined,
                  size: 45,
                ),
                const SizedBox(height: 9),
                Text(
                  _isSearching
                      ? 'لم نجد إعلانات تطابق بحثك'
                      : 'لا توجد إعلانات في هذا القسم حالياً',
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: results.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: _cardHeight,
            ),
            itemBuilder: (context, index) {
              final listing = results[index];

              return _buildListingCard(
                listing,
                fillWidth: true,
                isCommercial: promotedIds.contains(listing['id']),
              );
            },
          ),

        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  Widget _buildHomeSections() {
    if (_listingsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final promoted = _activePromoted;

    if (_listings.isEmpty && promoted.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 45,
            ),
            SizedBox(height: 10),
            Text('لا توجد إعلانات متاحة حالياً'),
          ],
        ),
      );
    }

    // فصل الإعلانات التجارية عن أحدث الإعلانات.
    final promotedIds = promoted.map((listing) => listing['id']).toSet();

    final latestListings = _listings
        .where((listing) => !promotedIds.contains(listing['id']))
        .take(10)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (promoted.isNotEmpty) ...[
          _sectionTitle(
            'إعلانات تجارية',
            icon: Icons.local_offer_outlined,
          ),
          _buildHorizontalListings(promoted, commercial: true),
          const SizedBox(height: 20),
        ],

        if (latestListings.isNotEmpty) ...[
          _sectionTitle(
            'أحدث الإعلانات',
            icon: Icons.access_time,
          ),
          _buildHorizontalListings(latestListings),
          const SizedBox(height: 20),
        ],

        _sectionTitle(
          'معروضات الأقسام',
          icon: Icons.grid_view_rounded,
        ),

        ..._categories.map((category) {
          final categoryId = category['id'] as int?;
          final categoryName = category['name']?.toString() ?? 'بدون اسم';

          if (categoryId == null) return const SizedBox.shrink();

          final categoryListings = _listings
              .where((listing) => listing['category_id'] == categoryId)
              .take(8)
              .toList();

          if (categoryListings.isEmpty) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionTitle(
                  categoryName,
                  icon: _iconForCategory(category),
                  trailing: TextButton(
                    onPressed: () => _selectCategory(categoryId),
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
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                onPressed: _loadAll,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    final user = _supabase.auth.currentUser;
    final name = (user?.userMetadata?['full_name'] as String?)?.trim();

    return RefreshIndicator(
      onRefresh: () => _loadAll(showSpinner: false),
      child: ListView(
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(13, 8, 13, 18),
        children: [
          _buildSearchField(),

          const SizedBox(height: 12),

          if (!_isFiltering) ...[
            if (name != null && name.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'مرحباً يا $name 👋',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            _buildPromoBanner(),
            const SizedBox(height: 14),
          ],

          _sectionTitle(
            'الأقسام',
            trailing: TextButton(
              onPressed: _clearFilters,
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

          if (_isFiltering) _buildSearchResults() else _buildHomeSections(),
        ],
      ),
    );
  }

  Widget _buildProfileButton() {
    final user = _supabase.auth.currentUser;
    final colorScheme = Theme.of(context).colorScheme;

    return IconButton(
      tooltip: user == null ? 'تسجيل الدخول' : 'الملف الشخصي',
      onPressed: _openProfile,
      icon: CircleAvatar(
        radius: 15,
        backgroundColor: colorScheme.primaryContainer,
        child: Icon(
          user == null ? Icons.person_outline : Icons.person,
          size: 19,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  // =========================
  // شريط التنقل السفلي
  // =========================
  Widget _buildBottomNavigation() {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = colorScheme.primary;

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
                  color: selected ? primary : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    color: selected ? primary : colorScheme.onSurfaceVariant,
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
          color: colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: colorScheme.outlineVariant,
              width: 0.6,
            ),
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            navItem(
              icon: Icons.home_outlined,
              label: 'الرئيسية',
              selected: true,
              // يصعد لأعلى الصفحة ويمسح الفلاتر بدون إعادة تحميل كل شيء.
              onTap: _clearFilters,
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
                        child: Icon(
                          Icons.add,
                          color: colorScheme.onPrimary,
                          size: 25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'أضف إعلان',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
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

  // =========================
  // القائمة الجانبية
  // =========================
  Widget _buildDrawerHeader(User? user, String? name) {
    final primary = Theme.of(context).colorScheme.primary;

    final displayName = name != null && name.trim().isNotEmpty
        ? name.trim()
        : user == null
            ? 'مرحباً بك'
            : 'مستخدم دلالة شبشة';

    // رقم الهاتف الحقيقي لحسابات الهاتف.
    final authPhone = user?.phone?.trim() ?? '';

    // البريد الإلكتروني لحسابات البريد.
    final email = user?.email?.trim() ?? '';

    // رقم الهاتف المحفوظ في metadata كخيار احتياطي.
    final metadataPhone =
        user?.userMetadata?['phone']?.toString().trim() ?? '';

    // إذا كان الحساب مرتبطاً برقم هاتف نعرضه أولاً.
    final phone = authPhone.isNotEmpty ? authPhone : metadataPhone;

    final contact = phone.isNotEmpty
        ? phone
        : email.isNotEmpty
            ? email
            : user == null
                ? 'تصفح الإعلانات بسهولة'
                : 'حسابك في دلالة شبشة';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: primary,
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(18),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              user == null ? Icons.person_outline : Icons.storefront_rounded,
              size: 28,
              color: primary,
            ),
          ),

          const SizedBox(width: 12),

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
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  contact,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
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

  Widget _buildDrawerSectionTitle(String title, IconData icon) {
    final primary = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(9, 5, 9, 4),
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

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    bool selected = false,
    bool isDestructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final itemColor = isDestructive
        ? Colors.red.shade700
        : selected
            ? colorScheme.primary
            : colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected
            ? colorScheme.primaryContainer.withValues(alpha: 0.65)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
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
                        ? colorScheme.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: itemColor,
                        ),
                      ),

                      if (subtitle != null) ...[
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
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

  Widget _buildDrawer(User? user, String? name) {
    final colorScheme = Theme.of(context).colorScheme;

    return Drawer(
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
            _buildDrawerHeader(user, name),

            const SizedBox(height: 5),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 2,
                ),
                children: [
                  _buildDrawerItem(
                    icon: user == null
                        ? Icons.login_outlined
                        : Icons.person_outline,
                    title: user == null ? 'تسجيل الدخول' : 'الملف الشخصي',
                    onTap: () async {
                      Navigator.pop(context);
                      await _openProfile();
                    },
                  ),

                  _buildDrawerItem(
                    icon: Icons.add_circle_outline,
                    title: 'إضافة إعلان',
                    onTap: () async {
                      Navigator.pop(context);
                      await _openAddListing();
                    },
                  ),

                  const SizedBox(height: 5),

                  if (_isAdmin) ...[
                    _buildDrawerItem(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'لوحة تحكم الإدارة',
                      subtitle: 'إدارة ومراجعة الإعلانات',
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

                  _buildDrawerSectionTitle(
                    'الأقسام',
                    Icons.grid_view_rounded,
                  ),

                  if (_categories.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'لا توجد أقسام حالياً',
                        style: TextStyle(fontSize: 13),
                      ),
                    )
                  else
                    ..._categories.map((category) {
                      final categoryId = category['id'] as int?;
                      final categoryName =
                          category['name']?.toString() ?? 'بدون اسم';

                      final selected = _selectedCategoryId == categoryId;

                      return _buildDrawerItem(
                        icon: _iconForCategory(category),
                        title: categoryName,
                        selected: selected,
                        onTap: () {
                          Navigator.pop(context);

                          if (categoryId == null) return;

                          _selectCategory(categoryId, clearSearch: true);
                        },
                      );
                    }),

                  const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Divider(height: 1),
                  ),

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

            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: colorScheme.outlineVariant,
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
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // البناء
  // =========================
  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final name = user?.userMetadata?['full_name'] as String?;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        drawer: _buildDrawer(user, name),

        // AppBar مبسّط: العنوان والحساب فقط.
        // زر "ضع إعلانك" أصبح في البانر والشريط السفلي والقائمة،
        // والتحديث بالسحب للأسفل.
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 0,
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
            _buildProfileButton(),
          ],
        ),

        body: _buildBody(),

        bottomNavigationBar: _buildBottomNavigation(),
      ),
    );
  }
}
