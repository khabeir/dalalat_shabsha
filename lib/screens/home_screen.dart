import 'dart:async';

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

enum _BannerAction { addListing, browseCategories }

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

enum _ListMode { home, featured, latest }

class _Tone {
  final Color bg;
  final Color fg;
  const _Tone(this.bg, this.fg);
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // =========================
  // ثوابت
  // =========================
  static const _homePageSize = 60;
  static const _categoryPageSize = 30;
  static const _searchPoolSize = 500;

  static const _cardWidth = 172.0;
  static const _cardHeight = 280.0;

  // ألوان الهوية المحسّنة
  static const _brand = Color(0xFF5B2DB5);
  static const _brandDark = Color(0xFF3B1785);
  static const _brandSoft = Color(0xFFF3EFFF);
  static const _ink = Color(0xFF1E1742);
  static const _orange = Color(0xFFFF9F1C);
  static const _gold = Color(0xFFFFC93C);

  // ارتفاع الترويسة
  static const _headerContentHeight = 200.0;

  // صور اختيارية
  static const _headerAsset = 'assets/images/home_header.jpg';
  static const _bannerAsset = 'assets/images/home_banner.jpg';

  // شرائح بانر العروض
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
      ['أقسام منظمة', 'بحث سريع', 'الأحدث أولاً'],
      'تصفح الأقسام',
      _BannerAction.browseCategories,
    ),
  ];

  static const _listingColumns =
      'id, title, description, price, currency, price_type, '
      'area, category_id, status, created_at';

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

  // حالة رؤية الترويسة
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

    _promotedRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _loadPromotedListings(),
    );

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadPromotedListings();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final isHeaderVisible = position.pixels < 110;

    if (_headerVisible.value != isHeaderVisible) {
      _headerVisible.value = isHeaderVisible;
    }

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
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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

  List<Map<String, dynamic>> get _visibleResults {
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

      setState(() => _searchPoolLoading = false);
    }
  }

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

  void _scrollToCategories() {
    final ctx = _categoriesKey.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
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

    await _loadFavorites();
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
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        child: Center(
          child: Icon(
            icon,
            size: 28,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
    _Tone(Color(0xFFEFE7FF), Color(0xFF5B2DB5)),
    _Tone(Color(0xFFFFF1D1), Color(0xFFD97706)),
    _Tone(Color(0xFFDDF5EA), Color(0xFF0D9488)),
    _Tone(Color(0xFFDFEDFF), Color(0xFF2563EB)),
    _Tone(Color(0xFFFFE3E9), Color(0xFFE11D48)),
    _Tone(Color(0xFFE2E8F0), Color(0xFF475569)),
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

  Color get _pageBackground => _isDark
      ? Theme.of(context).colorScheme.surface
      : const Color(0xFFF8F7FC);

  Color get _titleColor =>
      _isDark ? Theme.of(context).colorScheme.onSurface : _ink;

  Color get _cardColor => _isDark
      ? Theme.of(context).colorScheme.surfaceContainerHigh
      : Colors.white;

  // =========================
  // الترويسة
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
                    fontSize: 28,
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
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _brandDark,
                  shadows: glow,
                ),
              ),
            ],
          ),
        ),
        Tooltip(
          message: user == null ? 'تسجيل الدخول' : 'الملف الشخصي',
          child: GestureDetector(
            onTap: _openProfile,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                user == null
                    ? Icons.person_outline_rounded
                    : Icons.person_rounded,
                size: 25,
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
      width: 44,
      height: 50,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.location_on_rounded, size: 50, color: _brand),
          const Positioned(
            top: 11,
            child: Icon(
              Icons.shopping_cart_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                color: _gold,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_offer_rounded,
                size: 8,
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
      height: 52,
      decoration: BoxDecoration(
        color: _isDark
            ? Theme.of(context).colorScheme.surfaceContainerHigh
            : Colors.white,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: _brand.withValues(alpha: 0.14),
            blurRadius: 16,
            offset: const Offset(0, 5),
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
            style: const TextStyle(fontSize: 14.5),
            decoration: InputDecoration(
              hintText: 'ابحث عن إعلان أو منطقة ...',
              hintStyle: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 24,
                color: _brand,
              ),
              suffixIcon: value.text.isNotEmpty
                  ? IconButton(
                      onPressed: _clearSearch,
                      tooltip: 'مسح البحث',
                      icon: const Icon(Icons.close_rounded, size: 20),
                    )
                  : null,
              filled: false,
              isDense: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          );
        },
      ),
    );
  }

  // =========================
  // بانر العروض المتحرك
  // =========================
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

  Widget _buildBannerCarousel() {
    return Column(
      children: [
        SizedBox(
          height: 170,
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
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active ? _brand : _brand.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }

  Widget _buildBannerSlide(_BannerSlide slide) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final photoWidth = width * 0.48;

          return Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        Color(0xFF3B1785),
                        Color(0xFF5B2DB5),
                        Color(0xFF7A45DA),
                      ],
                    ),
                  ),
                ),
              ),
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
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.white24,
                      child: const Icon(
                        Icons.directions_car,
                        color: Colors.white,
                        size: 48,
                      ),
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
                left: 16,
                top: 12,
                bottom: 12,
                right: photoWidth - 10,
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
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
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
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: slide.bullets.map((bullet) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Row(
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
                              const SizedBox(width: 5),
                              Text(
                                bullet,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _onBannerAction(slide.action),
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFB02E), Color(0xFFFF8A00)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: _orange.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              slide.action == _BannerAction.addListing
                                  ? Icons.add_circle_outline_rounded
                                  : Icons.grid_view_rounded,
                              color: Colors.white,
                              size: 16,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              slide.cta,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                              ),
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
            Icon(icon, size: 22, color: iconColor ?? _brand),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _titleColor,
              ),
            ),
          ),
          if (onViewAll != null)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onViewAll,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'عرض الكل',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _isDark
                            ? Theme.of(context).colorScheme.primary
                            : _brand,
                      ),
                    ),
                    Icon(
                      Icons.chevron_left_rounded,
                      size: 20,
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
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? tone.fg : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: tone.fg.withValues(alpha: selected ? 0.22 : 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_filledCategoryIcon(name), size: 32, color: tone.fg),
            const SizedBox(height: 6),
            Text(
              name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
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
            height: 112,
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
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: 86,
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
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
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
    ].where((part) => part.isNotEmpty).join(' • ');

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
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: _brand.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: _cardColor,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _openListingDetails(listing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    _buildListingImage(listing, height: 120),
                    if (categoryName.isNotEmpty)
                      Positioned(
                        top: 8,
                        right: 8,
                        left: 46,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _brand.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _filledCategoryIcon(categoryName),
                                  size: 13,
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
                                      fontSize: 11,
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
                        top: 4,
                        left: 4,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _toggleFavorite(id),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.12),
                                    blurRadius: 6,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 18,
                                color: isFavorite ? Colors.red : _brand,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (isCommercial)
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _gold,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: _brandDark,
                              ),
                              SizedBox(width: 2),
                              Text(
                                'مميز',
                                style: TextStyle(
                                  fontSize: 10.5,
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
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: _titleColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _isDark
                              ? colorScheme.primary.withValues(alpha: 0.18)
                              : _brandSoft,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          priceText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isContactPrice ? 11.5 : 13.5,
                            fontWeight: FontWeight.w800,
                            color: _isDark ? colorScheme.primary : _brand,
                          ),
                        ),
                      ),
                      if (meta.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 13,
                              color: _brand,
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
                      if (isNegotiable) ...[
                        const SizedBox(height: 5),
                        Text(
                          'قابل للتفاوض',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _isDark ? colorScheme.primary : _brand,
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
      height: _cardHeight + 12,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: listings.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
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
  // نتائج البحث / القسم
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
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: _titleColor,
                  ),
                ),
              ),
              Text(
                '${results.length} إعلان',
                style: TextStyle(
                  fontSize: 12,
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
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text(
                  'إلغاء التصفية',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
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
                const Icon(Icons.search_off_outlined, size: 44),
                const SizedBox(height: 8),
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
                mainAxisSpacing: 12,
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
            Icon(Icons.inventory_2_outlined, size: 44),
            SizedBox(height: 8),
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
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionHeader(
                name,
                icon: _filledCategoryIcon(name),
                iconColor: _toneFor(name, i).fg,
                onViewAll: () => _selectCategory(categoryId),
              ),
              const SizedBox(height: 10),
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
          const SizedBox(height: 10),
          _buildHorizontalListings(promoted),
          const SizedBox(height: 12),
        ],
        if (latestListings.isNotEmpty) ...[
          _sectionHeader(
            'أحدث الإعلانات',
            icon: Icons.schedule_rounded,
            onViewAll: () => _showAll(_ListMode.latest),
          ),
          const SizedBox(height: 10),
          _buildHorizontalListings(latestListings),
          const SizedBox(height: 12),
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
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            _buildBannerCarousel(),
            const SizedBox(height: 14),
          ],
          _buildCategoriesSection(),
          const SizedBox(height: 6),
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
        padding: EdgeInsets.only(bottom: 110 + bottomInset),
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
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              selected
                  ? Container(
                      width: 24,
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
        height: 98,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 14,
              right: 14,
              bottom: 8,
              height: 64,
              child: Container(
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: _brand.withValues(alpha: 0.16),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
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
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              'أضف إعلان',
                              style: TextStyle(
                                fontSize: 11,
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
              top: 4,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _openAddListing,
                  child: SizedBox(
                    width: 80,
                    height: 62,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        const CustomPaint(
                          size: Size(80, 62),
                          painter: _SparklesPainter(),
                        ),
                        Container(
                          width: 56,
                          height: 56,
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
                                color: _brand.withValues(alpha: 0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add_rounded,
                            size: 34,
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
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              user == null ? Icons.person_outline : Icons.storefront_rounded,
              size: 26,
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
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
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
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: primary,
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
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
            ? colorScheme.primaryContainer.withValues(alpha: 0.6)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 7,
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: itemColor,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final user = _supabase.auth.currentUser;
    final name = (user?.userMetadata?['full_name'] as String?)?.trim();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _buildDrawerHeader(user, name),
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                children: [
                  _buildDrawerSectionTitle(
                      'التنقل السريع', Icons.explore_outlined),
                  _buildDrawerItem(
                    icon: Icons.home_outlined,
                    title: 'الرئيسية',
                    selected: !_isFiltering,
                    onTap: () {
                      Navigator.pop(context);
                      _clearFilters();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.add_circle_outline,
                    title: 'إضافة إعلان جديد',
                    onTap: () {
                      Navigator.pop(context);
                      _openAddListing();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.list_alt_outlined,
                    title: 'إعلاناتي',
                    onTap: () {
                      Navigator.pop(context);
                      _openMyListings();
                    },
                  ),
                  _buildDrawerItem(
                    icon: Icons.favorite_border_outlined,
                    title: 'المفضلة',
                    onTap: () {
                      Navigator.pop(context);
                      _openFavorites();
                    },
                  ),
                  const Divider(height: 18),
                  _buildDrawerSectionTitle(
                      'الحساب والضبط', Icons.person_outline),
                  _buildDrawerItem(
                    icon: Icons.account_circle_outlined,
                    title: 'الملف الشخصي',
                    onTap: () {
                      Navigator.pop(context);
                      _openProfile();
                    },
                  ),
                  if (_isAdmin)
                    _buildDrawerItem(
                      icon: Icons.admin_panel_settings_outlined,
                      title: 'لوحة الإدارة',
                      subtitle: 'إدارة الإعلانات الموقوفة والموافقة',
                      onTap: () {
                        Navigator.pop(context);
                        _openAdminPanel();
                      },
                    ),
                  if (user != null) ...[
                    const Divider(height: 18),
                    _buildDrawerItem(
                      icon: Icons.logout_rounded,
                      title: 'تسجيل الخروج',
                      isDestructive: true,
                      onTap: () {
                        Navigator.pop(context);
                        _signOut();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ValueListenableBuilder<bool>(
        valueListenable: _headerVisible,
        builder: (context, headerVisible, _) {
          final overlayStyle = headerVisible
              ? SystemUiOverlayStyle.dark.copyWith(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.dark,
                )
              : (isDark
                  ? SystemUiOverlayStyle.light.copyWith(
                      statusBarColor: Colors.transparent,
                    )
                  : SystemUiOverlayStyle.dark.copyWith(
                      statusBarColor: Colors.transparent,
                    ));

          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: overlayStyle,
            child: Scaffold(
              key: _scaffoldKey,
              backgroundColor: _pageBackground,
              drawer: _buildDrawer(),
              body: Stack(
                children: [
                  _buildBody(topPadding),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildBottomNavigation(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =========================
// الرسومات والتصميم الخارجي
// =========================
class _PhotoClipper extends CustomClipper<Path> {
  const _PhotoClipper();

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

class _SwooshPainter extends CustomPainter {
  const _SwooshPainter();

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

class _ShabshaScenePainter extends CustomPainter {
  const _ShabshaScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFEFE9FF);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final hillPaint = Paint()..color = const Color(0xFFDCD2F9);
    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(
        size.width * 0.3,
        size.height * 0.6,
        size.width * 0.7,
        size.height * 0.8,
      )
      ..quadraticBezierTo(
        size.width * 0.85,
        size.height * 0.9,
        size.width,
        size.height * 0.7,
      )
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, hillPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SparklesPainter extends CustomPainter {
  const _SparklesPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFFC93C).withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.3), 3, paint);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.25), 3.5, paint);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.7), 2.5, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
