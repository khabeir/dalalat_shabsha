import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  // بيانات الدعم.
  static const _supportPhone = '0914111214';
  static const _supportWhatsApp = '249914111214';

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

  Future<void> _callSupport() {
    return _launch(
      Uri(scheme: 'tel', path: _supportPhone),
      'تعذر فتح تطبيق الاتصال',
    );
  }

  Future<void> _openSupportWhatsApp() {
    return _launch(
      Uri.parse('https://wa.me/$_supportWhatsApp'),
      'تعذر فتح WhatsApp',
    );
  }

  Future<void> _openLink(String url) {
    return _launch(Uri.parse(url), 'تعذر فتح الرابط');
  }

  // ============================================================
  // مكوّنات الواجهة
  // ============================================================
  Widget _buildHeader() {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            Icons.storefront_rounded,
            size: 42,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'دلالة شبشة',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isLogin
              ? 'مرحباً بك، سجّل الدخول للمتابعة'
              : 'أنشئ حسابك وابدأ البيع والشراء',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildModeSwitch() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment<bool>(value: true, label: Text('تسجيل الدخول')),
          ButtonSegment<bool>(value: false, label: Text('حساب جديد')),
        ],
        selected: {_isLogin},
        showSelectedIcon: false,
        onSelectionChanged: _loading ? null : (value) => _setMode(value.first),
      ),
    );
  }

  Widget _buildMethodSwitch() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        segments: const [
          ButtonSegment<bool>(
            value: true,
            icon: Icon(Icons.phone_outlined),
            label: Text('رقم الهاتف'),
          ),
          ButtonSegment<bool>(
            value: false,
            icon: Icon(Icons.email_outlined),
            label: Text('البريد الإلكتروني'),
          ),
        ],
        selected: {_usePhone},
        showSelectedIcon: false,
        onSelectionChanged:
            _loading ? null : (value) => _setMethod(value.first),
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
            decoration: const InputDecoration(
              labelText: 'الاسم الكامل',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
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
          decoration: InputDecoration(
            labelText: _usePhone ? 'رقم الهاتف' : 'البريد الإلكتروني',
            hintText: _usePhone ? '0912345678' : 'example@email.com',
            helperText: _usePhone && !_isLogin
                ? 'رقم سوداني، مثال: 0912345678'
                : null,
            prefixIcon: Icon(
              _usePhone ? Icons.phone_outlined : Icons.email_outlined,
            ),
            border: const OutlineInputBorder(),
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
          decoration: InputDecoration(
            labelText: 'كلمة المرور',
            helperText: _isLogin ? null : '6 أحرف على الأقل',
            prefixIcon: const Icon(Icons.lock_outline),
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? 'إظهار' : 'إخفاء',
              onPressed: () {
                setState(() => _obscurePassword = !_obscurePassword);
              },
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
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
            decoration: InputDecoration(
              labelText: 'تأكيد كلمة المرور',
              prefixIcon: const Icon(Icons.lock_reset_outlined),
              border: const OutlineInputBorder(),
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
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: _loading ? null : _submit,
        child: _loading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                _isLogin ? 'تسجيل الدخول' : 'إنشاء الحساب',
                style: const TextStyle(fontSize: 17),
              ),
      ),
    );
  }

  Widget _buildLegalNote() {
    final colorScheme = Theme.of(context).colorScheme;

    final hasLinks = _privacyPolicyUrl.isNotEmpty || _termsUrl.isNotEmpty;

    return Column(
      children: [
        Text(
          'بإنشاء الحساب فإنك توافق على شروط الاستخدام وسياسة الخصوصية.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: colorScheme.onSurfaceVariant,
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

  Widget _buildSupport() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'واجهتك مشكلة أو نسيت كلمة المرور؟',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          ),
          const SizedBox(height: 4),
          Text(
            'تواصل معنا وسنساعدك',
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _callSupport,
                  icon: const Icon(Icons.phone_outlined),
                  label: const Text('اتصال'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _openSupportWhatsApp,
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('واتساب'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            _supportPhone,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // البناء
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(),

                        const SizedBox(height: 26),

                        _buildModeSwitch(),

                        const SizedBox(height: 14),

                        _buildMethodSwitch(),

                        const SizedBox(height: 20),

                        _buildFields(),

                        const SizedBox(height: 22),

                        _buildSubmitButton(),

                        if (!_isLogin) ...[
                          const SizedBox(height: 10),
                          _buildLegalNote(),
                        ],

                        const SizedBox(height: 22),

                        _buildSupport(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
