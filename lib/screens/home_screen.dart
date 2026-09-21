import 'my_listings_screen.dart';
import 'profile_screen.dart';
import 'favorites_screen.dart';
import 'auth_screen.dart';
import 'admin_listings_screen.dart';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_details_screen.dart';
import 'add_listing_screen.dart';

class HomeScreen extends StatefulWidget {
const HomeScreen({super.key});

@override
State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
final _supabase = Supabase.instance.client;

List<Map<String, dynamic>> _categories = [];
List<Map<String, dynamic>> _listings = [];

bool _loading = true;
bool _isAdmin = false;

String? _error;
int? _selectedCategoryId;

@override
void initState() {
super.initState();
_loadData();
_checkAdminStatus();
}

Future<void> _checkAdminStatus() async {
try {
final user = _supabase.auth.currentUser;

  if (user == null) {
    if (!mounted) return;

    setState(() {
      _isAdmin = false;
    });

    return;
  }

  final profile = await _supabase
      .from('profiles')
      .select('role')
      .eq('id', user.id)
      .maybeSingle();

  if (!mounted) return;

  setState(() {
    _isAdmin = profile?['role'] == 'admin';
  });
} catch (e) {
  if (!mounted) return;

  setState(() {
    _isAdmin = false;
  });
}

}

Future<void> _loadData() async {
if (mounted) {
setState(() {
_loading = true;
_error = null;
});
}

try {
  final categoriesResponse = await _supabase
      .from('categories')
      .select('id, name, icon')
      .eq('is_active', true)
      .order('sort_order');

  var listingsQuery = _supabase
      .from('listings')
      .select(
        'id, title, description, price, currency, price_type, area, created_at',
      )
      .eq('status', 'approved');

  if (_selectedCategoryId != null) {
    listingsQuery =
        listingsQuery.eq('category_id', _selectedCategoryId!);
  }

  final listingsResponse =
      await listingsQuery.order('created_at', ascending: false);

  final listings =
      List<Map<String, dynamic>>.from(listingsResponse);

  // جلب صور الإعلانات الموجودة في القائمة.
  if (listings.isNotEmpty) {
    final listingIds = listings
        .map((listing) => listing['id'])
        .where((id) => id != null)
        .toList();

    if (listingIds.isNotEmpty) {
      final imagesResponse = await _supabase
          .from('listing_images')
          .select('listing_id, image_path, sort_order')
          .inFilter('listing_id', listingIds)
          .order('sort_order');

      final images =
          List<Map<String, dynamic>>.from(imagesResponse);

      // ربط أول صورة بكل إعلان.
      for (final listing in listings) {
        final listingId = listing['id'];

        for (final image in images) {
          if (image['listing_id'] == listingId) {
            listing['image_path'] = image['image_path'];
            break;
          }
        }
      }
    }
  }

  if (!mounted) return;

  setState(() {
    _categories = List<Map<String, dynamic>>.from(
      categoriesResponse,
    );
    _listings = listings;
    _loading = false;
  });
} catch (e) {
  if (!mounted) return;

  setState(() {
    _error = 'تعذر تحميل البيانات. تحقق من اتصال الإنترنت وحاول مجدداً.';
    _loading = false;
  });
}

}

Future<void> _signOut() async {
try {
await _supabase.auth.signOut();

  if (!mounted) return;

  setState(() {
    _isAdmin = false;
  });

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('تم تسجيل الخروج بنجاح'),
    ),
  );
} catch (e) {
  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('تعذر تسجيل الخروج، حاول مرة أخرى'),
    ),
  );
}

}

Future<void> _openAddListing() async {
final user = _supabase.auth.currentUser;

if (user == null) {
  final loginResult = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => const AuthScreen(),
    ),
  );

  if (!mounted) return;

  if (loginResult != true ||
      _supabase.auth.currentUser == null) {
    return;
  }

  await _checkAdminStatus();

  if (!mounted) return;
}

await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => const AddListingScreen(),
  ),
);

if (!mounted) return;

_loadData();

}

Future<void> _openAdminPanel() async {
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const AdminListingsScreen(),
    ),
  );

  if (!mounted) return;

  await _checkAdminStatus();
  await _loadData();
}

String _formatPrice(Map<String, dynamic> listing) {
final price = listing['price'];
final currency = listing['currency'] ?? 'SDG';
final priceType = listing['price_type'];

if (priceType == 'contact' || price == null) {
  return 'السعر عند التواصل';
}

final priceText = price.toString();

if (priceType == 'negotiable') {
  return '$priceText $currency قابل للتفاوض';
}

return '$priceText $currency';

}

String? _imageUrl(dynamic imagePath) {
if (imagePath == null) {
return null;
}

final path = imagePath.toString().trim();

if (path.isEmpty) {
  return null;
}

if (path.startsWith('http://') ||
    path.startsWith('https://')) {
  return path;
}

return _supabase.storage
    .from('listing-images')
    .getPublicUrl(path);

}

Widget _buildListingImage(Map<String, dynamic> listing) {
  final imageUrl = _imageUrl(listing['image_path']);

  if (imageUrl == null) {
    return Container(
      height: 200,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(12),
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          size: 70,
          color: Colors.grey,
        ),
      ),
    );
  }

  return ClipRRect(
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(12),
    ),
    child: Image.network(
      imageUrl,
      height: 200,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          height: 200,
          width: double.infinity,
          color: Colors.grey.shade200,
          child: const Center(
            child: Icon(
              Icons.image_outlined,
              size: 70,
              color: Colors.grey,
            ),
          ),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }

        return Container(
          height: 200,
          width: double.infinity,
          color: Colors.grey.shade200,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    ),
  );
}

Widget _buildCategoryItem(Map<String, dynamic> category) {
final id = category['id'] as int;
final selected = _selectedCategoryId == id;
final icon = category['icon'] as String?;
final name = category['name'] as String? ?? '';

return Padding(
  padding: const EdgeInsetsDirectional.only(end: 8),
  child: ChoiceChip(
    selected: selected,
    label: Text('${icon ?? '📦'} $name'),
    onSelected: (_) {
      setState(() {
        _selectedCategoryId = selected ? null : id;
      });
      _loadData();
    },
  ),
);

}

Widget _buildListingCard(Map<String, dynamic> listing) {
return Card(
margin: const EdgeInsets.only(bottom: 12),
clipBehavior: Clip.antiAlias,
child: InkWell(
onTap: () {
final listingId = listing['id'];

      if (listingId is int) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ListingDetailsScreen(
              listingId: listingId,
            ),
          ),
        );
      }
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildListingImage(listing),

        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                listing['title']?.toString() ??
                    'إعلان بدون عنوان',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                _formatPrice(listing),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),

              if ((listing['area'] ?? '')
                  .toString()
                  .isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        listing['area'].toString(),
                      ),
                    ),
                  ],
                ),
              ],

              if ((listing['description'] ?? '')
                  .toString()
                  .isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  listing['description'].toString(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  ),
);

}

Widget _buildBody() {
if (_loading) {
return const Center(
child: CircularProgressIndicator(),
);
}

if (_error != null) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.wifi_off,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _loadData,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );
}

return RefreshIndicator(
  onRefresh: _loadData,
  child: ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'التصنيفات',
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.bold,
        ),
      ),

      const SizedBox(height: 12),

      if (_categories.isEmpty)
        const Text('لا توجد تصنيفات متاحة حالياً')
      else
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              Padding(
                padding:
                    const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  selected: _selectedCategoryId == null,
                  label: const Text('الكل'),
                  onSelected: (_) {
                    setState(
                      () => _selectedCategoryId = null,
                    );
                    _loadData();
                  },
                ),
              ),
              ..._categories.map(_buildCategoryItem),
            ],
          ),
        ),

      const SizedBox(height: 24),

      const Text(
        'أحدث الإعلانات',
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.bold,
        ),
      ),

      const SizedBox(height: 12),

      if (_listings.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              Icon(
                Icons.storefront_outlined,
                size: 56,
              ),
              SizedBox(height: 12),
              Text(
                'لا توجد إعلانات معتمدة حالياً',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        )
      else
        ..._listings.map(_buildListingCard),
    ],
  ),
);

}

@override
Widget build(BuildContext context) {
final user = _supabase.auth.currentUser;
final name =
user?.userMetadata?['full_name'] as String?;

return Directionality(
  textDirection: TextDirection.rtl,
  child: Scaffold(
    appBar: AppBar(
      title: const Text('دلالة شبشة'),
      actions: [
          if (_isAdmin)
            IconButton(
              tooltip: 'لوحة تحكم الأدمن',
              icon: const Icon(
                Icons.admin_panel_settings_outlined,
              ),
              onPressed: _openAdminPanel,
            ),
            
        IconButton(
          tooltip: 'الملف الشخصي',
          icon: const Icon(Icons.person_outline),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ProfileScreen(),
              ),
            );
          },
        ),

        IconButton(
          tooltip: 'المفضلة',
          icon: const Icon(Icons.favorite_border),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const FavoritesScreen(),
              ),
            );
          },
        ),

        IconButton(
          tooltip: 'إضافة إعلان',
          onPressed: _openAddListing,
          icon: const Icon(
            Icons.add_circle_outline,
          ),
        ),

        IconButton(
          tooltip: 'تحديث',
          onPressed: () {
            _loadData();
            _checkAdminStatus();
          },
          icon: const Icon(Icons.refresh),
        ),

        if (user != null)
          IconButton(
            tooltip: 'إعلاناتي',
            icon: const Icon(
              Icons.inventory_2_outlined,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const MyListingsScreen(),
                ),
              );
            },
          ),

        if (user != null)
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
      ],
    ),

    body: Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding:
              const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            name == null || name.isEmpty
                ? 'مرحباً بك في سوق شبشة'
                : 'مرحباً يا $name',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        Expanded(
          child: _buildBody(),
        ),
      ],
    ),
  ),
);

}
}