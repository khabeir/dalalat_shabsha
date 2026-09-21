import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ListingDetailsScreen extends StatefulWidget {
final int listingId;

const ListingDetailsScreen({
super.key,
required this.listingId,
});

@override
State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
final _supabase = Supabase.instance.client;

Map<String, dynamic>? _listing;
List<Map<String, dynamic>> _images = [];
int _currentImageIndex = 0;

bool _loading = true;
bool _favorite = false;
String? _error;

@override
void initState() {
super.initState();
_loadListing();
}

Future<void> _loadListing() async {
try {
final listing = await _supabase
.from('listings')
.select('''
id,
seller_id,
title,
description,
price,
currency,
price_type,
condition,
area,
contact_phone,
created_at
''')
.eq('id', widget.listingId)
.single();

  final images = await _supabase
      .from('listing_images')
      .select('id, image_path, sort_order')
      .eq('listing_id', widget.listingId)
      .order('sort_order');

  final user = _supabase.auth.currentUser;

  bool favorite = false;

  if (user != null) {
    final result = await _supabase
        .from('favorites')
        .select('listing_id')
        .eq('user_id', user.id)
        .eq('listing_id', widget.listingId);

    favorite = result.isNotEmpty;
  }

  if (!mounted) return;

  setState(() {
    _listing = Map<String, dynamic>.from(listing);
    _images = List<Map<String, dynamic>>.from(images);
    _favorite = favorite;
    _loading = false;
  });
} catch (e) {
  if (!mounted) return;

  setState(() {
    _error = 'تعذر تحميل تفاصيل الإعلان.';
    _loading = false;
  });
}

}

String _priceText() {
final price = _listing?['price'];
final currency = _listing?['currency'] ?? 'SDG';
final type = _listing?['price_type'];

if (type == 'contact' || price == null) {
  return 'السعر عند التواصل';
}

if (type == 'negotiable') {
  return '${price.toString()} $currency - قابل للتفاوض';
}

return '${price.toString()} $currency';

}

String _conditionText() {
switch (_listing?['condition']) {
case 'new':
return 'جديد';
case 'used':
return 'مستعمل';
default:
return 'غير محدد';
}
}

String _imageUrl(String path) {
final cleanPath = path.trim();

if (cleanPath.isEmpty) {
  return '';
}

if (cleanPath.startsWith('http://') ||
    cleanPath.startsWith('https://')) {
  return cleanPath;
}

return _supabase.storage
    .from('listing-images')
    .getPublicUrl(cleanPath);

}

Widget _buildImage(String path) {
final url = _imageUrl(path);

if (url.isEmpty) {
  return _buildImageError('مسار الصورة فارغ');
}

return ClipRRect(
  borderRadius: BorderRadius.circular(16),
  child: Container(
    width: double.infinity,
    height: double.infinity,
    color: Theme.of(context)
        .colorScheme
        .surfaceContainerHighest,
    child: Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (
        context,
        child,
        loadingProgress,
      ) {
        if (loadingProgress == null) {
          return child;
        }

        return const Center(
          child: CircularProgressIndicator(),
        );
      },
      errorBuilder: (
        context,
        error,
        stackTrace,
      ) {
        return _buildImageError(
          'تعذر تحميل الصورة',
        );
      },
    ),
  ),
);

}

Widget _buildImageError(String message) {
return Container(
width: double.infinity,
height: double.infinity,
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(16),
color: Theme.of(context)
.colorScheme
.surfaceContainerHighest,
),
child: Center(
child: Padding(
padding: const EdgeInsets.all(16),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
const Icon(
Icons.broken_image_outlined,
size: 60,
),
const SizedBox(height: 10),
Text(
message,
textAlign: TextAlign.center,
),
],
),
),
),
);
}

Future<void> _toggleFavorite() async {
final user = _supabase.auth.currentUser;

if (user == null) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('يجب تسجيل الدخول أولاً'),
    ),
  );
  return;
}

try {
  if (_favorite) {
    await _supabase
        .from('favorites')
        .delete()
        .eq('user_id', user.id)
        .eq('listing_id', widget.listingId);

    if (!mounted) return;

    setState(() => _favorite = false);
  } else {
    await _supabase.from('favorites').insert({
      'user_id': user.id,
      'listing_id': widget.listingId,
    });

    if (!mounted) return;

    setState(() => _favorite = true);
  }
} catch (e) {
  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('تعذر تحديث المفضلة'),
    ),
  );
}

}

Future<void> _callSeller() async {
  final phone = _listing?['contact_phone']?.toString().trim();

  if (phone == null || phone.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('رقم التواصل غير متوفر'),
      ),
    );
    return;
  }

  final uri = Uri(
    scheme: 'tel',
    path: phone,
  );

  try {
    final launched = await launchUrl(uri);

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح تطبيق الاتصال'),
        ),
      );
    }
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر فتح تطبيق الاتصال'),
      ),
    );
  }
}

Future<void> _openWhatsApp() async {
  final phone = _listing?['contact_phone']?.toString().trim();

  if (phone == null || phone.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('رقم التواصل غير متوفر'),
      ),
    );
    return;
  }

  var whatsappPhone = phone.replaceAll(RegExp(r'[^0-9+]'), '');

  if (whatsappPhone.startsWith('0')) {
    whatsappPhone = '249${whatsappPhone.substring(1)}';
  }

  whatsappPhone = whatsappPhone.replaceFirst('+', '');

  final uri = Uri.parse(
    'https://wa.me/$whatsappPhone',
  );

  try {
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح WhatsApp'),
        ),
      );
    }
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تعذر فتح WhatsApp'),
      ),
    );
  }
}

Future<void> _reportListing() async {
final user = _supabase.auth.currentUser;

if (user == null) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('يجب تسجيل الدخول أولاً'),
    ),
  );
  return;
}

final reasonController = TextEditingController();

final submit = await showDialog<bool>(
  context: context,
  builder: (context) {
    return AlertDialog(
      title: const Text('الإبلاغ عن الإعلان'),
      content: TextField(
        controller: reasonController,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'اكتب سبب الإبلاغ',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('إرسال'),
        ),
      ],
    );
  },
);

if (submit != true) {
  reasonController.dispose();
  return;
}

final reason = reasonController.text.trim();
reasonController.dispose();

if (reason.isEmpty) return;

try {
  await _supabase.from('reports').insert({
    'reporter_id': user.id,
    'listing_id': widget.listingId,
    'reason': reason,
  });

  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('تم إرسال البلاغ للمراجعة'),
    ),
  );
} catch (e) {
  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('تعذر إرسال البلاغ'),
    ),
  );
}

}

@override
Widget build(BuildContext context) {
return Directionality(
textDirection: TextDirection.rtl,
child: Scaffold(
appBar: AppBar(
title: const Text('تفاصيل الإعلان'),
actions: [
if (!_loading && _listing != null)
IconButton(
tooltip: 'المفضلة',
onPressed: _toggleFavorite,
icon: Icon(
_favorite
? Icons.favorite
: Icons.favorite_border,
),
),
if (!_loading && _listing != null)
IconButton(
tooltip: 'إبلاغ',
onPressed: _reportListing,
icon: const Icon(Icons.flag_outlined),
),
],
),
body: _buildBody(),
),
);
}

Widget _buildBody() {
if (_loading) {
return const Center(
child: CircularProgressIndicator(),
);
}

if (_error != null || _listing == null) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            size: 56,
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? 'الإعلان غير موجود',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loadListing,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );
}

final title = _listing!['title']?.toString() ?? '';

final description =
    _listing!['description']?.toString() ?? '';

final area = _listing!['area']?.toString() ?? '';

return ListView(
  padding: const EdgeInsets.all(16),
  children: [
    if (_images.isNotEmpty)
      Column(
        children: [
          SizedBox(
            height: 260,
            child: PageView.builder(
              itemCount: _images.length,
              onPageChanged: (index) {
                setState(() {
                  _currentImageIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final path =
                    _images[index]['image_path']?.toString() ?? '';

                return _buildImage(path);
              },
            ),
          ),

          if (_images.length > 1) ...[
            const SizedBox(height: 10),
            Text(
              '${_currentImageIndex + 1} / ${_images.length}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      )
    else
      Container(
        height: 220,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
        ),
        child: const Icon(
          Icons.image_outlined,
          size: 80,
        ),
      ),

    const SizedBox(height: 20),

    Text(
      title,
      style: const TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.bold,
      ),
    ),

    const SizedBox(height: 12),

    Text(
      _priceText(),
      style: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    ),

    const SizedBox(height: 18),

    if (area.isNotEmpty)
      _InfoRow(
        icon: Icons.location_on_outlined,
        title: 'المنطقة',
        value: area,
      ),

    _InfoRow(
      icon: Icons.inventory_2_outlined,
      title: 'الحالة',
      value: _conditionText(),
    ),

    const SizedBox(height: 20),

    const Text(
      'الوصف',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
      ),
    ),

    const SizedBox(height: 8),

    Text(
      description.isEmpty
          ? 'لا يوجد وصف لهذا الإعلان.'
          : description,
      style: const TextStyle(
        fontSize: 16,
        height: 1.6,
      ),
    ),

    const SizedBox(height: 28),

      Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _callSeller,
                icon: const Icon(Icons.phone),
                label: const Text(
                  'اتصال',
                  style: TextStyle(fontSize: 17),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _openWhatsApp,
                icon: const Icon(Icons.chat),
                label: const Text(
                  'WhatsApp',
                  style: TextStyle(fontSize: 17),
                ),
              ),
            ),
          ),
        ],
      ),

    const SizedBox(height: 12),

    OutlinedButton.icon(
      onPressed: _toggleFavorite,
      icon: Icon(
        _favorite
            ? Icons.favorite
            : Icons.favorite_border,
      ),
      label: Text(
        _favorite
            ? 'إزالة من المفضلة'
            : 'إضافة إلى المفضلة',
      ),
    ),

    const SizedBox(height: 12),

    TextButton.icon(
      onPressed: _reportListing,
      icon: const Icon(Icons.flag_outlined),
      label: const Text('الإبلاغ عن هذا الإعلان'),
    ),
  ],
);

}
}

class _InfoRow extends StatelessWidget {
final IconData icon;
final String title;
final String value;

const _InfoRow({
required this.icon,
required this.title,
required this.value,
});

@override
Widget build(BuildContext context) {
return Padding(
padding: const EdgeInsets.only(bottom: 10),
child: Row(
children: [
Icon(icon, size: 22),
const SizedBox(width: 8),
Text(
'$title: ',
style: const TextStyle(
fontWeight: FontWeight.bold,
),
),
Expanded(
child: Text(value),
),
],
),
);
}
}