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

  // رابط الصورة الأولى لكل إعلان.
  final Map<int, String> _listingImageUrls = {};

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

    final listings = List<Map<String, dynamic>>.from(response);

    // تنظيف روابط الصور القديمة.
    _listingImageUrls.clear();

    if (listings.isNotEmpty) {
      final listingIds = listings
          .map((listing) => listing['id'])
          .whereType<int>()
          .toList();

      if (listingIds.isNotEmpty) {
        try {
          final imagesResponse = await _supabase
              .from('listing_images')
              .select(
                'listing_id, image_path, sort_order',
              )
              .inFilter('listing_id', listingIds)
              .order('sort_order', ascending: true);

          final images =
              List<Map<String, dynamic>>.from(
            imagesResponse,
          );

          // نأخذ أول صورة فقط لكل إعلان.
          for (final image in images) {
            final listingId = image['listing_id'];
            final imagePath =
                image['image_path']?.toString();

            if (listingId is int &&
                imagePath != null &&
                imagePath.isNotEmpty &&
                !_listingImageUrls.containsKey(
                  listingId,
                )) {
              final publicUrl = _supabase.storage
                  .from('listing-images')
                  .getPublicUrl(imagePath);

              _listingImageUrls[listingId] =
                  publicUrl;
            }
          }
        } catch (_) {
          // في حالة حدوث مشكلة في الصور،
          // نترك الإعلانات تظهر بصورة طبيعية
          // مع صورة افتراضية.
        }
      }
    }

    return listings;
  }

  Future<void> _refreshListings() async {
    final newFuture = _loadMyListings();

    setState(() {
      _listingsFuture = newFuture;
    });

    await newFuture;
  }

  Future<void> _editListing(
    Map<String, dynamic> listing,
  ) async {
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
          content: Text(
            'تعذر تحديث حالة الإعلان: ${e.message}',
          ),
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
            'هل تريد أرشفة هذا الإعلان؟\n\n'
            '$title\n\n'
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

    return number.toInt().toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
  }

  String _priceText(
    Map<String, dynamic> listing,
  ) {
    final priceType =
        listing['price_type']?.toString();

    final price = listing['price'];

    final currency =
        listing['currency']?.toString() ?? 'SDG';

    if (priceType == 'contact' || price == null) {
      return 'السعر عند التواصل';
    }

    final formattedPrice =
        _formatPrice(price);

    if (priceType == 'negotiable') {
      return '$formattedPrice $currency قابل للتفاوض';
    }

    return '$formattedPrice $currency';
  }

  String _formatDate(dynamic value) {
    if (value == null) {
      return '';
    }

    final date = DateTime.tryParse(
      value.toString(),
    );

    if (date == null) {
      return '';
    }

    final localDate = date.toLocal();

    final day =
        localDate.day.toString().padLeft(2, '0');

    final month =
        localDate.month.toString().padLeft(2, '0');

    final year =
        localDate.year.toString();

    return '$day/$month/$year';
  }

  void _openListing(
    Map<String, dynamic> listing,
  ) {
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

  Widget _buildStatusBadge(String? status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius:
            BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _statusText(status),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusActions(
    Map<String, dynamic> listing,
  ) {
    final status =
        listing['status']?.toString();

    if (status == 'approved') {
      return Column(
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
                    size: 18,
                  ),
                  label: const Text('تم البيع'),
                  style:
                      OutlinedButton.styleFrom(
                    foregroundColor:
                        Colors.blue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _confirmChangeStatus(
                    listing,
                    'archived',
                  ),
                  icon: const Icon(
                    Icons.archive_outlined,
                    size: 18,
                  ),
                  label: const Text('أرشفة'),
                  style:
                      OutlinedButton.styleFrom(
                    foregroundColor:
                        Colors.grey,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      );
    }

    if (status == 'sold' ||
        status == 'archived') {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () =>
                  _confirmChangeStatus(
                listing,
                'approved',
              ),
              icon: const Icon(
                Icons.replay_outlined,
                size: 18,
              ),
              label: const Text(
                'إعادة إلى متاح',
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String text,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImage(
    Map<String, dynamic> listing,
  ) {
    final listingId = listing['id'];

    String? imageUrl;

    if (listingId is int) {
      imageUrl = _listingImageUrls[listingId];
    }

    return Container(
      width: 118,
      height: 118,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius:
            BorderRadius.circular(15),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null
          ? Icon(
              Icons.image_outlined,
              size: 42,
              color: Colors.grey.shade400,
            )
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              loadingBuilder:
                  (
                    context,
                    child,
                    loadingProgress,
                  ) {
                if (loadingProgress == null) {
                  return child;
                }

                return Center(
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                    value: loadingProgress
                                .expectedTotalBytes !=
                            null
                        ? loadingProgress
                                .cumulativeBytesLoaded /
                            loadingProgress
                                .expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder:
                  (
                    context,
                    error,
                    stackTrace,
                  ) {
                return Icon(
                  Icons.broken_image_outlined,
                  size: 42,
                  color: Colors.grey.shade400,
                );
              },
            ),
    );
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
        listing['description']?.toString() ??
            '';

    final createdAt =
        _formatDate(
      listing['created_at'],
    );

    final priceText =
        _priceText(listing);

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(18),
      ),
      child: InkWell(
        onTap: () => _openListing(listing),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              // الصورة + العنوان + الحالة
              Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _buildImage(listing),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 3,
                                overflow:
                                    TextOverflow.ellipsis,
                                style:
                                    const TextStyle(
                                  fontSize: 17,
                                  fontWeight:
                                      FontWeight.bold,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        _buildStatusBadge(status),

                        const SizedBox(height: 10),

                        Text(
                          priceText,
                          maxLines: 2,
                          overflow:
                              TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight.bold,
                            color: Theme.of(
                              context,
                            )
                                .colorScheme
                                .primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 13),

              // معلومات الإعلان
              if (area.isNotEmpty ||
                  createdAt.isNotEmpty)
                Row(
                  children: [
                    if (area.isNotEmpty)
                      Expanded(
                        child: _buildInfoRow(
                          icon: Icons
                              .location_on_outlined,
                          text: area,
                        ),
                      ),
                    if (area.isNotEmpty &&
                        createdAt.isNotEmpty)
                      const SizedBox(width: 12),
                    if (createdAt.isNotEmpty)
                      Expanded(
                        child: _buildInfoRow(
                          icon: Icons
                              .calendar_today_outlined,
                          text: createdAt,
                        ),
                      ),
                  ],
                ),

              if (description.isNotEmpty) ...[
                const SizedBox(height: 11),
                Container(
                  padding:
                      const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey
                        .withValues(alpha: 0.06),
                    borderRadius:
                        BorderRadius.circular(11),
                  ),
                  child: Text(
                    description,
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color:
                          Colors.grey.shade700,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 13),

              // عرض الإعلان
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () =>
                      _openListing(listing),
                  icon: const Icon(
                    Icons.visibility_outlined,
                    size: 18,
                  ),
                  label: const Text(
                    'عرض الإعلان',
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // تغيير الحالة
              _buildStatusActions(listing),

              // تعديل وحذف
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _editListing(listing),
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                      ),
                      label: const Text(
                        'تعديل',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _deleteListing(listing),
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                      ),
                      label: const Text(
                        'حذف',
                      ),
                      style:
                          OutlinedButton.styleFrom(
                        foregroundColor:
                            Colors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _refreshListings,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 130),
          Icon(
            Icons.inventory_2_outlined,
            size: 65,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'لم تضف أي إعلانات حتى الآن.',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'ابدأ بإضافة أول إعلان لك.',
              style: TextStyle(
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    Object? error,
  ) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 110),
        Icon(
          Icons.error_outline,
          size: 52,
          color: Colors.red.shade300,
        ),
        const SizedBox(height: 14),
        const Center(
          child: Text(
            'تعذر تحميل إعلاناتك.',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 24,
          ),
          child: Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: TextButton.icon(
            onPressed: () {
              setState(() {
                _listingsFuture =
                    _loadMyListings();
              });
            },
            icon: const Icon(
              Icons.refresh,
            ),
            label: const Text(
              'إعادة المحاولة',
            ),
          ),
        ),
      ],
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
              return _buildErrorState(
                snapshot.error,
              );
            }

            final listings =
                snapshot.data ?? [];

            if (listings.isEmpty) {
              return _buildEmptyState();
            }

            return RefreshIndicator(
              onRefresh: _refreshListings,
              child: ListView.builder(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding:
                    const EdgeInsets.only(
                  top: 8,
                  bottom: 20,
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