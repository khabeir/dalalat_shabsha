// =============================================================
// الصفحة الرئيسية لتطبيق دلالة شبشة (التصميم الجديد)
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
//   4) صور الترويسة والبانر اختيارية: ضع صورتك في
//        assets/images/home_header.jpg   (خلفية الترويسة)
//        assets/images/home_banner.jpg   (صورة البانر)
//      وأضف assets/images/ إلى pubspec.yaml. وإن لم توجد يظهر رسم
//      مشهد شبشة المرسوم بالكود.
// =============================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
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

  static const _cardWidth = 172.0;
  static const _cardHeight = 272.0;

  // ألوان الهوية.
  static const _brand = Color(0xFF5B2DB5);
  static const _brandDark = Color(0xFF3B1785);
  static const _brandSoft = Color(0xFFEFE9FF);
  static const _ink = Color(0xFF241A55);
  static const _orange = Color(0xFFFF9F1C);
  static const _gold = Color(0xFFFFC93C);

  // ارتفاع الترويسة بدون شريط الحالة.
  static const _headerContentHeight = 236.0;

  // صور اختيارية (انظر التعليق في أعلى الملف).
  static const _headerAsset = 'assets/images/home_header.jpg';
  static const _bannerAsset = 'assets/images/home_banner.jpg';

  // شرائح بانر العروض.
  static const _slides = <_BannerSlide>[
    _BannerSlide(
      'كل ما تحتاجه',
      'في مكان واحد',
      ['إعلانات مميزة', 'بيع وشراء محلي', 'انتشار واسع'],
      'أضف إعلانك الآن',
      _BannerAction.addListing,
    ),
    _BannerSlide(
      'بيع أسرع',
      'بصور واضحة',
      ['صوّر بالكاميرا', 'حتى 6 صور', 'سعر واضح'],
      'أضف إعلانك الآن',
      _BannerAction.addListing,
    ),
    _BannerSlide(
      'تسوق بثقة',
      'من أهل شبشة',
      ['عاين قبل الدفع', 'قابل البائع في مكان عام'],
      'تصفح الأقسام',
      _BannerAction.browseCategories,
    ),
    _BannerSlide(
      'ابحث بسهولة',
      'عن أي شيء',
      ['أقسام منظمة', 'بحث بالحي', 'الأحدث أولاً'],
      'تصفح الأقسام',
      _BannerAction.browseCategories,
    ),
  ];

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
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _categoriesKey = GlobalKey();
  final _bannerController = PageController();
  final _bannerIndex = ValueNotifier<int>(0);

  // هل الترويسة ظاهرة (لتغيير لون أيقونات شريط الحالة).
  final _headerVisible = ValueNotifier<bool>(true);

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
  Timer? _bannerTimer;

  _ListMode _mode = _ListMode.home;

  bool get _isSearching => _searchQuery.trim().isNotEmpty;
  bool get _isFiltering =>
      _isSearching || _selectedCategoryId != null || _mode != _ListMode.home;

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

    // تقليب شرائح البانر كل 5 ثوان.
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_bannerController.hasClients) return;

      _bannerController.animateToPage(
        (_bannerIndex.value + 1) % _slides.length,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promotedRefreshTimer?.cancel();
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _bannerIndex.dispose();
    _headerVisible.dispose();
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

  // التمرير: لون شريط الحالة + التحميل التلقائي للمزيد.
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;

    _headerVisible.value = position.pixels < 110;

    // التحميل التلقائي داخل القسم أو "أحدث الإعلانات" فقط.
    final canLoadMore =
        _selectedCategoryId != null || _mode == _ListMode.latest;

    if (!canLoadMore || _isSearching) return;

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
    // "عرض الكل" للإعلانات المميزة.
    if (_mode == _ListMode.featured &&
        _selectedCategoryId == null &&
        !_isSearching) {
      return _activePromoted;
    }

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
      _mode = _ListMode.home;
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
      _mode = _ListMode.home;
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

  // "عرض الكل" للإعلانات المميزة أو الأحدث.
  void _showAll(_ListMode mode) {
    _debounce?.cancel();
    _searchController.clear();

    setState(() {
      _mode = mode;
      _searchQuery = '';
    });

    _scrollToTop();
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
    await _loadFavorites();
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
    double height = 122,
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
  // ألوان وأيقونات الأقسام
  // =========================
  static const _tones = <_Tone>[
    _Tone(Color(0xFFEFE7FF), Color(0xFF5B2DB5)), // بنفسجي
    _Tone(Color(0xFFFFF1D1), Color(0xFFF59E0B)), // أصفر
    _Tone(Color(0xFFDDF5EA), Color(0xFF0F9D7A)), // أخضر
    _Tone(Color(0xFFDFEDFF), Color(0xFF2563EB)), // أزرق
    _Tone(Color(0xFFFFE3E9), Color(0xFFE11D48)), // وردي
    _Tone(Color(0xFFE9EEF5), Color(0xFF475569)), // رمادي
  ];

  _Tone _toneFor(String name, int index) {
    switch (name.trim()) {
      case 'عقارات':
      case 'موبايلات وإلكترونيات':
        return _tones[0];
      case 'سيارات ومركبات':
      case 'مواشي وحيوانات':
      case 'مواد غذائية':
        return _tones[1];
      case 'أثاث ومستلزمات منزلية':
      case 'محاصيل زراعية':
        return _tones[2];
      case 'ملابس وأحذية':
      case 'أجهزة كهربائية':
      case 'وظائف':
        return _tones[3];
      case 'خدمات':
        return _tones[4];
      case 'أدوات ومعدات':
      case 'أخرى':
        return _tones[5];
      default:
        return _tones[index % _tones.length];
    }
  }

  IconData _filledCategoryIcon(String name) {
    switch (name.trim()) {
      case 'سيارات ومركبات':
        return Icons.directions_car_rounded;
      case 'عقارات':
        return Icons.home_rounded;
      case 'موبايلات وإلكترونيات':
        return Icons.smartphone_rounded;
      case 'أجهزة كهربائية':
        return Icons.electrical_services_rounded;
      case 'ملابس وأحذية':
        return Icons.shopping_bag_rounded;
      case 'أثاث ومستلزمات منزلية':
        return Icons.weekend_rounded;
      case 'مواشي وحيوانات':
        return Icons.pets_rounded;
      case 'محاصيل زراعية':
        return Icons.agriculture_rounded;
      case 'مواد غذائية':
        return Icons.restaurant_rounded;
      case 'أدوات ومعدات':
        return Icons.build_rounded;
      case 'خدمات':
        return Icons.handshake_rounded;
      case 'وظائف':
        return Icons.work_rounded;
      case 'أخرى':
        return Icons.more_horiz_rounded;
      default:
        return Icons.category_rounded;
    }
  }

  Map<String, dynamic>? _categoryById(dynamic id) {
    for (final category in _categories) {
      if (category['id'] == id) return category;
    }
    return null;
  }

  // =========================
  // ألوان الصفحة
  // =========================
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _pageBackground => Color.alphaBlend(
        _brand.withValues(alpha: _isDark ? 0.06 : 0.045),
        Theme.of(context).colorScheme.surface,
      );

  Color get _titleColor =>
      _isDark ? Theme.of(context).colorScheme.onSurface : _ink;

  Color get _cardColor => _isDark
      ? Theme.of(context).colorScheme.surfaceContainerHigh
      : Colors.white;

  // =========================
  // الترويسة (صورة شبشة + الشعار + البحث)
  // =========================
  Widget _buildHeader(double topPadding) {
    final height = topPadding + _headerContentHeight;

    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Image.asset(
              _headerAsset,
              fit: BoxFit.cover,
              alignment: Alignment.bottomCenter,
              errorBuilder: (_, __, ___) => const RepaintBoundary(
                child: CustomPaint(painter: _ShabshaScenePainter()),
              ),
            ),
          ),

          // تدرج علوي خفيف لوضوح شريط الحالة.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPadding + 64,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            top: topPadding + 10,
            left: 16,
            right: 16,
            child: _buildTopRow(),
          ),

          Positioned(
            left: 16,
            right: 16,
            bottom: 36,
            child: _buildSearchField(),
          ),

          // حافة الصفحة المنحنية أسفل الترويسة.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 30,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _pageBackground,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopRow() {
    final user = _supabase.auth.currentUser;

    const glow = [
      Shadow(color: Colors.white, blurRadius: 10),
      Shadow(color: Colors.white, blurRadius: 4),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // (يمين) زر القائمة
        Tooltip(
          message: 'القائمة',
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.menu_rounded, size: 30, color: _brandDark),
            ),
          ),
        ),

        const SizedBox(width: 2),

        _buildLogo(),

        const SizedBox(width: 8),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'دلالة شبشة',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                    color: _brandDark,
                    shadows: glow,
                  ),
                ),
              ),
              Text(
                'سوقك المحلي في شبشة',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _brandDark,
                  shadows: glow,
                ),
              ),
            ],
          ),
        ),

        // (يسار) حساب المستخدم
        Tooltip(
          message: user == null ? 'تسجيل الدخول' : 'الملف الشخصي',
          child: GestureDetector(
            onTap: _openProfile,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                user == null
                    ? Icons.person_outline_rounded
                    : Icons.person_rounded,
                size: 26,
                color: _brandDark,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo() {
    return SizedBox(
      width: 46,
      height: 52,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.location_on_rounded, size: 52, color: _brand),
          const Positioned(
            top: 12,
            child: Icon(
              Icons.shopping_cart_rounded,
              size: 17,
              color: Colors.white,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: 15,
              height: 15,
              decoration: const BoxDecoration(
                color: _gold,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_offer_rounded,
                size: 9,
                color: _brandDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color: _isDark
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : Colors.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.20),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _searchController,
        builder: (context, value, _) {
          return TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            onChanged: _onSearchChanged,
            style: const TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: 'ابحث عن إعلان أو منطقة ...',
              hintStyle: TextStyle(
                fontSize: 14.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 27,
                color: _titleColor,
              ),
              suffixIcon: value.text.isNotEmpty
                  ? IconButton(
                      onPressed: _clearSearch,
                      tooltip: 'مسح البحث',
                      icon: const Icon(Icons.close_rounded, size: 21),
                    )
                  : null,
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 17),
            ),
          );
        },
      ),
    );
  }

  // =========================
  // بانر العروض المتحرك
  // =========================
  Widget _buildBannerCarousel() {
    return Column(
      children: [
        SizedBox(
          height: 196,
          child: PageView.builder(
            controller: _bannerController,
            itemCount: _slides.length,
            onPageChanged: (index) => _bannerIndex.value = index,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildBannerSlide(_slides[index]),
              );
            },
          ),
        ),

        const SizedBox(height: 10),

        ValueListenableBuilder<int>(
          valueListenable: _bannerIndex,
          builder: (context, current, _) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (index) {
                final active = index == current;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 12 : 8,
                  height: active ? 12 : 8,
                  decoration: BoxDecoration(
                    color: active ? _brand : _brand.withValues(alpha: 0.22),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  void _onBannerAction(_BannerAction action) {
    switch (action) {
      case _BannerAction.addListing:
        _openAddListing();
        break;
      case _BannerAction.browseCategories:
        _scrollToCategories();
        break;
    }
  }

  void _scrollToCategories() {
    final target = _categoriesKey.currentContext;

    if (target == null) return;

    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  Widget _buildBannerSlide(_BannerSlide slide) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final photoWidth = width * 0.56;

          return Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFF3B1785),
                        Color(0xFF5B2DB5),
                        Color(0xFF7A45DA),
                      ],
                    ),
                  ),
                ),
              ),

              // الصورة على اليمين بحافة منحنية.
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: photoWidth,
                child: ClipPath(
                  clipper: const _PhotoClipper(),
                  child: Image.asset(
                    _bannerAsset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const RepaintBoundary(
                      child: CustomPaint(painter: _ShabshaScenePainter()),
                    ),
                  ),
                ),
              ),

              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: photoWidth,
                child: const IgnorePointer(
                  child: CustomPaint(painter: _SwooshPainter()),
                ),
              ),

              Positioned(
                left: 18,
                top: 14,
                bottom: 14,
                width: width * 0.58,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        slide.line1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        slide.line2,
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 3,
                      children: [
                        for (final bullet in slide.bullets)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: _gold,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                bullet,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => _onBannerAction(slide.action),
                      child: Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFB02E), Color(0xFFFF8A00)],
                          ),
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: _orange.withValues(alpha: 0.45),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              slide.cta,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              slide.action == _BannerAction.addListing
                                  ? Icons.add_circle_outline_rounded
                                  : Icons.grid_view_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ],
                        ),
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

  // =========================
  // عناوين الأقسام
  // =========================
  Widget _sectionHeader(
    String title, {
    IconData? icon,
    Color? iconColor,
    VoidCallback? onViewAll,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 24, color: iconColor ?? _brand),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: _titleColor,
              ),
            ),
          ),
          if (onViewAll != null)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onViewAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'عرض الكل',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _isDark
                            ? Theme.of(context).colorScheme.primary
                            : _brand,
                      ),
                    ),
                    Icon(
                      Icons.chevron_left_rounded,
                      size: 22,
                      color: _isDark
                          ? Theme.of(context).colorScheme.primary
                          : _brand,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =========================
  // الأقسام
  // =========================
  Widget _buildCategoryTile(
    Map<String, dynamic> category,
    int index, {
    required bool selected,
    required VoidCallback onTap,
  }) {
    final name = category['name']?.toString() ?? 'بدون اسم';
    final tone = _toneFor(name, index);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: _isDark ? tone.fg.withValues(alpha: 0.16) : tone.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected ? tone.fg : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: tone.fg.withValues(alpha: selected ? 0.28 : 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_filledCategoryIcon(name), size: 34, color: tone.fg),
            const SizedBox(height: 8),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: _titleColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesSection() {
    return Column(
      key: _categoriesKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'الأقسام',
          icon: Icons.grid_view_rounded,
          onViewAll: _categories.isEmpty ? null : _showAllCategories,
        ),

        const SizedBox(height: 10),

        if (_categories.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(child: Text('لا توجد أقسام متاحة حالياً')),
          )
        else
          SizedBox(
            height: 118,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final category = _categories[index];
                final categoryId = category['id'] as int?;
                final selected = _selectedCategoryId == categoryId;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: SizedBox(
                    width: 88,
                    child: _buildCategoryTile(
                      category,
                      index,
                      selected: selected,
                      onTap: () {
                        if (categoryId == null) return;

                        _selectCategory(selected ? null : categoryId);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  // كل الأقسام في نافذة سفلية.
  void _showAllCategories() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'كل الأقسام',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: GridView.builder(
                      shrinkWrap: true,
                      itemCount: _categories.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.05,
                      ),
                      itemBuilder: (context, index) {
                        final category = _categories[index];
                        final categoryId = category['id'] as int?;

                        return _buildCategoryTile(
                          category,
                          index,
                          selected: _selectedCategoryId == categoryId,
                          onTap: () {
                            Navigator.pop(sheetContext);

                            if (categoryId != null) {
                              _selectCategory(categoryId, clearSearch: true);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
    ].where((part) => part.isNotEmpty).join(' - ');

    final category = _categoryById(listing['category_id']);
    final categoryName = category?['name']?.toString() ?? '';

    final isFavorite = id != null && _favoriteIds.contains(id);
    final isNegotiable = listing['price_type'] == 'negotiable';
    final priceText = _formatPrice(listing);
    final isContactPrice = priceText == 'السعر عند التواصل';

    return SizedBox(
      width: fillWidth ? double.infinity : _cardWidth,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: _brand.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: _cardColor,
          borderRadius: BorderRadius.circular(22),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openListingDetails(listing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    _buildListingImage(listing, height: 122),

                    if (categoryName.isNotEmpty)
                      Positioned(
                        top: 9,
                        right: 9,
                        // نترك مكاناً لزر المفضلة على اليسار.
                        left: 48,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _brand,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _filledCategoryIcon(categoryName),
                                  size: 14,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    categoryName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    if (id != null)
                      Positioned(
                        top: 3,
                        left: 3,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _toggleFavorite(id),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.14),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 20,
                                color: isFavorite ? Colors.red : _brand,
                              ),
                            ),
                          ),
                        ),
                      ),

                    if (isCommercial)
                      Positioned(
                        bottom: 8,
                        right: 9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 13,
                                color: _brandDark,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'مميز',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _brandDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: _titleColor,
                        ),
                      ),

                      const SizedBox(height: 7),

                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _isDark
                              ? colorScheme.primary.withValues(alpha: 0.18)
                              : _brandSoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          priceText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isContactPrice ? 12.5 : 14.5,
                            fontWeight: FontWeight.w800,
                            color: _isDark ? colorScheme.primary : _brand,
                          ),
                        ),
                      ),

                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 15,
                              color: _brand,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                meta,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      if (isNegotiable) ...[
                        const SizedBox(height: 7),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _isDark
                                ? colorScheme.primary.withValues(alpha: 0.18)
                                : _brandSoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'سعر قابل للتفاوض',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: _isDark ? colorScheme.primary : _brand,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalListings(
    List<Map<String, dynamic>> listings, {
    bool commercial = false,
  }) {
    return SizedBox(
      height: _cardHeight + 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: listings.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildListingCard(
              listings[index],
              isCommercial: commercial,
            ),
          );
        },
      ),
    );
  }

  // =========================
  // نتائج البحث / القسم / عرض الكل
  // =========================
  Widget _buildSearchResults() {
    final colorScheme = Theme.of(context).colorScheme;
    final results = _visibleResults;
    final promotedIds =
        _activePromoted.map((listing) => listing['id']).toSet();

    final showSpinner =
        _listingsLoading || (_isSearching && _searchPoolLoading);

    final String title;

    if (_isSearching) {
      title = 'نتائج البحث';
    } else if (_selectedCategoryId != null) {
      title = _selectedCategoryName ?? 'إعلانات القسم';
    } else if (_mode == _ListMode.featured) {
      title = 'إعلانات مميزة';
    } else {
      title = 'أحدث الإعلانات';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: _titleColor,
                  ),
                ),
              ),
              Text(
                '${results.length} إعلان',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed: _clearFilters,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: const Icon(Icons.close_rounded, size: 17),
                label: const Text(
                  'إلغاء التصفية',
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        if (showSpinner && results.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 35, horizontal: 16),
            child: Column(
              children: [
                const Icon(Icons.search_off_outlined, size: 48),
                const SizedBox(height: 9),
                Text(
                  _isSearching
                      ? 'لم نجد إعلانات تطابق بحثك'
                      : 'لا توجد إعلانات هنا حالياً',
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: results.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
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

  // =========================
  // أقسام الصفحة الرئيسية
  // =========================
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
            Icon(Icons.inventory_2_outlined, size: 48),
            SizedBox(height: 10),
            Text('لا توجد إعلانات متاحة حالياً'),
          ],
        ),
      );
    }

    final promotedIds = promoted.map((listing) => listing['id']).toSet();

    final latestListings = _listings
        .where((listing) => !promotedIds.contains(listing['id']))
        .take(10)
        .toList();

    // صفوف الأقسام التي فيها إعلانات.
    final categoryRows = <Widget>[];

    for (var i = 0; i < _categories.length; i++) {
      final category = _categories[i];
      final categoryId = category['id'] as int?;

      if (categoryId == null) continue;

      final items = _listings
          .where((listing) => listing['category_id'] == categoryId)
          .take(8)
          .toList();

      if (items.isEmpty) continue;

      final name = category['name']?.toString() ?? 'بدون اسم';

      categoryRows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader(
                name,
                icon: _filledCategoryIcon(name),
                iconColor: _toneFor(name, i).fg,
                onViewAll: () => _selectCategory(categoryId),
              ),
              const SizedBox(height: 12),
              _buildHorizontalListings(items),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (promoted.isNotEmpty) ...[
          _sectionHeader(
            'إعلانات مميزة',
            icon: Icons.local_fire_department_rounded,
            iconColor: const Color(0xFFFF6A1A),
            onViewAll: () => _showAll(_ListMode.featured),
          ),
          const SizedBox(height: 12),
          _buildHorizontalListings(promoted),
          const SizedBox(height: 14),
        ],

        if (latestListings.isNotEmpty) ...[
          _sectionHeader(
            'أحدث الإعلانات',
            icon: Icons.schedule_rounded,
            onViewAll: () => _showAll(_ListMode.latest),
          ),
          const SizedBox(height: 12),
          _buildHorizontalListings(latestListings),
          const SizedBox(height: 14),
        ],

        ...categoryRows,
      ],
    );
  }

  // =========================
  // جسم الصفحة
  // =========================
  Widget _buildBody(double topPadding) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final Widget content;

    if (_loading) {
      content = const Padding(
        padding: EdgeInsets.symmetric(vertical: 90),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      content = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.wifi_off, size: 44),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _loadAll,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    } else {
      final user = _supabase.auth.currentUser;
      final name = (user?.userMetadata?['full_name'] as String?)?.trim();

      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isFiltering) ...[
            if (name != null && name.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'مرحباً يا $name 👋',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            _buildBannerCarousel(),
            const SizedBox(height: 16),
          ],

          _buildCategoriesSection(),

          const SizedBox(height: 8),

          if (_isFiltering) _buildSearchResults() else _buildHomeSections(),
        ],
      );
    }

    return RefreshIndicator(
      displacement: topPadding + 50,
      onRefresh: () => _loadAll(showSpinner: false),
      child: ListView(
        controller: _scrollController,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        // نحدد الحشوة صراحة حتى تبدأ الترويسة من أعلى الشاشة.
        padding: EdgeInsets.only(bottom: 112 + bottomInset),
        children: [
          _buildHeader(topPadding),
          content,
        ],
      ),
    );
  }

  // =========================
  // شريط التنقل السفلي العائم
  // =========================
  Widget _buildBottomNavigation() {
    final colorScheme = Theme.of(context).colorScheme;

    Widget navItem({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool selected = false,
    }) {
      final color = selected ? _brand : colorScheme.onSurfaceVariant;

      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: color),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              selected
                  ? Container(
                      width: 30,
                      height: 3,
                      decoration: BoxDecoration(
                        color: _brand,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    )
                  : const SizedBox(height: 3),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: SizedBox(
        height: 104,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 14,
              right: 14,
              bottom: 8,
              height: 68,
              child: Container(
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: _brand.withValues(alpha: 0.20),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    navItem(
                      icon: Icons.home_rounded,
                      label: 'الرئيسية',
                      selected: true,
                      // يصعد لأعلى الصفحة ويمسح الفلاتر.
                      onTap: _clearFilters,
                    ),
                    navItem(
                      icon: Icons.list_alt_rounded,
                      label: 'إعلاناتي',
                      onTap: _openMyListings,
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _openAddListing,
                        child: const Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: EdgeInsets.only(bottom: 9),
                            child: Text(
                              'أضف إعلان',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: _brand,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    navItem(
                      icon: Icons.favorite_border_rounded,
                      label: 'المفضلة',
                      onTap: _openFavorites,
                    ),
                    navItem(
                      icon: Icons.person_outline_rounded,
                      label: 'الملف الشخصي',
                      onTap: _openProfile,
                    ),
                  ],
                ),
              ),
            ),

            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _openAddListing,
                  child: SizedBox(
                    width: 84,
                    height: 66,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        const CustomPaint(
                          size: Size(84, 66),
                          painter: _SparklesPainter(),
                        ),
                        Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF8A5CE6), _brand],
                            ),
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: _brand.withValues(alpha: 0.40),
                                blurRadius: 14,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            size: 36,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
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
    final topPadding = MediaQuery.of(context).padding.top;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ValueListenableBuilder<bool>(
        valueListenable: _headerVisible,
        // أيقونات شريط الحالة بيضاء فوق الصورة، وداكنة بعد التمرير.
        builder: (context, headerVisible, child) {
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: (headerVisible
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
            child: child!,
          );
        },
        child: PopScope(
          // زر الرجوع يلغي التصفية أولاً قبل الخروج من التطبيق.
          canPop: !_isFiltering,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _clearFilters();
          },
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor: _pageBackground,
            extendBody: true,
            drawer: _buildDrawer(user, name),
            body: _buildBody(topPadding),
            bottomNavigationBar: _buildBottomNavigation(),
          ),
        ),
      ),
    );
  }
}

// =============================================================
// أنواع مساعدة للتصميم
// =============================================================

// وضع عرض القائمة الكاملة (عرض الكل).
enum _ListMode { home, featured, latest }

// ألوان بطاقة القسم.
class _Tone {
  final Color bg;
  final Color fg;

  const _Tone(this.bg, this.fg);
}

enum _BannerAction { addListing, browseCategories }

// شريحة في بانر العروض.
class _BannerSlide {
  final String line1;
  final String line2;
  final List<String> bullets;
  final String cta;
  final _BannerAction action;

  const _BannerSlide(
    this.line1,
    this.line2,
    this.bullets,
    this.cta,
    this.action,
  );
}

// قص الصورة داخل البانر بحافة منحنية من جهة النص.
class _PhotoClipper extends CustomClipper<Path> {
  const _PhotoClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;

    return Path()
      ..moveTo(w * 0.34, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w * 0.02, h)
      ..cubicTo(w * 0.40, h * 0.86, w * 0.02, h * 0.42, w * 0.34, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

// الخط البرتقالي المنحني على حافة الصورة.
class _SwooshPainter extends CustomPainter {
  const _SwooshPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    Path curve(double dx) {
      return Path()
        ..moveTo(w * 0.02 + dx, h)
        ..cubicTo(w * 0.40 + dx, h * 0.86, w * 0.02 + dx, h * 0.42,
            w * 0.34 + dx, 0);
    }

    canvas.drawPath(
      curve(-3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF7A45DA).withValues(alpha: 0.55),
    );

    canvas.drawPath(
      curve(-6),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xFFFF9F1C), Color(0xFFFFC93C)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      curve(-17),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// شرارات صغيرة حول زر "أضف إعلان".
class _SparklesPainter extends CustomPainter {
  const _SparklesPainter();

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
class _ShabshaScenePainter extends CustomPainter {
  const _ShabshaScenePainter();

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
