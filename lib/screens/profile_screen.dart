import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'my_listings_screen.dart';

class ProfileScreen extends StatefulWidget {
const ProfileScreen({super.key});

@override
State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
final _supabase = Supabase.instance.client;

final _nameController = TextEditingController();
final _phoneController = TextEditingController();
final _areaController = TextEditingController();

bool _loading = true;
bool _saving = false;
bool _isPhoneAccount = false;

String? _error;
String? _email;
int _listingsCount = 0;

@override
void initState() {
super.initState();
_loadProfile();
}

@override
void dispose() {
_nameController.dispose();
_phoneController.dispose();
_areaController.dispose();
super.dispose();
}

// ============================================================
// تحميل بيانات الملف الشخصي
// ============================================================

Future<void> _loadProfile() async {
if (!mounted) return;

setState(() {
  _loading = true;
  _error = null;
});

try {
  final user = _supabase.auth.currentUser;

  if (user == null) {
    throw Exception('لا يوجد مستخدم مسجل الدخول.');
  }

  final authEmail = user.email ?? '';

  // حساب الهاتف يستخدم بريدًا داخليًا غير مخصص للمستخدم.
  final isPhoneAccount =
      authEmail.toLowerCase().endsWith('@phone-auth.invalid');

  final profile = await _supabase
      .from('profiles')
      .select('full_name, phone, area')
      .eq('id', user.id)
      .maybeSingle();

  final fullName =
      profile?['full_name']?.toString() ??
      user.userMetadata?['full_name']?.toString() ??
      '';

  final phone =
      profile?['phone']?.toString() ??
      user.userMetadata?['phone']?.toString() ??
      '';

  final area = profile?['area']?.toString() ?? '';

  final listings = await _supabase
      .from('listings')
      .select('id')
      .eq('seller_id', user.id);

  if (!mounted) return;

  setState(() {
    _isPhoneAccount = isPhoneAccount;

    // لا نعرض البريد الداخلي الاصطناعي.
    _email = isPhoneAccount ? null : authEmail;

    _nameController.text = fullName;
    _phoneController.text = phone;
    _areaController.text = area;

    _listingsCount = listings.length;
    _loading = false;
  });
} catch (e) {
  if (!mounted) return;

  setState(() {
    _error =
        'تعذر تحميل الملف الشخصي. تحقق من اتصال الإنترنت وحاول مجدداً.';
    _loading = false;
  });
}

}

// ============================================================
// حفظ بيانات الملف الشخصي
// ============================================================

Future<void> _saveProfile() async {
final user = _supabase.auth.currentUser;

if (user == null) {
  _showMessage('يرجى تسجيل الدخول أولاً');
  return;
}

final fullName = _nameController.text.trim();
final phone = _phoneController.text.trim();
final area = _areaController.text.trim();

if (fullName.isEmpty) {
  _showMessage('يرجى إدخال الاسم الكامل');
  return;
}

if (!mounted) return;

setState(() {
  _saving = true;
});

try {
  await _supabase.from('profiles').upsert(
    {
      'id': user.id,
      'full_name': fullName,

      // حساب الهاتف يحتفظ برقمه المرتبط بتسجيل الدخول.
      'phone': phone.isEmpty ? null : phone,

      'area': area.isEmpty ? null : area,
    },
    onConflict: 'id',
  );

  if (!mounted) return;

  setState(() {
    _saving = false;
  });

  _showMessage('تم حفظ بيانات الملف الشخصي بنجاح');
} catch (e) {
  if (!mounted) return;

  setState(() {
    _saving = false;
  });

  _showMessage(
    'تعذر حفظ البيانات. تحقق من إعدادات صلاحيات profiles في Supabase.',
  );
}

}

// ============================================================
// فتح صفحة إعلاناتي
// ============================================================

Future<void> openMyListings() async {
await Navigator.push(
context,
MaterialPageRoute(
builder: () => const MyListingsScreen(),
),
);

if (mounted) {
  _loadProfile();
}

}

// ============================================================
// عرض رسالة
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
// نموذج الملف الشخصي
// ============================================================

Widget _buildProfileForm() {
return ListView(
padding: const EdgeInsets.all(20),
children: [
const Center(
child: CircleAvatar(
radius: 42,
child: Icon(
Icons.person_outline,
size: 48,
),
),
),

    const SizedBox(height: 16),

    Center(
      child: Chip(
        avatar: Icon(
          _isPhoneAccount
              ? Icons.phone_android_outlined
              : Icons.email_outlined,
        ),
        label: Text(
          _isPhoneAccount
              ? 'الحساب مرتبط برقم الهاتف'
              : 'الحساب مرتبط بالبريد الإلكتروني',
        ),
      ),
    ),

    const SizedBox(height: 24),

    // ========================================================
    // الاسم الكامل
    // ========================================================

    TextField(
      controller: _nameController,
      textInputAction: TextInputAction.next,
      decoration: const InputDecoration(
        labelText: 'الاسم الكامل',
        prefixIcon: Icon(Icons.person_outline),
        border: OutlineInputBorder(),
      ),
    ),

    const SizedBox(height: 16),

    // ========================================================
    // رقم الهاتف
    // ========================================================

    TextField(
      controller: _phoneController,
      readOnly: _isPhoneAccount,
      keyboardType: TextInputType.phone,
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: 'رقم الهاتف',
        prefixIcon: const Icon(Icons.phone_outlined),
        border: const OutlineInputBorder(),
        helperText: _isPhoneAccount
            ? 'هذا الرقم مرتبط بتسجيل الدخول ولا يمكن تغييره هنا'
            : 'يمكنك إضافة رقم هاتف للتواصل معك',
        suffixIcon: _isPhoneAccount
            ? const Icon(Icons.lock_outline)
            : null,
      ),
    ),

    const SizedBox(height: 16),

    // ========================================================
    // المنطقة
    // ========================================================

    TextField(
      controller: _areaController,
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        labelText: 'المنطقة',
        prefixIcon: Icon(Icons.location_on_outlined),
        border: OutlineInputBorder(),
      ),
    ),

    const SizedBox(height: 16),

    // ========================================================
    // البريد الإلكتروني
    // ========================================================

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
      ),
    ),

    const SizedBox(height: 24),

    // ========================================================
    // حفظ التغييرات
    // ========================================================

    FilledButton.icon(
      onPressed: _saving ? null : _saveProfile,
      icon: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            )
          : const Icon(Icons.save_outlined),
      label: Text(
        _saving ? 'جارٍ الحفظ...' : 'حفظ التغييرات',
      ),
    ),

    const SizedBox(height: 24),

    // ========================================================
    // إعلاناتي
    // ========================================================

    Card(
      child: ListTile(
        leading: const Icon(
          Icons.inventory_2_outlined,
        ),
        title: const Text('إعلاناتي'),
        subtitle: Text(
          'عدد الإعلانات: $_listingsCount',
        ),
        trailing: const Icon(
          Icons.chevron_left,
        ),
        onTap: _openMyListings,
      ),
    ),
  ],
);

}

// ============================================================
// بناء الصفحة
// ============================================================

@override
Widget build(BuildContext context) {
return Directionality(
textDirection: TextDirection.rtl,
child: Scaffold(
appBar: AppBar(
title: const Text('الملف الشخصي'),
),
body: _loading
? const Center(
child: CircularProgressIndicator(),
)
: _error != null
? Center(
child: Padding(
padding: const EdgeInsets.all(24),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Text(
_error!,
textAlign: TextAlign.center,
),
const SizedBox(height: 16),
FilledButton(
onPressed: _loadProfile,
child: const Text(
'إعادة المحاولة',
),
),
],
),
),
)
: _buildProfileForm(),
),
);
}
}