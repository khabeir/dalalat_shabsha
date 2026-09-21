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
  final _otpController = TextEditingController();

  bool _isLogin = true;
  bool _loading = false;
  bool _showOtpScreen = false;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String _verificationMethod = 'sms';
  String _verifiedPhone = '';

  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
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
    phone = phone.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    // إذا بدأ بـ 00 نحوله إلى +
    if (phone.startsWith('00')) {
      phone = '+${phone.substring(2)}';
    }

    // رقم سوداني محلي:
    // 09XXXXXXXX
    if (phone.startsWith('0')) {
      phone = '+249${phone.substring(1)}';
    }

    // 249XXXXXXXX
    if (phone.startsWith('249')) {
      phone = '+$phone';
    }

    // التأكد من أنه يبدأ +
    if (!phone.startsWith('+')) {
      return null;
    }

    // التحقق من الأرقام فقط بعد +
    final digits = phone.substring(1);

    if (!RegExp(r'^\d{8,15}$').hasMatch(digits)) {
      return null;
    }

    return phone;
  }

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
  // التسجيل / تسجيل الدخول
  // ============================================================

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final phone = _normalizePhone(_phoneController.text);

    if (phone == null) {
      _showMessage('رقم الهاتف غير صحيح');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      if (_isLogin) {
        // --------------------------------------------------------
        // تسجيل الدخول برقم الهاتف + كلمة المرور
        // --------------------------------------------------------

        await _supabase.auth.signInWithPassword(
          phone: phone,
          password: _passwordController.text,
        );

        if (!mounted) return;

        _showMessage(
          'تم تسجيل الدخول بنجاح',
        );

        Navigator.of(context).pop(true);
      } else {
        // --------------------------------------------------------
        // إنشاء الحساب
        // --------------------------------------------------------

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
          _showMessage('تعذر إنشاء الحساب');
          return;
        }

        _verifiedPhone = phone;

        // --------------------------------------------------------
        // إرسال رمز التحقق
        // --------------------------------------------------------

        await _sendOtp(phone);

        if (!mounted) return;

        setState(() {
          _showOtpScreen = true;
          _otpController.clear();
        });
      }
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
  // إرسال OTP
  // ============================================================

  Future<void> _sendOtp(String phone) async {
    if (_verificationMethod == 'sms') {
      await _supabase.auth.signInWithOtp(
        phone: phone,
      );
    } else {
      // WhatsApp
      //
      // Supabase يعتمد على إعداد مزود WhatsApp في لوحة
      // Authentication > Providers > Phone.
      //
      // إذا كان مشروع Supabase مضبوطًا لاستخدام WhatsApp
      // كقناة OTP، يمكن استخدام channel: OtpChannel.whatsapp.

      await _supabase.auth.signInWithOtp(
        phone: phone,
        channel: OtpChannel.whatsapp,
      );
    }
  }

  // ============================================================
  // التحقق من رمز OTP
  // ============================================================

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();

    if (otp.length < 4) {
      _showMessage('أدخل رمز التحقق');
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final response = await _supabase.auth.verifyOTP(
        phone: _verifiedPhone,
        token: otp,
        type: OtpType.sms,
      );

      if (!mounted) return;

      if (response.user != null) {
        _showMessage(
          'تم تأكيد رقم الهاتف وإنشاء الحساب بنجاح',
        );

        Navigator.of(context).pop(true);
      } else {
        _showMessage(
          'تعذر تأكيد رقم الهاتف',
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;

      _showMessage(
        _translateAuthError(e.message),
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'حدث خطأ أثناء التحقق',
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
  // إعادة إرسال الرمز
  // ============================================================

  Future<void> _resendOtp() async {
    if (_verifiedPhone.isEmpty) {
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      await _sendOtp(_verifiedPhone);

      if (!mounted) return;

      _showMessage(
        _verificationMethod == 'sms'
            ? 'تم إرسال رمز جديد عبر SMS'
            : 'تم إرسال رمز جديد عبر WhatsApp',
      );
    } on AuthException catch (e) {
      if (!mounted) return;

      _showMessage(
        _translateAuthError(e.message),
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'تعذر إرسال رمز جديد',
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
  // أخطاء Supabase
  // ============================================================

  String _translateAuthError(String message) {
    final text = message.toLowerCase();

    if (text.contains('invalid login credentials')) {
      return 'رقم الهاتف أو كلمة المرور غير صحيحة';
    }

    if (text.contains('user already registered')) {
      return 'رقم الهاتف مسجل بالفعل';
    }

    if (text.contains('phone number') &&
        text.contains('invalid')) {
      return 'رقم الهاتف غير صحيح';
    }

    if (text.contains('password should be at least')) {
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    }

    if (text.contains('invalid otp') ||
        text.contains('invalid token')) {
      return 'رمز التحقق غير صحيح';
    }

    if (text.contains('expired')) {
      return 'رمز التحقق منتهي الصلاحية، اطلب رمزًا جديدًا';
    }

    if (text.contains('too many requests')) {
      return 'تم تجاوز عدد المحاولات. حاول مرة أخرى لاحقًا';
    }

    if (text.contains('rate limit')) {
      return 'تم تجاوز الحد المسموح لإرسال الرموز. حاول لاحقًا';
    }

    if (text.contains('sms')) {
      return 'تعذر إرسال رسالة SMS. تحقق من إعدادات خدمة الرسائل';
    }

    if (text.contains('whatsapp')) {
      return 'تعذر إرسال رمز WhatsApp. تحقق من إعدادات WhatsApp';
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
  // التحقق من الحقول
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
  // شاشة OTP
  // ============================================================

  Widget _buildOtpScreen() {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تأكيد رقم الهاتف'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _loading
                ? null
                : () {
                    setState(() {
                      _showOtpScreen = false;
                      _otpController.clear();
                    });
                  },
          ),
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 500,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '🔐',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 60,
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      'تأكيد رقم الهاتف',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      _verificationMethod == 'sms'
                          ? 'أرسلنا رمز التحقق عبر SMS'
                          : 'أرسلنا رمز التحقق عبر WhatsApp',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      _verifiedPhone,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 30),

                    TextFormField(
                      controller: _otpController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'رمز التحقق',
                        prefixIcon: Icon(
                          Icons.verified_outlined,
                        ),
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onFieldSubmitted: (_) {
                        if (!_loading) {
                          _verifyOtp();
                        }
                      },
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed:
                            _loading ? null : _verifyOtp,
                        child: _loading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'تأكيد الرمز',
                                style: TextStyle(
                                  fontSize: 17,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextButton(
                      onPressed:
                          _loading ? null : _resendOtp,
                      child: Text(
                        _verificationMethod == 'sms'
                            ? 'إعادة إرسال الرمز عبر SMS'
                            : 'إعادة إرسال الرمز عبر WhatsApp',
                      ),
                    ),

                    const SizedBox(height: 8),

                    TextButton(
                      onPressed: _loading
                          ? null
                          : () {
                              setState(() {
                                _showOtpScreen = false;
                                _otpController.clear();
                              });
                            },
                      child: const Text(
                        'تغيير رقم الهاتف أو طريقة التحقق',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // شاشة تسجيل الدخول / إنشاء الحساب
  // ============================================================

  Widget _buildAuthScreen() {
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
                      // الاسم عند التسجيل
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
                            border: OutlineInputBorder(),
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
                        controller: _phoneController,
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
                          border: OutlineInputBorder(),
                        ),
                        validator: _validatePhone,
                      ),

                      const SizedBox(height: 16),

                      // ==================================================
                      // طريقة التحقق عند التسجيل
                      // ==================================================

                      if (!_isLogin) ...[
                        const Text(
                          'طريقة استلام رمز التحقق',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                        const SizedBox(height: 8),

                        RadioGroup<String>(
                          groupValue:
                              _verificationMethod,
                          onChanged: (value) {
                            if (value == null) return;

                            setState(() {
                              _verificationMethod =
                                  value;
                            });
                          },
                          child: Column(
                            children: [
                              RadioListTile<String>(
                                value: 'sms',
                                title:
                                    const Text('SMS'),
                                subtitle: const Text(
                                  'استلام الرمز برسالة نصية',
                                ),
                                secondary: const Icon(
                                  Icons.sms_outlined,
                                ),
                              ),
                              RadioListTile<String>(
                                value: 'whatsapp',
                                title:
                                    const Text('WhatsApp'),
                                subtitle: const Text(
                                  'استلام الرمز عبر WhatsApp',
                                ),
                                secondary:
                                    const Icon(
                                  Icons.chat_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),
                      ],

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
                      // زر التنفيذ
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

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_showOtpScreen) {
      return _buildOtpScreen();
    }

    return _buildAuthScreen();
  }
}