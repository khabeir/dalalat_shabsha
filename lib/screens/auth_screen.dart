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
  final _emailController = TextEditingController();
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
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      if (_isLogin) {
        await _supabase.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

        if (!mounted) return;

        Navigator.pop(context, true);
      } else {
        final response = await _supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {
            'full_name': _nameController.text.trim(),
          },
        );

        if (!mounted) return;

        if (response.user != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'تم إنشاء الحساب بنجاح. تحقق من بريدك الإلكتروني إذا طُلب منك ذلك.',
              ),
            ),
          );

          setState(() {
            _isLogin = true;
            _passwordController.clear();
            _confirmPasswordController.clear();
          });
        }
      }
    } on AuthException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_translateAuthError(e.message)),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ غير متوقع: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _translateAuthError(String message) {
    final text = message.toLowerCase();

    if (text.contains('invalid login credentials')) {
      return 'البريد الإلكتروني أو كلمة المرور غير صحيحة';
    }

    if (text.contains('user already registered')) {
      return 'هذا البريد الإلكتروني مسجل بالفعل';
    }

    if (text.contains('password should be at least')) {
      return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    }

    if (text.contains('email not confirmed')) {
      return 'يرجى تأكيد البريد الإلكتروني أولاً';
    }

    return message;
  }

  String? _required(String? value, String message) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

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
                constraints: const BoxConstraints(maxWidth: 500),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        '🛒',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 55),
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
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 30),

                      if (!_isLogin) ...[
                        TextFormField(
                          controller: _nameController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'الاسم الكامل',
                            prefixIcon: Icon(Icons.person_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              _required(value, 'أدخل الاسم الكامل'),
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف',
                            prefixIcon: Icon(Icons.phone_outlined),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'البريد الإلكتروني',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final required =
                              _required(value, 'أدخل البريد الإلكتروني');

                          if (required != null) return required;

                          if (!value!.contains('@')) {
                            return 'أدخل بريداً إلكترونياً صحيحاً';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: _isLogin
                            ? TextInputAction.done
                            : TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) {
                          final required =
                              _required(value, 'أدخل كلمة المرور');

                          if (required != null) return required;

                          if (value!.length < 6) {
                            return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                          }

                          return null;
                        },
                        onFieldSubmitted: (_) {
                          if (_isLogin) _submit();
                        },
                      ),

                      if (!_isLogin) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmPasswordController,
                          obscureText: _obscureConfirmPassword,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'تأكيد كلمة المرور',
                            prefixIcon: const Icon(Icons.lock_reset_outlined),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword;
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
                            if (value == null || value.isEmpty) {
                              return 'أكد كلمة المرور';
                            }

                            if (value != _passwordController.text) {
                              return 'كلمتا المرور غير متطابقتين';
                            }

                            return null;
                          },
                          onFieldSubmitted: (_) => _submit(),
                        ),
                      ],

                      const SizedBox(height: 24),

                      SizedBox(
                        height: 52,
                        child: FilledButton(
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isLogin
                                      ? 'تسجيل الدخول'
                                      : 'إنشاء الحساب',
                                  style: const TextStyle(fontSize: 17),
                                ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _isLogin = !_isLogin;
                                  _formKey.currentState?.reset();
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