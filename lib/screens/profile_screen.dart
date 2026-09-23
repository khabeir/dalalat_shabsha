import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'favorites_screen.dart';
import 'my_listings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _areaController = TextEditingController();

  // القيم المحفوظة، لمعرفة هل عدّل المستخدم شيئاً.
  String _savedName = '';
  String _savedPhone = '';
  String _savedArea = '';

  bool _loading = true;
  bool _saving = false;
  bool _isPhoneAccount = false;

  String? _error;
  String? _email;
  DateTime? _memberSince;

  int _totalCount = 0;
  int _activeCount = 0;
  int _pendingCount = 0;
  int _favoritesCount = 0;

  @override
  void initState() {
    super.initState();

    _nameController.addListener(_onFieldChanged);
    _phoneController.addListener(_onFieldChanged);
    _areaController.addListener(_onFieldChanged);

    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  bool get _isDirty {
    return _nameController.text.trim() != _savedName ||
        _phoneController.text.trim() != _savedPhone ||
        _areaController.text.trim() != _savedArea;
  }

  // =========================
  // أدوات مساعدة
  // =========================
  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  // تحويل الأرقام العربية (٠١٢) إلى غربية (012).
  String _toWesternDigits(String input) {
    const arabic = '٠١٢٣٤٥٦٧٨٩';

    final buffer = StringBuffer();

    for (final char in input.split('')) {
      final index = arabic.indexOf(char);
      buffer.write(index == -1 ? char : index.toString());
    }

    return buffer.toString();
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

  // =========================
  // تحميل البيانات
  // =========================
  Future<void> _loadProfile({bool silent = false}) async {
    if (!mounted) return;

    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = _supabase.auth.currentUser;

      if (user == null) {
        throw Exception('لا يوجد مستخدم مسجل الدخول.');
      }

      final authEmail = user.email ?? '';

      // حساب الهاتف يستخدم بريداً داخلياً غير مخصص للمستخدم.
      final isPhoneAccount =
          authEmail.toLowerCase().endsWith('@phone-auth.invalid');

      final results = await Future.wait<Object?>([
        _supabase
            .from('profiles')
            .select('full_name, phone, area')
            .eq('id', user.id)
            .maybeSingle(),
        _supabase.from('listings').select('id, status').eq('seller_id', user.id),
        _loadFavoritesCount(user.id),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final listings = List<Map<String, dynamic>>.from(results[1] as List);
      final favoritesCount = results[2] as int;

      final fullName = _firstNonEmpty([
        profile?['full_name']?.toString(),
        user.userMetadata?['full_name']?.toString(),
      ]);

      final phone = _firstNonEmpty([
        profile?['phone']?.toString(),
        user.userMetadata?['phone']?.toString(),
        user.phone,
      ]);

      final area = _firstNonEmpty([profile?['area']?.toString()]);

      if (!mounted) return;

      // عند التحديث بالسحب لا نكتب فوق ما يكتبه المستخدم الآن.
      final keepFields = silent && _isDirty;

      // نكتب في الحقول خارج setState لأن لها مستمعين يعيدون البناء.
      if (!keepFields) {
        _nameController.text = fullName;
        _phoneController.text = phone;
        _areaController.text = area;
      }

      setState(() {
        _isPhoneAccount = isPhoneAccount;

        // لا نعرض البريد الداخلي الاصطناعي.
        _email = isPhoneAccount ? null : authEmail;
        _memberSince = DateTime.tryParse(user.createdAt)?.toLocal();

        if (!keepFields) {
          _savedName = fullName;
          _savedPhone = phone;
          _savedArea = area;
        }

        _totalCount = listings.length;
        _activeCount =
            listings.where((l) => l['status'] == 'approved').length;
        _pendingCount =
            listings.where((l) => l['status'] == 'pending').length;
        _favoritesCount = favoritesCount;

        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('loadProfile error: $e');

      if (!mounted) return;

      if (silent) {
        _showMessage('تعذر تحديث البيانات');
        return;
      }

      setState(() {
        _error =
            'تعذر تحميل الملف الشخصي. تحقق من اتصال الإنترنت وحاول مجدداً.';
        _loading = false;
      });
    }
  }

  Future<int> _loadFavoritesCount(String userId) async {
    try {
      final rows = await _supabase
          .from('favorites')
          .select('listing_id')
          .eq('user_id', userId);

      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  // =========================
  // حفظ البيانات
  // =========================
  String? _validateName(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) return 'يرجى إدخال الاسم الكامل';
    if (text.length < 2) return 'الاسم قصير جداً';

    return null;
  }

  String? _validatePhone(String? value) {
    // رقم حساب الهاتف مرتبط بتسجيل الدخول ولا يتغير.
    if (_isPhoneAccount) return null;

    final digits =
        _toWesternDigits(value ?? '').replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) return null;

    if (digits.length < 9 || digits.length > 15) {
      return 'رقم الهاتف غير صحيح';
    }

    return null;
  }

  Future<void> _saveProfile() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      _showMessage('يرجى تسجيل الدخول أولاً');
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();

    final fullName = _nameController.text.trim();
    final area = _areaController.text.trim();

    final phone = _isPhoneAccount
        ? _phoneController.text.trim()
        : _toWesternDigits(_phoneController.text).trim();

    setState(() => _saving = true);

    try {
      await _supabase.from('profiles').upsert(
        {
          'id': user.id,
          'full_name': fullName,
          'phone': phone.isEmpty ? null : phone,
          'area': area.isEmpty ? null : area,
        },
        onConflict: 'id',
      );
    } catch (e) {
      debugPrint('saveProfile error: $e');

      if (!mounted) return;

      setState(() => _saving = false);

      _showMessage(
        'تعذر حفظ البيانات. تحقق من اتصال الإنترنت وحاول مرة أخرى.',
      );
      return;
    }

    // نحدّث بيانات الحساب أيضاً ليظهر الاسم الجديد في الصفحة الرئيسية
    // والقائمة الجانبية (تقرأ الاسم من بيانات الحساب).
    try {
      await _supabase.auth.updateUser(
        UserAttributes(
          data: {
            'full_name': fullName,
            if (!_isPhoneAccount && phone.isNotEmpty) 'phone': phone,
          },
        ),
      );
    } catch (e) {
      debugPrint('updateUser metadata error: $e');
    }

    if (!mounted) return;

    _phoneController.text = phone;

    setState(() {
      _savedName = fullName;
      _savedPhone = phone;
      _savedArea = area;

      _saving = false;
    });

    _showMessage('تم حفظ بيانات الملف الشخصي');
  }

  // =========================
  // التنقل وتسجيل الخروج
  // =========================
  Future<void> _openMyListings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyListingsScreen()),
    );

    if (mounted) _loadProfile(silent: true);
  }

  Future<void> _openFavorites() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FavoritesScreen()),
    );

    if (mounted) _loadProfile(silent: true);
  }

  Future<void> _signOut() async {
    final confirmed = await _confirm(
      title: 'تسجيل الخروج',
      message: 'هل تريد تسجيل الخروج من حسابك؟',
      confirmLabel: 'تسجيل الخروج',
      destructive: true,
    );

    if (!confirmed || !mounted) return;

    try {
      await _supabase.auth.signOut();

      if (!mounted) return;

      // نعود للصفحة الرئيسية.
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      debugPrint('signOut error: $e');
      _showMessage('تعذر تسجيل الخروج، حاول مرة أخرى');
    }
  }

  // عند الخروج من الصفحة مع تعديلات غير محفوظة.
  Future<void> _onPopBlocked() async {
    final leave = await _confirm(
      title: 'تعديلات غير محفوظة',
      message: 'لديك تعديلات لم تُحفظ. هل تريد الخروج وتجاهلها؟',
      confirmLabel: 'خروج',
      destructive: true,
    );

    if (leave && mounted) Navigator.pop(context);
  }

  // =========================
  // مكوّنات الواجهة
  // =========================
  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;

    final name = _savedName;
    final initial = name.isEmpty ? null : String.fromCharCode(name.runes.first);

    final contact = _firstNonEmpty([
      _savedPhone,
      _email,
    ]);

    return Column(
      children: [
        CircleAvatar(
          radius: 42,
          backgroundColor: colorScheme.primaryContainer,
          child: initial == null
              ? Icon(
                  Icons.person_outline,
                  size: 44,
                  color: colorScheme.onPrimaryContainer,
                )
              : Text(
                  initial,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onPrimaryContainer,
                  ),
                ),
        ),

        const SizedBox(height: 12),

        Text(
          name.isEmpty ? 'أضف اسمك' : name,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        if (contact.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            contact,
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: 13.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],

        const SizedBox(height: 10),

        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            _infoChip(
              _isPhoneAccount
                  ? Icons.phone_android_outlined
                  : Icons.email_outlined,
              _isPhoneAccount ? 'حساب بالهاتف' : 'حساب بالبريد',
            ),
            if (_memberSince != null)
              _infoChip(
                Icons.calendar_month_outlined,
                'عضو منذ ${_memberSince!.year}',
              ),
          ],
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String text) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _statTile({
    required String label,
    required int value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                Icon(icon, size: 20, color: colorScheme.primary),
                const SizedBox(height: 4),
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildForm() {
    final colorScheme = Theme.of(context).colorScheme;
    final canSave = _isDirty && !_saving;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            validator: _validateName,
            decoration: const InputDecoration(
              labelText: 'الاسم الكامل',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 14),

          TextFormField(
            controller: _phoneController,
            readOnly: _isPhoneAccount,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            validator: _validatePhone,
            decoration: InputDecoration(
              labelText: 'رقم الهاتف',
              prefixIcon: const Icon(Icons.phone_outlined),
              border: const OutlineInputBorder(),
              helperText: _isPhoneAccount
                  ? 'هذا الرقم مرتبط بتسجيل الدخول ولا يمكن تغييره هنا'
                  : 'رقم للتواصل يظهر في إعلاناتك',
              helperMaxLines: 2,
              suffixIcon:
                  _isPhoneAccount ? const Icon(Icons.lock_outline) : null,
            ),
          ),

          const SizedBox(height: 14),

          TextFormField(
            controller: _areaController,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) {
              if (canSave) _saveProfile();
            },
            decoration: const InputDecoration(
              labelText: 'المنطقة',
              prefixIcon: Icon(Icons.location_on_outlined),
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 14),

          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'البريد الإلكتروني',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            child: Text(
              _email ??
                  (_isPhoneAccount
                      ? 'لا يوجد بريد إلكتروني مرتبط بالحساب'
                      : 'غير متوفر'),
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),

          const SizedBox(height: 18),

          FilledButton.icon(
            onPressed: canSave ? _saveProfile : null,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ التغييرات'),
          ),
        ],
      ),
    );
  }

  Widget _buildMenu() {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('إعلاناتي'),
            subtitle: Text('$_totalCount إعلان'),
            trailing: const Icon(Icons.chevron_left),
            onTap: _openMyListings,
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('المفضلة'),
            subtitle: Text('$_favoritesCount إعلان محفوظ'),
            trailing: const Icon(Icons.chevron_left),
            onTap: _openFavorites,
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      onRefresh: () => _loadProfile(silent: true),
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          _buildHeader(),

          const SizedBox(height: 20),

          Row(
            children: [
              _statTile(
                label: 'نشطة',
                value: _activeCount,
                icon: Icons.check_circle_outline,
                onTap: _openMyListings,
              ),
              const SizedBox(width: 10),
              _statTile(
                label: 'قيد المراجعة',
                value: _pendingCount,
                icon: Icons.hourglass_empty,
                onTap: _openMyListings,
              ),
              const SizedBox(width: 10),
              _statTile(
                label: 'المفضلة',
                value: _favoritesCount,
                icon: Icons.favorite_border,
                onTap: _openFavorites,
              ),
            ],
          ),

          const SizedBox(height: 24),

          _sectionTitle('بياناتي'),
          _buildForm(),

          const SizedBox(height: 24),

          _buildMenu(),

          const SizedBox(height: 16),

          OutlinedButton.icon(
            onPressed: _signOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade200),
            ),
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل الخروج'),
          ),
        ],
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
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadProfile,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }

    return _buildContent();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: !_isDirty || _saving,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onPopBlocked();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('الملف الشخصي'),
          ),
          body: _buildBody(),
        ),
      ),
    );
  }
}
