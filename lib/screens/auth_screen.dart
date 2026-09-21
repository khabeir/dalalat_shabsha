import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ============================================================
  // تحويل رقم الهاتف إلى الصيغة الدولية
  // ============================================================

  String? _normalizePhone(String value) {
    var phone = value.trim();

    if (phone.isEmpty) {
      return null;
    }

    // إزالة المسافات والشرطات والأقواس
    phone = phone.replaceAll(
      RegExp(r'[\s\-\(\)]'),
      '',
    );

    // 00XXXXXXXXX -> +XXXXXXXXX
    if (phone.startsWith('00')) {
      phone = '+${phone.substring(2)}';
    }

    // الرقم السوداني المحلي:
    // 09XXXXXXXX -> +2499XXXXXXXX
    if (phone.startsWith('0')) {
      phone = '+249${phone.substring(1)}';
    }

    // 249XXXXXXXX -> +249XXXXXXXX
    if (phone.startsWith('249')) {
      phone = '+$phone';
    }

    // يجب أن يبدأ الرقم بـ +
    if (!phone.startsWith('+')) {
      return null;
    }

    final digits = phone.substring(1);

    // أرقام دولية من 8 إلى 15 رقمًا
    if (!RegExp(r'^\d{8,15}$').hasMatch(digits)) {
      return null;
    }

    return phone;
  }

  // ============================================================
  // التحقق من رقم الهاتف
  // ============================================================

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'أدخل رقم الهاتف';
    }

    final phone = _normalizePhone(value);

    if (phone == null) {
      return 'أدخل رقم هاتف صحيح';
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

    final phone = _normalizePhone(
      _phoneController.text,
    );

    if (phone == null) {
      _showMessage('رقم الهاتف غير صحيح');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      // ==========================================================
      // تسجيل الدخول
      // ==========================================================

      if (_isLogin) {
        await _supabase.auth.signInWithPassword(
          phone: phone,
          password: _passwordController.text,
        );

        if (!mounted) return;

        _showMessage(
          'تم تسجيل الدخول بنجاح',
        );

        Navigator.of(context).pop(true);
        return;
      }

      // ==========================================================
      // إنشاء حساب جديد
      // ==========================================================

      final response = await _supabase.auth.signUp(
        phone: phone,
        password: _passwordController.text,
        data: {
          'full_name': _nameController.text.trim(),
          'phone': phone,
        },
      );

      if (!mounted) return;

      if (response.user == null) {
        _showMessage(
          'تعذر إنشاء الحساب',
        );
        return;
      }

      // ==========================================================
      // إذا أنشأ Supabase جلسة مباشرة
      // ==========================================================

      if (response.session != null) {
        _showMessage(
          'تم إنشاء الحساب وتسجيل الدخول بنجاح',
        );

        Navigator.of(context).pop(true);
        return;
      }

      // ==========================================================
      // في حال لم يتم إنشاء جلسة
      // ==========================================================

      _showMessage(
        'تم إنشاء الحساب. يمكنك الآن تسجيل الدخول.',
      );

      setState(() {
        _isLogin = true;
        _passwordController.clear();
        _confirmPasswordController.clear();
      });
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
  // ترجمة أخطاء Supabase
  // ============================================================

  String _translateAuthError(String message) {
    final text = message.toLowerCase();

    if (text.contains('invalid login credentials')) {
      return 'رقم الهاتف أو كلمة المرور غير صحيحة';
    }

    if (text.contains('user already registered')) {
      return 'رقم الهاتف مسجل بالفعل';
    }

    if (text.contains('phone signups are disabled')) {
      return 'تسجيل الحسابات برقم الهاتف غير مفعّل في Supabase';
    }

    if (text.contains('phone provider is disabled')) {
      return 'مزود تسجيل الهاتف غير مفعّل في Supabase';
    }

    if (text.contains('invalid phone')) {
      return 'رقم الهاتف غير صحيح';
    }

    if (text.contains('phone number')) {
      return 'رقم الهاتف غير صحيح أو غير مدعوم';
    }

    if (text.contains('password should be at least')) {
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    }

    if (text.contains('weak password')) {
      return 'كلمة المرور ضعيفة، اختر كلمة مرور أقوى';
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
                      // ==================================================
                      // الشعار
                      // ==================================================

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
                          controller: _nameController,
                          textInputAction:
                              TextInputAction.next,
                          decoration:
                              const InputDecoration(
                            labelText: 'الاسم الكامل',
                            prefixIcon: Icon(
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
                      // رقم الهاتف
                      // ==================================================

                      TextFormField(
                        controller:
                            _phoneController,
                        keyboardType:
                            TextInputType.phone,
                        textInputAction:
                            TextInputAction.next,
                        decoration:
                            const InputDecoration(
                          labelText: 'رقم الهاتف',
                          hintText:
                              'مثال: 0912345678',
                          prefixIcon: Icon(
                            Icons.phone_outlined,
                          ),
                          border:
                              OutlineInputBorder(),
                        ),
                        validator: _validatePhone,
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
                        textInputAction: _isLogin
                            ? TextInputAction.done
                            : TextInputAction.next,
                        decoration:
                            InputDecoration(
                          labelText: 'كلمة المرور',
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
                      // زر تسجيل الدخول / إنشاء الحساب
                      // ==================================================

                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed:
                              _loading ? null : _submit,
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
                      // التبديل بين التسجيل والدخول
                      // ==================================================

                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _isLogin =
                                      !_isLogin;

                                  _formKey.currentState
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