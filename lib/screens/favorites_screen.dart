import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_details_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      setState(() {
        _loading = false;
        _error = 'يجب تسجيل الدخول لعرض المفضلة.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _supabase
          .from('favorites')
          .select('''
            listing_id,
            created_at,
            listings (
              id,
              title,
              description,
              price,
              currency,
              price_type,
              area
            )
          ''')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _favorites = List<Map<String, dynamic>>.from(response);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'تعذر تحميل المفضلة. حاول مرة أخرى.';
        _loading = false;
      });
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

  Future<void> _removeFavorite(int listingId) async {
    final user = _supabase.auth.currentUser;

    if (user == null) return;

    try {
      await _supabase
          .from('favorites')
          .delete()
          .eq('user_id', user.id)
          .eq('listing_id', listingId);

      if (!mounted) return;

      setState(() {
        _favorites.removeWhere(
          (favorite) => favorite['listing_id'] == listingId,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تمت إزالة الإعلان من المفضلة'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر إزالة الإعلان من المفضلة'),
        ),
      );
    }
  }

  Widget _buildFavoriteCard(Map<String, dynamic> favorite) {
    final listing = favorite['listings'];

    if (listing is! Map<String, dynamic>) {
      return const SizedBox.shrink();
    }

    final listingId = listing['id'];

    if (listingId is! int) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ListingDetailsScreen(
                listingId: listingId,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(
                radius: 28,
                child: Icon(Icons.storefront_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      listing['title']?.toString() ?? 'إعلان بدون عنوان',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatPrice(listing),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if ((listing['area'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 17,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              listing['area'].toString(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'إزالة من المفضلة',
                onPressed: () => _removeFavorite(listingId),
                icon: const Icon(Icons.favorite),
              ),
            ],
          ),
        ),
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
      return RefreshIndicator(
        onRefresh: _loadFavorites,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Icon(
              Icons.favorite_border,
              size: 72,
            ),
            SizedBox(height: 16),
            Center(
              child: Text(
                'لا توجد إعلانات في المفضلة',
                style: TextStyle(fontSize: 17),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadFavorites,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: _favorites.map(_buildFavoriteCard).toList(),
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
