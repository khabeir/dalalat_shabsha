import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'add_listing_screen.dart';
import 'admin_listings_screen.dart';
import 'auth_screen.dart';
import 'favorites_screen.dart';
import 'listing_details_screen.dart';
import 'my_listings_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
const HomeScreen({super.key});

@override
State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
final _supabase = Supabase.instance.client;
final _searchController = TextEditingController();

List<Map<String, dynamic>> _categories = [];
List<Map<String, dynamic>> _listings = [];

bool _loading = true;
bool _isAdmin = false;

String? _error;
String _searchQuery = '';
int? _selectedCategoryId;

@override
void initState() {
super.initState();
_loadData();
_checkAdminStatus();
}

@override
void dispose() {
_searchController.dispose();
super.dispose();
}

String _normalizeSearchText(String text) {
return text
.toLowerCase()
.replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
.replaceAll('أ', 'ا')
.replaceAll('إ', 'ا')
.replaceAll('آ', 'ا')
.replaceAll('ى', 'ي')
.replaceAll('ة', 'ه')
.replaceAll('ـ', '')
.replaceAll(RegExp(r'\s+'), ' ')
.trim();
}

List<Map<String, dynamic>> get _filteredListings {
final query = _normalizeSearchText(_searchQuery);

if (query.isEmpty) {
  return _listings;
}

return _listings.where((listing) {
  final title = _normalizeSearchText(
    listing['title']?.toString() ?? '',
  );

  final description = _normalizeSearchText(
    listing['description']?.toString() ?? '',
  );

  final area = _normalizeSearchText(
    listing['area']?.toString() ?? '',
  );

  return title.contains(query) ||
      description.contains(query) ||
      area.contains(query);
}).toList();

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
} catch (_) {
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

  // السوق العام يعرض الإعلانات المتاحة فقط.
  // sold و archived لا تظهر للعامة.
  var listingsQuery = _supabase
      .from('listings')
      .select(
        'id, title, description, price, currency, price_type, '
        'area, category_id, status, created_at',
      )
      .eq('status', 'approved');

  if (_selectedCategoryId != null) {
    listingsQuery = listingsQuery.eq(
      'category_id',
      _selectedCategoryId!,
    );
  }

  final listingsResponse = await listingsQuery.order(
    'created_at',
    ascending: false,
  );

  final listings = List<Map<String, dynamic>>.from(
    listingsResponse,
  );

  // جلب صور الإعلانات.
  if (listings.isNotEmpty) {
    final listingIds = listings
        .map((listing) => listing['id'])
        .where((id) => id != null)
        .toList();

    if (listingIds.isNotEmpty) {
      final imagesResponse = await _supabase
          .from('listing_images')
          .select(
            'listing_id, image_path, sort_order',
          )
          .inFilter(
            'listing_id',
            listingIds,
          )
          .order('sort_order');

      final images = List<Map<String, dynamic>>.from(
        imagesResponse,
      );

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
} catch (_) {
  if (!mounted) return;

  setState(() {
    _error =
        'تعذر تحميل البيانات. تحقق من اتصال الإنترنت وحاول مجدداً.';
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
} catch (_) {
  if (!mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'تعذر تسجيل الخروج، حاول مرة أخرى',
      ),
    ),
  );
}

}

Future<void> _openProfile() async {
final user = _supabase.auth.currentUser;

// الزائر: افتح تسجيل الدخول بدل فتح ProfileScreen.
if (user == null) {
  final loginResult = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => const AuthScreen(),
    ),
  );

  if (!mounted) return;

  // إذا تم تسجيل الدخول بنجاح، افتح الملف الشخصي مباشرة.
  if (loginResult == true &&
      _supabase.auth.currentUser != null) {
    await _checkAdminStatus();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ProfileScreen(),
      ),
    );

    if (!mounted) return;

    setState(() {});
  }

  return;
}

// المستخدم المسجل: افتح الملف الشخصي مباشرة.
await Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => const ProfileScreen(),
  ),
);

if (!mounted) return;

setState(() {});
await _checkAdminStatus();

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

await _loadData();
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

}

IconData _categoryIcon(String name) {
final value = name.trim();

switch (value) {
  case 'سيارات ومركبات':
    return Icons.directions_car_outlined;
  case 'عقارات':
    return Icons.home_work_outlined;
  case 'موبايلات وإلكترونيات':
    return Icons.phone_android_outlined;
  case 'أجهزة كهربائية':
    return Icons.electrical_services_outlined;
  case 'ملابس وأحذية':
    return Icons.checkroom_outlined;
  case 'أثاث ومستلزمات منزلية':
    return Icons.weekend_outlined;
  case 'مواشي وحيوانات':
    return Icons.pets_outlined;
  case 'محاصيل زراعية':
    return Icons.agriculture_outlined;
  case 'مواد غذائية':
    return Icons.restaurant_outlined;
  case 'أدوات ومعدات':
    return Icons.build_outlined;
  case 'خدمات':
    return Icons.handyman_outlined;
  case 'وظائف':
    return Icons.work_outline;
  case 'أخرى':
    return Icons.more_horiz_outlined;
  default:
    return Icons.category_outlined;
}

}

String _formatPrice(
Map<String, dynamic> listing,
) {
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

Widget _buildListingImage(
Map<String, dynamic> listing,
) {
final imageUrl = _imageUrl(
listing['image_path'],
);

Widget buildNoImage() {
  return Container(
    height: 145,
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.grey.shade100,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(12),
      ),
    ),
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 40,
            color: Colors.grey,
          ),
          SizedBox(height: 7),
          Text(
            'لا توجد صور',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

if (imageUrl == null) {
  return buildNoImage();
}

return ClipRRect(
  borderRadius: const BorderRadius.vertical(
    top: Radius.circular(12),
  ),
  child: Image.network(
    imageUrl,
    height: 145,
    width: double.infinity,
    fit: BoxFit.cover,
    errorBuilder: (
      context,
      error,
      stackTrace,
    ) {
      return buildNoImage();
    },
    loadingBuilder: (
      context,
      child,
      loadingProgress,
    ) {
      if (loadingProgress == null) {
        return child;
      }

      return Container(
        height: 145,
        width: double.infinity,
        color: Colors.grey.shade100,
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
          ),
        ),
      );
    },
  ),
);

}

Widget _buildAvailableBadge() {
return Container(
padding: const EdgeInsets.symmetric(
horizontal: 9,
vertical: 5,
),
decoration: BoxDecoration(
color: Colors.green.withValues(
alpha: 0.92,
),
borderRadius: BorderRadius.circular(20),
),
child: const Row(
mainAxisSize: MainAxisSize.min,
children: [
Icon(
Icons.check_circle,
color: Colors.white,
size: 15,
),
SizedBox(width: 4),
Text(
'متاح',
style: TextStyle(
color: Colors.white,
fontSize: 11.5,
fontWeight: FontWeight.bold,
),
),
],
),
);
}

Widget _buildListingCard(
Map<String, dynamic> listing,
) {
final title = listing['title']
?.toString()
.trim()
.isNotEmpty ==
true
? listing['title'].toString()
: 'إعلان بدون عنوان';

final area = listing['area']
        ?.toString()
        .trim() ??
    '';

final price = _formatPrice(listing);

return Card(
  margin: const EdgeInsets.only(
    bottom: 12,
  ),
  elevation: 1.5,
  shadowColor: Colors.black26,
  clipBehavior: Clip.antiAlias,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  ),
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
        Stack(
          children: [
            _buildListingImage(listing),
            Positioned(
              top: 9,
              right: 9,
              child: _buildAvailableBadge(),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            11,
            9,
            11,
            10,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  const Icon(
                    Icons.sell_outlined,
                    size: 17,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      price,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              if (area.isNotEmpty) ...[
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        area,
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color:
                              Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    final listingId =
                        listing['id'];

                    if (listingId is int) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ListingDetailsScreen(
                            listingId:
                                listingId,
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    size: 13,
                  ),
                  label: const Text(
                    'عرض الإعلان',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize:
                        const Size.fromHeight(36),
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 8,
                    ),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(9),
                    ),
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
            child: const Text(
              'إعادة المحاولة',
            ),
          ),
        ],
      ),
    ),
  );
}

return RefreshIndicator(
  onRefresh: _loadData,
  child: ListView(
    physics:
        const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(
      16,
      8,
      16,
      24,
    ),
    children: [
      TextField(
        controller: _searchController,
        textInputAction:
            TextInputAction.search,
        decoration: InputDecoration(
          hintText:
              'ابحث عن إعلان أو منطقة...',
          prefixIcon: const Icon(
            Icons.search,
          ),
          suffixIcon:
              _searchQuery.isNotEmpty
                  ? IconButton(
                      onPressed: () {
                        _searchController
                            .clear();

                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(
                        Icons.clear,
                      ),
                      tooltip: 'مسح البحث',
                    )
                  : null,
          filled: true,
          border: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
      const SizedBox(height: 18),
      Row(
        children: [
          const Expanded(
            child: Text(
              'الأقسام',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _selectedCategoryId = null;
              });

              _loadData();
            },
            child: const Text(
              'عرض الكل',
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      if (_categories.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(
            vertical: 16,
          ),
          child: Text(
            'لا توجد أقسام متاحة حالياً',
            textAlign: TextAlign.center,
          ),
        )
      else
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            separatorBuilder: (_, __) {
              return const SizedBox(
                width: 10,
              );
            },
            itemBuilder: (
              context,
              index,
            ) {
              final category =
                  _categories[index];

              final categoryId =
                  category['id'] as int?;

              final categoryName =
                  category['name']
                          ?.toString() ??
                      'بدون اسم';

              final selected =
                  _selectedCategoryId ==
                      categoryId;

              return GestureDetector(
                onTap: () {
                  if (categoryId == null) {
                    return;
                  }

                  setState(() {
                    _selectedCategoryId =
                        categoryId;
                  });

                  _loadData();
                },
                child: Container(
                  width: 92,
                  padding:
                      const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context)
                            .colorScheme
                            .primaryContainer
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                    borderRadius:
                        BorderRadius.circular(
                      16,
                    ),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                          : Colors.transparent,
                      width: 1.2,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment:
                        MainAxisAlignment.center,
                    children: [
                      Icon(
                        _categoryIcon(
                          categoryName,
                        ),
                        size: 30,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        categoryName,
                        textAlign:
                            TextAlign.center,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      const SizedBox(height: 26),
      if (_searchQuery.isNotEmpty ||
          _selectedCategoryId != null) ...[
        Row(
          children: [
            const Expanded(
              child: Text(
                'النتائج',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '${_filteredListings.length} إعلان',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_filteredListings.isEmpty)
          Padding(
            padding:
                const EdgeInsets.symmetric(
              vertical: 32,
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.search_off_outlined,
                  size: 56,
                ),
                const SizedBox(height: 12),
                Text(
                  _searchQuery.isEmpty
                      ? 'لا توجد إعلانات في هذا القسم'
                      : 'لم نجد إعلانات تطابق بحثك',
                  textAlign:
                      TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          )
        else
          ..._filteredListings.map(
            _buildListingCard,
          ),
      ] else ...[
        if (_listings.isEmpty)
          Padding(
            padding:
                const EdgeInsets.symmetric(
              vertical: 32,
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.inventory_2_outlined,
                  size: 56,
                ),
                const SizedBox(height: 12),
                const Text(
                  'لا توجد إعلانات متاحة حالياً',
                  textAlign:
                      TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          )
        else ...[
          const Text(
            'أحدث الإعلانات',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 285,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _listings.length,
              separatorBuilder: (_, __) {
                return const SizedBox(
                  width: 10,
                );
              },
              itemBuilder: (
                context,
                index,
              ) {
                return SizedBox(
                  width: 210,
                  child: _buildListingCard(
                    _listings[index],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 28),
          ..._categories.map(
            (category) {
              final categoryId =
                  category['id'] as int?;

              final categoryName =
                  category['name']
                          ?.toString() ??
                      'بدون اسم';

              if (categoryId == null) {
                return const SizedBox.shrink();
              }

              final categoryListings =
                  _listings.where(
                (listing) {
                  return listing[
                          'category_id'] ==
                      categoryId;
                },
              ).toList();

              if (categoryListings.isEmpty) {
                return const SizedBox.shrink();
              }

              return Padding(
                padding:
                    const EdgeInsets.only(
                  bottom: 28,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _categoryIcon(
                            categoryName,
                          ),
                          size: 22,
                        ),
                        const SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: Text(
                            categoryName,
                            style:
                                const TextStyle(
                              fontSize: 19,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedCategoryId =
                                  categoryId;
                            });

                            _loadData();
                          },
                          child: const Text(
                            'عرض الكل',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 285,
                      child: ListView
                          .separated(
                        scrollDirection:
                            Axis.horizontal,
                        itemCount:
                            categoryListings
                                .length,
                        separatorBuilder:
                            (_, __) {
                          return const SizedBox(
                            width: 10,
                          );
                        },
                        itemBuilder: (
                          context,
                          index,
                        ) {
                          return SizedBox(
                            width: 210,
                            child:
                                _buildListingCard(
                              categoryListings[
                                  index],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    ],
  ),
);

}

Widget _buildProfileButton() {
final user = _supabase.auth.currentUser;

return IconButton(
  tooltip: user == null
      ? 'تسجيل الدخول'
      : 'الملف الشخصي',
  icon: CircleAvatar(
    radius: 17,
    backgroundColor:
        Theme.of(context)
            .colorScheme
            .primaryContainer,
    child: Icon(
      user == null
          ? Icons.person_outline
          : Icons.person,
      size: 21,
      color: Theme.of(context)
          .colorScheme
          .onPrimaryContainer,
    ),
  ),
  onPressed: _openProfile,
);

}

Widget _buildPostListingButton() {
return FilledButton.icon(
onPressed: _openAddListing,
icon: const Icon(
Icons.add_circle_outline,
size: 20,
),
label: const Text(
'ضع إعلانك',
style: TextStyle(
fontSize: 14,
fontWeight: FontWeight.bold,
),
),
style: FilledButton.styleFrom(
minimumSize: const Size(0, 42),
padding: const EdgeInsets.symmetric(
horizontal: 14,
),
shape: RoundedRectangleBorder(
borderRadius:
BorderRadius.circular(12),
),
),
);
}

@override
Widget build(BuildContext context) {
final user =
_supabase.auth.currentUser;

final name =
    user?.userMetadata?['full_name']
        as String?;

return Directionality(
  textDirection: TextDirection.rtl,
  child: Scaffold(
    drawer: Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primary,
              ),
              accountName: Text(
                name == null || name.isEmpty
                    ? 'مرحباً بك في دلالة شبشة'
                    : name,
              ),
              accountEmail: user == null
                  ? null
                  : Text(
                      user.email ?? '',
                    ),
              currentAccountPicture:
                  CircleAvatar(
                backgroundColor:
                    Theme.of(context)
                        .colorScheme
                        .onPrimary,
                child: Icon(
                  Icons.storefront_rounded,
                  size: 32,
                  color: Theme.of(context)
                      .colorScheme
                      .primary,
                ),
              ),
            ),

            ListTile(
              leading: const Icon(
                Icons.person_outline,
              ),
              title: Text(
                user == null
                    ? 'تسجيل الدخول'
                    : 'الملف الشخصي',
              ),
              subtitle: user == null
                  ? const Text(
                      'سجّل الدخول للوصول إلى ملفك',
                    )
                  : null,
              onTap: () async {
                Navigator.pop(context);
                await _openProfile();
              },
            ),

            const Divider(),

            const Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                8,
              ),
              child: Text(
                'الأقسام',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            if (_categories.isEmpty)
              const Padding(
                padding:
                    EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'لا توجد أقسام حالياً',
                  style: TextStyle(
                    color: Colors.grey,
                  ),
                ),
              )
            else
              ..._categories.map(
                (category) {
                  final categoryId =
                      category['id'] as int?;

                  final categoryName =
                      category['name']
                              ?.toString() ??
                          'بدون اسم';

                  return ListTile(
                    leading: Icon(
                      _categoryIcon(
                        categoryName,
                      ),
                    ),
                    title: Text(
                      categoryName,
                    ),
                    selected:
                        _selectedCategoryId ==
                            categoryId,
                    onTap: () {
                      Navigator.pop(context);

                      if (categoryId == null) {
                        return;
                      }

                      setState(() {
                        _selectedCategoryId =
                            categoryId;
                      });

                      _loadData();
                    },
                  );
                },
              ),

            const Divider(),

            ListTile(
              leading: const Icon(
                Icons.favorite_border,
              ),
              title: const Text(
                'المفضلة',
              ),
              onTap: () {
                Navigator.pop(context);

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const FavoritesScreen(),
                  ),
                );
              },
            ),

            if (user != null)
              ListTile(
                leading: const Icon(
                  Icons.inventory_2_outlined,
                ),
                title: const Text(
                  'إعلاناتي',
                ),
                onTap: () {
                  Navigator.pop(context);

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const MyListingsScreen(),
                    ),
                  );
                },
              ),

            if (user != null)
              ListTile(
                leading: const Icon(
                  Icons.logout,
                ),
                title: const Text(
                  'تسجيل الخروج',
                ),
                onTap: () {
                  Navigator.pop(context);
                  _signOut();
                },
              ),
          ],
        ),
      ),
    ),

    appBar: AppBar(
      centerTitle: false,
      elevation: 0,
      titleSpacing: 12,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer,
              borderRadius:
                  BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.storefront_rounded,
              size: 24,
              color: Theme.of(context)
                  .colorScheme
                  .onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 9),
          const Flexible(
            child: Text(
              'دلالة شبشة',
              overflow:
                  TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (_isAdmin)
          IconButton(
            tooltip: 'لوحة تحكم الأدمن',
            icon: const Icon(
              Icons.admin_panel_settings_outlined,
            ),
            onPressed: _openAdminPanel,
          ),

        _buildProfileButton(),

        _buildPostListingButton(),

        IconButton(
          tooltip: 'تحديث',
          onPressed: () {
            _loadData();
            _checkAdminStatus();
          },
          icon: const Icon(
            Icons.refresh,
          ),
        ),
      ],
    ),

    body: Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            18,
            16,
            10,
          ),
          child: Column(
            children: [
              Text(
                name == null || name.isEmpty
                    ? 'مرحباً بك في دلالة شبشة 👋'
                    : 'مرحباً يا $name 👋',
                textAlign:
                    TextAlign.center,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'تسوّق أو أعلن معنا',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'دلالة شبشة — بيع وشراء بدون وسيط',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context)
                      .colorScheme
                      .primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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