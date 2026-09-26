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
  static const _bucket = 'listing-images';

  // ترتيب ظهور الحالات في شريط التصفية.
  static const _statusOrder = [
    'approved',
    'pending',
    'sold',
    'archived',
    'rejected',
  ];

  static final _numberFormat = NumberFormat('#,##0.##', 'en');

  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _listings = [];

  // رابط الصورة الأولى لكل إعلان.
  Map<int, String> _imageUrls = {};

  // إعلانات جارٍ تنفيذ عملية عليها.
  final Set<int> _busyIds = {};

  bool _loading = true;
  String? _error;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadListings();
  }

  // =========================
  // تحميل البيانات
  // =========================
  Future<void> _loadListings({bool silent = false}) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = 'يجب تسجيل الدخول أولاً.';
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
          .from('listings')
          .select()
          .eq('seller_id', user.id)
          .order('created_at', ascending: false);

      final listings = List<Map<String, dynamic>>.from(response);

      final imageUrls = await _loadImageUrls(listings);

      if (!mounted) return;

      setState(() {
        _listings = listings;
        _imageUrls = imageUrls;
        _loading = false;
        _error = null;
        _normalizeFilter();
      });
    } catch (e) {
      debugPrint('loadMyListings error: $e');

      if (!mounted) return;

      if (silent && _listings.isNotEmpty) {
        _showSnack('تعذر تحديث الإعلانات');
        return;
      }

      setState(() {
        _error =
            'تعذر تحميل إعلاناتك. تحقق من اتصال الإنترنت وحاول مجدداً.';
        _loading = false;
      });
    }
  }

  // أول صورة لكل إعلان. الصور اختيارية فلا نفشل إن تعذّرت.
  Future<Map<int, String>> _loadImageUrls(
    List<Map<String, dynamic>> listings,
  ) async {
    final urls = <int, String>{};

    final ids = listings.map((l) => l['id']).whereType<int>().toList();

    if (ids.isEmpty) return urls;

    try {
      final response = await _supabase
          .from('listing_images')
          .select('listing_id, image_path, sort_order')
          .inFilter('listing_id', ids)
          .order('sort_order', ascending: true);

      for (final image in List<Map<String, dynamic>>.from(response)) {
        final listingId = image['listing_id'];
        final path = image['image_path']?.toString().trim() ?? '';

        if (listingId is int &&
            path.isNotEmpty &&
            !urls.containsKey(listingId)) {
          urls[listingId] = path.startsWith('http')
              ? path
              : _supabase.storage.from(_bucket).getPublicUrl(path);
        }
      }
    } catch (e) {
      debugPrint('my listings images error: $e');
    }

    return urls;
  }

  // إن أصبحت الحالة المختارة بلا إعلانات نعود إلى "الكل".
  void _normalizeFilter() {
    if (_filter == 'all') return;

    final hasAny = _listings.any((l) => l['status'] == _filter);

    if (!hasAny) _filter = 'all';
  }

  // =========================
  // أدوات مساعدة
  // =========================
  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: destructive
                        ? Colors.red.withValues(alpha: 0.10)
                        : AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    destructive
                        ? Icons.warning_amber_rounded
                        : Icons.help_outline_rounded,
                    color: destructive ? Colors.red.shade700 : AppColors.brand,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor:
                      destructive ? Colors.red.shade700 : AppColors.brand,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        );
      },
    );

    return result == true;
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
        return Colors.orange.shade800;
      case 'approved':
        return Colors.green.shade700;
      case 'rejected':
        return Colors.red.shade700;
      case 'sold':
        return Colors.blue.shade700;
      case 'archived':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  IconData _statusIcon(String? status) {
    switch (status) {
      case 'pending':
        return Icons.hourglass_top_rounded;
      case 'approved':
        return Icons.check_circle_outline;
      case 'rejected':
        return Icons.cancel_outlined;
      case 'sold':
        return Icons.sell_outlined;
      case 'archived':
        return Icons.archive_outlined;
      default:
        return Icons.help_outline;
    }
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

    final formatted =
        number == null ? price.toString() : _numberFormat.format(number);

    final suffix =
        listing['price_type'] == 'negotiable' ? ' · قابل للتفاوض' : '';

    return '$formatted $currency$suffix';
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

  // =========================
  // العمليات
  // =========================
  void _openListing(Map<String, dynamic> listing) {
    final id = listing['id'];

    if (id is! int) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ListingDetailsScreen(listingId: id),
      ),
    );
  }

  Future<void> _addListing() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddListingScreen()),
    );

    if (mounted) await _loadListings(silent: true);
  }

  Future<void> _editListing(Map<String, dynamic> listing) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditListingScreen(listing: listing),
      ),
    );

    if (result == true && mounted) {
      await _loadListings(silent: true);
    }
  }

  Future<void> _confirmChangeStatus(
    Map<String, dynamic> listing,
    String newStatus,
  ) async {
    final title = listing['title']?.toString() ?? 'هذا الإعلان';

    final String actionTitle;
    final String message;

    switch (newStatus) {
      case 'sold':
        actionTitle = 'تم البيع';
        message = 'هل تريد تغيير حالة الإعلان إلى "تم البيع"؟\n\n$title';
        break;
      case 'archived':
        actionTitle = 'أرشفة';
        message = 'هل تريد أرشفة هذا الإعلان؟\n\n$title\n\n'
            'يمكنك إعادته إلى "متاح" لاحقاً.';
        break;
      case 'approved':
        actionTitle = 'إعادة إلى متاح';
        message = 'هل تريد إعادة هذا الإعلان إلى حالة "متاح"؟\n\n$title';
        break;
      default:
        return;
    }

    final confirmed = await _confirm(
      title: actionTitle,
      message: message,
      confirmLabel: actionTitle,
    );

    if (confirmed && mounted) {
      await _changeStatus(listing, newStatus);
    }
  }

  Future<void> _changeStatus(
    Map<String, dynamic> listing,
    String newStatus,
  ) async {
    final id = listing['id'];

    if (id is! int || _busyIds.contains(id)) return;

    final String message;

    switch (newStatus) {
      case 'sold':
        message = 'تم تغيير حالة الإعلان إلى "تم البيع".';
        break;
      case 'archived':
        message = 'تمت أرشفة الإعلان.';
        break;
      case 'approved':
        message = 'تمت إعادة الإعلان إلى "متاح".';
        break;
      default:
        message = 'تم تحديث حالة الإعلان.';
    }

    setState(() => _busyIds.add(id));

    try {
      await _supabase
          .from('listings')
          .update({'status': newStatus}).eq('id', id);

      if (!mounted) return;

      setState(() {
        listing['status'] = newStatus;
        _normalizeFilter();
      });

      _showSnack(message);
    } catch (e) {
      debugPrint('changeStatus error: $e');
      _showSnack('تعذر تحديث حالة الإعلان، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _deleteListing(Map<String, dynamic> listing) async {
    final id = listing['id'];

    if (id is! int || _busyIds.contains(id)) return;

    final title = listing['title']?.toString() ?? 'هذا الإعلان';

    final confirmed = await _confirm(
      title: 'حذف الإعلان',
      message: 'هل أنت متأكد من حذف:\n\n$title\n\n'
          'سيُحذف الإعلان وصوره نهائياً ولا يمكن التراجع.',
      confirmLabel: 'حذف',
      destructive: true,
    );

    if (!confirmed || !mounted) return;

    setState(() => _busyIds.add(id));

    try {
      await _deleteImageFiles(id);

      await _supabase.from('listings').delete().eq('id', id);

      if (!mounted) return;

      setState(() {
        _listings.removeWhere((l) => l['id'] == id);
        _imageUrls.remove(id);
        _normalizeFilter();
      });

      _showSnack('تم حذف الإعلان بنجاح.');
    } catch (e) {
      debugPrint('deleteListing error: $e');
      _showSnack('تعذر حذف الإعلان، حاول مرة أخرى');

      if (mounted) await _loadListings(silent: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  // حذف ملفات صور الإعلان من التخزين (لا نوقف الحذف إن فشلت).
  Future<void> _deleteImageFiles(int listingId) async {
    try {
      final response = await _supabase
          .from('listing_images')
          .select('image_path')
          .eq('listing_id', listingId);

      final paths = List<Map<String, dynamic>>.from(response)
          .map((row) => row['image_path']?.toString().trim() ?? '')
          .where((path) => path.isNotEmpty && !path.startsWith('http'))
          .toList();

      if (paths.isEmpty) return;

      await _supabase.storage.from(_bucket).remove(paths);
    } catch (e) {
      debugPrint('deleteImageFiles error: $e');
    }
  }

  void _onMenuSelected(String value, Map<String, dynamic> listing) {
    switch (value) {
      case 'view':
        _openListing(listing);
        break;
      case 'edit':
        _editListing(listing);
        break;
      case 'sold':
        _confirmChangeStatus(listing, 'sold');
        break;
      case 'archive':
        _confirmChangeStatus(listing, 'archived');
        break;
      case 'restore':
        _confirmChangeStatus(listing, 'approved');
        break;
      case 'delete':
        _deleteListing(listing);
        break;
    }
  }

  // =========================
  // مكوّنات الواجهة
  // =========================
  Widget _buildStatusBadge(String? status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _statusIcon(status),
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            _statusText(status),
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(int? id) {
    final url = id == null ? null : _imageUrls[id];

    Widget placeholder(IconData icon) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              AppColors.brandSoft,
              AppColors.pageBackground,
            ],
          ),
        ),
        child: Icon(
          icon,
          size: 34,
          color: AppColors.brand,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 92,
        height: 92,
        child: url == null
            ? placeholder(Icons.image_outlined)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                memCacheWidth: 300,
                placeholder: (_, __) => placeholder(Icons.image_outlined),
                errorWidget: (_, __, ___) =>
                    placeholder(Icons.broken_image_outlined),
              ),
      ),
    );
  }

  List<PopupMenuEntry<String>> _menuItems(String? status) {
    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String label, {
      Color? color,
    }) {
      return PopupMenuItem<String>(
        value: value,
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: color ?? AppColors.ink,
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                color: color ?? AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return [
      item('view', Icons.visibility_outlined, 'عرض الإعلان'),
      item('edit', Icons.edit_outlined, 'تعديل'),
      if (status == 'approved') ...[
        item('sold', Icons.sell_outlined, 'تم البيع'),
        item('archive', Icons.archive_outlined, 'أرشفة'),
      ],
      if (status == 'sold' || status == 'archived')
        item('restore', Icons.replay_outlined, 'إعادة إلى متاح'),
      const PopupMenuDivider(),
      item(
        'delete',
        Icons.delete_outline,
        'حذف',
        color: Colors.red.shade700,
      ),
    ];
  }

  Widget _buildListingCard(Map<String, dynamic> listing) {
    final colorScheme = Theme.of(context).colorScheme;

    final id = listing['id'] as int?;
    final status = listing['status']?.toString();
    final busy = id != null && _busyIds.contains(id);

    final rawTitle = listing['title']?.toString().trim() ?? '';
    final title = rawTitle.isEmpty ? 'إعلان بدون عنوان' : rawTitle;

    final area = listing['area']?.toString().trim() ?? '';
    final timeAgo = _timeAgo(listing['created_at']);

    final meta = [
      if (area.isNotEmpty) area,
      if (timeAgo.isNotEmpty) timeAgo,
    ].join(' · ');

    Widget? statusAction;

    if (status == 'approved') {
      statusAction = FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          foregroundColor: AppColors.brand,
          backgroundColor: AppColors.brandSoft,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 11,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: busy
            ? null
            : () => _confirmChangeStatus(listing, 'sold'),
        icon: const Icon(Icons.sell_outlined, size: 18),
        label: const Text('تم البيع'),
      );
    } else if (status == 'sold' || status == 'archived') {
      statusAction = FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          foregroundColor: AppColors.brand,
          backgroundColor: AppColors.brandSoft,
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 11,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: busy
            ? null
            : () => _confirmChangeStatus(listing, 'approved'),
        icon: const Icon(Icons.replay_outlined, size: 18),
        label: const Text('إعادة إلى متاح'),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: AppDecorations.card(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : () => _openListing(listing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy)
              const LinearProgressIndicator(
                minHeight: 3,
                color: AppColors.brand,
                backgroundColor: AppColors.brandSoft,
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildThumbnail(id),

                      const SizedBox(width: 12),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.ink,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _priceText(listing),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.brand,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 7),
                            _buildStatusBadge(status),
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: 7),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_outlined,
                                    size: 14,
                                    color: AppColors.brand,
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
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                      PopupMenuButton<String>(
                        enabled: !busy,
                        tooltip: 'المزيد',
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          color: AppColors.ink,
                        ),
                        onSelected: (value) =>
                            _onMenuSelected(value, listing),
                        itemBuilder: (_) => _menuItems(status),
                      ),
                    ],
                  ),

                  if (status == 'rejected')
                    Container(
                      margin: const EdgeInsets.only(top: 10, left: 6),
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 20,
                            color: Colors.red.shade700,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (listing['rejection_reason']
                                          ?.toString()
                                          .trim()
                                          .isNotEmpty ??
                                      false)
                                  ? 'سبب الرفض: ${listing['rejection_reason']}\n'
                                      'عدّل الإعلان ثم احفظ ليُعاد إرساله للمراجعة.'
                                  : 'تم رفض الإعلان. عدّله ثم احفظ ليُعاد إرساله للمراجعة.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.5,
                                color: Colors.red.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (status == 'pending')
                    Container(
                      margin: const EdgeInsets.only(top: 10, left: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.hourglass_top_rounded,
                            size: 19,
                            color: AppColors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'بانتظار مراجعة الإدارة، وسيظهر للجميع بعد الموافقة.',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.5,
                                color: Colors.orange.shade900,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 11),

                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.brand,
                              side: const BorderSide(
                                color: AppColors.brand,
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed:
                                busy ? null : () => _editListing(listing),
                            icon: const Icon(
                              Icons.edit_outlined,
                              size: 18,
                            ),
                            label: const Text('تعديل'),
                          ),
                        ),
                        if (statusAction != null) ...[
                          const SizedBox(width: 8),
                          Expanded(child: statusAction),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================
  // شريط تصفية الإعلانات
  // =========================
  Widget _buildFilters() {
    final counts = <String, int>{};

    for (final listing in _listings) {
      final status = listing['status']?.toString() ?? '';
      counts[status] = (counts[status] ?? 0) + 1;
    }

    final statuses =
        _statusOrder.where((status) => (counts[status] ?? 0) > 0).toList();

    if (statuses.length < 2) return const SizedBox.shrink();

    final options = <MapEntry<String, String>>[
      MapEntry('all', 'الكل (${_listings.length})'),
      for (final status in statuses)
        MapEntry(
          status,
          '${_statusText(status)} (${counts[status]})',
        ),
    ];

    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 9,
        ),
        itemCount: options.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final option = options[index];
          final selected = _filter == option.key;

          final statusColor = option.key == 'all'
              ? AppColors.brand
              : _statusColor(option.key);

          return ChoiceChip(
            label: Text(
              option.value,
              style: TextStyle(
                color: selected ? Colors.white : statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            selected: selected,
            showCheckmark: false,
            backgroundColor: Colors.white,
            selectedColor: statusColor,
            side: BorderSide(
              color: selected
                  ? statusColor
                  : statusColor.withValues(alpha: 0.20),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            onSelected: (_) => setState(() => _filter = option.key),
          );
        },
      ),
    );
  }

  // =========================
  // الحالات الفارغة والخطأ
  // =========================
  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: () => _loadListings(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 32),
        children: [
          const SizedBox(height: 110),

          Container(
            width: 92,
            height: 92,
            margin: const EdgeInsets.symmetric(horizontal: 80),
            decoration: BoxDecoration(
              color: AppColors.brandSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              size: 48,
              color: AppColors.brand,
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'لم تضف أي إعلانات حتى الآن',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            'أضف أول إعلان لك ليراه الناس في شبشة.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13.5,
              height: 1.5,
            ),
          ),

          const SizedBox(height: 22),

          Center(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _addListing,
              icon: const Icon(Icons.add),
              label: const Text(
                'أضف إعلانك الأول',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: AppDecorations.card(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 36,
                  color: Colors.red.shade700,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'تعذر تحميل الإعلانات',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error ?? 'حدث خطأ غير متوقع',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                onPressed: _loadListings,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'),
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

    if (_error != null) return _buildErrorState();

    if (_listings.isEmpty) return _buildEmptyState();

    final visible = _filter == 'all'
        ? _listings
        : _listings.where((l) => l['status'] == _filter).toList();

    return Column(
      children: [
        _buildFilters(),

        Expanded(
          child: RefreshIndicator(
            color: AppColors.brand,
            onRefresh: () => _loadListings(silent: true),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),

              // مساحة أسفل القائمة حتى لا يغطي الزر العائم آخر إعلان.
              padding: const EdgeInsets.only(
                top: 4,
                bottom: 90,
              ),

              itemCount: visible.length,

              itemBuilder: (context, index) {
                return _buildListingCard(visible[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final showFab = !_loading &&
        _error == null &&
        _listings.isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.pageBackground,

        appBar: AppBar(
          backgroundColor: AppColors.pageBackground,
          foregroundColor: AppColors.ink,
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'إعلاناتي',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),

        body: _buildBody(),

        floatingActionButton: showFab
            ? FloatingActionButton.extended(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                elevation: 4,
                onPressed: _addListing,
                icon: const Icon(Icons.add),
                label: const Text(
                  'إعلان جديد',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}