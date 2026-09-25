import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand_theme.dart';
import 'support_card.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // ضع هنا رابط سياسة الخصوصية وشروط الاستخدام (تطلبها Google Play).
  // إن تركتها فارغة لا يظهر الرابط.
  static const _privacyPolicyUrl = '';
  static const _termsUrl = '';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  final _supabase = Supabase.instance.client;

  bool _isLogin = true;
  bool _usePhone = true;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _identifierController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ============================================================
  // أدوات مساعدة
  // ============================================================
  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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

  // ============================================================
  // تطبيع رقم الهاتف السوداني
  // يقبل: 0912345678 و 912345678 و +249912345678 و 00249912345678
  // strict: عند إنشاء حساب جديد نتأكد أن الرقم السوداني 9 أرقام بعد الرمز.
  // عند الدخول نكون متساهلين حتى لا نمنع حسابات مسجلة سابقاً.
  // ============================================================
  String? _normalizePhone(String value, {bool strict = false}) {
    var phone =
        _toWesternDigits(value).replaceAll(RegExp(r'[\s\-().]'), '').trim();

    if (phone.isEmpty) return null;

    if (phone.startsWith('00')) {
      phone = '+${phone.substring(2)}';
    } else if (phone.startsWith('+')) {
      // كما هو
    } else if (phone.startsWith('0')) {
      phone = '+249${phone.substring(1)}';
    } else if (phone.startsWith('249')) {
      phone = '+$phone';
    } else if (RegExp(r'^[19]\d{8}$').hasMatch(phone)) {
      phone = '+249$phone';
    } else {
      return null;
    }

    final digits = phone.substring(1);

    if (!RegExp(r'^\d{8,15}$').hasMatch(digits)) return null;

    if (strict && phone.startsWith('+249') && digits.length != 12) {
      return null;
    }

    return phone;
  }

  bool _isValidEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
  }

  String? _validateIdentifier(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return _usePhone ? 'أدخل رقم الهاتف' : 'أدخل البريد الإلكتروني';
    }

    if (_usePhone) {
      return _normalizePhone(text, strict: !_isLogin) == null
          ? 'أدخل رقم هاتف صحيح'
          : null;
    }

    return _isValidEmail(text) ? null : 'أدخل بريداً إلكترونياً صحيحاً';
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'أدخل كلمة المرور';

    if (value.length < 6) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';

    return null;
  }

  String? _validateName(String? value) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) return 'أدخل الاسم الكامل';
    if (text.length < 2) return 'الاسم قصير جداً';

    return null;
  }

  // ============================================================
  // تبديل الوضع مع الاحتفاظ بالبريد/الهاتف المكتوب
  // ============================================================
  void _setMode(bool isLogin) {
    if (_loading || isLogin == _isLogin) return;

    final identifier = _identifierController.text;

    setState(() {
      _isLogin = isLogin;
      _passwordController.clear();
      _confirmPasswordController.clear();
    });

    _formKey.currentState?.reset();
    _identifierController.text = identifier;
  }

  void _setMethod(bool usePhone) {
    if (_loading || usePhone == _usePhone) return;

    setState(() {
      _usePhone = usePhone;
      _identifierController.clear();
    });

    _formKey.currentState?.reset();
  }

  // ============================================================
  // الإرسال
  // ============================================================
  Future<void> _submit() async {
    if (_loading) return;

    if (!(_formKey.currentState?.validate() ?? false)) return;

    FocusScope.of(context).unfocus();

    setState(() => _loading = true);

    try {
      final signedIn = _isLogin ? await _login() : await _register();

      if (signedIn && mounted) {
        // يحفظ مدير كلمات المرور في الهاتف بيانات الدخول.
        TextInput.finishAutofillContext();

        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('auth error: $e');

      _showMessage(_errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // يرجع true إذا تم تسجيل الدخول.
  Future<bool> _login() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;

    if (_usePhone) {
      final phone = _normalizePhone(identifier);

      if (phone == null) {
        _showMessage('رقم الهاتف غير صحيح');
        return false;
      }

      final response = await _phoneAuthRequest(
        action: 'login',
        phone: phone,
        password: password,
      );

      if (response['success'] != true) {
        _showMessage(
          response['message']?.toString() ??
              'رقم الهاتف أو كلمة المرور غير صحيحة',
        );
        return false;
      }

      final session = _readSession(response);

      if (session == null) {
        _showMessage('تعذر إنشاء جلسة تسجيل الدخول');
        return false;
      }

      await _setSupabaseSession(session);
    } else {
      await _supabase.auth.signInWithPassword(
        email: identifier.toLowerCase(),
        password: password,
      );
    }

    _showMessage('تم تسجيل الدخول بنجاح');

    return true;
  }

  Future<bool> _register() async {
    final identifier = _identifierController.text.trim();
    final password = _passwordController.text;
    final fullName = _nameController.text.trim();

    // ---------- بالبريد ----------
    if (!_usePhone) {
      final response = await _supabase.auth.signUp(
        email: identifier.toLowerCase(),
        password: password,
        data: {'full_name': fullName},
      );

      if (response.user == null) {
        _showMessage('تعذر إنشاء الحساب');
        return false;
      }

      if (response.session != null) {
        _showMessage('تم إنشاء الحساب وتسجيل الدخول بنجاح');
        return true;
      }

      // لا توجد جلسة: التأكيد عبر البريد مطلوب.
      _showMessage(
        'تم إنشاء الحساب. أكّد بريدك الإلكتروني من الرسالة التي وصلتك، '
        'ثم سجّل الدخول.',
      );

      if (mounted) {
        setState(() {
          _isLogin = true;
          _passwordController.clear();
          _confirmPasswordController.clear();
        });
      }

      return false;
    }

    // ---------- بالهاتف ----------
    final phone = _normalizePhone(identifier, strict: true);

    if (phone == null) {
      _showMessage('رقم الهاتف غير صحيح');
      return false;
    }

    final response = await _phoneAuthRequest(
      action: 'signup',
      phone: phone,
      password: password,
      fullName: fullName,
    );

    if (response['success'] != true) {
      _showMessage(response['message']?.toString() ?? 'تعذر إنشاء الحساب');
      return false;
    }

    final session = _readSession(response);

    if (session == null) {
      _showMessage('تم إنشاء الحساب ولكن تعذر تسجيل الدخول');
      return false;
    }

    await _setSupabaseSession(session);

    _showMessage('تم إنشاء الحساب وتسجيل الدخول بنجاح');

    return true;
  }

  // ============================================================
  // Edge Function الخاصة بالهاتف (phone-auth)
  // ============================================================
  Future<Map<String, dynamic>> _phoneAuthRequest({
    required String action,
    required String phone,
    required String password,
    String fullName = '',
  }) async {
    final response = await _supabase.functions.invoke(
      'phone-auth',
      body: {
        'action': action,
        'phone': phone,
        'password': password,
        if (fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
      },
    );

    final data = response.data;

    if (data is Map) return Map<String, dynamic>.from(data);

    throw Exception('استجابة غير صحيحة من خادم تسجيل الهاتف');
  }

  Map<String, dynamic>? _readSession(Map<String, dynamic> response) {
    final value = response['session'];

    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  Future<void> _setSupabaseSession(Map<String, dynamic> session) async {
    final refreshToken = session['refresh_token']?.toString();

    if (refreshToken == null || refreshToken.isEmpty) {
      throw Exception('بيانات جلسة تسجيل الدخول ناقصة');
    }

    await _supabase.auth.setSession(refreshToken);
  }

  // ============================================================
  // رسائل الأخطاء
  // ============================================================
  bool _isNetworkError(Object error) {
    if (error is AuthRetryableFetchException) return true;

    final text = error.toString().toLowerCase();

    return text.contains('socketexception') ||
        text.contains('clientexception') ||
        text.contains('failed host lookup') ||
        text.contains('timeout') ||
        text.contains('network is unreachable');
  }

  String _errorMessage(Object error) {
    if (_isNetworkError(error)) {
      return 'تعذر الاتصال بالإنترنت. تحقق من اتصالك وحاول مرة أخرى.';
    }

    if (error is AuthException) return _translateAuthError(error.message);

    if (error is FunctionException) return _extractFunctionError(error);

    if (error.toString().contains('رقم الهاتف أو كلمة المرور')) {
      return 'رقم الهاتف أو كلمة المرور غير صحيحة';
    }

    return 'حدث خطأ غير متوقع. حاول مرة أخرى.';
  }

  String _extractFunctionError(FunctionException error) {
    final details = error.details;

    if (details is Map) {
      final message = details['message']?.toString();

      if (message != null && message.isNotEmpty) return message;
    }

    if (details != null && details.toString().contains('رقم الهاتف')) {
      return 'رقم الهاتف أو كلمة المرور غير صحيحة';
    }

    if (error.status == 429) {
      return 'محاولات كثيرة. انتظر قليلاً ثم حاول مرة أخرى.';
    }

    if (error.status >= 500) {
      return 'الخادم مشغول حالياً. حاول مرة أخرى بعد قليل.';
    }

    return 'تعذر الاتصال بخادم تسجيل الهاتف';
  }

  String _translateAuthError(String message) {
    final text = message.toLowerCase();

    if (text.contains('invalid login credentials')) {
      return _usePhone
          ? 'رقم الهاتف أو كلمة المرور غير صحيحة'
          : 'البريد الإلكتروني أو كلمة المرور غير صحيحة';
    }

    if (text.contains('user already registered')) {
      return 'هذا البريد الإلكتروني مسجل بالفعل';
    }

    if (text.contains('email address') && text.contains('invalid')) {
      return 'أدخل بريداً إلكترونياً صحيحاً';
    }

    if (text.contains('password should be at least')) {
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    }

    if (text.contains('weak password')) {
      return 'كلمة المرور ضعيفة، اختر كلمة مرور أقوى';
    }

    if (text.contains('email not confirmed')) {
      return 'يرجى تأكيد البريد الإلكتروني أولاً';
    }

    if (text.contains('too many requests') || text.contains('rate limit')) {
      return 'تم تجاوز عدد المحاولات. حاول مرة أخرى لاحقاً';
    }

    // لا نعرض نصاً إنجليزياً خاماً للمستخدم.
    return 'تعذر إكمال العملية. حاول مرة أخرى.';
  }

  // ============================================================
  // الدعم والروابط
  // ============================================================
  Future<void> _launch(Uri uri, String errorMessage) async {
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) _showMessage(errorMessage);
    } catch (_) {
      _showMessage(errorMessage);
    }
  }

  Future<void> _openLink(String url) {
    return _launch(Uri.parse(url), 'تعذر فتح الرابط');
  }

  // ============================================================
  // مكوّنات الواجهة
  // ============================================================
  Widget _buildHeader() {
    return Column(
      children: [
        const BrandWordmark(logoSize: 62, titleSize: 26),
        const SizedBox(height: 10),
        Text(
          _isLogin
              ? 'مرحباً بك، سجّل الدخول للمتابعة'
              : 'أنشئ حسابك وابدأ البيع والشراء',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  // مبدّل مقسّم بلون العلامة التجارية (بديل SegmentedButton الافتراضي).
  Widget _buildPillSwitch<T>({
    required List<(T value, IconData? icon, String label)> options,
    required T selected,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Brand.soft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: GestureDetector(
                onTap: _loading ? null : () => onChanged(option.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    color: option.$1 == selected ? Brand.primary : null,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: option.$1 == selected
                        ? [
                            BoxShadow(
                              color: Brand.primary.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (option.$2 != null) ...[
                        Icon(
                          option.$2,
                          size: 17,
                          color: option.$1 == selected
                              ? Colors.white
                              : Brand.ink,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          option.$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: option.$1 == selected
                                ? Colors.white
                                : Brand.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeSwitch() {
    return _buildPillSwitch<bool>(
      options: const [
        (true, null, 'تسجيل الدخول'),
        (false, null, 'حساب جديد'),
      ],
      selected: _isLogin,
      onChanged: _setMode,
    );
  }

  Widget _buildMethodSwitch() {
    return _buildPillSwitch<bool>(
      options: const [
        (true, Icons.phone_outlined, 'رقم الهاتف'),
        (false, Icons.email_outlined, 'البريد الإلكتروني'),
      ],
      selected: _usePhone,
      onChanged: _setMethod,
    );
  }

  // تنسيق موحّد لكل حقول النموذج: تعبئة بنفسجية فاتحة بلا حدود.
  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
    String? helper,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperMaxLines: 2,
      prefixIcon: Icon(icon, color: Brand.primary, size: 22),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Brand.soft.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Brand.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
      ),
    );
  }

  Widget _buildFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_isLogin) ...[
          TextFormField(
            controller: _nameController,
            enabled: !_loading,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: _fieldDecoration(
              label: 'الاسم الكامل',
              icon: Icons.person_outline_rounded,
            ),
            validator: _validateName,
          ),
          const SizedBox(height: 16),
        ],

        TextFormField(
          controller: _identifierController,
          enabled: !_loading,
          keyboardType:
              _usePhone ? TextInputType.phone : TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          autofillHints: [
            _usePhone ? AutofillHints.telephoneNumber : AutofillHints.email,
          ],
          inputFormatters: _usePhone
              ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩+\s\-]'))]
              : null,
          decoration: _fieldDecoration(
            label: _usePhone ? 'رقم الهاتف' : 'البريد الإلكتروني',
            hint: _usePhone ? '0912345678' : 'example@email.com',
            helper: _usePhone && !_isLogin
                ? 'رقم سوداني، مثال: 0912345678'
                : null,
            icon: _usePhone
                ? Icons.phone_outlined
                : Icons.email_outlined,
          ),
          validator: _validateIdentifier,
        ),

        const SizedBox(height: 16),

        TextFormField(
          controller: _passwordController,
          enabled: !_loading,
          obscureText: _obscurePassword,
          textInputAction:
              _isLogin ? TextInputAction.done : TextInputAction.next,
          autofillHints: [
            _isLogin ? AutofillHints.password : AutofillHints.newPassword,
          ],
          decoration: _fieldDecoration(
            label: 'كلمة المرور',
            icon: Icons.lock_outline_rounded,
            helper: _isLogin ? null : '6 أحرف على الأقل',
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? 'إظهار' : 'إخفاء',
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: Brand.ink,
              ),
            ),
          ),
          validator: _validatePassword,
          onFieldSubmitted: (_) {
            if (_isLogin) _submit();
          },
        ),

        if (!_isLogin) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            enabled: !_loading,
            obscureText: _obscureConfirmPassword,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.newPassword],
            decoration: _fieldDecoration(
              label: 'تأكيد كلمة المرور',
              icon: Icons.lock_reset_rounded,
              suffixIcon: IconButton(
                tooltip: _obscureConfirmPassword ? 'إظهار' : 'إخفاء',
                onPressed: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Brand.ink,
                ),
              ),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'أكد كلمة المرور';

              if (value != _passwordController.text) {
                return 'كلمتا المرور غير متطابقتين';
              }

              return null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
        ],
      ],
    );
  }

  Widget _buildSubmitButton() {
    return BrandGoldButton(
      label: _isLogin ? 'تسجيل الدخول' : 'إنشاء الحساب',
      icon: Icons.arrow_back_rounded,
      loading: _loading,
      onTap: _loading ? null : _submit,
    );
  }

  Widget _buildLegalNote() {
    final hasLinks = _privacyPolicyUrl.isNotEmpty || _termsUrl.isNotEmpty;

    return Column(
      children: [
        Text(
          'بإنشاء الحساب فإنك توافق على شروط الاستخدام وسياسة الخصوصية.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: Brand.ink.withValues(alpha: 0.65),
          ),
        ),
        if (hasLinks)
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (_termsUrl.isNotEmpty)
                TextButton(
                  onPressed: () => _openLink(_termsUrl),
                  child: const Text('شروط الاستخدام'),
                ),
              if (_privacyPolicyUrl.isNotEmpty)
                TextButton(
                  onPressed: () => _openLink(_privacyPolicyUrl),
                  child: const Text('سياسة الخصوصية'),
                ),
            ],
          ),
      ],
    );
  }

  // ============================================================
  // البناء
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            // زر الرجوع فوق الترويسة مباشرة.
            Positioned(
              top: topPadding + 4,
              right: 4,
              child: SafeArea(
                bottom: false,
                child: IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                children: [
                  BrandHeaderBackground(
                    height: topPadding + 210,
                    child: Padding(
                      padding: EdgeInsets.only(top: topPadding + 26),
                      child: _buildHeader(),
                    ),
                  ),

                  // بطاقة النموذج، ترتفع فوق حافة الترويسة المنحنية.
                  Transform.translate(
                    offset: const Offset(0, -18),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 18),
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Brand.primary.withValues(alpha: 0.14),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: AutofillGroup(
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildModeSwitch(),

                                  const SizedBox(height: 14),

                                  _buildMethodSwitch(),

                                  const SizedBox(height: 20),

                                  _buildFields(),

                                  const SizedBox(height: 22),

                                  _buildSubmitButton(),

                                  if (!_isLogin) ...[
                                    const SizedBox(height: 12),
                                    _buildLegalNote(),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: const SupportContactCard(
                        title: 'لا تستطيع التسجيل أو إضافة إعلانك؟',
                        subtitle:
                            'تواصل معنا وسنساعدك، أو نضيف إعلانك بدلاً عنك. '
                            'وإن نسيت كلمة المرور فنعيد تعيينها لك.',
                      ),
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
}
