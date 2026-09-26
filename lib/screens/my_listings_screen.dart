import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_decorations.dart';
import 'add_listing_screen.dart';
import 'edit_listing_screen.dart';
import 'listing_details_screen.dart';

class MyListingsScreen extends StatefulWidget {
  const MyListingsScreen({super.key});

  @override
  State<MyListingsScreen> createState() => _MyListingsScreenState();
}

class _MyListingsScreenState extends State<MyListingsScreen> {
  static const String _bucket = 'listing-images';

  static const List<String> _statusOrder = [
    'approved',
    'pending',
    'sold',
    'archived',
    'rejected',
  ];

  final NumberFormat _numberFormat = NumberFormat('#,##0.##', 'en');
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _listings = [];
  Map<String, String?> _imageUrls = {};
  final Set<String> _busyIds = {};

  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  Future<void> _loadListings() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw Exception('يجب تسجيل الدخول أولاً.');
      }

      final data = await _supabase
          .from('listings')
          .select()
          .eq('seller_id', user.id)
          .order('created_at', ascending: false);

      final rows = List<Map<String, dynamic>>.from(data);

      final imageUrls = await _loadImageUrls(
        rows.map((item) => item['id'].toString()).toList(),
      );

      if (!mounted) return;

      setState(() {
        _listings = rows;
        _imageUrls = imageUrls;
        _filter = _normalizeFilter(_filter);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });

      if (_listings.isNotEmpty) {
        _showSnack(
          'تعذر تحديث الإعلانات حالياً',
          isError: true,
        );
      }
    }
  }

  Future<Map<String, String?>> _loadImageUrls(List<String> listingIds) async {
    if (listingIds.isEmpty) return {};

    try {
      final data = await _supabase
          .from('listing_images')
          .select('listing_id, image_path, sort_order')
          .inFilter('listing_id', listingIds)
          .order('sort_order', ascending: true);

      final result = <String, String?>{};

      for (final row in List<Map<String, dynamic>>.from(data)) {
        final listingId = row['listing_id']?.toString();
        final path = row['image_path']?.toString();

        if (listingId == null || path == null || path.isEmpty) {
          continue;
        }

        if (result.containsKey(listingId)) {
          continue;
        }

        if (path.startsWith('http://') || path.startsWith('https://')) {
          result[listingId] = path;
        } else {
          result[listingId] = _supabase.storage
              .from(_bucket)
              .getPublicUrl(path);
        }
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  String _normalizeFilter(String value) {
    if (value == 'all') return value;

    final exists = _listings.any(
      (listing) => (listing['status'] ?? '').toString() == value,
    );

    return exists ? value : 'all';
  }

  void _showSnack(
    String message, {
    bool isError = false,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              isError ? Colors.red.shade700 : AppColors.ink,
          margin: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmText,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text(
              message,
              style: TextStyle(
                color: AppColors.ink.withValues(alpha: 0.72),
                height: 1.6,
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'إلغاء',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      destructive ? Colors.red.shade700 : AppColors.brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  confirmText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    return result ?? false;
  }

  String _statusText(String? status) {
    switch (status) {
      case 'approved':
        return 'منشور';
      case 'pending':
        return 'قيد المراجعة';
      case 'sold':
        return 'تم البيع';
      case 'archived':
        return 'مؤرشف';
      case 'rejected':
        return 'مرفوض';
      default:
        return 'غير محدد';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'approved':
        return Colors.green.shade700;
      case 'pending':
        return AppColors.orange;
      case 'sold':
        return AppColors.brand;
      case 'archived':
        return Colors.blueGrey.shade600;
      case 'rejected':
        return Colors.red.shade700;
      default:
        return AppColors.ink.withValues(alpha: 0.55);
    }
  }

  String _priceText(Map<String, dynamic> listing) {
    final price = listing['price'];
    final priceType = listing['price_type']?.toString();

    if (price == null ||
        priceType == 'contact' ||
        priceType == 'contact_only') {
      return 'السعر عند التواصل';
    }

    final numericPrice = double.tryParse(price.toString());

    if (numericPrice == null) {
      return 'السعر عند التواصل';
    }

    final formatted = _numberFormat.format(numericPrice);
    final currency = listing['currency']?.toString();

    if (currency == null || currency.isEmpty) {
      return formatted;
    }

    return '$formatted $currency';
  }

  String _timeAgo(dynamic value) {
    if (value == null) return '';

    DateTime? date;

    try {
      date = DateTime.parse(value.toString()).toLocal();
    } catch (_) {
      return '';
    }

    final difference = DateTime.now().difference(date);

    if (difference.inMinutes < 1) {
      return 'الآن';
    }

    if (difference.inMinutes < 60) {
      return 'منذ ${difference.inMinutes} دقيقة';
    }

    if (difference.inHours < 24) {
      return 'منذ ${difference.inHours} ساعة';
    }

    if (difference.inDays < 7) {
      return 'منذ ${difference.inDays} يوم';
    }

    if (difference.inDays < 30) {
      return 'منذ ${(difference.inDays / 7).floor()} أسبوع';
    }

    if (difference.inDays < 365) {
      return 'منذ ${(difference.inDays / 30).floor()} شهر';
    }

    return 'منذ ${(difference.inDays / 365).floor()} سنة';
  }

  Future<void> _openListing(Map<String, dynamic> listing) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ListingDetailsScreen(
        listing: listing,
      ),
    ),
  );

  if (mounted) {
    _loadListings();
  }
}

  Future<void> _addListing() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AddListingScreen(),
      ),
    );

    if (mounted) {
      _loadListings();
    }
  }

  Future<void> _editListing(Map<String, dynamic> listing) async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => EditListingScreen(
        listing: listing,
      ),
    ),
  );

  if (mounted) {
    _loadListings();
  }

  Future<void> _confirmChangeStatus(
    Map<String, dynamic> listing,
    String newStatus,
  ) async {
    final listingId = listing['id']?.toString();

    if (listingId == null || listingId.isEmpty) return;

    final title = listing['title']?.toString() ?? 'هذا الإعلان';

    String message;
    String confirmText;

    switch (newStatus) {
      case 'sold':
        message =
            'هل تريد تحديد الإعلان "$title" على أنه تم بيعه؟';
        confirmText = 'تم البيع';
        break;

      case 'archived':
        message =
            'هل تريد أرشفة الإعلان "$title"؟';
        confirmText = 'أرشفة';
        break;

      case 'approved':
        message =
            'هل تريد إعادة نشر الإعلان "$title"؟';
        confirmText = 'نشر';
        break;

      default:
        return;
    }

    final confirmed = await _confirm(
      title: 'تأكيد الإجراء',
      message: message,
      confirmText: confirmText,
    );

    if (!confirmed) return;

    await _changeStatus(
      listingId,
      newStatus,
    );
  }

  Future<void> _changeStatus(
    String listingId,
    String newStatus,
  ) async {
    if (_busyIds.contains(listingId)) return;

    setState(() {
      _busyIds.add(listingId);
    });

    try {
      await _supabase
          .from('listings')
          .update({
            'status': newStatus,
          })
          .eq('id', listingId);

      if (!mounted) return;

      setState(() {
        final index = _listings.indexWhere(
          (listing) => listing['id']?.toString() == listingId,
        );

        if (index != -1) {
          _listings[index] = {
            ..._listings[index],
            'status': newStatus,
          };
        }

        _busyIds.remove(listingId);
        _filter = _normalizeFilter(_filter);
      });

      _showSnack(
        'تم تحديث حالة الإعلان بنجاح',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _busyIds.remove(listingId);
      });

      _showSnack(
        'تعذر تحديث حالة الإعلان',
        isError: true,
      );
    }
  }

  Future<void> _deleteListing(
    Map<String, dynamic> listing,
  ) async {
    final listingId = listing['id']?.toString();

    if (listingId == null || listingId.isEmpty) return;

    final title = listing['title']?.toString() ?? 'هذا الإعلان';

    final confirmed = await _confirm(
      title: 'حذف الإعلان',
      message:
          'هل أنت متأكد من حذف "$title"؟\n\nلا يمكن التراجع عن هذا الإجراء.',
      confirmText: 'حذف نهائياً',
      destructive: true,
    );

    if (!confirmed) return;

    if (_busyIds.contains(listingId)) return;

    setState(() {
      _busyIds.add(listingId);
    });

    try {
      await _deleteImageFiles(listingId);

      await _supabase
          .from('listings')
          .delete()
          .eq('id', listingId);

      if (!mounted) return;

      setState(() {
        _listings.removeWhere(
          (item) => item['id']?.toString() == listingId,
        );
        _imageUrls.remove(listingId);
        _busyIds.remove(listingId);
        _filter = _normalizeFilter(_filter);
      });

      _showSnack(
        'تم حذف الإعلان بنجاح',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _busyIds.remove(listingId);
      });

      _showSnack(
        'تعذر حذف الإعلان، حاول مرة أخرى',
        isError: true,
      );

      await _loadListings();
    }
  }

  Future<void> _deleteImageFiles(String listingId) async {
    try {
      final rows = await _supabase
          .from('listing_images')
          .select('image_path')
          .eq('listing_id', listingId);

      final paths = <String>[];

      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final path = row['image_path']?.toString();

        if (path != null &&
            path.isNotEmpty &&
            !path.startsWith('http://') &&
            !path.startsWith('https://')) {
          paths.add(path);
        }
      }

      if (paths.isNotEmpty) {
        try {
          await _supabase.storage
              .from(_bucket)
              .remove(paths);
        } catch (_) {
          // لا نوقف حذف الإعلان إذا فشل حذف الملفات من التخزين.
        }
      }
    } catch (_) {
      // لا نوقف حذف الإعلان بسبب خطأ في جلب الصور.
    }
  }

  void _onMenuSelected(
    String value,
    Map<String, dynamic> listing,
  ) {
    switch (value) {
      case 'view':
        final id = listing['id']?.toString();

        if (id != null) {
          _openListing(listing);
        }
        break;

      case 'edit':
        final id = listing['id']?.toString();

        if (id != null) {
          _openListing(listing);
        }
        break;

      case 'sold':
        _confirmChangeStatus(
          listing,
          'sold',
        );
        break;

      case 'archive':
        _confirmChangeStatus(
          listing,
          'archived',
        );
        break;

      case 'publish':
        _confirmChangeStatus(
          listing,
          'approved',
        );
        break;

      case 'delete':
        _deleteListing(listing);
        break;
    }
  }

  Widget _buildStatusBadge(String? status) {
    final color = _statusColor(status);
    final text = _statusText(status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: color.withValues(alpha: 0.20),
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
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(
    String listingId,
  ) {
    final imageUrl = _imageUrls[listingId];

    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.brand.withValues(alpha: 0.10),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null || imageUrl.isEmpty
          ? const Center(
              child: Icon(
                Icons.image_outlined,
                color: AppColors.brand,
                size: 32,
              ),
            )
          : CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.brand,
                  ),
                ),
              ),
              errorWidget: (_, __, ___) => const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.brand,
                  size: 30,
                ),
              ),
            ),
    );
  }

  List<PopupMenuEntry<String>> _menuItems(
    Map<String, dynamic> listing,
  ) {
    final status = listing['status']?.toString();

    return [
      const PopupMenuItem<String>(
        value: 'view',
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.visibility_outlined,
            color: AppColors.ink,
          ),
          title: Text('عرض الإعلان'),
        ),
      ),
      const PopupMenuItem<String>(
        value: 'edit',
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.edit_outlined,
            color: AppColors.brand,
          ),
          title: Text('تعديل الإعلان'),
        ),
      ),
      if (status == 'approved')
        const PopupMenuItem<String>(
          value: 'sold',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.sell_outlined,
              color: AppColors.brand,
            ),
            title: Text('تحديد كمباع'),
          ),
        ),
      if (status == 'approved' || status == 'sold')
        const PopupMenuItem<String>(
          value: 'archive',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.archive_outlined,
              color: Colors.blueGrey,
            ),
            title: Text('أرشفة'),
          ),
        ),
      if (status == 'archived' || status == 'rejected')
        const PopupMenuItem<String>(
          value: 'publish',
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              Icons.publish_outlined,
              color: AppColors.brand,
            ),
            title: Text('إعادة النشر'),
          ),
        ),
      const PopupMenuDivider(),
      const PopupMenuItem<String>(
        value: 'delete',
        child: ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.delete_outline,
            color: Colors.red,
          ),
          title: Text(
            'حذف الإعلان',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildListingCard(
    Map<String, dynamic> listing,
  ) {
    final listingId = listing['id']?.toString() ?? '';
    final status = listing['status']?.toString();
    final title = listing['title']?.toString() ?? 'بدون عنوان';
    final area = listing['area']?.toString();
    final time = _timeAgo(listing['created_at']);
    final busy = _busyIds.contains(listingId);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: AppDecorations.card(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: busy || listingId.isEmpty
              ? null
              : () => _openListing(listing),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildThumbnail(listingId),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: 'خيارات الإعلان',
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.more_vert,
                                  color: AppColors.ink,
                                ),
                                onSelected: busy
                                    ? null
                                    : (value) => _onMenuSelected(
                                          value,
                                          listing,
                                        ),
                                itemBuilder: (_) =>
                                    _menuItems(listing),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _priceText(listing),
                            style: const TextStyle(
                              color: AppColors.brand,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildStatusBadge(status),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.only(top: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: AppColors.brand.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (area != null && area.isNotEmpty) ...[
                        Icon(
                          Icons.location_on_outlined,
                          size: 16,
                          color: AppColors.ink.withValues(alpha: 0.52),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            area,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppColors.ink.withValues(alpha: 0.62),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ] else
                        const Spacer(),
                      if (time.isNotEmpty) ...[
                        Icon(
                          Icons.schedule_outlined,
                          size: 15,
                          color: AppColors.ink.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          time,
                          style: TextStyle(
                            color: AppColors.ink.withValues(alpha: 0.55),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (status == 'rejected') ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.red.shade700,
                          size: 19,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            listing['rejection_reason']?.toString() ??
                                'تم رفض الإعلان. يمكنك تعديله وإعادة إرساله.',
                            style: TextStyle(
                              color: Colors.red.shade800,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (status == 'pending') ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.hourglass_top_rounded,
                          color: AppColors.brand,
                          size: 18,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'الإعلان قيد المراجعة وسيظهر للمستخدمين بعد اعتماده.',
                            style: TextStyle(
                              color: AppColors.ink,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (status == 'rejected' || status == 'pending') ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: busy || listingId.isEmpty
                          ? null
                          : () => _editListing(listing),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brand,
                        side: BorderSide(
                          color: AppColors.brand.withValues(alpha: 0.35),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 11,
                        ),
                      ),
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 18,
                      ),
                      label: const Text(
                        'تعديل الإعلان',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
                if (status == 'approved') ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: busy || listingId.isEmpty
                          ? null
                          : () => _confirmChangeStatus(
                                listing,
                                'sold',
                              ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brand,
                        side: BorderSide(
                          color: AppColors.brand.withValues(alpha: 0.28),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 11,
                        ),
                      ),
                      icon: const Icon(
                        Icons.sell_outlined,
                        size: 18,
                      ),
                      label: const Text(
                        'تم البيع',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
                if (busy) ...[
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(
                    minHeight: 2,
                    color: AppColors.brand,
                    backgroundColor: AppColors.brandSoft,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    final counts = <String, int>{
      'all': _listings.length,
      for (final status in _statusOrder)
        status: _listings
            .where(
              (listing) =>
                  (listing['status'] ?? '').toString() == status,
            )
            .length,
    };

    final filters = <String>[
      'all',
      ..._statusOrder,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: AppDecorations.card(),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((filter) {
            final selected = _filter == filter;
            final count = counts[filter] ?? 0;

            return Padding(
              padding: const EdgeInsetsDirectional.only(
                end: 8,
              ),
              child: ChoiceChip(
                selected: selected,
                onSelected: (_) {
                  setState(() {
                    _filter = filter;
                  });
                },
                selectedColor: AppColors.brandSoft,
                backgroundColor: Colors.white,
                side: BorderSide(
                  color: selected
                      ? AppColors.brand
                      : AppColors.brand.withValues(alpha: 0.12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                label: Text(
                  '${filter == 'all' ? 'الكل' : _statusText(filter)} ($count)',
                ),
                labelStyle: TextStyle(
                  color: selected
                      ? AppColors.brand
                      : AppColors.ink.withValues(alpha: 0.70),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
                checkmarkColor: AppColors.brand,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isFiltered = _filter != 'all';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                color: AppColors.brandSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
                size: 44,
                color: AppColors.brand,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isFiltered
                  ? 'لا توجد إعلانات بهذه الحالة'
                  : 'لا توجد لديك إعلانات بعد',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Text(
              isFiltered
                  ? 'جرّب اختيار حالة أخرى من الفلاتر أعلاه.'
                  : 'ابدأ بإضافة أول إعلان لك في دلالة شبشة.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.ink.withValues(alpha: 0.62),
                fontSize: 13,
                height: 1.6,
              ),
            ),
            if (!isFiltered) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _addListing,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(
                  Icons.add_rounded,
                ),
                label: const Text(
                  'إضافة إعلان',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.red.withValues(alpha: 0.12),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.07),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_outlined,
                  color: Colors.red.shade700,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'تعذر تحميل إعلاناتك',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'حدث خطأ غير متوقع.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.ink.withValues(alpha: 0.62),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loadListings,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: const Icon(
                  Icons.refresh_rounded,
                ),
                label: const Text(
                  'إعادة المحاولة',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
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
        child: CircularProgressIndicator(
          color: AppColors.brand,
        ),
      );
    }

    if (_error != null && _listings.isEmpty) {
      return _buildErrorState();
    }

    final filteredListings = _filter == 'all'
        ? _listings
        : _listings
            .where(
              (listing) =>
                  (listing['status'] ?? '').toString() == _filter,
            )
            .toList();

    if (_listings.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      color: AppColors.brand,
      backgroundColor: Colors.white,
      onRefresh: _loadListings,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          14,
          14,
          14,
          100,
        ),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  AppColors.brand,
                  AppColors.brandDark,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand.withValues(alpha: 0.18),
                  blurRadius: 16,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إعلاناتك',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${_listings.length} إعلان${_listings.length == 1 ? '' : 'ات'} في حسابك',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _loading ? null : _loadListings,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          _buildFilters(),
          if (filteredListings.isEmpty)
            _buildEmptyState()
          else
            ...filteredListings.map(_buildListingCard),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.pageBackground,
        appBar: AppBar(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'إعلاناتي',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _loadListings,
              icon: const Icon(
                Icons.refresh_rounded,
                color: Colors.white,
              ),
            ),
          ],
        ),
        body: _buildBody(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addListing,
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          elevation: 5,
          icon: const Icon(
            Icons.add_rounded,
          ),
          label: const Text(
            'إعلان جديد',
            style: TextStyle(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}