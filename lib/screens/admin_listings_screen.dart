import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_details_screen.dart';

class AdminListingsScreen extends StatefulWidget {
  const AdminListingsScreen({super.key});

  @override
  State<AdminListingsScreen> createState() => _AdminListingsScreenState();
}

class _AdminListingsScreenState extends State<AdminListingsScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _listings = [];
  bool _loading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        if (!mounted) return;

        setState(() {
          _isAdmin = false;
          _loading = false;
        });

        return;
      }

      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      final isAdmin = profile?['role'] == 'admin';

      if (!isAdmin) {
        if (!mounted) return;

        setState(() {
          _isAdmin = false;
          _loading = false;
        });

        return;
      }

      final data = await _supabase
          .from('listings')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _isAdmin = true;
        _listings = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحميل الإعلانات'),
        ),
      );
    }
  }

  Future<void> _updateStatus(
    int listingId,
    String status,
  ) async {
    try {
      await _supabase
          .from('listings')
          .update({'status': status})
          .eq('id', listingId);

      if (!mounted) return;

      setState(() {
        _listings.removeWhere(
          (listing) => listing['id'] == listingId,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'approved'
                ? 'تمت الموافقة على الإعلان'
                : 'تم رفض الإعلان',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحديث حالة الإعلان'),
        ),
      );
    }
  }

  Future<void> _approveListing(int listingId) async {
    await _updateStatus(listingId, 'approved');
  }

  Future<void> _rejectListing(int listingId) async {
    final shouldReject = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('رفض الإعلان'),
          content: const Text(
            'هل تريد رفض هذا الإعلان؟',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: const Text('رفض'),
            ),
          ],
        );
      },
    );

    if (shouldReject == true) {
      await _updateStatus(listingId, 'rejected');
    }
  }

  String _formatPrice(dynamic price, dynamic priceType) {
    if (price == null) {
      return 'السعر غير محدد';
    }

    final priceText = price.toString();

    switch (priceType?.toString()) {
      case 'negotiable':
        return '$priceText - قابل للتفاوض';

      case 'free':
        return 'مجاناً';

      case 'contact':
        return 'السعر عند الاتصال';

      default:
        return priceText;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) {
      return '';
    }

    final value = DateTime.tryParse(date.toString());

    if (value == null) {
      return '';
    }

    final local = value.toLocal();

    return '${local.year}/${local.month.toString().padLeft(2, '0')}/'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildListingCard(Map<String, dynamic> listing) {
    final id = listing['id'];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              listing['title']?.toString() ?? 'بدون عنوان',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              listing['description']?.toString() ?? '',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 8),

            if (listing['price'] != null)
              Text(
                _formatPrice(
                  listing['price'],
                  listing['price_type'],
                ),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),

            if (listing['area'] != null &&
                listing['area'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'المنطقة: ${listing['area']}',
                ),
              ),

            if (listing['contact_phone'] != null &&
                listing['contact_phone'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'الهاتف: ${listing['contact_phone']}',
                ),
              ),

            if (listing['created_at'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'تاريخ الإضافة: ${_formatDate(listing['created_at'])}',
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
              ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ListingDetailsScreen(
                            listingId: id,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('عرض'),
                  ),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      _approveListing(id);
                    },
                    icon: const Icon(Icons.check),
                    label: const Text('موافقة'),
                  ),
                ),

                const SizedBox(width: 8),

                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _rejectListing(id);
                    },
                    icon: const Icon(Icons.close),
                    label: const Text('رفض'),
                  ),
                ),
              ],
            ),
          ],
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
          title: const Text('لوحة تحكم الأدمن'),
          actions: [
            IconButton(
              onPressed: _loading ? null : _loadListings,
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث',
            ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (!_isAdmin) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
              ),
              SizedBox(height: 16),
              Text(
                'هذه الصفحة مخصصة للأدمن فقط',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_listings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadListings,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 64,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'لا توجد إعلانات معلقة للمراجعة',
                    style: TextStyle(
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadListings,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _listings.length,
        itemBuilder: (context, index) {
          return _buildListingCard(_listings[index]);
        },
      ),
    );
  }
}
