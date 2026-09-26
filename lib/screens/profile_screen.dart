import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_decorations.dart';
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

  String _savedName = '';
  String _savedPhone = '';
  String _savedArea = '';

  bool _loading = true;
  bool _saving = false;
  bool _isPhoneAccount = false;
  bool _deleting = false;

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
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          backgroundColor: AppColors.ink,
          content: Text(
            message,
            textAlign: TextAlign.right,
          ),
        ),
      );
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final text = value?.trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            title: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: AppDecorations.softCard(),
                  child: Icon(
                    destructive
                        ? Icons.warning_amber_rounded
                        : Icons.help_outline_rounded,
                    color: destructive
                        ? Colors.red.shade700
                        : AppColors.brand,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            content: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                message,
                style: const TextStyle(
                  height: 1.7,
                  fontSize: 14,
                ),
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                      )
                    : FilledButton.styleFrom(
                        backgroundColor: AppColors.brand,
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

      final area = _firstNonEmpty([
        profile?['area']?.toString(),
      ]);

      if (!mounted) return;

      final keepFields = silent && _isDirty;

      if (!keepFields) {
        _nameController.text = fullName;
        _phoneController.text = phone;
        _areaController.text = area;
      }

      setState(() {
        _isPhoneAccount = isPhoneAccount;

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
      MaterialPageRoute(
        builder: (_) => const MyListingsScreen(),
      ),
    );

    if (mounted) _loadProfile(silent: true);
  }

  Future<void> _openFavorites() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const FavoritesScreen(),
      ),
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

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      debugPrint('signOut error: $e');
      _showMessage('تعذر تسجيل الخروج، حاول مرة أخرى');
    }
  }

  // =========================
  // حذف الحساب نهائياً
  // =========================

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);

    try {
      await _supabase.functions.invoke('delete-account');
    } catch (e) {
      debugPrint('deleteAccount error: $e');

      if (!mounted) return;

      setState(() => _deleting = false);

      if (e is FunctionException && e.status == 403) {
        _showMessage('حسابات الإدارة لا يمكن حذفها من التطبيق');
      } else {
        _showMessage('تعذر حذف الحساب. حاول مرة أخرى لاحقاً.');
      }
      return;
    }

    try {
      await _supabase.auth.signOut(
        scope: SignOutScope.local,
      );
    } catch (_) {}

    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);

    Navigator.of(context).popUntil((route) => route.isFirst);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('تم حذف حسابك وبياناتك نهائياً'),
        ),
      );
  }

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
    final name = _savedName;
    final initial =
        name.isEmpty ? null : String.fromCharCode(name.runes.first);

    final contact = _firstNonEmpty([
      _savedPhone,
      _email,
    ]);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: AppDecorations.card(
        color: Colors.white,
      ),
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  AppColors.brand,
                  AppColors.brandDark,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand.withValues(alpha: 0.22),
                  blurRadius: 18,
                  offset: const Offset(0, 7),
                ),
              ],
            ),
            child: Center(
              child: initial == null
                  ? const Icon(
                      Icons.person_outline,
                      size: 46,
                      color: Colors.white,
                    )
                  : Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),

          const SizedBox(height: 14),

          Text(
            name.isEmpty ? 'أضف اسمك' : name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),

          if (contact.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              contact,
              textDirection: TextDirection.ltr,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey.shade700,
              ),
            ),
          ],

          const SizedBox(height: 12),

          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 7,
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
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.brandSoft,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: AppColors.brand,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
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
    return Expanded(
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              vertical: 13,
              horizontal: 5,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.brand.withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: AppDecorations.softCard(),
                  child: Icon(
                    icon,
                    size: 20,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '$value',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
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
      child: Row(
        children: [
          Container(
            width: 5,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.orange,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    String? helperText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      helperText: helperText,
      helperMaxLines: 2,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: Colors.grey.shade300,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: Colors.grey.shade300,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(
          color: AppColors.brand,
          width: 1.7,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: Colors.red.shade400,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(
          color: Colors.red.shade700,
          width: 1.5,
        ),
      ),
    );
  }

  Widget _buildForm() {
    final canSave = _isDirty && !_saving;

    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppDecorations.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              validator: _validateName,
              decoration: _inputDecoration(
                label: 'الاسم الكامل',
                icon: Icons.person_outline,
              ),
            ),

            const SizedBox(height: 14),

            TextFormField(
              controller: _phoneController,
              readOnly: _isPhoneAccount,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              validator: _validatePhone,
              decoration: _inputDecoration(
                label: 'رقم الهاتف',
                icon: Icons.phone_outlined,
                helperText: _isPhoneAccount
                    ? 'هذا الرقم مرتبط بتسجيل الدخول ولا يمكن تغييره هنا'
                    : 'رقم للتواصل يظهر في إعلاناتك',
                suffixIcon: _isPhoneAccount
                    ? const Icon(Icons.lock_outline)
                    : null,
              ),
            ),

            const SizedBox(height: 14),

            TextFormField(
              controller: _areaController,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (canSave) _saveProfile();
              },
              decoration: _inputDecoration(
                label: 'المنطقة',
                icon: Icons.location_on_outlined,
              ),
            ),

            const SizedBox(height: 14),

            InputDecorator(
              decoration: _inputDecoration(
                label: 'البريد الإلكتروني',
                icon: Icons.email_outlined,
              ),
              child: Text(
                _email ??
                    (_isPhoneAccount
                        ? 'لا يوجد بريد إلكتروني مرتبط بالحساب'
                        : 'غير متوفر'),
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 13.5,
                ),
              ),
            ),

            const SizedBox(height: 18),

            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: canSave ? _saveProfile : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.brandSoft,
                  disabledForegroundColor: Colors.grey.shade500,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: _saving
                    ? const SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _saving ? 'جارٍ الحفظ...' : 'حفظ التغييرات',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenu() {
    return Container(
      decoration: AppDecorations.card(),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: _menuIcon(
              Icons.inventory_2_outlined,
            ),
            title: const Text(
              'إعلاناتي',
              style: TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              '$_totalCount إعلان',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_left,
              color: AppColors.brand,
            ),
            onTap: _openMyListings,
          ),
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: Colors.grey.shade200,
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: _menuIcon(
              Icons.favorite_border,
            ),
            title: const Text(
              'المفضلة',
              style: TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
            subtitle: Text(
              '$_favoritesCount إعلان محفوظ',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
            trailing: const Icon(
              Icons.chevron_left,
              color: AppColors.brand,
            ),
            onTap: _openFavorites,
          ),
        ],
      ),
    );
  }

  Widget _menuIcon(IconData icon) {
    return Container(
      width: 42,
      height: 42,
      decoration: AppDecorations.softCard(),
      child: Icon(
        icon,
        color: AppColors.brand,
        size: 21,
      ),
    );
  }

  Widget _buildContent() {
    return RefreshIndicator(
      color: AppColors.brand,
      onRefresh: () => _loadProfile(silent: true),
      child: ListView(
        keyboardDismissBehavior:
            ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _buildHeader(),

          const SizedBox(height: 18),

          Row(
            children: [
              _statTile(
                label: 'نشطة',
                value: _activeCount,
                icon: Icons.check_circle_outline,
                onTap: _openMyListings,
              ),
              const SizedBox(width: 8),
              _statTile(
                label: 'قيد المراجعة',
                value: _pendingCount,
                icon: Icons.hourglass_empty,
                onTap: _openMyListings,
              ),
              const SizedBox(width: 8),
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

          _sectionTitle('الوصول السريع'),
          _buildMenu(),

          const SizedBox(height: 18),

          OutlinedButton.icon(
            onPressed: _signOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: Colors.red.shade200,
              ),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: const Icon(Icons.logout),
            label: const Text(
              'تسجيل الخروج',
              style: TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),

          const SizedBox(height: 7),

          TextButton.icon(
            onPressed: _deleting ? null : _deleteAccount,
            style: TextButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              minimumSize: const Size.fromHeight(44),
            ),
            icon: _deleting
                ? SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.red.shade700,
                    ),
                  )
                : const Icon(Icons.delete_forever_outlined),
            label: Text(
              _deleting
                  ? 'جارٍ حذف الحساب...'
                  : 'حذف حسابي نهائياً',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: AppDecorations.card(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline,
                    size: 32,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _loadProfile,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand,
                  ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
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
        canPop: !_deleting && (!_isDirty || _saving),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && !_deleting) {
            _onPopBlocked();
          }
        },
        child: Scaffold(
          backgroundColor: AppColors.pageBackground,
          appBar: AppBar(
            backgroundColor: AppColors.pageBackground,
            foregroundColor: AppColors.ink,
            elevation: 0,
            centerTitle: false,
            title: const Text(
              'الملف الشخصي',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
          ),
          body: _buildBody(),
        ),
      ),
    );
  }
}

// =========================
// تأكيد حذف الحساب
// يتطلب كتابة كلمة "حذف"
// =========================

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  static const _confirmWord = 'حذف';

  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _controller.text.trim() == _confirmWord;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
        ),
        title: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.delete_forever_outlined,
                color: Colors.red.shade700,
                size: 25,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'حذف الحساب نهائياً',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red.shade700,
                    size: 21,
                  ),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'سيتم حذف حسابك وجميع إعلاناتك وصورك '
                      'ومفضلتك بشكل نهائي، ولا يمكن التراجع عن ذلك.',
                      style: TextStyle(
                        height: 1.6,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'للتأكيد اكتب كلمة "$_confirmWord" في الحقل:',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'اكتب: حذف',
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Colors.grey.shade300,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: Colors.red.shade600,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: matches
                ? () => Navigator.pop(context, true)
                : null,
            child: const Text(
              'حذف الحساب',
              style: TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}