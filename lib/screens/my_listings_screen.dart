import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'edit_listing_screen.dart';
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
          'id, category_id, title, description, price, currency, '
          'price_type, condition, area, contact_phone, status, created_at',
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

  Future<void> _editListing(Map<String, dynamic> listing) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditListingScreen(
          listing: listing,
        ),
      ),
    );

    if (result == true && mounted) {
      setState(() {
        _listingsFuture = _loadMyListings();
      });
    }
  }

  // تغيير حالة الإعلان.
  Future<void> _changeListingStatus(
    Map<String, dynamic> listing,
    String newStatus,
  ) async {
    final listingId = listing['id'];

    if (listingId is! int) {
      return;
    }

    String message;

    switch (newStatus) {
      case 'sold':
        message = 'تم تغيير حالة الإعلان إلى "تم البيع".';
        break;

      case 'archived':
        message = 'تمت أرشفة الإعلان.';
        break;

      case 'approved':
        message = 'تم إعادة الإعلان إلى "متاح".';
        break;

      default:
        message = 'تم تحديث حالة الإعلان.';
    }

    try {
      await _supabase
          .from('listings')
          .update({'status': newStatus})
          .eq('id', listingId);

      if (!mounted) return;

      setState(() {
        _listingsFuture = _loadMyListings();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحديث حالة الإعلان: ${e.message}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ: $e'),
        ),
      );
    }
  }

  // تأكيد تغيير الحالة قبل التنفيذ.
  Future<void> _confirmChangeStatus(
    Map<String, dynamic> listing,
    String newStatus,
  ) async {
    final title =
        listing['title']?.toString() ?? 'هذا الإعلان';

    String actionTitle;
    String message;

    switch (newStatus) {
      case 'sold':
        actionTitle = 'تم البيع';
        message =
            'هل تريد تغيير حالة الإعلان إلى "تم البيع"؟\n\n$title';
        break;

      case 'archived':
        actionTitle = 'أرشفة';
        message =
            'هل تريد أرشفة هذا الإعلان؟\n\n$title\n\n'
            'يمكنك إعادته إلى "متاح" لاحقًا.';
        break;

      case 'approved':
        actionTitle = 'إعادة إلى متاح';
        message =
            'هل تريد إعادة هذا الإعلان إلى حالة "متاح"؟\n\n$title';
        break;

      default:
        return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: Text(actionTitle),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: Text(actionTitle),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed == true && mounted) {
      await _changeListingStatus(
        listing,
        newStatus,
      );
    }
  }

  Future<void> _deleteListing(
    Map<String, dynamic> listing,
  ) async {
    final title =
        listing['title']?.toString() ?? 'هذا الإعلان';

    final listingId = listing['id'];

    if (listingId is! int) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('حذف الإعلان'),
            content: Text(
              'هل أنت متأكد من حذف:\n\n'
              '$title\n\n'
              'لا يمكن التراجع عن هذه العملية.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('حذف'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _listingsFuture = _deleteAndReload(listingId);
    });

    try {
      await _listingsFuture;

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الإعلان بنجاح.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر حذف الإعلان: $e'),
        ),
      );

      setState(() {
        _listingsFuture = _loadMyListings();
      });
    }
  }

  Future<List<Map<String, dynamic>>> _deleteAndReload(
    int listingId,
  ) async {
    await _supabase
        .from('listings')
        .delete()
        .eq('id', listingId);

    return _loadMyListings();
  }

  String _statusText(String? status) {
    switch (status) {
      case 'pending':
        return 'قيد المراجعة';

      case 'approved':
        return 'متاح';

      case 'rejected':
        return 'مرفوض';

      case 'sold':
        return 'تم البيع';

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

  String _formatPrice(dynamic value) {
  if (value == null) return '';

  final number = num.tryParse(value.toString());

  if (number == null) {
    return value.toString();
  }

  if (number % 1 != 0) {
    return number.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
  }

  return number
      .toInt()
      .toString()
      .replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (match) => ',',
      );
}

String _priceText(Map<String, dynamic> listing) {
  final priceType = listing['price_type']?.toString();
  final price = listing['price'];
  final currency = listing['currency']?.toString() ?? 'SDG';

  if (priceType == 'contact' || price == null) {
    return 'السعر عند التواصل';
  }

  final formattedPrice = _formatPrice(price);

  if (priceType == 'negotiable') {
    return '$formattedPrice $currency قابل للتفاوض';
  }

  return '$formattedPrice $currency';
}

  void _openListing(Map<String, dynamic> listing) {
    final listingId = listing['id'];

    if (listingId is! int) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListingDetailsScreen(
          listingId: listingId,
        ),
      ),
    );
  }

  Widget _buildStatusActions(
    Map<String, dynamic> listing,
  ) {
    final status =
        listing['status']?.toString();

    // الإعلان المتاح.
    if (status == 'approved') {
      return Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _confirmChangeStatus(
                    listing,
                    'sold',
                  ),
                  icon: const Icon(
                    Icons.sell_outlined,
                    size: 19,
                  ),
                  label: const Text('تم البيع'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _confirmChangeStatus(
                    listing,
                    'archived',
                  ),
                  icon: const Icon(
                    Icons.archive_outlined,
                    size: 19,
                  ),
                  label: const Text('أرشفة'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      );
    }

    // الإعلان المباع أو المؤرشف.
    if (status == 'sold' ||
        status == 'archived') {
      return Column(
        crossAxisAlignment:
            CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () =>
                _confirmChangeStatus(
              listing,
              'approved',
            ),
            icon: const Icon(
              Icons.replay_outlined,
              size: 19,
            ),
            label: const Text('إعادة إلى متاح'),
          ),
          const SizedBox(height: 10),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildListingCard(
    Map<String, dynamic> listing,
  ) {
    final status =
        listing['status']?.toString();

    final title =
        listing['title']?.toString() ??
            'إعلان بدون عنوان';

    final area =
        listing['area']?.toString() ?? '';

    final description =
        listing['description']?.toString() ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      child: InkWell(
        borderRadius:
            BorderRadius.circular(12),
        onTap: () => _openListing(listing),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration:
                        BoxDecoration(
                      color: _statusColor(
                        status,
                      ).withValues(
                        alpha: 0.12,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        20,
                      ),
                    ),
                    child: Text(
                      _statusText(status),
                      style: TextStyle(
                        color: _statusColor(
                          status,
                        ),
                        fontSize: 12,
                        fontWeight:
                            FontWeight.bold,
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
                  fontWeight:
                      FontWeight.w600,
                ),
              ),

              if (area.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(area),
                  ],
                ),
              ],

              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  description,
                  maxLines: 2,
                  overflow:
                      TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // أزرار تغيير حالة الإعلان.
              _buildStatusActions(listing),

              // التعديل والحذف.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _editListing(listing),
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 19,
                      ),
                      label: const Text('تعديل'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _deleteListing(listing),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 19,
                      ),
                      label: const Text('حذف'),
                      style:
                          OutlinedButton.styleFrom(
                        foregroundColor:
                            Colors.red,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              const Align(
                alignment:
                    Alignment.centerLeft,
                child: Icon(
                  Icons.chevron_left,
                ),
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
                  _listingsFuture =
                      _loadMyListings();
                });
              },
              icon: const Icon(
                Icons.refresh,
              ),
            ),
          ],
        ),
        body: FutureBuilder<
            List<Map<String, dynamic>>>(
          future: _listingsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState ==
                ConnectionState.waiting) {
              return const Center(
                child:
                    CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 120),
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Center(
                    child: Text(
                      'تعذر تحميل إعلاناتك.',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: Padding(
                      padding:
                          const EdgeInsets.all(16),
                      child: Text(
                        snapshot.error.toString(),
                        textAlign:
                            TextAlign.center,
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _listingsFuture =
                              _loadMyListings();
                        });
                      },
                      child: const Text(
                        'إعادة المحاولة',
                      ),
                    ),
                  ),
                ],
              );
            }

            final listings =
                snapshot.data ?? [];

            if (listings.isEmpty) {
              return RefreshIndicator(
                onRefresh: _refreshListings,
                child: ListView(
                  physics:
                      const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 150),
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 60,
                    ),
                    SizedBox(height: 16),
                    Center(
                      child: Text(
                        'لم تضف أي إعلانات حتى الآن.',
                        style: TextStyle(
                          fontSize: 16,
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Center(
                      child: Text(
                        'اسحب الشاشة إلى الأسفل للتحديث.',
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: _refreshListings,
              child: ListView.builder(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.symmetric(
                  vertical: 8,
                ),
                itemCount: listings.length,
                itemBuilder:
                    (context, index) {
                  return _buildListingCard(
                    listings[index],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}