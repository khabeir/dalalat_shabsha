import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_details_screen.dart';
import 'add_listing_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _listings = [];

  bool _loading = true;
  String? _error;
  int? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final categoriesResponse = await _supabase
          .from('categories')
          .select('id, name, icon')
          .eq('is_active', true)
          .order('sort_order');

      var listingsQuery = _supabase
          .from('listings')
          .select(
            'id, title, description, price, currency, price_type, area, created_at',
          )
          .eq('status', 'approved');

      if (_selectedCategoryId != null) {
        listingsQuery =
            listingsQuery.eq('category_id', _selectedCategoryId!);
      }

      final listingsResponse =
          await listingsQuery.order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _categories = List<Map<String, dynamic>>.from(categoriesResponse);
        _listings = List<Map<String, dynamic>>.from(listingsResponse);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = 'تعذر تحميل البيانات. تحقق من اتصال الإنترنت وحاول مجدداً.';
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر تسجيل الخروج، حاول مرة أخرى')),
      );
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

  Widget _buildCategoryItem(Map<String, dynamic> category) {
    final id = category['id'] as int;
    final selected = _selectedCategoryId == id;
    final icon = category['icon'] as String?;
    final name = category['name'] as String? ?? '';

    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: ChoiceChip(
        selected: selected,
        label: Text('${icon ?? '📦'} $name'),
        onSelected: (_) {
          setState(() {
            _selectedCategoryId = selected ? null : id;
          });
          _loadData();
        },
      ),
    );
  }

  Widget _buildListingCard(Map<String, dynamic> listing) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          final listingId = listing['id'];

          if (listingId is int) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ListingDetailsScreen(
                  listingId: listingId,
                ),
              ),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                listing['title']?.toString() ?? 'إعلان بدون عنوان',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _formatPrice(listing),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if ((listing['area'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 18),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(listing['area'].toString()),
                    ),
                  ],
                ),
              ],
              if ((listing['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  listing['description'].toString(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadData,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'التصنيفات',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_categories.isEmpty)
            const Text('لا توجد تصنيفات متاحة حالياً')
          else
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      selected: _selectedCategoryId == null,
                      label: const Text('الكل'),
                      onSelected: (_) {
                        setState(() => _selectedCategoryId = null);
                        _loadData();
                      },
                    ),
                  ),
                  ..._categories.map(_buildCategoryItem),
                ],
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            'أحدث الإعلانات',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_listings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(Icons.storefront_outlined, size: 56),
                  SizedBox(height: 12),
                  Text(
                    'لا توجد إعلانات معتمدة حالياً',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            )
          else
            ..._listings.map(_buildListingCard),
        ],
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
        appBar: AppBar(
          title: const Text('دلالة شبشة'),
          actions: [
            IconButton(
              tooltip: 'إضافة إعلان',
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AddListingScreen(),
                  ),
                );

                _loadData();
              },
              icon: const Icon(Icons.add_circle_outline),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                name == null || name.isEmpty
                    ? 'مرحباً بك في سوق شبشة'
                    : 'مرحباً يا $name',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}
