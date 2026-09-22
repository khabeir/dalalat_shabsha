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

  List<Map<String, dynamic>> _pendingListings = [];
  List<Map<String, dynamic>> _approvedListings = [];

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

      final pendingData = await _supabase
          .from('listings')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      final approvedData = await _supabase
          .from('listings')
          .select()
          .eq('status', 'approved')
          .order('created_at', ascending: false);

      final approvedListings =
          List<Map<String, dynamic>>.from(approvedData);

      /*
       * جلب آخر سجل ترويج لكل إعلان معتمد.
       */
      if (approvedListings.isNotEmpty) {
        final approvedIds = approvedListings
            .map((listing) => listing['id'])
            .where((id) => id != null)
            .toList();

        if (approvedIds.isNotEmpty) {
          final promotedData = await _supabase
              .from('promoted_listings')
              .select(
                'id, listing_id, start_at, end_at, '
                'is_active, created_by',
              )
              .inFilter('listing_id', approvedIds)
              .order('id', ascending: false);

          final promotedRows =
              List<Map<String, dynamic>>.from(promotedData);

          /*
           * نأخذ أحدث سجل ترويج لكل إعلان.
           */
          final promotionByListingId =
              <dynamic, Map<String, dynamic>>{};

          for (final promotion in promotedRows) {
            final listingId = promotion['listing_id'];

            if (listingId == null) continue;

            if (!promotionByListingId.containsKey(listingId)) {
              promotionByListingId[listingId] = promotion;
            }
          }

          for (final listing in approvedListings) {
            final promotion =
                promotionByListingId[listing['id']];

            if (promotion != null) {
              listing['promoted_listing_id'] =
                  promotion['id'];

              listing['promotion_start_at'] =
                  promotion['start_at'];

              listing['promotion_end_at'] =
                  promotion['end_at'];

              listing['promotion_is_active'] =
                  promotion['is_active'];
            }
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _isAdmin = true;
        _pendingListings =
            List<Map<String, dynamic>>.from(pendingData);
        _approvedListings = approvedListings;
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
        _pendingListings.removeWhere(
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

      /*
       * إذا تمت الموافقة، نعيد تحميل القائمة
       * حتى يظهر الإعلان في قسم الإعلانات المعتمدة.
       */
      await _loadListings();
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

  String _formatPrice(
    dynamic price,
    dynamic priceType,
  ) {
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

    final value = DateTime.tryParse(
      date.toString(),
    );

    if (value == null) {
      return '';
    }

    final local = value.toLocal();

    return '${local.year}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  bool _isPromotionActive(
    Map<String, dynamic> listing,
  ) {
    final isActive =
        listing['promotion_is_active'] == true;

    if (!isActive) return false;

    final endAt = DateTime.tryParse(
      listing['promotion_end_at']?.toString() ?? '',
    );

    if (endAt == null) return false;

    return endAt.isAfter(DateTime.now().toUtc());
  }

  bool _hasPromotion(
    Map<String, dynamic> listing,
  ) {
    return listing['promoted_listing_id'] != null;
  }

  Future<void> _promoteListing(
    Map<String, dynamic> listing,
  ) async {
    final listingId = listing['id'];

    if (listingId == null) return;

    final currentPromotionId =
        listing['promoted_listing_id'];

    final currentUser =
        _supabase.auth.currentUser;

    if (currentUser == null) return;

    final days = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('إعلان تجاري'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                listing['title']?.toString() ??
                    'بدون عنوان',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              const Text(
                'اختر مدة الترويج:',
              ),
              const SizedBox(height: 10),

              _durationOption(
                context,
                1,
                'يوم واحد',
              ),

              _durationOption(
                context,
                3,
                '3 أيام',
              ),

              _durationOption(
                context,
                7,
                '7 أيام',
              ),

              _durationOption(
                context,
                14,
                '14 يومًا',
              ),

              _durationOption(
                context,
                30,
                '30 يومًا',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('إلغاء'),
            ),
          ],
        );
      },
    );

    if (days == null) return;

    try {
      final startAt = DateTime.now().toUtc();
      final endAt = startAt.add(
        Duration(days: days),
      );

      final data = {
        'listing_id': listingId,
        'start_at': startAt.toIso8601String(),
        'end_at': endAt.toIso8601String(),
        'is_active': true,
        'created_by': currentUser.id,
      };

      /*
       * إذا كان هناك سجل ترويج سابق للإعلان،
       * نعيد استخدامه بدلاً من إنشاء سجل مكرر.
       */
      if (currentPromotionId != null) {
        await _supabase
            .from('promoted_listings')
            .update({
              'start_at': data['start_at'],
              'end_at': data['end_at'],
              'is_active': true,
              'created_by': data['created_by'],
            })
            .eq(
              'id',
              currentPromotionId,
            );
      } else {
        await _supabase
            .from('promoted_listings')
            .insert(data);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تفعيل الإعلان التجاري لمدة $days يوم',
          ),
        ),
      );

      await _loadListings();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر تفعيل الإعلان التجاري: $e',
          ),
        ),
      );
    }
  }

  Widget _durationOption(
    BuildContext context,
    int days,
    String label,
  ) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {
          Navigator.pop(context, days);
        },
        child: Text(label),
      ),
    );
  }

  Future<void> _stopPromotion(
    Map<String, dynamic> listing,
  ) async {
    final promotionId =
        listing['promoted_listing_id'];

    if (promotionId == null) return;

    final shouldStop = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'إيقاف الإعلان التجاري',
          ),
          content: const Text(
            'هل تريد إيقاف الترويج لهذا الإعلان؟',
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
              child: const Text('إيقاف'),
            ),
          ],
        );
      },
    );

    if (shouldStop != true) return;

    try {
      await _supabase
          .from('promoted_listings')
          .update({
            'is_active': false,
          })
          .eq(
            'id',
            promotionId,
          );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم إيقاف الإعلان التجاري',
          ),
        ),
      );

      await _loadListings();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر إيقاف الإعلان التجاري: $e',
          ),
        ),
      );
    }
  }

  Widget _buildCommercialButton(
    Map<String, dynamic> listing,
  ) {
    final hasPromotion =
        _hasPromotion(listing);

    final active =
        _isPromotionActive(listing);

    if (active) {
      return Expanded(
        child: FilledButton.icon(
          onPressed: () {
            _showPromotionManagement(
              listing,
            );
          },
          icon: const Icon(
            Icons.campaign,
            size: 18,
          ),
          label: const Text(
            'إدارة الإعلان التجاري',
          ),
        ),
      );
    }

    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () {
          _promoteListing(listing);
        },
        icon: Icon(
          hasPromotion
              ? Icons.refresh
              : Icons.campaign_outlined,
          size: 18,
        ),
        label: Text(
          hasPromotion
              ? 'إعادة التفعيل'
              : 'إعلان تجاري',
        ),
      ),
    );
  }

  Future<void> _showPromotionManagement(
    Map<String, dynamic> listing,
  ) async {
    final promotionId =
        listing['promoted_listing_id'];

    if (promotionId == null) return;

    final startAt =
        _formatDate(
      listing['promotion_start_at'],
    );

    final endAt =
        _formatDate(
      listing['promotion_end_at'],
    );

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'الإعلان التجاري',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                listing['title']?.toString() ??
                    'بدون عنوان',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.play_arrow_outlined,
                ),
                title: const Text(
                  'بدأ الترويج',
                ),
                subtitle: Text(startAt),
              ),
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.event_outlined,
                ),
                title: const Text(
                  'ينتهي الترويج',
                ),
                subtitle: Text(endAt),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('إغلاق'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _stopPromotion(listing);
              },
              icon: const Icon(
                Icons.stop_circle_outlined,
              ),
              label: const Text(
                'إيقاف الترويج',
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildListingCard(
    Map<String, dynamic> listing, {
    bool showCommercial = false,
  }) {
    final id = listing['id'];

    final promotionActive =
        _isPromotionActive(listing);

    return Card(
      margin: const EdgeInsets.only(
        bottom: 12,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                    listing['title']?.toString() ??
                        'بدون عنوان',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                if (promotionActive)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primary,
                      borderRadius:
                          BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'تجاري',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            Text(
              listing['description']
                      ?.toString() ??
                  '',
              maxLines: 3,
              overflow:
                  TextOverflow.ellipsis,
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
                listing['area']
                    .toString()
                    .isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.only(
                  top: 4,
                ),
                child: Text(
                  'المنطقة: ${listing['area']}',
                ),
              ),

            if (listing['contact_phone'] != null &&
                listing['contact_phone']
                    .toString()
                    .isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.only(
                  top: 4,
                ),
                child: Text(
                  'الهاتف: ${listing['contact_phone']}',
                ),
              ),

            if (listing['created_at'] != null)
              Padding(
                padding:
                    const EdgeInsets.only(
                  top: 4,
                ),
                child: Text(
                  'تاريخ الإضافة: '
                  '${_formatDate(listing['created_at'])}',
                  style: TextStyle(
                    color:
                        Colors.grey.shade700,
                    fontSize: 12,
                  ),
                ),
              ),

            if (promotionActive) ...[
              const SizedBox(height: 6),
              Text(
                'ينتهي الإعلان التجاري: '
                '${_formatDate(listing['promotion_end_at'])}',
                style: TextStyle(
                  color: Theme.of(context)
                      .colorScheme
                      .primary,
                  fontSize: 12,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child:
                      OutlinedButton.icon(
                    onPressed: () {
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
                    icon: const Icon(
                      Icons.visibility_outlined,
                    ),
                    label: const Text(
                      'عرض',
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                if (showCommercial)
                  _buildCommercialButton(
                    listing,
                  )
                else ...[
                  Expanded(
                    child:
                        FilledButton.icon(
                      onPressed: () {
                        _approveListing(id);
                      },
                      icon: const Icon(
                        Icons.check,
                      ),
                      label: const Text(
                        'موافقة',
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child:
                        OutlinedButton.icon(
                      onPressed: () {
                        _rejectListing(id);
                      },
                      icon: const Icon(
                        Icons.close,
                      ),
                      label: const Text(
                        'رفض',
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    String title,
    int count,
    IconData icon,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        top: 8,
        bottom: 10,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: Theme.of(context)
                .colorScheme
                .primary,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest,
              borderRadius:
                  BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection:
          TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'لوحة تحكم الأدمن',
          ),
          actions: [
            IconButton(
              onPressed:
                  _loading
                      ? null
                      : _loadListings,
              icon: const Icon(
                Icons.refresh,
              ),
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
        child:
            CircularProgressIndicator(),
      );
    }

    if (!_isAdmin) {
      return const Center(
        child: Padding(
          padding:
              EdgeInsets.all(24),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 64,
              ),
              SizedBox(height: 16),
              Text(
                'هذه الصفحة مخصصة للأدمن فقط',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_pendingListings.isEmpty &&
        _approvedListings.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadListings,
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
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
                    'لا توجد إعلانات حالياً',
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
      child: ListView(
        padding:
            const EdgeInsets.all(12),
        children: [
          // =================================================
          // الإعلانات المعلقة
          // =================================================

          if (_pendingListings.isNotEmpty) ...[
            _buildSectionHeader(
              'إعلانات معلقة للمراجعة',
              _pendingListings.length,
              Icons.pending_actions,
            ),

            ..._pendingListings.map(
              (listing) =>
                  _buildListingCard(
                listing,
              ),
            ),

            const SizedBox(height: 12),
          ],

          // =================================================
          // الإعلانات المعتمدة
          // =================================================

          if (_approvedListings.isNotEmpty) ...[
            _buildSectionHeader(
              'الإعلانات المعتمدة',
              _approvedListings.length,
              Icons.verified_outlined,
            ),

            ..._approvedListings.map(
              (listing) =>
                  _buildListingCard(
                listing,
                showCommercial: true,
              ),
            ),
          ],
        ],
      ),
    );
  }
}