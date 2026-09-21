import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final _supabase = Supabase.instance.client;

  // ============================================================
  // رقم الهاتف
  // ============================================================

  String? _normalizePhone(String value) {
    var phone = value.trim();

    if (phone.isEmpty) {
      return null;
    }

    phone = phone.replaceAll(
      RegExp(r'[\s\-\(\)]'),
      '',
    );

    if (phone.startsWith('00')) {
      phone = '+${phone.substring(2)}';
    }

    if (phone.startsWith('0')) {
      phone = '+249${phone.substring(1)}';
    }

    if (phone.startsWith('249')) {
      phone = '+$phone';
    }

    if (!phone.startsWith('+')) {
      return null;
    }

    final digits = phone.substring(1);

    if (!RegExp(r'^\d{8,15}$').hasMatch(digits)) {
      return null;
    }

    return phone;
  }

  // ============================================================
  // هل الإدخال بريد إلكتروني؟
  // ============================================================

  bool _isEmail(String value) {
    return RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(value.trim());
  }

  // ============================================================
  // التحقق من البريد أو الهاتف
  // ============================================================

  String? _validateIdentifier(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'أدخل البريد الإلكتروني أو رقم الهاتف';
    }

    final text = value.trim();

    // بريد إلكتروني
    if (text.contains('@')) {
      if (!_isEmail(text)) {
        return 'أدخل بريدًا إلكترونيًا صحيحًا';
      }

      return null;
    }

    // رقم هاتف
    if (_normalizePhone(text) == null) {
      return 'أدخل بريدًا إلكترونيًا أو رقم هاتف صحيحًا';
    }

    return null;
  }

  // ============================================================
  // تسجيل الدخول / إنشاء الحساب
  // ============================================================

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final identifier =
        _identifierController.text.trim();

    setState(() {
      _loading = true;
    });

    try {
      // ==========================================================
      // تسجيل الدخول
      // ==========================================================

      if (_isLogin) {
        // --------------------------------------------------------
        // تسجيل الدخول بالبريد الإلكتروني
        // --------------------------------------------------------

        if (_isEmail(identifier)) {
          await _supabase.auth.signInWithPassword(
            email: identifier,
            password: _passwordController.text,
          );
        }

        // --------------------------------------------------------
        // تسجيل الدخول برقم الهاتف
        // --------------------------------------------------------

        else {
          final phone = _normalizePhone(identifier);

          if (phone == null) {
            _showMessage('رقم الهاتف غير صحيح');
            return;
          }

          await _loginWithPhone(
            phone: phone,
            password: _passwordController.text,
          );
        }

        if (!mounted) return;

        _showMessage('تم تسجيل الدخول بنجاح');

        Navigator.of(context).pop(true);
        return;
      }

      // ==========================================================
      // إنشاء حساب جديد
      // ==========================================================

      final fullName =
          _nameController.text.trim();

      // ----------------------------------------------------------
      // التسجيل بالبريد الإلكتروني
      // ----------------------------------------------------------

      if (_isEmail(identifier)) {
        final response =
            await _supabase.auth.signUp(
          email: identifier,
          password: _passwordController.text,
          data: {
            'full_name': fullName,
          },
        );

        if (!mounted) return;

        if (response.user == null) {
          _showMessage('تعذر إنشاء الحساب');
          return;
        }

        if (response.session != null) {
          _showMessage(
            'تم إنشاء الحساب وتسجيل الدخول بنجاح',
          );

          Navigator.of(context).pop(true);
          return;
        }

        _showMessage(
          'تم إنشاء الحساب. يمكنك الآن تسجيل الدخول.',
        );

        setState(() {
          _isLogin = true;
          _passwordController.clear();
          _confirmPasswordController.clear();
        });

        return;
      }

      // ----------------------------------------------------------
      // التسجيل برقم الهاتف
      // ----------------------------------------------------------

      final phone = _normalizePhone(identifier);

      if (phone == null) {
        _showMessage('رقم الهاتف غير صحيح');
        return;
      }

      final response =
          await _phoneAuthRequest(
        action: 'signup',
        phone: phone,
        password: _passwordController.text,
        fullName: fullName,
      );

      if (!mounted) return;

      if (response['success'] != true) {
        _showMessage(
          response['message']?.toString() ??
              'تعذر إنشاء الحساب',
        );
        return;
      }

      // ----------------------------------------------------------
      // حفظ Session في Supabase Flutter
      // ----------------------------------------------------------

      final session =
          response['session'] as Map<String, dynamic>?;

      if (session == null) {
        _showMessage(
          'تم إنشاء الحساب ولكن تعذر تسجيل الدخول',
        );
        return;
      }

      await _setSupabaseSession(session);

      if (!mounted) return;

      _showMessage(
        'تم إنشاء الحساب وتسجيل الدخول بنجاح',
      );

      Navigator.of(context).pop(true);
    } on AuthException catch (e) {
      if (!mounted) return;

      _showMessage(
        _translateAuthError(e.message),
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'حدث خطأ غير متوقع: $e',
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ============================================================
  // تسجيل الدخول بالهاتف عبر Edge Function
  // ============================================================

  Future<void> _loginWithPhone({
    required String phone,
    required String password,
  }) async {
    final response = await _phoneAuthRequest(
      action: 'login',
      phone: phone,
      password: password,
    );

    if (response['success'] != true) {
      throw Exception(
        response['message']?.toString() ??
            'رقم الهاتف أو كلمة المرور غير صحيحة',
      );
    }

    final session =
        response['session'] as Map<String, dynamic>?;

    if (session == null) {
      throw Exception(
        'تعذر إنشاء جلسة تسجيل الدخول',
      );
    }

    await _setSupabaseSession(session);
  }

  // ============================================================
  // استدعاء Edge Function
  // ============================================================

  Future<Map<String, dynamic>> _phoneAuthRequest({
    required String action,
    required String phone,
    required String password,
    String fullName = '',
  }) async {
    final response =
        await _supabase.functions.invoke(
      'phone-auth',
      body: {
        'action': action,
        'phone': phone,
        'password': password,
        if (fullName.trim().isNotEmpty)
          'full_name': fullName.trim(),
      },
    );

    final data = response.data;

    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }

    return {
      'success': false,
      'message': 'استجابة غير صحيحة من الخادم',
    };
  }

  // ============================================================
  // حفظ جلسة Supabase
  // ============================================================

  Future<void> _setSupabaseSession(
    Map<String, dynamic> session,
  ) async {
    final accessToken =
        session['access_token']?.toString();

    final refreshToken =
        session['refresh_token']?.toString();

    if (accessToken == null ||
        accessToken.isEmpty ||
        refreshToken == null ||
        refreshToken.isEmpty) {
      throw Exception(
        'بيانات جلسة تسجيل الدخول ناقصة',
      );
    }

    await _supabase.auth.setSession(
      refreshToken,
    );
  }

  // ============================================================
  // ترجمة أخطاء Supabase
  // ============================================================

  String _translateAuthError(String message) {
    final text = message.toLowerCase();

    if (text.contains('invalid login credentials')) {
      return 'البريد الإلكتروني أو رقم الهاتف أو كلمة المرور غير صحيحة';
    }

    if (text.contains('user already registered')) {
      return 'هذا البريد الإلكتروني مسجل بالفعل';
    }

    if (text.contains('email address') &&
        text.contains('invalid')) {
      return 'أدخل بريدًا إلكترونيًا صحيحًا';
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

    if (text.contains('too many requests')) {
      return 'تم تجاوز عدد المحاولات. حاول مرة أخرى لاحقًا';
    }

    if (text.contains('rate limit')) {
      return 'تم تجاوز الحد المسموح. حاول مرة أخرى لاحقًا';
    }

    return message;
  }

  // ============================================================
  // رسالة للمستخدم
  // ============================================================

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
  }

  // ============================================================
  // الحقول المطلوبة
  // ============================================================

  String? _required(
    String? value,
    String message,
  ) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }

    return null;
  }

  // ============================================================
  // الاتصال بالدعم
  // ============================================================

  Future<void> _callSupport() async {
    final uri = Uri(
      scheme: 'tel',
      path: '0914111214',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        _showMessage(
          'تعذر فتح تطبيق الاتصال',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'تعذر فتح تطبيق الاتصال',
        );
      }
    }
  }

  // ============================================================
  // WhatsApp للدعم
  // ============================================================

  Future<void> _openSupportWhatsApp() async {
    const phone = '249914111214';

    final uri = Uri.parse(
      'https://wa.me/$phone',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        _showMessage(
          'تعذر فتح WhatsApp',
        );
      }
    } catch (_) {
      if (mounted) {
        _showMessage(
          'تعذر فتح WhatsApp',
        );
      }
    }
  }

  // ============================================================
  // واجهة التطبيق
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 500,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '🛒',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 55,
                        ),
                      ),

                      const SizedBox(height: 12),

                      const Text(
                        'دلالة شبشة',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        _isLogin
                            ? 'مرحباً بك، سجّل الدخول للمتابعة'
                            : 'أنشئ حسابك وابدأ البيع والشراء',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                        ),
                      ),

                      const SizedBox(height: 30),

                      // ==================================================
                      // الاسم - التسجيل فقط
                      // ==================================================

                      if (!_isLogin) ...[
                        TextFormField(
                          controller:
                              _nameController,
                          textInputAction:
                              TextInputAction.next,
                          decoration:
                              const InputDecoration(
                            labelText:
                                'الاسم الكامل',
                            prefixIcon:
                                Icon(
                              Icons.person_outline,
                            ),
                            border:
                                OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              _required(
                            value,
                            'أدخل الاسم الكامل',
                          ),
                        ),

                        const SizedBox(height: 16),
                      ],

                      // ==================================================
                      // البريد أو الهاتف
                      // ==================================================

                      TextFormField(
                        controller:
                            _identifierController,
                        keyboardType:
                            TextInputType.emailAddress,
                        textInputAction:
                            TextInputAction.next,
                        decoration:
                            const InputDecoration(
                          labelText:
                              'البريد الإلكتروني أو رقم الهاتف',
                          hintText:
                              'example@email.com أو 0912345678',
                          prefixIcon:
                              Icon(
                            Icons
                                .alternate_email_outlined,
                          ),
                          border:
                              OutlineInputBorder(),
                        ),
                        validator:
                            _validateIdentifier,
                      ),

                      const SizedBox(height: 16),

                      // ==================================================
                      // كلمة المرور
                      // ==================================================

                      TextFormField(
                        controller:
                            _passwordController,
                        obscureText:
                            _obscurePassword,
                        textInputAction:
                            _isLogin
                                ? TextInputAction.done
                                : TextInputAction.next,
                        decoration:
                            InputDecoration(
                          labelText:
                              'كلمة المرور',
                          prefixIcon:
                              const Icon(
                            Icons.lock_outline,
                          ),
                          border:
                              const OutlineInputBorder(),
                          suffixIcon:
                              IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePassword =
                                    !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons
                                      .visibility_outlined
                                  : Icons
                                      .visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final required =
                              _required(
                            value,
                            'أدخل كلمة المرور',
                          );

                          if (required != null) {
                            return required;
                          }

                          if (value!.length < 6) {
                            return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                          }

                          return null;
                        },
                        onFieldSubmitted: (_) {
                          if (_isLogin &&
                              !_loading) {
                            _submit();
                          }
                        },
                      ),

                      // ==================================================
                      // تأكيد كلمة المرور
                      // ==================================================

                      if (!_isLogin) ...[
                        const SizedBox(height: 16),

                        TextFormField(
                          controller:
                              _confirmPasswordController,
                          obscureText:
                              _obscureConfirmPassword,
                          textInputAction:
                              TextInputAction.done,
                          decoration:
                              InputDecoration(
                            labelText:
                                'تأكيد كلمة المرور',
                            prefixIcon:
                                const Icon(
                              Icons
                                  .lock_reset_outlined,
                            ),
                            border:
                                const OutlineInputBorder(),
                            suffixIcon:
                                IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
                                });
                              },
                              icon: Icon(
                                _obscureConfirmPassword
                                    ? Icons
                                        .visibility_outlined
                                    : Icons
                                        .visibility_off_outlined,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null ||
                                value.isEmpty) {
                              return 'أكد كلمة المرور';
                            }

                            if (value !=
                                _passwordController
                                    .text) {
                              return 'كلمتا المرور غير متطابقتين';
                            }

                            return null;
                          },
                          onFieldSubmitted: (_) {
                            if (!_loading) {
                              _submit();
                            }
                          },
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ==================================================
                      // زر الدخول / التسجيل
                      // ==================================================

                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed:
                              _loading
                                  ? null
                                  : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isLogin
                                      ? 'تسجيل الدخول'
                                      : 'إنشاء الحساب',
                                  style:
                                      const TextStyle(
                                    fontSize: 17,
                                  ),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // ==================================================
                      // التبديل
                      // ==================================================

                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _isLogin =
                                      !_isLogin;

                                  _formKey
                                      .currentState
                                      ?.reset();

                                  _passwordController
                                      .clear();

                                  _confirmPasswordController
                                      .clear();
                                });
                              },
                        child: Text(
                          _isLogin
                              ? 'ليس لديك حساب؟ إنشاء حساب جديد'
                              : 'لديك حساب بالفعل؟ تسجيل الدخول',
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ==================================================
                      // الدعم
                      // ==================================================

                      const Divider(),

                      const SizedBox(height: 12),

                      const Text(
                        'واجهتك مشكلة في التسجيل؟',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),

                      const SizedBox(height: 4),

                      const Text(
                        'تواصل معنا',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                        ),
                      ),

                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _loading
                                      ? null
                                      : _callSupport,
                              icon: const Icon(
                                Icons.phone_outlined,
                              ),
                              label: const Text(
                                'اتصال',
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _loading
                                      ? null
                                      : _openSupportWhatsApp,
                              icon: const Icon(
                                Icons.chat_outlined,
                              ),
                              label: const Text(
                                'WhatsApp',
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),

                      const Text(
                        '0914111214',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                        ),
                      ),
                    ],
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