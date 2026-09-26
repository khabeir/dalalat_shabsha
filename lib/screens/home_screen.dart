//home screen
//==================================
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/widgets/home_loading.dart';
import '../core/widgets/home_bottom_navigation.dart';
import '../core/widgets/categories_section.dart';
import '../core/widgets/listing_section.dart';
import '../core/theme/app_colors.dart';
import '../core/widgets/home_banner.dart';
import '../core/widgets/home_drawer.dart';
import '../core/widgets/listing_card.dart';
import '../core/widgets/home_header.dart';

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

  bool _loading = true;
  bool _listingsLoading = false;
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

  _ListMode _mode = _ListMode.home;

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  bool get _isFiltering =>
      _isSearching ||
      _selectedCategoryId != null ||
      _mode != _ListMode.home;

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

    // تحديث الإعلانات التجارية كل 5 دقائق.
    _promotedRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _loadPromotedListings(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _promotedRefreshTimer?.cancel();
    _headerVisible.dispose();
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPromotedListings();
    }
  }

  // =========================
  // التمرير
  // =========================
  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;

    _headerVisible.value = position.pixels < 110;

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

  void _scrollToCategories() {
    final targetContext = _categoriesKey.currentContext;

    if (targetContext == null) return;

    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      alignment: 0.08,
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

    _debounce = Timer(
      const Duration(milliseconds: 300),
      () {
        if (!mounted) return;

        setState(() => _searchQuery = value);

        if (value.trim().isNotEmpty) {
          _ensureSearchPool();
        }
      },
    );
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();

    setState(() => _searchQuery = '');
  }

  List<Map<String, dynamic>> get _visibleResults {
    if (_mode == _ListMode.featured &&
        _selectedCategoryId == null &&
        !_isSearching) {
      return _activePromoted;
    }

    final query = _normalizeSearchText(_searchQuery);

    final source =
        query.isEmpty ? _listings : (_searchPool ?? _listings);

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

      setState(() => _searchPoolLoading = false);
    }
  }

  List<Map<String, dynamic>> get _activePromoted {
    final now = DateTime.now().toUtc();

    return _promotedListings.where((listing) {
      final end =
          DateTime.tryParse('${listing['promotion_end_at']}');

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

    _searchPool = null;

    try {
      await Future.wait([
        _loadCategories(),
        _loadListings(),
        _loadPromotedListings(),
        _loadFavorites(),
      ]);

      if (mounted) {
        setState(() => _error = null);
      }
    } catch (e) {
      debugPrint('loadAll error: $e');

      if (mounted) {
        if (_listings.isEmpty) {
          setState(() {
            _error =
                'تعذر تحميل البيانات. تحقق من اتصال الإنترنت وحاول مجدداً.';
          });
        } else {
          _showSnack(
            'تعذر تحديث البيانات، تحقق من اتصال الإنترنت',
          );
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
      _categories =
          List<Map<String, dynamic>>.from(response);
    });
  }

  int _pageSizeFor(int? categoryId) {
    return categoryId == null
        ? _homePageSize
        : _categoryPageSize;
  }

  Future<void> _loadListings({bool reset = true}) async {
    if (!reset &&
        (_loadingMore || !_hasMore || _listingsLoading)) {
      return;
    }

    final requestId =
        reset ? ++_listingsRequestId : _listingsRequestId;

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

      if (!mounted || requestId != _listingsRequestId) {
        return;
      }

      setState(() {
        _listings = reset
            ? rows
            : [..._listings, ...rows];

        _page = page + 1;
        _hasMore = rows.length == pageSize;
        _loadingMore = false;
        _listingsLoading = false;
      });
    } catch (e) {
      debugPrint('loadListings error: $e');

      if (!mounted || requestId != _listingsRequestId) {
        return;
      }

      setState(() {
        _loadingMore = false;
        _listingsLoading = false;
      });

      if (reset) rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchListings({
    required int from,
    required int to,
    int? categoryId,
  }) async {
    try {
      var query = _supabase
          .from('listings')
          .select(
            '$_listingColumns, '
            'listing_images(image_path, sort_order)',
          )
          .eq('status', 'approved');

      if (categoryId != null) {
        query = query.eq(
          'category_id',
          categoryId,
        );
      }

      final response = await query
          .order(
            'created_at',
            ascending: false,
          )
          .order(
            'sort_order',
            referencedTable: 'listing_images',
          )
          .limit(
            1,
            referencedTable: 'listing_images',
          )
          .range(from, to);

      return List<Map<String, dynamic>>.from(response)
          .map(_prepareListing)
          .toList();
    } catch (e) {
      debugPrint(
        'embedded images query failed, using fallback: $e',
      );

      var query = _supabase
          .from('listings')
          .select(_listingColumns)
          .eq('status', 'approved');

      if (categoryId != null) {
        query = query.eq(
          'category_id',
          categoryId,
        );
      }

      final response = await query
          .order(
            'created_at',
            ascending: false,
          )
          .range(from, to);

      final rows =
          List<Map<String, dynamic>>.from(response);

      await _attachCoverImages(rows);

      return rows.map(_prepareListing).toList();
    }
  }

  Map<String, dynamic> _prepareListing(
    Map<String, dynamic> row,
  ) {
    final images = row['listing_images'];

    if (images is List &&
        images.isNotEmpty &&
        images.first is Map) {
      row['image_path'] =
          (images.first as Map)['image_path'];
    }

    row['_search'] = _normalizeSearchText(
      '${row['title'] ?? ''} '
      '${row['description'] ?? ''} '
      '${row['area'] ?? ''}',
    );

    return row;
  }

  Future<void> _attachCoverImages(
    List<Map<String, dynamic>> rows,
  ) async {
    final ids = rows
        .map((row) => row['id'])
        .where((id) => id != null)
        .toList();

    if (ids.isEmpty) return;

    final response = await _supabase
        .from('listing_images')
        .select(
          'listing_id, image_path, sort_order',
        )
        .inFilter('listing_id', ids)
        .order('sort_order');

    final covers = <dynamic, dynamic>{};

    for (final image
        in List<Map<String, dynamic>>.from(response)) {
      covers.putIfAbsent(
        image['listing_id'],
        () => image['image_path'],
      );
    }

    for (final row in rows) {
      final path = covers[row['id']];

      if (path != null) {
        row['image_path'] = path;
      }
    }
  }

  Future<void> _loadPromotedListings() async {
    try {
      final now =
          DateTime.now().toUtc().toIso8601String();

      final promotedResponse = await _supabase
          .from('promoted_listings')
          .select(
            'id, listing_id, start_at, end_at, '
            'is_active, created_by',
          )
          .eq('is_active', true)
          .lte('start_at', now)
          .gt('end_at', now)
          .order(
            'start_at',
            ascending: false,
          );

      final promotedRows =
          List<Map<String, dynamic>>.from(
        promotedResponse,
      );

      final listingIds = promotedRows
          .map((item) => item['listing_id'])
          .where((id) => id != null)
          .toList();

      if (listingIds.isEmpty) {
        if (mounted) {
          setState(() => _promotedListings = []);
        }

        return;
      }

      final listingsResponse = await _supabase
          .from('listings')
          .select(_listingColumns)
          .inFilter('id', listingIds)
          .eq('status', 'approved');

      final listingsById =
          <dynamic, Map<String, dynamic>>{};

      for (final listing
          in List<Map<String, dynamic>>.from(
        listingsResponse,
      )) {
        listingsById[listing['id']] = listing;
      }

      final result = <Map<String, dynamic>>[];

      for (final promoted in promotedRows) {
        final listing =
            listingsById[promoted['listing_id']];

        if (listing == null) continue;

        final item =
            Map<String, dynamic>.from(listing);

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

      await _attachCoverImages(result);

      if (!mounted) return;

      setState(() => _promotedListings = result);
    } catch (e) {
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

      setState(() {
        _isAdmin = profile?['role'] == 'admin';
      });
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

    if (clearSearch) {
      _searchController.clear();
    }

    setState(() {
      _mode = _ListMode.home;
      _selectedCategoryId = id;
      _listingsLoading = true;

      if (clearSearch) {
        _searchQuery = '';
      }
    });

    _scrollToTop();

    try {
      await _loadListings();
    } catch (_) {
      _showSnack(
        'تعذر تحميل الإعلانات، حاول مرة أخرى',
      );
    }
  }

  Future<void> _clearFilters() async {
    final hadCategory =
        _selectedCategoryId != null;

    _debounce?.cancel();
    _searchController.clear();

    setState(() {
      _mode = _ListMode.home;
      _searchQuery = '';
      _selectedCategoryId = null;

      if (hadCategory) {
        _listingsLoading = true;
      }
    });

    _scrollToTop();

    if (!hadCategory) return;

    try {
      await _loadListings();
    } catch (_) {
      _showSnack(
        'تعذر تحميل الإعلانات، حاول مرة أخرى',
      );
    }
  }

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
        if (mounted) {
          setState(() => _favoriteIds = {});
        }

        return;
      }

      final rows = await _supabase
          .from(_favoritesTable)
          .select(_favListingColumn)
          .eq(_favUserColumn, user.id);

      final ids = <int>{};

      for (final row in rows) {
        final value = row[_favListingColumn];

        if (value is num) {
          ids.add(value.toInt());
        }
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

    final wasFavorite =
        _favoriteIds.contains(listingId);

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
            .eq(
              _favListingColumn,
              listingId,
            );
      } else {
        await _supabase
            .from(_favoritesTable)
            .insert({
          _favUserColumn: user.id,
          _favListingColumn: listingId,
        });
      }
    } catch (e) {
      debugPrint('toggleFavorite error: $e');

      if (!mounted) return;

      setState(() {
        if (wasFavorite) {
          _favoriteIds.add(listingId);
        } else {
          _favoriteIds.remove(listingId);
        }
      });

      _showSnack(
        'تعذر تحديث المفضلة، حاول مرة أخرى',
      );
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
      _showSnack(
        'تعذر تسجيل الخروج، حاول مرة أخرى',
      );
    }
  }

  Future<bool> _ensureSignedIn() async {
    if (_supabase.auth.currentUser != null) {
      return true;
    }

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

  Future<void> _openListingDetails(
    Map<String, dynamic> listing,
  ) async {
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

    await _loadFavorites();
  }

  // =========================
  // تنسيق السعر والوقت
  // =========================
  String _formatPrice(
    Map<String, dynamic> listing,
  ) {
    final price = listing['price'];

    final currency =
        (listing['currency']
                    ?.toString()
                    .trim()
                    .isNotEmpty ??
                false)
            ? listing['currency']
                .toString()
                .trim()
            : 'SDG';

    final priceType =
        listing['price_type']
                ?.toString()
                .trim() ??
            '';

    if (priceType == 'contact' || price == null) {
      return 'السعر عند التواصل';
    }

    final number =
        num.tryParse(price.toString());

    if (number == null) {
      return '$price $currency';
    }

    return '${_numberFormat.format(number)} $currency';
  }

  String _timeAgo(dynamic value) {
    final date =
        DateTime.tryParse(
          value?.toString() ?? '',
        )?.toLocal();

    if (date == null) return '';

    final diff =
        DateTime.now().difference(date);

    if (diff.inMinutes < 1) return 'الآن';

    if (diff.inMinutes < 60) {
      return 'قبل ${diff.inMinutes} د';
    }

    if (diff.inHours < 24) {
      return 'قبل ${diff.inHours} س';
    }

    if (diff.inDays < 30) {
      return 'قبل ${diff.inDays} يوم';
    }

    return 'قبل ${diff.inDays ~/ 30} شهر';
  }

  // =========================
  // الصور
  // =========================
  String? _imageUrl(dynamic imagePath) {
    if (imagePath == null) return null;

    final path =
        imagePath.toString().trim();

    if (path.isEmpty) return null;

    if (path.startsWith('http://') ||
        path.startsWith('https://')) {
      return path;
    }

    return _supabase.storage
        .from('listing-images')
        .getPublicUrl(path);
  }

  // =========================
  // ألوان وأيقونات الأقسام
  // =========================
  static const _tones = <_Tone>[
    _Tone(
      Color(0xFFEFE7FF),
      Color(0xFF5B2DB5),
    ),
    _Tone(
      Color(0xFFFFF1D1),
      Color(0xFFF59E0B),
    ),
    _Tone(
      Color(0xFFDDF5EA),
      Color(0xFF0F9D7A),
    ),
    _Tone(
      Color(0xFFDFEDFF),
      Color(0xFF2563EB),
    ),
    _Tone(
      Color(0xFFFFE3E9),
      Color(0xFFE11D48),
    ),
    _Tone(
      Color(0xFFE9EEF5),
      Color(0xFF475569),
    ),
  ];

  _Tone _toneFor(
    String name,
    int index,
  ) {
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

  IconData _filledCategoryIcon(
    String name,
  ) {
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

  Map<String, dynamic>? _categoryById(
    dynamic id,
  ) {
    for (final category in _categories) {
      if (category['id'] == id) {
        return category;
      }
    }

    return null;
  }

  // =========================
  // ألوان الصفحة
  // =========================
  bool get _isDark =>
      Theme.of(context).brightness ==
      Brightness.dark;

  Color get _pageBackground =>
      Color.alphaBlend(
        AppColors.brand.withValues(
          alpha: _isDark ? 0.06 : 0.045,
        ),
        Theme.of(context)
            .colorScheme
            .surface,
      );

  Color get _titleColor =>
      _isDark
          ? Theme.of(context)
              .colorScheme
              .onSurface
          : AppColors.ink;

  Color get _cardColor => _isDark
      ? Theme.of(context)
          .colorScheme
          .surfaceContainerHigh
      : Colors.white;

  // =========================
  // الترويسة
  // =========================
  Widget _buildHeader(
    double topPadding,
  ) {
    final user =
        _supabase.auth.currentUser;

    return HomeHeader(
      topPadding: topPadding,
      isDark: _isDark,
      pageBackground: _pageBackground,
      titleColor: _titleColor,
      searchController: _searchController,
      isSignedIn: user != null,
      onOpenDrawer: () {
        _scaffoldKey.currentState
            ?.openDrawer();
      },
      onProfile: _openProfile,
      onSearchChanged: _onSearchChanged,
      onClearSearch: _clearSearch,
    );
  }

  // =========================
  // بانر العروض المتحرك
  // =========================
  Widget _buildBannerCarousel() {
    return HomeBanner(
      onAddListing: () {
        _openAddListing();
      },
      onBrowseCategories:
          _scrollToCategories,
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
    final id = listing['id'] as int?;

    final category =
        _categoryById(
      listing['category_id'],
    );

    final categoryName =
        category?['name']?.toString() ?? '';

    return ListingCard(
      listing: listing,
      imageUrl: _imageUrl(
        listing['image_path'],
      ),
      width: fillWidth
          ? double.infinity
          : _cardWidth,
      isCommercial: isCommercial,
      isFavorite: id != null &&
          _favoriteIds.contains(id),
      categoryName: categoryName,
      isDark: _isDark,
      cardColor: _cardColor,
      titleColor: _titleColor,
      onTap: () =>
          _openListingDetails(listing),
      onToggleFavorite: id == null
          ? null
          : () => _toggleFavorite(id),
      categoryIcon:
          _filledCategoryIcon(
        categoryName,
      ),
      formatPrice:
          _formatPrice(listing),
      timeAgo:
          _timeAgo(listing['created_at']),
    );
  }

  // =========================
  // نتائج البحث / القسم / عرض الكل
  // =========================
  Widget _buildSearchResults() {
    final colorScheme =
        Theme.of(context).colorScheme;

    final results = _visibleResults;

    final promotedIds =
        _activePromoted
            .map(
              (listing) => listing['id'],
            )
            .toSet();

    final showSpinner =
        _listingsLoading ||
        (_isSearching &&
            _searchPoolLoading);

    final String title;

    if (_isSearching) {
      title = 'نتائج البحث';
    } else if (_selectedCategoryId != null) {
      title =
          _selectedCategoryName ??
          'إعلانات القسم';
    } else if (_mode ==
        _ListMode.featured) {
      title = 'إعلانات مميزة';
    } else {
      title = 'أحدث الإعلانات';
    }

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 16,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight:
                        FontWeight.w900,
                    color: _titleColor,
                  ),
                ),
              ),
              Text(
                '${results.length} إعلان',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colorScheme
                      .onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 6),
              TextButton.icon(
                onPressed:
                    _clearFilters,
                style: TextButton.styleFrom(
                  visualDensity:
                      VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 8,
                  ),
                ),
                icon: const Icon(
                  Icons.close_rounded,
                  size: 17,
                ),
                label: const Text(
                  'إلغاء التصفية',
                  style: TextStyle(
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (showSpinner &&
            results.isEmpty)
          const Padding(
            padding:
                EdgeInsets.symmetric(
              vertical: 40,
            ),
            child: const HomeLoading(),
          )
        else if (results.isEmpty)
          Padding(
            padding:
                const EdgeInsets.symmetric(
              vertical: 35,
              horizontal: 16,
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.search_off_outlined,
                  size: 48,
                ),
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
            padding:
                const EdgeInsets.symmetric(
              horizontal: 16,
            ),
            child: GridView.builder(
              shrinkWrap: true,
              physics:
                  const NeverScrollableScrollPhysics(),
              itemCount: results.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                mainAxisExtent:
                    _cardHeight,
              ),
              itemBuilder:
                  (context, index) {
                final listing =
                    results[index];

                return _buildListingCard(
                  listing,
                  fillWidth: true,
                  isCommercial:
                      promotedIds.contains(
                    listing['id'],
                  ),
                );
              },
            ),
          ),
        if (_loadingMore)
          const Padding(
            padding: EdgeInsets.all(16),
            child: const HomeLoading(),
            ),
          ),
      ],
    );
  }

  // =========================
  // جسم الصفحة
  // =========================
  Widget _buildBody(
    double topPadding,
  ) {
    final bottomInset =
        MediaQuery.of(context)
            .padding
            .bottom;

    final Widget content;

    if (_loading) {
      content = const Padding(
        padding:
            EdgeInsets.symmetric(
          vertical: 90,
        ),
        child: const HomeLoading(),
      );
    } else if (_error != null) {
      content = Padding(
        padding:
            const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.wifi_off,
              size: 44,
            ),
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign:
                  TextAlign.center,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _loadAll,
              child: const Text(
                'إعادة المحاولة',
              ),
            ),
          ],
        ),
      );
    } else {
      final user =
          _supabase.auth.currentUser;

      final name =
          (user?.userMetadata?[
                      'full_name']
                  as String?)
              ?.trim();

      content = Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          if (!_isFiltering) ...[
            if (name != null &&
                name.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  20,
                  0,
                  20,
                  8,
                ),
                child: Text(
                  'مرحباً يا $name 👋',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant,
                  ),
                ),
              ),
            _buildBannerCarousel(),
            const SizedBox(height: 16),
          ],

          CategoriesSection(
            sectionKey:
                _categoriesKey,
            categories: _categories,
            selectedCategoryId:
                _selectedCategoryId,
            isDark: _isDark,
            titleColor: _titleColor,
            categoryIcon:
                _filledCategoryIcon,
            categoryColor:
                (name, index) {
              return _toneFor(
                name,
                index,
              ).fg;
            },
            onSelectCategory:
                (categoryId) {
              if (categoryId < 0) {
                _selectCategory(null);
              } else {
                _selectCategory(
                  categoryId,
                  clearSearch: true,
                );
              }
            },
          ),

          const SizedBox(height: 8),

          if (_isFiltering)
            _buildSearchResults()
          else
            ListingSection(
              loading:
                  _listingsLoading,
              promotedListings:
                  _activePromoted,
              listings: _listings,
              categories: _categories,
              isDark: _isDark,
              titleColor:
                  _titleColor,
              cardHeight:
                  _cardHeight,
              buildListingCard: (
                listing, {
                bool isCommercial =
                    false,
              }) {
                return _buildListingCard(
                  listing,
                  isCommercial:
                      isCommercial,
                );
              },
              categoryIcon:
                  _filledCategoryIcon,
              categoryColor:
                  (name, index) {
                return _toneFor(
                  name,
                  index,
                ).fg;
              },
              onShowFeatured: () {
                _showAll(
                  _ListMode.featured,
                );
              },
              onShowLatest: () {
                _showAll(
                  _ListMode.latest,
                );
              },
              onSelectCategory:
                  (categoryId) {
                _selectCategory(
                  categoryId,
                );
              },
            ),
        ],
      );
    }

    return RefreshIndicator(
      displacement:
          topPadding + 50,
      onRefresh: () =>
          _loadAll(
        showSpinner: false,
      ),
      child: ListView(
        controller:
            _scrollController,
        keyboardDismissBehavior:
            ScrollViewKeyboardDismissBehavior
                .onDrag,
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          bottom: 112 + bottomInset,
        ),
        children: [
          _buildHeader(
            topPadding,
          ),
          content,
        ],
      ),
    );
  }

  // =========================
  // البناء
  // =========================
  @override
  Widget build(
    BuildContext context,
  ) {
    final user =
        _supabase.auth.currentUser;

    final name =
        user?.userMetadata?[
            'full_name'] as String?;

    final topPadding =
        MediaQuery.of(context)
            .padding
            .top;

    return Directionality(
      textDirection:
          TextDirection.rtl,
      child:
          ValueListenableBuilder<bool>(
        valueListenable:
            _headerVisible,
        builder: (
          context,
          headerVisible,
          child,
        ) {
          return AnnotatedRegion<
              SystemUiOverlayStyle>(
            value: (headerVisible
                    ? SystemUiOverlayStyle
                        .light
                    : SystemUiOverlayStyle
                        .dark)
                .copyWith(
              statusBarColor:
                  Colors.transparent,
            ),
            child: child!,
          );
        },
        child: PopScope(
          canPop: !_isFiltering,
          onPopInvokedWithResult:
              (didPop, _) {
            if (!didPop) {
              _clearFilters();
            }
          },
          child: Scaffold(
            key: _scaffoldKey,
            backgroundColor:
                _pageBackground,
            extendBody: true,
            drawer: HomeDrawer(
              user: user,
              name: name,
              isAdmin: _isAdmin,
              categories:
                  _categories,
              selectedCategoryId:
                  _selectedCategoryId,
              onProfile:
                  _openProfile,
              onAddListing:
                  _openAddListing,
              onAdminPanel:
                  _openAdminPanel,
              onSelectCategory:
                  (categoryId) {
                _selectCategory(
                  categoryId,
                  clearSearch: true,
                );
              },
              onFavorites:
                  _openFavorites,
              onMyListings:
                  _openMyListings,
              onSignOut:
                  _signOut,
            ),
            body: _buildBody(
              topPadding,
            ),
            bottomNavigationBar:
    HomeBottomNavigation(
  isDark: _isDark,
  cardColor: _cardColor,
  onHome: _clearFilters,
  onMyListings: _openMyListings,
  onAddListing: _openAddListing,
  onFavorites: _openFavorites,
  onProfile: _openProfile,
),
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
enum _ListMode {
  home,
  featured,
  latest,
}

// ألوان بطاقة القسم.
class _Tone {
  final Color bg;
  final Color fg;

  const _Tone(
    this.bg,
    this.fg,
  );
}