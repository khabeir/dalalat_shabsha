import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_decorations.dart';
import 'auth_screen.dart';

class ListingDetailsScreen extends StatefulWidget {
  final int listingId;

  const ListingDetailsScreen({
    super.key,
    required this.listingId,
  });

  @override
  State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
  static final _numberFormat = NumberFormat('#,##0.##', 'en');

  static const _whatsappGreen = Color(0xFF25D366);
  static const _defaultCountryCode = '249';

  final _supabase = Supabase.instance.client;
  final _pageController = PageController();

  Map<String, dynamic>? _listing;
  List<Map<String, dynamic>> _images = [];
  List<Map<String, dynamic>> _similar = [];

  String? _categoryName;
  String? _sellerName;
  int? _sellerAdsCount;

  int _currentImageIndex = 0;

  bool _loading = true;
  bool _favorite = false;
  bool _favoriteBusy = false;
  bool _isCommercial = false;
  bool _descriptionExpanded = false;

  String? _error;

  @override
  void initState() {
    super.initState();
    _loadListing();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // =========================
  // أدوات مساعدة
  // =========================

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
  }

  bool get _isOwner {
    final user = _supabase.auth.currentUser;
    return user != null && user.id == _listing?['seller_id']?.toString();
  }

  String _timeAgo(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    if (date == null) return '';

    final diff = DateTime.now().difference(date);

    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} ساعة';
    if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';

    return 'قبل ${diff.inDays ~/ 30} شهر';
  }

  String _priceLabel(Map<String, dynamic> listing) {
    final price = listing['price'];

    final currency =
        listing['currency']?.toString().trim().isNotEmpty == true
            ? listing['currency'].toString().trim()
            : 'SDG';

    if (listing['price_type'] == 'contact' || price == null) {
      return 'السعر عند التواصل';
    }

    final number = num.tryParse(price.toString());

    if (number == null) {
      return '$price $currency';
    }

    return '${_numberFormat.format(number)} $currency';
  }

  String _conditionText() {
    switch (_listing?['condition']) {
      case 'new':
        return 'جديد';
      case 'used':
        return 'مستعمل';
      default:
        return 'غير محدد';
    }
  }

  String _statusMessage(String? status) {
    switch (status) {
      case 'pending':
        return 'هذا الإعلان قيد المراجعة ولا يظهر للآخرين بعد.';
      case 'rejected':
        return 'تم رفض هذا الإعلان من الإدارة.';
      case 'sold':
        return 'تم بيع هذا المنتج.';
      case 'archived':
        return 'هذا الإعلان مؤرشف.';
      default:
        return '';
    }
  }

  String _imageUrl(String path) {
    final cleanPath = path.trim();

    if (cleanPath.isEmpty) return '';

    if (cleanPath.startsWith('http://') ||
        cleanPath.startsWith('https://')) {
      return cleanPath;
    }

    return _supabase.storage
        .from('listing-images')
        .getPublicUrl(cleanPath);
  }

  String _toWesternDigits(String input) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final buffer = StringBuffer();

    for (final char in input.split('')) {
      final index = arabic.indexOf(char);
      buffer.write(index == -1 ? char : index.toString());
    }

    return buffer.toString();
  }

  String? _whatsappNumber(String phone) {
    var digits =
        _toWesternDigits(phone).replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0')) {
      digits = '$_defaultCountryCode${digits.substring(1)}';
    } else if (digits.length == 9) {
      digits = '$_defaultCountryCode$digits';
    }

    return digits.length < 8 ? null : digits;
  }

  // =========================
  // تحميل البيانات
  // =========================

  Future<void> _loadListing({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }

    try {
      final results = await Future.wait<Object?>([
        _supabase
            .from('listings')
            .select(
              'id, seller_id, category_id, title, description, price, '
              'currency, price_type, condition, area, contact_phone, '
              'status, created_at',
            )
            .eq('id', widget.listingId)
            .single(),
        _fetchImages(),
        _checkCommercial(),
        _checkFavorite(),
      ]);

      final listing = Map<String, dynamic>.from(results[0] as Map);

      if (!mounted) return;

      setState(() {
        _listing = listing;
        _images = results[1] as List<Map<String, dynamic>>;
        _isCommercial = results[2] as bool;
        _favorite = results[3] as bool;
        _loading = false;
        _error = null;
        _currentImageIndex = 0;
        _descriptionExpanded = false;
      });

      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }

      _loadExtras(listing);
    } catch (e) {
      debugPrint('loadListing error: $e');

      if (!mounted) return;

      if (_listing != null) {
        _showSnack('تعذر تحديث الإعلان');
        return;
      }

      setState(() {
        _error = 'تعذر تحميل تفاصيل الإعلان.';
        _loading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _fetchImages() async {
    final response = await _supabase
        .from('listing_images')
        .select('id, image_path, sort_order')
        .eq('listing_id', widget.listingId)
        .order('sort_order');

    return List<Map<String, dynamic>>.from(response);
  }

  Future<bool> _checkCommercial() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      final promotion = await _supabase
          .from('promoted_listings')
          .select('id')
          .eq('listing_id', widget.listingId)
          .eq('is_active', true)
          .lte('start_at', now)
          .gt('end_at', now)
          .limit(1);

      return promotion.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkFavorite() async {
    try {
      final user = _supabase.auth.currentUser;

      if (user == null) return false;

      final result = await _supabase
          .from('favorites')
          .select('listing_id')
          .eq('user_id', user.id)
          .eq('listing_id', widget.listingId);

      return result.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadExtras(Map<String, dynamic> listing) async {
    final categoryId = listing['category_id'];
    final sellerId = listing['seller_id'];

    await Future.wait([
      _loadCategoryName(categoryId),
      _loadSeller(sellerId),
      _loadSimilar(categoryId),
    ]);
  }

  Future<void> _loadCategoryName(dynamic categoryId) async {
    if (categoryId == null) return;

    try {
      final category = await _supabase
          .from('categories')
          .select('name')
          .eq('id', categoryId)
          .maybeSingle();

      if (!mounted) return;

      setState(
        () => _categoryName = category?['name']?.toString(),
      );
    } catch (e) {
      debugPrint('loadCategoryName error: $e');
    }
  }

  Future<void> _loadSeller(dynamic sellerId) async {
    if (sellerId == null) return;

    try {
      final result = await _supabase.rpc(
        'get_seller_name',
        params: {'p_seller_id': sellerId},
      );

      final name = result?.toString().trim();

      if (!mounted) return;

      if (name != null && name.isNotEmpty) {
        setState(() => _sellerName = name);
      }
    } catch (e) {
      debugPrint('loadSellerName error: $e');
    }

    try {
      final ads = await _supabase
          .from('listings')
          .select('id')
          .eq('seller_id', sellerId)
          .eq('status', 'approved');

      if (!mounted) return;

      setState(() => _sellerAdsCount = ads.length);
    } catch (e) {
      debugPrint('loadSellerAds error: $e');
    }
  }

  Future<void> _loadSimilar(dynamic categoryId) async {
    if (categoryId == null) return;

    try {
      final response = await _supabase
          .from('listings')
          .select(
            'id, title, price, currency, price_type, area',
          )
          .eq('status', 'approved')
          .eq('category_id', categoryId)
          .neq('id', widget.listingId)
          .order('created_at', ascending: false)
          .limit(8);

      final rows = List<Map<String, dynamic>>.from(response);

      if (rows.isEmpty) return;

      final ids = rows.map((row) => row['id']).toList();

      final imagesResponse = await _supabase
          .from('listing_images')
          .select('listing_id, image_path, sort_order')
          .inFilter('listing_id', ids)
          .order('sort_order');

      final covers = <dynamic, dynamic>{};

      for (final image
          in List<Map<String, dynamic>>.from(imagesResponse)) {
        covers.putIfAbsent(
          image['listing_id'],
          () => image['image_path'],
        );
      }

      for (final row in rows) {
        row['image_path'] = covers[row['id']];
      }

      if (!mounted) return;

      setState(() => _similar = rows);
    } catch (e) {
      debugPrint('loadSimilar error: $e');
    }
  }

  // =========================
  // مصادقة وتفاعل
  // =========================

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
      final favorite = await _checkFavorite();

      if (!mounted) return false;

      setState(() => _favorite = favorite);

      return true;
    }

    return false;
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteBusy) return;

    if (!await _ensureSignedIn()) return;

    final user = _supabase.auth.currentUser;

    if (user == null) return;

    final wasFavorite = _favorite;

    setState(() {
      _favorite = !wasFavorite;
      _favoriteBusy = true;
    });

    try {
      if (wasFavorite) {
        await _supabase
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('listing_id', widget.listingId);
      } else {
        await _supabase.from('favorites').insert({
          'user_id': user.id,
          'listing_id': widget.listingId,
        });
      }
    } catch (e) {
      debugPrint('toggleFavorite error: $e');

      if (mounted) {
        setState(() => _favorite = wasFavorite);
        _showSnack('تعذر تحديث المفضلة');
      }
    }

    if (mounted) {
      setState(() => _favoriteBusy = false);
    }
  }

  Future<void> _callSeller() async {
    final phone =
        _listing?['contact_phone']?.toString().trim();

    if (phone == null || phone.isEmpty) {
      _showSnack('رقم التواصل غير متوفر');
      return;
    }

    final cleaned = _toWesternDigits(phone)
        .replaceAll(RegExp(r'[^0-9+]'), '');

    try {
      final launched = await launchUrl(
        Uri(
          scheme: 'tel',
          path: cleaned,
        ),
      );

      if (!launched) {
        _showSnack('تعذر فتح تطبيق الاتصال');
      }
    } catch (_) {
      _showSnack('تعذر فتح تطبيق الاتصال');
    }
  }

  Future<void> _openWhatsApp() async {
    final phone =
        _listing?['contact_phone']?.toString().trim();

    if (phone == null || phone.isEmpty) {
      _showSnack('رقم التواصل غير متوفر');
      return;
    }

    final number = _whatsappNumber(phone);

    if (number == null) {
      _showSnack('رقم التواصل غير صالح لواتساب');
      return;
    }

    final title =
        _listing?['title']?.toString().trim() ?? '';

    final message = title.isEmpty
        ? 'مرحباً، رأيت إعلانك في تطبيق دلالة شبشة.'
        : 'مرحباً، رأيت إعلانك "$title" في تطبيق دلالة شبشة. هل ما زال متاحاً؟';

    final uri = Uri(
      scheme: 'https',
      host: 'wa.me',
      path: '/$number',
      queryParameters: {'text': message},
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _showSnack('تعذر فتح واتساب');
      }
    } catch (_) {
      _showSnack('تعذر فتح واتساب');
    }
  }

  Future<void> _shareListing() async {
    final listing = _listing;

    if (listing == null) return;

    final title =
        listing['title']?.toString().trim() ?? '';

    final area =
        listing['area']?.toString().trim() ?? '';

    final text = [
      if (title.isNotEmpty) title,
      _priceLabel(listing),
      if (area.isNotEmpty) 'المنطقة: $area',
      '',
      'شاهد الإعلان في تطبيق دلالة شبشة',
    ].join('\n');

    final uri = Uri(
      scheme: 'https',
      host: 'wa.me',
      path: '/',
      queryParameters: {'text': text},
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        _showSnack('تعذر فتح واتساب للمشاركة');
      }
    } catch (_) {
      _showSnack('تعذر فتح واتساب للمشاركة');
    }
  }

  Future<void> _reportListing() async {
    if (!await _ensureSignedIn()) return;

    final user = _supabase.auth.currentUser;

    if (user == null || !mounted) return;

    final result =
        await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReportSheet(),
    );

    final reason =
        result?['reason']?.trim() ?? '';

    final details =
        result?['details']?.trim() ?? '';

    if (reason.isEmpty) return;

    try {
      await _supabase.from('reports').insert({
        'reporter_id': user.id,
        'listing_id': widget.listingId,
        'reason': reason,
        'details': details.isEmpty ? null : details,
      });

      _showSnack(
        'تم إرسال البلاغ للمراجعة، شكراً لك',
      );
    } catch (e) {
      debugPrint('report error: $e');
      _showSnack('تعذر إرسال البلاغ');
    }
  }

  // =========================
  // الصور
  // =========================

  List<String> get _imageUrls {
    return _images
        .map(
          (image) => _imageUrl(
            image['image_path']?.toString() ?? '',
          ),
        )
        .where((url) => url.isNotEmpty)
        .toList();
  }

  void _openFullScreenGallery(int index) {
    final urls = _imageUrls;

    if (urls.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullScreenGallery(
          urls: urls,
          initialIndex: index.clamp(0, urls.length - 1),
          listingId: widget.listingId,
        ),
      ),
    );
  }

  Widget _imagePlaceholder({
    IconData icon = Icons.image_outlined,
    String? message,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: AppColors.brandSoft,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: AppColors.brand,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _networkImage(
    String url, {
    int memCacheWidth = 900,
    String? heroTag,
  }) {
    Widget image = CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      memCacheWidth: memCacheWidth,
      placeholder: (_, __) => Container(
        color: AppColors.brandSoft,
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.brand,
          ),
        ),
      ),
      errorWidget: (_, __, ___) => _imagePlaceholder(
        icon: Icons.broken_image_outlined,
        message: 'تعذر تحميل الصورة',
      ),
    );

    if (heroTag != null) {
      return Hero(
        tag: heroTag,
        child: image,
      );
    }

    return image;
  }

  Widget _buildGallery() {
    final urls = _imageUrls;

    return SizedBox(
      height: 310,
      child: Stack(
        children: [
          Positioned.fill(
            child: urls.isEmpty
                ? _imagePlaceholder(
                    message: 'لا توجد صور لهذا الإعلان',
                  )
                : PageView.builder(
                    controller: _pageController,
                    itemCount: urls.length,
                    onPageChanged: (index) {
                      setState(
                        () => _currentImageIndex = index,
                      );
                    },
                    itemBuilder: (context, index) {
                      final heroTag =
                          'listing_img_${widget.listingId}_$index';

                      return GestureDetector(
                        onTap: () =>
                            _openFullScreenGallery(index),
                        child: _networkImage(
                          urls[index],
                          heroTag: heroTag,
                        ),
                      );
                    },
                  ),
          ),

          // إعلان مميز
          if (_isCommercial)
            Positioned(
              top: 14,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.orange,
                      AppColors.gold,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: 0.20,
                      ),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.local_offer_rounded,
                      size: 15,
                      color: Colors.white,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'إعلان مميز',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // نقاط الصور
          if (urls.length > 1)
            Positioned(
              bottom: 13,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                children: List.generate(
                  urls.length,
                  (index) {
                    final active =
                        index == _currentImageIndex;

                    return AnimatedContainer(
                      duration:
                          const Duration(milliseconds: 200),
                      margin:
                          const EdgeInsets.symmetric(
                        horizontal: 3,
                      ),
                      width: active ? 20 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white60,
                        borderRadius:
                            BorderRadius.circular(4),
                      ),
                    );
                  },
                ),
              ),
            ),

          // رقم الصورة
          if (urls.length > 1)
            Positioned(
              bottom: 10,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(
                    alpha: 0.62,
                  ),
                  borderRadius:
                      BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentImageIndex + 1} / ${urls.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =========================
  // مكونات الصفحة
  // =========================

  Widget _buildChip(
    IconData icon,
    String text,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.brand.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: AppColors.brand,
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required Widget child,
  }) {
    return Container(
      decoration: AppDecorations.card(),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildSectionTitle(
    IconData icon,
    String title,
  ) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.brandSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            icon,
            size: 20,
            color: AppColors.brand,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBanner(String? status) {
    final message = _statusMessage(status);

    if (status == 'approved' ||
        status == null ||
        message.isEmpty) {
      return const SizedBox.shrink();
    }

    final isRejected = status == 'rejected';

    final background = isRejected
        ? Colors.red.shade50
        : AppColors.brandSoft;

    final foreground = isRejected
        ? Colors.red.shade700
        : AppColors.brandDark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: foreground.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isRejected
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            color: foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBox(
    Map<String, dynamic> listing,
  ) {
    final isContact =
        listing['price_type'] == 'contact' ||
        listing['price'] == null;

    final isNegotiable =
        listing['price_type'] == 'negotiable';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.centerStart,
          end: AlignmentDirectional.centerEnd,
          colors: [
            AppColors.brandSoft,
            AppColors.brandSoft.withValues(alpha: 0.65),
          ],
        ),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: AppColors.brand.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.brand,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.sell_outlined,
              color: Colors.white,
              size: 23,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _priceLabel(listing),
              style: TextStyle(
                fontSize: isContact ? 18 : 22,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
          ),
          if (isNegotiable)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 5,
              ),
              decoration: BoxDecoration(
                color: AppColors.orange,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'قابل للتفاوض',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDescription(
    String description,
  ) {
    final isLong = description.length > 220;

    return _buildCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle(
            Icons.description_outlined,
            'وصف الإعلان',
          ),
          const SizedBox(height: 14),
          SelectableText(
            description.isEmpty
                ? 'لا يوجد وصف لهذا الإعلان.'
                : description,
            maxLines:
                (_descriptionExpanded || !isLong)
                    ? null
                    : 6,
            style: const TextStyle(
              fontSize: 15,
              height: 1.8,
              color: AppColors.ink,
            ),
          ),
          if (isLong)
            Align(
              alignment:
                  AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () {
                  setState(
                    () => _descriptionExpanded =
                        !_descriptionExpanded,
                  );
                },
                icon: Icon(
                  _descriptionExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                ),
                label: Text(
                  _descriptionExpanded
                      ? 'عرض أقل'
                      : 'عرض المزيد',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSellerCard() {
    if (_sellerName == null &&
        _sellerAdsCount == null) {
      return const SizedBox.shrink();
    }

    final name = _sellerName ?? 'البائع';

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: _buildCard(
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.brand,
                    AppColors.brandDark,
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  name.runes.isEmpty
                      ? 'ب'
                      : String.fromCharCode(
                          name.runes.first,
                        ),
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                  if (_sellerAdsCount != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.storefront_outlined,
                          size: 15,
                          color: AppColors.orange,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$_sellerAdsCount إعلان نشط',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
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
    );
  }

  Widget _buildSafetyTips() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.22),
        ),
      ),
      child: const Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.shield_outlined,
            color: AppColors.orange,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'نصائح للأمان: عاين المنتج قبل الدفع، وقابل البائع في مكان عام، ولا تحوّل أي مبلغ مقدماً لشخص لا تعرفه.',
              style: TextStyle(
                fontSize: 13,
                height: 1.6,
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSimilarCard(
    Map<String, dynamic> listing,
  ) {
    final id = listing['id'];
    final path =
        listing['image_path']?.toString() ?? '';

    final url =
        path.isEmpty ? '' : _imageUrl(path);

    final title =
        listing['title']?.toString().trim() ?? '';

    return SizedBox(
      width: 155,
      child: Container(
        decoration: AppDecorations.card(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: id is! int
              ? null
              : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ListingDetailsScreen(
                        listingId: id,
                      ),
                    ),
                  );
                },
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 98,
                child: url.isEmpty
                    ? _imagePlaceholder()
                    : _networkImage(
                        url,
                        memCacheWidth: 350,
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(9),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty
                          ? 'إعلان بدون عنوان'
                          : title,
                      maxLines: 2,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _priceLabel(listing),
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.brand,
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

  Widget _buildSimilarSection() {
    if (_similar.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          _buildSectionTitle(
            Icons.auto_awesome_outlined,
            'إعلانات مشابهة',
          ),
          const SizedBox(height: 11),
          SizedBox(
            height: 188,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _similar.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: 10),
              itemBuilder: (_, index) =>
                  _buildSimilarCard(
                _similar[index],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildContactBar() {
    final listing = _listing;

    if (listing == null) return null;
    if (_isOwner) return null;
    if (listing['status'] != 'approved') {
      return null;
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          16,
          11,
          16,
          12,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: AppColors.brand.withValues(
                alpha: 0.10,
              ),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
          border: Border(
            top: BorderSide(
              color: AppColors.brand.withValues(
                alpha: 0.08,
              ),
              width: 0.8,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 49,
                child: FilledButton.icon(
                  onPressed: _callSeller,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        AppColors.brand,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(
                    Icons.phone_rounded,
                  ),
                  label: const Text(
                    'اتصال',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 49,
                child: FilledButton.icon(
                  onPressed: _openWhatsApp,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        _whatsappGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(
                    Icons.chat_rounded,
                  ),
                  label: const Text(
                    'واتساب',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.brand,
        ),
      );
    }

    final listing = _listing;

    if (_error != null || listing == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  borderRadius:
                      BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  size: 40,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _error ?? 'الإعلان غير موجود',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _loadListing,
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
                label: const Text('إعادة المحاولة'),
                style: FilledButton.styleFrom(
                  backgroundColor:
                      AppColors.brand,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(13),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final title =
        listing['title']?.toString().trim() ?? '';

    final description =
        listing['description']?.toString().trim() ??
            '';

    final area =
        listing['area']?.toString().trim() ?? '';

    final timeAgo =
        _timeAgo(listing['created_at']);

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: () =>
          _loadListing(silent: true),
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          _buildGallery(),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.stretch,
              children: [
                _buildStatusBanner(
                  listing['status']?.toString(),
                ),

                if (_isOwner)
                  Container(
                    margin:
                        const EdgeInsets.only(
                      bottom: 12,
                    ),
                    padding:
                        const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
                      borderRadius:
                          BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.brand
                            .withValues(alpha: 0.10),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons
                              .person_pin_outlined,
                          color:
                              AppColors.brand,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'هذا إعلانك. يمكنك إدارته من صفحة "إعلاناتي".',
                            style: TextStyle(
                              fontWeight:
                                  FontWeight.w700,
                              color:
                                  AppColors.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                Text(
                  title.isEmpty
                      ? 'إعلان بدون عنوان'
                      : title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight.w900,
                    height: 1.4,
                    color: AppColors.ink,
                  ),
                ),

                const SizedBox(height: 10),

                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (area.isNotEmpty)
                      _buildChip(
                        Icons.location_on_outlined,
                        area,
                      ),
                    if (listing['condition'] ==
                            'new' ||
                        listing['condition'] ==
                            'used')
                      _buildChip(
                        Icons.inventory_2_outlined,
                        _conditionText(),
                      ),
                    if (_categoryName != null)
                      _buildChip(
                        Icons.category_outlined,
                        _categoryName!,
                      ),
                    if (timeAgo.isNotEmpty)
                      _buildChip(
                        Icons.schedule_rounded,
                        timeAgo,
                      ),
                  ],
                ),

                const SizedBox(height: 14),

                _buildPriceBox(listing),

                const SizedBox(height: 12),

                _buildDescription(description),

                _buildSellerCard(),

                _buildSafetyTips(),

                _buildSimilarSection(),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        !_loading && _listing != null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            AppColors.pageBackground,
        appBar: AppBar(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'تفاصيل الإعلان',
            style: TextStyle(
              fontWeight: FontWeight.w900,
            ),
          ),
          actions: [
            if (ready) ...[
              IconButton(
                tooltip: _favorite
                    ? 'إزالة من المفضلة'
                    : 'إضافة للمفضلة',
                onPressed: _toggleFavorite,
                icon: Icon(
                  _favorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: _favorite
                      ? Colors.red.shade200
                      : Colors.white,
                ),
              ),
              IconButton(
                tooltip: 'مشاركة',
                onPressed: _shareListing,
                icon: const Icon(
                  Icons.share_outlined,
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert_rounded,
                ),
                onSelected: (value) {
                  if (value == 'report') {
                    _reportListing();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'report',
                    child: Row(
                      children: [
                        Icon(
                          Icons.flag_outlined,
                          color: AppColors.brand,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'الإبلاغ عن الإعلان',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        body: _buildBody(),
        bottomNavigationBar:
            _buildContactBar(),
      ),
    );
  }
}

// =========================
// عرض الصور بملء الشاشة
// =========================

class _FullScreenGallery
    extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  final int listingId;

  const _FullScreenGallery({
    required this.urls,
    required this.initialIndex,
    required this.listingId,
  });

  @override
  State<_FullScreenGallery> createState() =>
      _FullScreenGalleryState();
}

class _FullScreenGalleryState
    extends State<_FullScreenGallery> {
  late final PageController _controller =
      PageController(
    initialPage: widget.initialIndex,
  );

  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(
            '${_index + 1} من ${widget.urls.length}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        body: PageView.builder(
          controller: _controller,
          itemCount: widget.urls.length,
          onPageChanged: (index) =>
              setState(() => _index = index),
          itemBuilder: (context, index) {
            final heroTag =
                'listing_img_${widget.listingId}_$index';

            return InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: Hero(
                  tag: heroTag,
                  child: CachedNetworkImage(
                    imageUrl: widget.urls[index],
                    fit: BoxFit.contain,
                    placeholder: (_, __) =>
                        const Center(
                      child:
                          CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    ),
                    errorWidget:
                        (_, __, ___) =>
                            const Icon(
                      Icons
                          .broken_image_outlined,
                      color: Colors.white54,
                      size: 60,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// =========================
// نافذة الإبلاغ
// =========================

class _ReportSheet extends StatefulWidget {
  const _ReportSheet();

  @override
  State<_ReportSheet> createState() =>
      _ReportSheetState();
}

class _ReportSheetState
    extends State<_ReportSheet> {
  static const _otherReason = 'سبب آخر';

  static const _reasons = [
    'احتيال أو نصب',
    'السعر غير حقيقي',
    'محتوى مخالف أو غير لائق',
    'الإعلان مكرر',
    'تم بيع المنتج',
    _otherReason,
  ];

  final _noteController =
      TextEditingController();

  String? _selected;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final note =
        _noteController.text.trim();

    if (_selected == null) {
      setState(
        () => _error = 'اختر سبب البلاغ',
      );
      return;
    }

    if (_selected == _otherReason &&
        note.isEmpty) {
      setState(
        () => _error = 'اكتب تفاصيل السبب',
      );
      return;
    }

    Navigator.pop(
      context,
      {
        'reason': _selected!,
        'details': note,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(
          bottom:
              MediaQuery.of(context)
                  .viewInsets
                  .bottom,
        ),
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.fromLTRB(
            20,
            0,
            20,
            20,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),

              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.red
                          .withValues(alpha: 0.10),
                      borderRadius:
                          BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.flag_outlined,
                      color:
                          Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'الإبلاغ عن الإعلان',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight:
                          FontWeight.w900,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              ..._reasons.map((reason) {
                final selected =
                    _selected == reason;

                return Container(
                  margin:
                      const EdgeInsets.only(
                    bottom: 5,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.brandSoft
                        : null,
                    borderRadius:
                        BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? AppColors.brand
                              .withValues(
                              alpha: 0.20,
                            )
                          : Colors.transparent,
                    ),
                  ),
                  child: InkWell(
                    borderRadius:
                        BorderRadius.circular(12),
                    onTap: () {
                      setState(() {
                        _selected = reason;
                        _error = null;
                      });
                    },
                    child: Padding(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        vertical: 10,
                        horizontal: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons
                                    .radio_button_checked
                                : Icons
                                    .radio_button_unchecked,
                            color: selected
                                ? AppColors.brand
                                : Colors.grey
                                    .shade500,
                          ),
                          const SizedBox(
                            width: 10,
                          ),
                          Text(
                            reason,
                            style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color:
                                  AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),

              const SizedBox(height: 8),

              TextField(
                controller:
                    _noteController,
                maxLines: 3,
                maxLength: 300,
                onChanged: (_) {
                  if (_error != null) {
                    setState(
                      () => _error = null,
                    );
                  }
                },
                decoration:
                    InputDecoration(
                  hintText:
                      'تفاصيل إضافية (اختياري)',
                  filled: true,
                  fillColor:
                      AppColors.pageBackground,
                  border:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      13,
                    ),
                    borderSide: BorderSide(
                      color: AppColors.brand
                          .withValues(
                        alpha: 0.12,
                      ),
                    ),
                  ),
                  enabledBorder:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      13,
                    ),
                    borderSide: BorderSide(
                      color: AppColors.brand
                          .withValues(
                        alpha: 0.12,
                      ),
                    ),
                  ),
                  focusedBorder:
                      OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(
                      13,
                    ),
                    borderSide:
                        const BorderSide(
                      color: AppColors.brand,
                      width: 1.5,
                    ),
                  ),
                ),
              ),

              if (_error != null)
                Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom: 8,
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          Colors.red.shade700,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                ),

              const SizedBox(height: 4),

              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        AppColors.brand,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(
                    Icons.send_rounded,
                  ),
                  label: const Text(
                    'إرسال البلاغ',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}