import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_decorations.dart';
import '../core/theme/app_text_styles.dart';
import 'listing_details_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  static final _numberFormat = NumberFormat('#,##0.##', 'en');

  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  // =========================
  // تحميل البيانات
  // =========================

  Future<void> _loadFavorites({bool silent = false}) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'يجب تسجيل الدخول لعرض المفضلة.';
      });

      return;
    }

    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final response = await _supabase
          .from('favorites')
          .select('''
            listing_id,
            created_at,
            listings (
              id,
              title,
              price,
              currency,
              price_type,
              area,
              status
            )
          ''')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final favorites = List<Map<String, dynamic>>.from(response);

      await _attachCoverImages(favorites);

      if (!mounted) return;

      setState(() {
        _favorites = favorites;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('loadFavorites error: $e');

      if (!mounted) return;

      if (silent && _favorites.isNotEmpty) {
        _showSnack('تعذر تحديث المفضلة');
        return;
      }

      setState(() {
        _error = 'تعذر تحميل المفضلة. حاول مرة أخرى.';
        _loading = false;
      });
    }
  }

  Future<void> _attachCoverImages(
    List<Map<String, dynamic>> favorites,
  ) async {
    try {
      final ids = favorites
          .map((favorite) => favorite['listing_id'])
          .whereType<int>()
          .toList();

      if (ids.isEmpty) return;

      final response = await _supabase
          .from('listing_images')
          .select('listing_id, image_path, sort_order')
          .inFilter('listing_id', ids)
          .order('sort_order');

      final covers = <dynamic, dynamic>{};

      for (final image in List<Map<String, dynamic>>.from(response)) {
        covers.putIfAbsent(
          image['listing_id'],
          () => image['image_path'],
        );
      }

      for (final favorite in favorites) {
        favorite['cover_path'] = covers[favorite['listing_id']];
      }
    } catch (e) {
      debugPrint('favorites covers error: $e');
    }
  }

  // =========================
  // أدوات مساعدة
  // =========================

  void _showSnack(String message, {SnackBarAction? action}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.ink,
          content: Text(
            message,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          action: action,
        ),
      );
  }

  String _imageUrl(dynamic imagePath) {
    final path = imagePath?.toString().trim() ?? '';

    if (path.isEmpty) return '';

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    return _supabase.storage.from('listing-images').getPublicUrl(path);
  }

  String _priceText(Map<String, dynamic> listing) {
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

  String _timeAgo(dynamic value) {
    final date = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) return '';

    final diff = DateTime.now().difference(date);

    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'قبل ${diff.inMinutes} د';
    if (diff.inHours < 24) return 'قبل ${diff.inHours} س';
    if (diff.inDays < 30) return 'قبل ${diff.inDays} يوم';

    return 'قبل ${diff.inDays ~/ 30} شهر';
  }

  String? _unavailableText(Map<String, dynamic>? listing) {
    if (listing == null) {
      return 'هذا الإعلان لم يعد متاحاً';
    }

    switch (listing['status']) {
      case 'approved':
        return null;

      case 'sold':
        return 'تم بيع هذا المنتج';

      case 'pending':
        return 'الإعلان قيد المراجعة';

      default:
        return 'هذا الإعلان غير متاح حالياً';
    }
  }

  // =========================
  // إزالة من المفضلة
  // =========================

  Future<void> _removeFavorite(int listingId) async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    final index = _favorites.indexWhere(
      (favorite) => favorite['listing_id'] == listingId,
    );

    if (index == -1) return;

    final removed = _favorites[index];

    setState(() {
      _favorites.removeAt(index);
    });

    try {
      await _supabase
          .from('favorites')
          .delete()
          .eq('user_id', user.id)
          .eq('listing_id', listingId);

      _showSnack(
        'تمت إزالة الإعلان من المفضلة',
        action: SnackBarAction(
          label: 'تراجع',
          textColor: AppColors.gold,
          onPressed: () => _undoRemove(removed, index),
        ),
      );
    } catch (e) {
      debugPrint('removeFavorite error: $e');

      if (!mounted) return;

      setState(() {
        _favorites.insert(
          index.clamp(0, _favorites.length),
          removed,
        );
      });

      _showSnack('تعذر إزالة الإعلان من المفضلة');
    }
  }

  Future<void> _undoRemove(
    Map<String, dynamic> removed,
    int index,
  ) async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    try {
      await _supabase.from('favorites').insert({
        'user_id': user.id,
        'listing_id': removed['listing_id'],
      });

      if (!mounted) return;

      setState(() {
        _favorites.insert(
          index.clamp(0, _favorites.length),
          removed,
        );
      });
    } catch (e) {
      debugPrint('undoRemove error: $e');
      _showSnack('تعذر التراجع عن الإزالة');
    }
  }

  Future<void> _openListing(int listingId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListingDetailsScreen(
          listingId: listingId,
        ),
      ),
    );

    if (!mounted) return;

    await _loadFavorites(silent: true);
  }

  // =========================
  // صورة الإعلان
  // =========================

  Widget _buildThumbnail(
    String url, {
    required bool unavailable,
  }) {

    Widget placeholder(IconData icon) {
      return Container(
        color: AppColors.brandSoft,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 30,
          color: AppColors.brand.withValues(alpha: 0.65),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.brand.withValues(alpha: 0.10),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: 84,
          height: 84,
          child: url.isEmpty
              ? placeholder(Icons.image_outlined)
              : ColorFiltered(
                  colorFilter: unavailable
                      ? const ColorFilter.mode(
                          Colors.grey,
                          BlendMode.saturation,
                        )
                      : const ColorFilter.mode(
                          Colors.transparent,
                          BlendMode.dst,
                        ),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    memCacheWidth: 250,
                    placeholder: (_, __) =>
                        placeholder(Icons.image_outlined),
                    errorWidget: (_, __, ___) =>
                        placeholder(Icons.broken_image_outlined),
                  ),
                ),
        ),
      ),
    );
  }

  // =========================
  // بطاقة المفضلة
  // =========================

  Widget _buildFavoriteCard(
    Map<String, dynamic> favorite,
  ) {

    final listingId = favorite['listing_id'];

    if (listingId is! int) {
      return const SizedBox.shrink();
    }

    final rawListing = favorite['listings'];

    final listing =
        rawListing is Map
            ? Map<String, dynamic>.from(rawListing)
            : null;

    final unavailableText = _unavailableText(listing);
    final unavailable = unavailableText != null;

    final title =
        listing?['title']?.toString().trim().isNotEmpty == true
            ? listing!['title'].toString().trim()
            : 'إعلان بدون عنوان';

    final area = listing?['area']?.toString().trim() ?? '';

    final savedAgo = _timeAgo(
      favorite['created_at'],
    );

    final meta = [
      if (area.isNotEmpty) area,
      if (savedAgo.isNotEmpty) 'أُضيف $savedAgo',
    ].join(' · ');

    final isNegotiable =
        listing?['price_type'] == 'negotiable';

    return Dismissible(
      key: ValueKey('favorite_$listingId'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => _removeFavorite(listingId),
      background: _dismissBackground(
        Alignment.centerRight,
      ),
      secondaryBackground: _dismissBackground(
        Alignment.centerLeft,
      ),
      child: Container(
        decoration: AppDecorations.card(
          color: colorScheme.surface,
        ),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: listing == null
                ? null
                : () => _openListing(listingId),
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _buildThumbnail(
                    _imageUrl(
                      favorite['cover_path'],
                    ),
                    unavailable: unavailable,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing == null
                              ? 'إعلان محذوف'
                              : title,
                          maxLines: 2,
                          overflow:
                              TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 14.5,
                            fontWeight:
                                FontWeight.w800,
                            height: 1.35,
                            color: unavailable
                                ? colorScheme
                                    .onSurfaceVariant
                                : AppColors.ink,
                          ),
                        ),

                        const SizedBox(height: 5),

                        if (listing != null)
                          Text(
                            _priceText(listing),
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 14,
                              fontWeight:
                                  FontWeight.w900,
                              color: unavailable
                                  ? colorScheme
                                      .onSurfaceVariant
                                  : AppColors.brand,
                            ),
                          ),

                        if (isNegotiable &&
                            !unavailable)
                          Padding(
                            padding:
                                const EdgeInsets.only(
                              top: 2,
                            ),
                            child: Text(
                              'قابل للتفاوض',
                              style:
                                  TextStyle(
                                fontFamily:
                                    'Cairo',
                                fontSize: 10.5,
                                fontWeight:
                                    FontWeight.w700,
                                color:
                                    AppColors.orange,
                              ),
                            ),
                          ),

                        if (unavailable)
                          Container(
                            margin:
                                const EdgeInsets.only(
                              top: 5,
                            ),
                            padding:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme
                                  .errorContainer,
                              borderRadius:
                                  BorderRadius
                                      .circular(20),
                            ),
                            child: Text(
                              unavailableText,
                              style: TextStyle(
                                fontFamily:
                                    'Cairo',
                                fontSize: 10.5,
                                fontWeight:
                                    FontWeight.w700,
                                color: colorScheme
                                    .onErrorContainer,
                              ),
                            ),
                          )
                        else if (meta.isNotEmpty)
                          Padding(
                            padding:
                                const EdgeInsets
                                    .only(top: 5),
                            child: Row(
                              children: [
                                Icon(
                                  Icons
                                      .location_on_outlined,
                                  size: 14,
                                  color: AppColors
                                      .brand
                                      .withValues(
                                    alpha: 0.65,
                                  ),
                                ),
                                const SizedBox(
                                  width: 3,
                                ),
                                Expanded(
                                  child: Text(
                                    meta,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow
                                            .ellipsis,
                                    style: TextStyle(
                                      fontFamily:
                                          'Cairo',
                                      fontSize: 10.5,
                                      fontWeight:
                                          FontWeight
                                              .w600,
                                      color: colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 2),

                  IconButton(
                    tooltip: 'إزالة من المفضلة',
                    visualDensity:
                        VisualDensity.compact,
                    onPressed: () =>
                        _removeFavorite(
                      listingId,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors
                          .brandSoft
                          .withValues(alpha: 0.65),
                      foregroundColor:
                          AppColors.brand,
                    ),
                    icon: const Icon(
                      Icons.favorite,
                      size: 21,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dismissBackground(
    Alignment alignment,
  ) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(
        horizontal: 22,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(
        Icons.heart_broken_outlined,
        color: AppColors.brand,
        size: 26,
      ),
    );
  }

  // =========================
  // حالة الخطأ
  // =========================

  Widget _buildErrorState() {

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: AppDecorations.card(
            color: colorScheme.surface,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline,
                  size: 34,
                  color: colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  height: 1.6,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loadFavorites,
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
                label: const Text(
                  'إعادة المحاولة',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================
  // المفضلة فارغة
  // =========================

  Widget _buildEmptyState() {

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: () =>
          _loadFavorites(silent: true),
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: 28,
        ),
        children: [
          const SizedBox(height: 85),

          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border_rounded,
                size: 52,
                color: AppColors.brand,
              ),
            ),
          ),

          const SizedBox(height: 20),

          Text(
            'مفضلتك فارغة',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'اضغط على القلب في أي إعلان لتحفظه هنا '
            'وترجع له بسهولة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              height: 1.7,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),

          const SizedBox(height: 22),

          Center(
            child: FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                Icons.storefront_outlined,
              ),
              label: const Text(
                'تصفح الإعلانات',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================
  // المحتوى
  // =========================

  Widget _buildBody() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppColors.brand,
        ),
      );
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_favorites.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;

      return _buildEmptyState();
    }

    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: () =>
          _loadFavorites(silent: true),
      child: ListView.separated(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          28,
        ),
        itemCount: _favorites.length + 1,
        separatorBuilder: (_, __) =>
            const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration:
                  AppDecorations.softCard(),
              child: Row(
                children: [
                  const Icon(
                    Icons.favorite_rounded,
                    size: 18,
                    color: AppColors.brand,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_favorites.length} إعلان محفوظ',
                      style:
                          AppTextStyles.smallBrand,
                    ),
                  ),
                  Text(
                    'اسحب البطاقة للإزالة',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }

          return _buildFavoriteCard(
            _favorites[index - 1],
          );
        },
      ),
    );
  }

  // =========================
  // الصفحة
  // =========================

  @override
  Widget build(BuildContext context) {
    final colorScheme =
        Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor:
            Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          elevation: 0,
          scrolledUnderElevation: 0,
          backgroundColor:
              Theme.of(context).scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          leading: IconButton(
            tooltip: 'رجوع',
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
            ),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.brandSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  size: 19,
                  color: AppColors.brand,
                ),
              ),
              const SizedBox(width: 9),
              Text(
                'المفضلة',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }
}