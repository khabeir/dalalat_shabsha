import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_decorations.dart';
import '../core/widgets/home_banner.dart';

// شاشة الأدمن لتحرير الخانات الثلاث لبنر الصفحة الرئيسية.
// كل خانة: عنوان + نص فرعي + تفعيل، مع معاينة مطابقة تماماً لشكلها الحقيقي.
class AdminBannersScreen extends StatefulWidget {
  const AdminBannersScreen({super.key});

  @override
  State<AdminBannersScreen> createState() => _AdminBannersScreenState();
}

class _AdminBannersScreenState extends State<AdminBannersScreen> {
  final _supabase = Supabase.instance.client;

  bool _checkingAdmin = true;
  bool _isAdmin = false;
  bool _loading = true;
  String? _error;

  // متحكمات كل خانة (1، 2، 3).
  final _headlineControllers = <int, TextEditingController>{
    1: TextEditingController(),
    2: TextEditingController(),
    3: TextEditingController(),
  };

  final _subtitleControllers = <int, TextEditingController>{
    1: TextEditingController(),
    2: TextEditingController(),
    3: TextEditingController(),
  };

  final _activeBySlot = <int, bool>{1: false, 2: false, 3: false};
  final _savingBySlot = <int, bool>{1: false, 2: false, 3: false};
  final _dirtyBySlot = <int, bool>{1: false, 2: false, 3: false};

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final controller in _headlineControllers.values) {
      controller.dispose();
    }
    for (final controller in _subtitleControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // =========================
  // التحميل
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

    if (_isAdmin) await _loadSlides();
  }

  Future<void> _loadSlides() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _supabase
          .from('home_banner_slides')
          .select('slot, headline, subtitle, is_active')
          .order('slot');

      for (final row in List<Map<String, dynamic>>.from(response)) {
        final slot = row['slot'];

        if (slot is! int || !_headlineControllers.containsKey(slot)) continue;

        _headlineControllers[slot]!.text = row['headline']?.toString() ?? '';
        _subtitleControllers[slot]!.text = row['subtitle']?.toString() ?? '';
        _activeBySlot[slot] = row['is_active'] == true;
        _dirtyBySlot[slot] = false;
      }

      if (!mounted) return;

      setState(() => _loading = false);
    } catch (e) {
      debugPrint('loadBannerSlides error: $e');

      if (!mounted) return;

      setState(() {
        _error = 'تعذر تحميل البنر. تحقق من اتصال الإنترنت وحاول مجدداً.';
        _loading = false;
      });
    }
  }

  // =========================
  // الحفظ
  // =========================
  Future<void> _saveSlot(int slot) async {
    setState(() => _savingBySlot[slot] = true);

    final headline = _headlineControllers[slot]!.text.trim();
    final subtitle = _subtitleControllers[slot]!.text.trim();
    final active = _activeBySlot[slot] ?? false;

    if (active && headline.isEmpty) {
      _showSnack('اكتب النص الإعلاني قبل تفعيل الخانة');
      setState(() => _savingBySlot[slot] = false);
      return;
    }

    try {
      await _supabase.from('home_banner_slides').update({
        'headline': headline,
        'subtitle': subtitle,
        'is_active': active,
      }).eq('slot', slot);

      if (!mounted) return;

      setState(() => _dirtyBySlot[slot] = false);

      _showSnack('تم حفظ الخانة $slot');
    } catch (e) {
      debugPrint('saveBannerSlide error: $e');
      _showSnack('تعذر حفظ الخانة $slot، حاول مرة أخرى');
    } finally {
      if (mounted) setState(() => _savingBySlot[slot] = false);
    }
  }

  // =========================
  // الواجهة
  // =========================
  Widget _buildSlotCard(int slot) {
    final headlineController = _headlineControllers[slot]!;
    final subtitleController = _subtitleControllers[slot]!;
    final active = _activeBySlot[slot] ?? false;
    final saving = _savingBySlot[slot] ?? false;
    final dirty = _dirtyBySlot[slot] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.brand,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$slot',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'الخانة $slot',
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const Spacer(),
              Switch(
                value: active,
                activeTrackColor: AppColors.brand,
                onChanged: (value) {
                  setState(() {
                    _activeBySlot[slot] = value;
                    _dirtyBySlot[slot] = true;
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 6),

          TextField(
            controller: headlineController,
            maxLength: 30,
            onChanged: (_) => setState(() => _dirtyBySlot[slot] = true),
            decoration: const InputDecoration(
              labelText: 'العنوان الرئيسي',
              hintText: 'مثال: عروض نهاية الأسبوع',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          const SizedBox(height: 10),

          TextField(
            controller: subtitleController,
            maxLength: 70,
            maxLines: 2,
            onChanged: (_) => setState(() => _dirtyBySlot[slot] = true),
            decoration: const InputDecoration(
              labelText: 'النص الفرعي',
              hintText: 'مثال: خصومات على الأثاث حتى نهاية الأسبوع',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          const SizedBox(height: 12),

          // معاينة حية بنفس شكل البنر الحقيقي في الصفحة الرئيسية.
          AnimatedBuilder(
            animation: Listenable.merge([headlineController, subtitleController]),
            builder: (context, _) {
              final headline = headlineController.text.trim();

              return Opacity(
                opacity: active ? 1 : 0.45,
                child: BannerCardContent(
                  headline: headline.isEmpty ? 'عنوان الإعلان' : headline,
                  subtitle: subtitleController.text.trim(),
                  onAddListing: null,
                  onBrowseCategories: null,
                ),
              );
            },
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (!dirty || saving) ? null : () => _saveSlot(slot),
              style: FilledButton.styleFrom(backgroundColor: AppColors.brand),
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(saving ? 'جاري الحفظ...' : 'حفظ الخانة $slot'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_checkingAdmin || _loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.brand),
      );
    }

    if (!_isAdmin) {
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

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadSlides,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSlides,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: AppDecorations.softCard(),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: AppColors.brand, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'يظهر البنر في الصفحة الرئيسية بالخانات المفعّلة فقط، '
                    'وتُعرض بالترتيب مع تمرير تلقائي عند وجود أكثر من خانة.',
                    style: TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          _buildSlotCard(1),
          _buildSlotCard(2),
          _buildSlotCard(3),
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
          title: const Text(
            'البنر الإعلاني',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        body: _buildBody(),
      ),
    );
  }
}
