import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_details_screen.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  late Future<List<Map<String, dynamic>>> _listingsFuture;

  @override
  void initState() {
    super.initState();
    _listingsFuture = _loadMyListings();
  }

  Future<List<Map<String, dynamic>>> _loadMyListings() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('يجب تسجيل الدخول أولاً.');
    }

    final response = await _supabase
        .from('listings')
        .select(
          'id, title, description, price, currency, price_type, '
          'condition, area, status, created_at',
        )
        .eq('seller_id', user.id)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _refreshListings() async {
    final newFuture = _loadMyListings();

    setState(() {
      _listingsFuture = newFuture;
    });

    await newFuture;
  }

  String _statusText(String? status) {
    switch (status) {
      case 'pending':
        return 'قيد المراجعة';
      case 'approved':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      case 'sold':
        return 'مباع';
      case 'archived':
        return 'مؤرشف';
      default:
        return 'غير معروف';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'sold':
        return Colors.blue;
      case 'archived':
        return Colors.grey;
      default:
        return Colors.black54;
    }
  }

  String _priceText(Map<String, dynamic> listing) {
    final priceType = listing['price_type']?.toString();

    if (priceType == 'contact' || listing['price'] == null) {
      return 'السعر عند التواصل';
    }

    final price = listing['price'];
    final currency = listing['currency']?.toString() ?? 'SDG';

    final formattedPrice = price is num
        ? price.toStringAsFixed(price % 1 == 0 ? 0 : 2)
        : price.toString();

    if (priceType == 'negotiable') {
      return '$formattedPrice $currency قابل للتفاوض';
    }

    return '$formattedPrice $currency';
  }

  void _openListing(Map<String, dynamic> listing) {
    final listingId = listing['id'];

    if (listingId is! int) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListingDetailsScreen(listingId: listingId),
      ),
    );
  }

  Widget _buildListingCard(Map<String, dynamic> listing) {
    final status = listing['status']?.toString();
    final title = listing['title']?.toString() ?? 'إعلان بدون عنوان';
    final area = listing['area']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openListing(listing),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _statusColor(status).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusText(status),
                      style: TextStyle(
                        color: _statusColor(status),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                _priceText(listing),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (area.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, size: 18),
                    const SizedBox(width: 4),
                    Text(area),
                  ],
                ),
              ],
              if ((listing['description']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  listing['description'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Icon(Icons.chevron_left),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعلاناتي'),
          centerTitle: true,
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: () {
                setState(() {
                  _listingsFuture = _loadMyListings();
                });
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _listingsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  const Center(child: Text('تعذر تحميل إعلاناتك.')),
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _listingsFuture = _loadMyListings();
                        });
                      },
                      child: const Text('إعادة المحاولة'),
                    ),
                  ),
                ],
              );
            }

            final listings = snapshot.data ?? [];

            if (listings.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refreshListings,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 150),
                    Icon(Icons.inventory_2_outlined, size: 60),
                    SizedBox(height: 16),
                    Center(
                      child: Text(
                        'لم تضف أي إعلانات حتى الآن.',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    SizedBox(height: 8),
                    Center(child: Text('اسحب الشاشة إلى الأسفل للتحديث.')),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _refreshListings,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: listings.length,
                itemBuilder: (context, index) {
                  return _buildListingCard(listings[index]);
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
