import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_details_screen.dart';

// مجموعة بلاغات على إعلان واحد.
class _ReportGroup {
  final int listingId;
  final Map<String, dynamic> listing;
  final List<Map<String, dynamic>> reports;

  _ReportGroup({
    required this.listingId,
    required this.listing,
    required this.reports,
  });

  // عدد المبلّغين المختلفين (لا نحسب تكرار نفس الشخص).
  int get reporterCount =>
      reports.map((report) => report['reporter_id']).toSet().length;
}

class AdminListingsScreen extends StatefulWidget {
  const AdminListingsScreen({super.key});

  @override
  State<AdminListingsScreen> createState() => _AdminListingsScreenState();
}

class _AdminListingsScreenState extends State<AdminListingsScreen> {
  static const _approvedPageSize = 30;
  static const _bucket = 'listing-images';

  static final _numberFormat = NumberFormat('#,##0.##', 'en');

  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _checkingAdmin = true;
  bool _isAdmin = false;
  bool _loading = true;
  bool _loadFailed = false;

  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _approved = [];
  List<Map<String, dynamic>> _promotions = [];
  List<_ReportGroup> _reportGroups = [];
  String? _reportsError;

  // بيانات مساعدة لعرض البطاقات.
  final Map<int, List<String>> _imageUrls = {};
  final Map<String, String> _sellerNames = {};
  Map<int, String> _categoryNames = {};

  // إعلانات جارٍ تنفيذ عملية عليها.
  final Set<int> _busyIds = {};

  // ترقيم صفحات "المعتمدة".
  int _approvedPage = 0;
  bool _approvedHasMore = true;
  bool _approvedLoadingMore = false;
  String _approvedQuery = '';

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // =========================
  // أدوات مساعدة
  // =========================
  void _showSnack(String message, {SnackBarAction? action, int seconds = 4}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: action,
          duration: Duration(seconds: seconds),
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
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                      )
                    : null,
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

  String _formatDate(dynamic date) {
    final value = DateTime.tryParse(date?.toString() ?? '')?.toLocal();

    if (value == null) return '';

    return '${value.year}/'
        '${value.month.toString().padLeft(2, '0')}/'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}';
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

  String _remaining(dynamic end) {
    final date = DateTime.tryParse(end?.toString() ?? '')?.toUtc();

    if (date == null) return '';

    final diff = date.difference(DateTime.now().toUtc());

    if (diff.isNegative) return 'انتهى';
    if (diff.inDays >= 1) return 'متبقي ${diff.inDays} يوم';
    if (diff.inHours >= 1) return 'متبقي ${diff.inHours} ساعة';

    return 'متبقي ${diff.inMinutes} دقيقة';
  }

  String _priceText(Map<String, dynamic> listing) {
    final price = listing['price'];
    final priceType = listing['price_type']?.toString();

    if (priceType == 'contact') return 'السعر عند التواصل';
    if (price == null) return 'السعر غير محدد';

    final currency = listing['currency']?.toString().trim().isNotEmpty == true
        ? listing['currency'].toString().trim()
        : 'SDG';

    final number = num.tryParse(price.toString());

    final formatted =
        number == null ? price.toString() : _numberFormat.format(number);

    final suffix = priceType == 'negotiable' ? ' · قابل للتفاوض' : '';

    return '$formatted $currency$suffix';
  }

  String _conditionText(dynamic condition) {
    switch (condition) {
      case 'new':
        return 'جديد';
      case 'used':
        return 'مستعمل';
      default:
        return '';
    }
  }

  bool _isPromotionActive(Map<String, dynamic> listing) {
    if (listing['promotion_is_active'] != true) return false;

    final endAt = DateTime.tryParse(
      listing['promotion_end_at']?.toString() ?? '',
    );

    return endAt != null && endAt.isAfter(DateTime.now().toUtc());
  }

  bool _hasPromotion(Map<String, dynamic> listing) {
    return listing['promoted_listing_id'] != null;
  }

  void _openListing(Map<String, dynamic> listing) {
    final id = listing['id'];

    if (id is! int) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ListingDetailsScreen(listingId: id)),
    );
  }

  // =========================
  // تحميل البيانات
  // =========================
  Future<void> _init() async {
    try {
      final user = _supabase.auth.currentUser;

      if (user != null) {
        final profile = await _supabase
            .from('profiles')
            .select('role')
            .eq('id', user.id)
            .maybeSingle();

        _isAdmin = profile?['role'] == 'admin';
      }
    } catch (e) {
      debugPrint('admin check error: $e');
      _isAdmin = false;
    }

    if (!mounted) return;

    setState(() => _checkingAdmin = false);

    if (!_isAdmin) return;

    await _loadCategories();
    await _loadAll(showSpinner: false);
  }

  Future<void> _loadCategories() async {
    try {
      final response = await _supabase.from('categories').select('id, name');

      final names = <int, String>{};

      for (final row in List<Map<String, dynamic>>.from(response)) {
        final id = row['id'];
        if (id is int) names[id] = row['name']?.toString() ?? '';
      }

      _categoryNames = names;
    } catch (e) {
      debugPrint('loadCategories error: $e');
    }
  }

  Future<void> _loadAll({bool showSpinner = true}) async {
    if (showSpinner && mounted) setState(() => _loading = true);

    _loadFailed = false;

    await Future.wait([
      _loadPending(),
      _loadApproved(reset: true),
      _loadPromotions(),
      _loadReports(),
    ]);

    if (!mounted) return;

    setState(() => _loading = false);

    if (_loadFailed) _showSnack('تعذر تحميل بعض البيانات، اسحب للتحديث');
  }

  // صور وأسماء بائعين للبطاقات.
  Future<void> _loadMeta(List<Map<String, dynamic>> listings) async {
    final listingIds = listings.map((l) => l['id']).whereType<int>().toList();

    final sellerIds = listings
        .map((l) => l['seller_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    await Future.wait([
      _loadImageUrls(listingIds),
      _loadSellerNames(sellerIds),
    ]);
  }

  Future<void> _loadImageUrls(List<int> listingIds) async {
    if (listingIds.isEmpty) return;

    try {
      final response = await _supabase
          .from('listing_images')
          .select('listing_id, image_path, sort_order')
          .inFilter('listing_id', listingIds)
          .order('sort_order');

      final grouped = <int, List<String>>{};

      for (final row in List<Map<String, dynamic>>.from(response)) {
        final id = row['listing_id'];
        final path = row['image_path']?.toString().trim() ?? '';

        if (id is! int || path.isEmpty) continue;

        final url = path.startsWith('http')
            ? path
            : _supabase.storage.from(_bucket).getPublicUrl(path);

        grouped.putIfAbsent(id, () => []).add(url);
      }

      _imageUrls.addAll(grouped);
    } catch (e) {
      debugPrint('admin images error: $e');
    }
  }

  Future<void> _loadSellerNames(List<String> sellerIds) async {
    if (sellerIds.isEmpty) return;

    try {
      final response = await _supabase
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', sellerIds);

      for (final row in List<Map<String, dynamic>>.from(response)) {
        final name = row['full_name']?.toString().trim() ?? '';

        if (name.isNotEmpty) _sellerNames[row['id'].toString()] = name;
      }
    } catch (e) {
      debugPrint('admin sellers error: $e');
    }
  }

  Future<void> _loadPending() async {
    try {
      final response = await _supabase
          .from('listings')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: true); // الأقدم أولاً

      final rows = List<Map<String, dynamic>>.from(response);

      await _loadMeta(rows);

      if (!mounted) return;

      setState(() => _pending = rows);
    } catch (e) {
      debugPrint('loadPending error: $e');
      _loadFailed = true;
    }
  }

  // آخر سجل ترويج لكل إعلان في الصفحة.
  Future<void> _attachPromotions(List<Map<String, dynamic>> listings) async {
    final ids = listings.map((l) => l['id']).where((id) => id != null).toList();

    if (ids.isEmpty) return;

    try {
      final response = await _supabase
          .from('promoted_listings')
          .select('id, listing_id, start_at, end_at, is_active, created_by')
          .inFilter('listing_id', ids)
          .order('id', ascending: false);

      final latest = <dynamic, Map<String, dynamic>>{};

      for (final promotion in List<Map<String, dynamic>>.from(response)) {
        latest.putIfAbsent(promotion['listing_id'], () => promotion);
      }

      for (final listing in listings) {
        final promotion = latest[listing['id']];

        if (promotion == null) continue;

        listing['promoted_listing_id'] = promotion['id'];
        listing['promotion_start_at'] = promotion['start_at'];
        listing['promotion_end_at'] = promotion['end_at'];
        listing['promotion_is_active'] = promotion['is_active'];
      }
    } catch (e) {
      debugPrint('attachPromotions error: $e');
    }
  }

  Future<void> _loadApproved({bool reset = true}) async {
    if (!reset && (_approvedLoadingMore || !_approvedHasMore)) return;

    final page = reset ? 0 : _approvedPage;
    final query = _approvedQuery;

    if (!reset && mounted) setState(() => _approvedLoadingMore = true);

    try {
      var request = _supabase.from('listings').select().eq('status', 'approved');

      if (query.isNotEmpty) {
        request = request.ilike('title', '%$query%');
      }

      final from = page * _approvedPageSize;

      final response = await request
          .order('created_at', ascending: false)
          .range(from, from + _approvedPageSize - 1);

      final rows = List<Map<String, dynamic>>.from(response);

      await Future.wait([_attachPromotions(rows), _loadMeta(rows)]);

      // بحث أحدث بدأ أثناء الانتظار، نتجاهل هذه النتيجة.
      if (!mounted || query != _approvedQuery) return;

      setState(() {
        _approved = reset ? rows : [..._approved, ...rows];
        _approvedPage = page + 1;
        _approvedHasMore = rows.length == _approvedPageSize;
        _approvedLoadingMore = false;
      });
    } catch (e) {
      debugPrint('loadApproved error: $e');
      _loadFailed = true;

      if (mounted) setState(() => _approvedLoadingMore = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 450), () {
      final query = value.trim();

      if (!mounted || query == _approvedQuery) return;

      setState(() => _approvedQuery = query);

      _loadApproved(reset: true);
    });
  }

  // الإعلانات التجارية النشطة حالياً.
  Future<void> _loadPromotions() async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      final promotionsResponse = await _supabase
          .from('promoted_listings')
          .select('id, listing_id, start_at, end_at, is_active, created_by')
          .eq('is_active', true)
          .gt('end_at', now)
          .order('end_at', ascending: true);

      final promotions = List<Map<String, dynamic>>.from(promotionsResponse);

      final ids = promotions
          .map((p) => p['listing_id'])
          .where((id) => id != null)
          .toList();

      if (ids.isEmpty) {
        if (mounted) setState(() => _promotions = []);
        return;
      }

      final listingsResponse =
          await _supabase.from('listings').select().inFilter('id', ids);

      final byId = <dynamic, Map<String, dynamic>>{};

      for (final listing in List<Map<String, dynamic>>.from(listingsResponse)) {
        byId[listing['id']] = listing;
      }

      final items = <Map<String, dynamic>>[];

      for (final promotion in promotions) {
        final listing = byId[promotion['listing_id']];

        if (listing == null) continue;

        final item = Map<String, dynamic>.from(listing);

        item['promoted_listing_id'] = promotion['id'];
        item['promotion_start_at'] = promotion['start_at'];
        item['promotion_end_at'] = promotion['end_at'];
        item['promotion_is_active'] = promotion['is_active'];

        items.add(item);
      }

      await _loadMeta(items);

      if (!mounted) return;

      setState(() => _promotions = items);
    } catch (e) {
      debugPrint('loadPromotions error: $e');
      _loadFailed = true;
    }
  }

  // البلاغات مجمّعة حسب الإعلان (الإعلانات المتاحة أو المعلقة فقط).
  Future<void> _loadReports() async {
    try {
      final response = await _supabase
          .from('reports')
          .select()
          .inFilter('status', ['pending', 'reviewing'])
          .limit(500);

      final reports = List<Map<String, dynamic>>.from(response);

      // الأحدث أولاً إن وُجد عمود created_at.
      reports.sort((a, b) {
        final da = DateTime.tryParse(a['created_at']?.toString() ?? '');
        final db = DateTime.tryParse(b['created_at']?.toString() ?? '');

        if (da == null || db == null) return 0;

        return db.compareTo(da);
      });

      final grouped = <int, List<Map<String, dynamic>>>{};

      for (final report in reports) {
        final id = report['listing_id'];

        if (id is int) grouped.putIfAbsent(id, () => []).add(report);
      }

      if (grouped.isEmpty) {
        if (mounted) {
          setState(() {
            _reportGroups = [];
            _reportsError = null;
          });
        }
        return;
      }

      final listingsResponse = await _supabase
          .from('listings')
          .select()
          .inFilter('id', grouped.keys.toList());

      final listings = List<Map<String, dynamic>>.from(listingsResponse)
          .where((l) => l['status'] == 'approved' || l['status'] == 'pending')
          .toList();

      await _loadMeta(listings);

      final groups = <_ReportGroup>[];

      for (final listing in listings) {
        final id = listing['id'];

        if (id is! int) continue;

        groups.add(
          _ReportGroup(
            listingId: id,
            listing: listing,
            reports: grouped[id] ?? [],
          ),
        );
      }

      groups.sort((a, b) => b.reporterCount.compareTo(a.reporterCount));

      if (!mounted) return;

      setState(() {
        _reportGroups = groups;
        _reportsError = null;
      });
    } catch (e) {
      debugPrint('loadReports error: $e');

      if (!mounted) return;

      setState(() {
        _reportsError =
            'تعذر تحميل البلاغات. شغّل سكربت supabase_security.sql '
            'ليُسمح للأدمن بقراءة جدول reports.';
      });
    }
  }

  // =========================
  // المراجعة (موافقة / رفض)
  // =========================
  Future<void> _approve(Map<String, dynamic> listing) async {
    await _moderate(listing, 'approved');
  }

  Future<void> _reject(
    Map<String, dynamic> listing, {
    String initialReason = '',
  }) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _RejectReasonDialog(initialReason: initialReason),
    );

    // null = ألغى الأدمن العملية.
    if (reason == null || !mounted) return;

    await _moderate(listing, 'rejected', reason: reason);
  }

  Future<void> _moderate(
    Map<String, dynamic> listing,
    String status, {
    String? reason,
  }) async {
    final id = listing['id'];

    if (id is! int || _busyIds.contains(id)) return;

    // العمود اختياري: لا نكتب فيه إلا إن كان موجوداً في الجدول.
    final hasReasonColumn = listing.containsKey('rejection_reason');
    final cleanReason = reason?.trim() ?? '';

    final payload = <String, dynamic>{'status': status};

    if (hasReasonColumn) {
      payload['rejection_reason'] =
          (status == 'rejected' && cleanReason.isNotEmpty) ? cleanReason : null;
    }

    setState(() => _busyIds.add(id));

    try {
      await _supabase.from('listings').update(payload).eq('id', id);

      // رفض الإعلان يُغلق بلاغاته (اختياري، لا يوقف العملية إن فشل).
      if (status == 'rejected') {
        try {
          await _supabase
              .from('reports')
              .update({'status': 'resolved'})
              .eq('listing_id', id)
              .inFilter('status', ['pending', 'reviewing']);
        } catch (e) {
          debugPrint('resolve reports error: $e');
        }
      }

      if (!mounted) return;

      final reasonLost =
          status == 'rejected' && cleanReason.isNotEmpty && !hasReasonColumn;

      final message = status == 'approved'
          ? 'تمت الموافقة على الإعلان'
          : reasonLost
              ? 'تم رفض الإعلان (لم يُحفظ السبب: أضف عمود rejection_reason)'
              : 'تم رفض الإعلان';

      _showSnack(
        message,
        seconds: 7,
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () => _undoModeration(id, hasReasonColumn),
        ),
      );

      await _loadAll(showSpinner: false);
    } catch (e) {
      debugPrint('moderate error: $e');
      _showSnack('تعذر تحديث حالة الإعلان');
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  // التراجع يعيد الإعلان إلى "قيد المراجعة".
  Future<void> _undoModeration(int id, bool hasReasonColumn) async {
    try {
      await _supabase.from('listings').update({
        'status': 'pending',
        if (hasReasonColumn) 'rejection_reason': null,
      }).eq('id', id);

      _showSnack('أُعيد الإعلان إلى قيد المراجعة');

      await _loadAll(showSpinner: false);
    } catch (e) {
      debugPrint('undoModeration error: $e');
      _showSnack('تعذر التراجع');
    }
  }

  // =========================
  // البلاغات
  // =========================
  Future<void> _dismissReports(_ReportGroup group) async {
    final confirmed = await _confirm(
      title: 'تجاهل البلاغات',
      message: 'سيتم إغلاق ${group.reports.length} بلاغ على هذا الإعلان '
          'وإبقاء الإعلان منشوراً. متابعة؟',
      confirmLabel: 'تجاهل',
    );

    if (!confirmed || !mounted) return;

    try {
      await _supabase
          .from('reports')
          .update({'status': 'dismissed'})
          .eq('listing_id', group.listingId)
          .inFilter('status', ['pending', 'reviewing']);

      _showSnack('تم تجاهل البلاغات');

      await _loadReports();
    } catch (e) {
      debugPrint('dismissReports error: $e');
      _showSnack('تعذر إغلاق البلاغات');
    }
  }

  // =========================
  // الإعلانات التجارية
  // =========================
  Future<void> _promote(Map<String, dynamic> listing) async {
    final listingId = listing['id'];
    final currentUser = _supabase.auth.currentUser;

    if (listingId == null || currentUser == null) return;

    final days = await showDialog<int>(
      context: context,
      builder: (dialogContext) {
        Widget option(int days, String label) {
          return SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(dialogContext, days),
              child: Text(label),
            ),
          );
        }

        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('إعلان تجاري'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  listing['title']?.toString() ?? 'بدون عنوان',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text('اختر مدة الترويج:'),
                const SizedBox(height: 10),
                option(1, 'يوم واحد'),
                option(3, '3 أيام'),
                option(7, '7 أيام'),
                option(14, '14 يوماً'),
                option(30, '30 يوماً'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        );
      },
    );

    if (days == null) return;

    try {
      final startAt = DateTime.now().toUtc();
      final endAt = startAt.add(Duration(days: days));

      final values = {
        'start_at': startAt.toIso8601String(),
        'end_at': endAt.toIso8601String(),
        'is_active': true,
        'created_by': currentUser.id,
      };

      final promotionId = listing['promoted_listing_id'];

      // نعيد استخدام السجل السابق بدل إنشاء سجل مكرر.
      if (promotionId != null) {
        await _supabase
            .from('promoted_listings')
            .update(values)
            .eq('id', promotionId);
      } else {
        await _supabase
            .from('promoted_listings')
            .insert({'listing_id': listingId, ...values});
      }

      _showSnack('تم تفعيل الإعلان التجاري لمدة $days يوم');

      await _loadAll(showSpinner: false);
    } catch (e) {
      debugPrint('promote error: $e');
      _showSnack('تعذر تفعيل الإعلان التجاري');
    }
  }

  Future<void> _stopPromotion(Map<String, dynamic> listing) async {
    final promotionId = listing['promoted_listing_id'];

    if (promotionId == null) return;

    final confirmed = await _confirm(
      title: 'إيقاف الإعلان التجاري',
      message: 'هل تريد إيقاف الترويج لهذا الإعلان؟',
      confirmLabel: 'إيقاف',
      destructive: true,
    );

    if (!confirmed || !mounted) return;

    try {
      await _supabase
          .from('promoted_listings')
          .update({'is_active': false}).eq('id', promotionId);

      _showSnack('تم إيقاف الإعلان التجاري');

      await _loadAll(showSpinner: false);
    } catch (e) {
      debugPrint('stopPromotion error: $e');
      _showSnack('تعذر إيقاف الإعلان التجاري');
    }
  }

  // =========================
  // مكوّنات الواجهة
  // =========================
  Widget _thumb(String? url, double size) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget placeholder(IconData icon) {
      return Container(
        color: colorScheme.surfaceContainerHighest,
        child: Icon(icon, color: colorScheme.onSurfaceVariant),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size,
        height: size,
        child: url == null
            ? placeholder(Icons.image_not_supported_outlined)
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

  Widget _badge(String text, {Color? background, Color? foreground}) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background ?? colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground ?? colorScheme.onPrimary,
          fontSize: 11.5,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _actionsRow(List<Widget> buttons) {
    final children = <Widget>[];

    for (var i = 0; i < buttons.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 8));
      children.add(Expanded(child: buttons[i]));
    }

    return Row(children: children);
  }

  // بطاقة إعلان مشتركة بين كل التبويبات.
  Widget _buildCard(
    Map<String, dynamic> listing, {
    required List<Widget> actions,
    bool showAllImages = false,
    Widget? footer,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    final id = listing['id'];
    final images = id is int ? (_imageUrls[id] ?? const <String>[]) : const <String>[];
    final busy = id is int && _busyIds.contains(id);

    final title = listing['title']?.toString().trim() ?? '';
    final description = listing['description']?.toString().trim() ?? '';
    final area = listing['area']?.toString().trim() ?? '';
    final phone = listing['contact_phone']?.toString().trim() ?? '';
    final seller = _sellerNames[listing['seller_id']?.toString()];

    final categoryId = listing['category_id'];
    final category = categoryId is int ? _categoryNames[categoryId] : null;
    final condition = _conditionText(listing['condition']);

    final meta = [
      if (area.isNotEmpty) area,
      _timeAgo(listing['created_at']),
    ].where((part) => part.isNotEmpty).join(' · ');

    final tags = [
      if (category != null && category.isNotEmpty) category,
      if (condition.isNotEmpty) condition,
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: busy ? null : () => _openListing(listing),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (busy) const LinearProgressIndicator(minHeight: 3),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _thumb(images.isEmpty ? null : images.first, 88),
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
                                    title.isEmpty ? 'بدون عنوان' : title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                                if (_isPromotionActive(listing)) ...[
                                  const SizedBox(width: 6),
                                  _badge('تجاري'),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _priceText(listing),
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w800,
                                color: colorScheme.primary,
                              ),
                            ),
                            if (meta.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                meta,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if (seller != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                'البائع: $seller',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  if (showAllImages && images.length > 1) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 64,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length - 1,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, index) => _thumb(images[index + 1], 64),
                      ),
                    ),
                  ],

                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, height: 1.5),
                    ),
                  ],

                  if (tags.isNotEmpty || phone.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final tag in tags)
                          _badge(
                            tag,
                            background: colorScheme.surfaceContainerHighest,
                            foreground: colorScheme.onSurfaceVariant,
                          ),
                        if (phone.isNotEmpty)
                          SelectableText(
                            phone,
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ],

                  if (footer != null) ...[
                    const SizedBox(height: 10),
                    footer,
                  ],

                  const SizedBox(height: 12),

                  _actionsRow(actions),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  ButtonStyle get _compactStyle {
    return ButtonStyle(
      visualDensity: VisualDensity.compact,
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      ),
    );
  }

  Widget _viewButton(Map<String, dynamic> listing) {
    return OutlinedButton.icon(
      style: _compactStyle,
      onPressed: () => _openListing(listing),
      icon: const Icon(Icons.visibility_outlined, size: 18),
      label: const Text('عرض'),
    );
  }

  Widget _buildPendingCard(Map<String, dynamic> listing) {
    final id = listing['id'];
    final busy = id is int && _busyIds.contains(id);

    return _buildCard(
      listing,
      showAllImages: true,
      actions: [
        _viewButton(listing),
        FilledButton.icon(
          style: _compactStyle,
          onPressed: busy ? null : () => _approve(listing),
          icon: const Icon(Icons.check, size: 18),
          label: const Text('موافقة'),
        ),
        OutlinedButton.icon(
          style: _compactStyle.copyWith(
            foregroundColor: WidgetStateProperty.all(Colors.red.shade700),
          ),
          onPressed: busy ? null : () => _reject(listing),
          icon: const Icon(Icons.close, size: 18),
          label: const Text('رفض'),
        ),
      ],
    );
  }

  Widget _buildApprovedCard(Map<String, dynamic> listing) {
    final id = listing['id'];
    final busy = id is int && _busyIds.contains(id);
    final active = _isPromotionActive(listing);
    final hasPromotion = _hasPromotion(listing);

    return _buildCard(
      listing,
      footer: active
          ? Text(
              'ينتهي الترويج: ${_formatDate(listing['promotion_end_at'])} '
              '(${_remaining(listing['promotion_end_at'])})',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : null,
      actions: [
        _viewButton(listing),
        if (active)
          FilledButton.icon(
            style: _compactStyle,
            onPressed: () => _stopPromotion(listing),
            icon: const Icon(Icons.stop_circle_outlined, size: 18),
            label: const Text('إيقاف الترويج'),
          )
        else
          OutlinedButton.icon(
            style: _compactStyle,
            onPressed: () => _promote(listing),
            icon: Icon(
              hasPromotion ? Icons.refresh : Icons.campaign_outlined,
              size: 18,
            ),
            label: Text(hasPromotion ? 'إعادة التفعيل' : 'إعلان تجاري'),
          ),
        OutlinedButton.icon(
          style: _compactStyle.copyWith(
            foregroundColor: WidgetStateProperty.all(Colors.red.shade700),
          ),
          onPressed: busy ? null : () => _reject(listing),
          icon: const Icon(Icons.visibility_off_outlined, size: 18),
          label: const Text('إخفاء'),
        ),
      ],
    );
  }

  Widget _buildPromotionCard(Map<String, dynamic> listing) {
    return _buildCard(
      listing,
      footer: Text(
        'بدأ: ${_formatDate(listing['promotion_start_at'])}\n'
        'ينتهي: ${_formatDate(listing['promotion_end_at'])} '
        '(${_remaining(listing['promotion_end_at'])})',
        style: TextStyle(
          fontSize: 12.5,
          height: 1.6,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      actions: [
        _viewButton(listing),
        OutlinedButton.icon(
          style: _compactStyle,
          onPressed: () => _promote(listing),
          icon: const Icon(Icons.update, size: 18),
          label: const Text('تجديد'),
        ),
        FilledButton.icon(
          style: _compactStyle,
          onPressed: () => _stopPromotion(listing),
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
          label: const Text('إيقاف'),
        ),
      ],
    );
  }

  Widget _buildReportCard(_ReportGroup group) {
    final colorScheme = Theme.of(context).colorScheme;
    final listing = group.listing;

    final id = listing['id'];
    final busy = id is int && _busyIds.contains(id);

    final shown = group.reports.take(5).toList();
    final more = group.reports.length - shown.length;

    final reasonsSummary = group.reports
        .map((r) => r['reason']?.toString().trim() ?? '')
        .where((reason) => reason.isNotEmpty)
        .toSet()
        .take(3)
        .join(' | ');

    return _buildCard(
      listing,
      footer: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.flag_outlined,
                  size: 18,
                  color: colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 6),
                Text(
                  '${group.reporterCount} بلاغ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final report in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• ${(report['reason']?.toString().trim().isNotEmpty ?? false) ? report['reason'] : 'بدون سبب'}'
                  '${(report['details']?.toString().trim().isNotEmpty ?? false) ? ' — ${report['details']}' : ''}'
                  '${_timeAgo(report['created_at']).isEmpty ? '' : '  (${_timeAgo(report['created_at'])})'}',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            if (more > 0)
              Text(
                'و$more بلاغات أخرى',
                style: TextStyle(
                  fontSize: 12.5,
                  color: colorScheme.onErrorContainer,
                ),
              ),
          ],
        ),
      ),
      actions: [
        _viewButton(listing),
        OutlinedButton.icon(
          style: _compactStyle,
          onPressed: () => _dismissReports(group),
          icon: const Icon(Icons.done_all, size: 18),
          label: const Text('تجاهل'),
        ),
        FilledButton.icon(
          style: _compactStyle.copyWith(
            backgroundColor: WidgetStateProperty.all(Colors.red.shade700),
          ),
          onPressed: busy
              ? null
              : () => _reject(listing, initialReason: reasonsSummary),
          icon: const Icon(Icons.visibility_off_outlined, size: 18),
          label: const Text('إخفاء'),
        ),
      ],
    );
  }

  Widget _emptyState(IconData icon, String message) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 130),
        Icon(icon, size: 64, color: colorScheme.onSurfaceVariant),
        const SizedBox(height: 14),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 17),
        ),
      ],
    );
  }

  Widget _buildPendingTab() {
    return RefreshIndicator(
      onRefresh: () => _loadAll(showSpinner: false),
      child: _pending.isEmpty
          ? _emptyState(Icons.check_circle_outline, 'لا توجد إعلانات للمراجعة')
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'الأقدم أولاً · اضغط على أي بطاقة لعرض التفاصيل',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                ..._pending.map(_buildPendingCard),
              ],
            ),
    );
  }

  Widget _buildReportsTab() {
    if (_reportsError != null) {
      return RefreshIndicator(
        onRefresh: () => _loadAll(showSpinner: false),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 100),
            const Icon(Icons.lock_outline, size: 56),
            const SizedBox(height: 12),
            Text(_reportsError!, textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadAll(showSpinner: false),
      child: _reportGroups.isEmpty
          ? _emptyState(Icons.flag_outlined, 'لا توجد بلاغات حالياً')
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: _reportGroups.map(_buildReportCard).toList(),
            ),
    );
  }

  Widget _buildApprovedTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: ValueListenableBuilder<TextEditingValue>(
            valueListenable: _searchController,
            builder: (context, value, _) {
              return TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ابحث في عناوين الإعلانات المعتمدة...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: value.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                  filled: true,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadAll(showSpinner: false),
            child: _approved.isEmpty
                ? _emptyState(
                    Icons.search_off_outlined,
                    _approvedQuery.isEmpty
                        ? 'لا توجد إعلانات معتمدة'
                        : 'لا نتائج للبحث',
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    children: [
                      ..._approved.map(_buildApprovedCard),
                      if (_approvedHasMore)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: _approvedLoadingMore
                                ? const CircularProgressIndicator()
                                : OutlinedButton.icon(
                                    onPressed: () =>
                                        _loadApproved(reset: false),
                                    icon: const Icon(Icons.expand_more),
                                    label: const Text('تحميل المزيد'),
                                  ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildPromotionsTab() {
    return RefreshIndicator(
      onRefresh: () => _loadAll(showSpinner: false),
      child: _promotions.isEmpty
          ? _emptyState(Icons.campaign_outlined, 'لا توجد إعلانات تجارية نشطة')
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              children: _promotions.map(_buildPromotionCard).toList(),
            ),
    );
  }

  Widget _buildLocked() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 64),
            SizedBox(height: 16),
            Text(
              'هذه الصفحة مخصصة للأدمن فقط',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  String _tabLabel(String title, int count) {
    return count > 0 ? '$title ($count)' : title;
  }

  @override
  Widget build(BuildContext context) {
    final showTabs = !_checkingAdmin && _isAdmin;

    final Widget body;

    if (_checkingAdmin || (_isAdmin && _loading)) {
      body = const Center(child: CircularProgressIndicator());
    } else if (!_isAdmin) {
      body = _buildLocked();
    } else {
      body = TabBarView(
        children: [
          _buildPendingTab(),
          _buildReportsTab(),
          _buildApprovedTab(),
          _buildPromotionsTab(),
        ],
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('لوحة تحكم الأدمن'),
            bottom: showTabs
                ? TabBar(
                    tabAlignment: TabAlignment.fill,
                    labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    tabs: [
                      Tab(text: _tabLabel('المراجعة', _pending.length)),
                      Tab(text: _tabLabel('البلاغات', _reportGroups.length)),
                      const Tab(text: 'المعتمدة'),
                      Tab(text: _tabLabel('التجارية', _promotions.length)),
                    ],
                  )
                : null,
          ),
          body: body,
        ),
      ),
    );
  }
}

// =========================
// حوار سبب الرفض
// =========================
class _RejectReasonDialog extends StatefulWidget {
  final String initialReason;

  const _RejectReasonDialog({this.initialReason = ''});

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  static const _presets = [
    'صور غير واضحة أو غير مناسبة',
    'معلومات ناقصة أو غير صحيحة',
    'سعر غير حقيقي',
    'إعلان مكرر',
    'مخالف لسياسة التطبيق',
  ];

  late final TextEditingController _noteController =
      TextEditingController(text: widget.initialReason);

  String? _selected;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = [
      if (_selected != null) _selected!,
      if (_noteController.text.trim().isNotEmpty) _noteController.text.trim(),
    ].join(' - ');

    Navigator.pop(context, reason);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('رفض / إخفاء الإعلان'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('اختر السبب (يظهر لصاحب الإعلان):'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final preset in _presets)
                    ChoiceChip(
                      label: Text(preset, style: const TextStyle(fontSize: 12.5)),
                      selected: _selected == preset,
                      onSelected: (selected) {
                        setState(() => _selected = selected ? preset : null);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteController,
                maxLines: 2,
                maxLength: 200,
                decoration: const InputDecoration(
                  hintText: 'ملاحظة إضافية (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: _submit,
            child: const Text('رفض'),
          ),
        ],
      ),
    );
  }
}
