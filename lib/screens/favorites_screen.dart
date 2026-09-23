import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

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

  // جلب أول صورة لكل إعلان بطلب واحد. الصور اختيارية، فلا نفشل إن تعذّرت.
  Future<void> _attachCoverImages(List<Map<String, dynamic>> favorites) async {
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
        covers.putIfAbsent(image['listing_id'], () => image['image_path']);
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
          content: Text(message),
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
    final currency = listing['currency']?.toString().trim().isNotEmpty == true
        ? listing['currency'].toString().trim()
        : 'SDG';

    if (listing['price_type'] == 'contact' || price == null) {
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

  // نص حالة الإعلان إن لم يكن متاحاً (null = متاح).
  String? _unavailableText(Map<String, dynamic>? listing) {
    if (listing == null) return 'هذا الإعلان لم يعد متاحاً';

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
  // إزالة من المفضلة (مع تراجع)
  // =========================
  Future<void> _removeFavorite(int listingId) async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    // نحفظ العنصر ومكانه لنستطيع التراجع.
    final index = _favorites.indexWhere(
      (favorite) => favorite['listing_id'] == listingId,
    );

    if (index == -1) return;

    final removed = _favorites[index];

    setState(() => _favorites.removeAt(index));

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
          onPressed: () => _undoRemove(removed, index),
        ),
      );
    } catch (e) {
      debugPrint('removeFavorite error: $e');

      if (!mounted) return;

      // نعيد العنصر لمكانه لأن الحذف فشل.
      setState(() {
        _favorites.insert(index.clamp(0, _favorites.length), removed);
      });

      _showSnack('تعذر إزالة الإعلان من المفضلة');
    }
  }

  Future<void> _undoRemove(Map<String, dynamic> removed, int index) async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    try {
      await _supabase.from('favorites').insert({
        'user_id': user.id,
        'listing_id': removed['listing_id'],
      });

      if (!mounted) return;

      setState(() {
        _favorites.insert(index.clamp(0, _favorites.length), removed);
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
        builder: (_) => ListingDetailsScreen(listingId: listingId),
      ),
    );

    if (!mounted) return;

    // قد يكون المستخدم أزال الإعلان من المفضلة داخل صفحة التفاصيل.
    await _loadFavorites(silent: true);
  }

  // =========================
  // الواجهة
  // =========================
  Widget _buildThumbnail(String url, {required bool unavailable}) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget placeholder(IconData icon) {
      return Container(
        color: colorScheme.surfaceContainerHighest,
        child: Icon(icon, color: colorScheme.onSurfaceVariant),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
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
                  placeholder: (_, __) => placeholder(Icons.image_outlined),
                  errorWidget: (_, __, ___) =>
                      placeholder(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }

  Widget _buildFavoriteCard(Map<String, dynamic> favorite) {
    final colorScheme = Theme.of(context).colorScheme;

    final listingId = favorite['listing_id'];

    if (listingId is! int) return const SizedBox.shrink();

    final rawListing = favorite['listings'];

    final listing =
        rawListing is Map ? Map<String, dynamic>.from(rawListing) : null;

    final unavailableText = _unavailableText(listing);
    final unavailable = unavailableText != null;

    final title = listing?['title']?.toString().trim().isNotEmpty == true
        ? listing!['title'].toString().trim()
        : 'إعلان بدون عنوان';

    final area = listing?['area']?.toString().trim() ?? '';
    final savedAgo = _timeAgo(favorite['created_at']);

    final meta = [
      if (area.isNotEmpty) area,
      if (savedAgo.isNotEmpty) 'أُضيف $savedAgo',
    ].join(' · ');

    final isNegotiable = listing?['price_type'] == 'negotiable';

    return Dismissible(
      key: ValueKey('favorite_$listingId'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => _removeFavorite(listingId),
      background: _dismissBackground(Alignment.centerRight),
      secondaryBackground: _dismissBackground(Alignment.centerLeft),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        child: InkWell(
          // الإعلان المحذوف نهائياً لا يُفتح، لكن غير المتاح مؤقتاً يُفتح.
          onTap: listing == null ? null : () => _openListing(listingId),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildThumbnail(
                  _imageUrl(favorite['cover_path']),
                  unavailable: unavailable,
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        listing == null ? 'إعلان محذوف' : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: unavailable
                              ? colorScheme.onSurfaceVariant
                              : colorScheme.onSurface,
                        ),
                      ),

                      const SizedBox(height: 4),

                      if (listing != null)
                        Text(
                          _priceText(listing),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: unavailable
                                ? colorScheme.onSurfaceVariant
                                : colorScheme.primary,
                          ),
                        ),

                      if (isNegotiable && !unavailable)
                        Text(
                          'قابل للتفاوض',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),

                      if (unavailable)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            unavailableText,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        )
                      else if (meta.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
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
                        ),
                    ],
                  ),
                ),

                IconButton(
                  tooltip: 'إزالة من المفضلة',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _removeFavorite(listingId),
                  icon: const Icon(
                    Icons.favorite,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dismissBackground(Alignment alignment) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(
        Icons.heart_broken_outlined,
        color: colorScheme.onErrorContainer,
      ),
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
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadFavorites,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    if (_favorites.isEmpty) {
      final colorScheme = Theme.of(context).colorScheme;

      return RefreshIndicator(
        onRefresh: () => _loadFavorites(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 32),
          children: [
            const SizedBox(height: 110),
            Icon(
              Icons.favorite_border,
              size: 72,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text(
              'مفضلتك فارغة',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'اضغط على القلب في أي إعلان لتحفظه هنا وترجع له بسهولة.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            Center(
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('تصفح الإعلانات'),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadFavorites(silent: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _favorites.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${_favorites.length} إعلان محفوظ · اسحب البطاقة لإزالتها',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }

          return _buildFavoriteCard(_favorites[index - 1]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المفضلة'),
        ),
        body: _buildBody(),
      ),
    );
  }
}
