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

  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _listings = [];

  bool _loading = true;
  bool _isAdmin = false;

  String? _error;
  String _searchQuery = '';
  String? _selectedCategoryId;

  @override
  void initState() {
    super.initState();
    _loadData();
    _checkAdminStatus();
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
    var result = List<Map<String, dynamic>>.from(_listings);

    if (_selectedCategoryId != null) {
      result = result.where((listing) {
        return listing['category_id']?.toString() ==
            _selectedCategoryId;
      }).toList();
    }

    final query = _normalizeSearchText(_searchQuery);

    if (query.isNotEmpty) {
      result = result.where((listing) {
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

    return result;
  }

  Future<void> _checkAdminStatus() async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        setState(() {
          _isAdmin = false;
        });
      }
      return;
    }

    try {
      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _isAdmin = profile?['role']?.toString() == 'admin';
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
          .select()
          .eq('is_active', true)
          .order('name');

      var query = _supabase
          .from('listings')
          .select()
          .eq('status', 'approved');

      if (_selectedCategoryId != null) {
        query = query.eq(
          'category_id',
          _selectedCategoryId!,
        );
      }

      final listingsResponse = await query
          .order('created_at', ascending: false);

      final listings = List<Map<String, dynamic>>.from(
        listingsResponse,
      );

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

          for (final listing in listings) {
            final listingId = listing['id'];

            final listingImages = images.where(
              (image) =>
                  image['listing_id']?.toString() ==
                  listingId?.toString(),
            );

            if (listingImages.isNotEmpty) {
              listing['image_path'] =
                  listingImages.first['image_path'];
            }
          }
        }
      }

      if (!mounted) return;

      setState(() {
        _categories =
            List<Map<String, dynamic>>.from(
          categoriesResponse,
        );
        _listings = listings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  String? _imageUrl(dynamic path) {
    if (path == null) return null;

    final value = path.toString().trim();

    if (value.isEmpty) return null;

    if (value.startsWith('http://') ||
        value.startsWith('https://')) {
      return value;
    }

    return _supabase.storage
        .from('listing-images')
        .getPublicUrl(value);
  }

  Widget _buildListingImage(
    Map<String, dynamic> listing, {
    required double height,
  }) {
    final url = _imageUrl(listing['image_path']);

    if (url == null) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
        ),
        child: Icon(
          Icons.image_outlined,
          size: 38,
          color: Theme.of(context)
              .colorScheme
              .onSurfaceVariant,
        ),
      );
    }

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        loadingBuilder: (
          context,
          child,
          loadingProgress,
        ) {
          if (loadingProgress == null) {
            return child;
          }

          return Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                value: loadingProgress
                            .expectedTotalBytes !=
                        null
                    ? loadingProgress
                            .cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (
          context,
          error,
          stackTrace,
        ) {
          return Container(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
            child: Icon(
              Icons.broken_image_outlined,
              size: 38,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
            ),
          );
        },
      ),
    );
  }

  Widget _buildAvailableBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: Colors.green.shade700,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            blurRadius: 4,
            offset: Offset(0, 1),
            color: Colors.black26,
          ),
        ],
      ),
      child: const Text(
        'متاح',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatPrice(Map<String, dynamic> listing) {
    final priceType =
        listing['price_type']?.toString();

    if (priceType == 'negotiable') {
      return 'قابل للتفاوض';
    }

    final price = listing['price'];

    if (price == null ||
        price.toString().trim().isEmpty) {
      return 'السعر عند التواصل';
    }

    final priceNumber = num.tryParse(
      price.toString(),
    );

    if (priceNumber == null) {
      return price.toString();
    }

    final formatted =
        priceNumber.toStringAsFixed(0);

    final withCommas = formatted.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );

    return '$withCommas ج.س';
  }

  void _openListingDetails(Map<String, dynamic> listing) {
    final listingId = listing[id]?.toString();

    if (listingId == null || listingId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر فتح الإعلان'),
        ),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListingDetailsScreen(
          listingId: listingId,
        ),
      ),
    );
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ListingDetailsScreen(
        listingId: listingId,
      ),
    ),
  );
}

  Widget _buildListingCard(
    Map<String, dynamic> listing,
  ) {
    final rawTitle =
        listing['title']?.toString().trim() ?? '';

    final title = rawTitle.isEmpty
        ? 'إعلان بدون عنوان'
        : rawTitle;

    final area =
        listing['area']?.toString().trim() ?? '';

    final priceText = _formatPrice(listing);

    final isNegotiable =
        listing['price_type'] == 'negotiable';

    return Card(
      margin: EdgeInsets.zero,
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(13),
        side: BorderSide(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        onTap: () => _openListingDetails(listing),
        child: SizedBox(
          width: 158,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  _buildListingImage(
                    listing,
                    height: 105,
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: _buildAvailableBadge(),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    8,
                    7,
                    8,
                    3,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          height: 1.18,
                        ),
                      ),

                      const SizedBox(height: 3),

                      // السعر بشكل أوضح
                      Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(7),
                        ),
                        child: Text(
                          priceText,
                          maxLines: 2,
                          overflow:
                              TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                FontWeight.w800,
                            height: 1.1,
                            color: Theme.of(context)
                                .colorScheme
                                .primary,
                          ),
                        ),
                      ),

                      if (isNegotiable)
                        Padding(
                          padding:
                              const EdgeInsets.only(
                            top: 2,
                          ),
                          child: Text(
                            'قابل للتفاوض',
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight:
                                  FontWeight.w600,
                              color:
                                  Colors.grey.shade600,
                            ),
                          ),
                        ),

                      if (area.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color:
                                  Colors.grey.shade600,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                area,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors
                                      .grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const Spacer(),

                      SizedBox(
                        width: double.infinity,
                        height: 28,
                        child: OutlinedButton(
                          onPressed: () =>
                              _openListingDetails(
                            listing,
                          ),
                          style:
                              OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            visualDensity:
                                VisualDensity.compact,
                            minimumSize:
                                const Size(0, 28),
                            tapTargetSize:
                                MaterialTapTargetSize
                                    .shrinkWrap,
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(
                                    alpha: 0.65,
                                  ),
                            ),
                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(
                                8,
                              ),
                            ),
                          ),
                          child: Text(
                            'عرض الإعلان',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight:
                                  FontWeight.w600,
                              color:
                                  Theme.of(context)
                                      .colorScheme
                                      .primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalListings(
    List<Map<String, dynamic>> listings,
  ) {
    if (listings.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: 2,
        ),
        itemCount: listings.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return _buildListingCard(
            listings[index],
          );
        },
      ),
    );
  }

  Widget _buildCategories() {
    if (_categories.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 70,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: 2,
        ),
        itemCount: _categories.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _categories[index];

          final id =
              category['id']?.toString();

          final name =
              category['name']?.toString() ?? '';

          final selected =
              _selectedCategoryId == id;

          return SizedBox(
            width: 76,
            child: InkWell(
              borderRadius:
                  BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  _selectedCategoryId =
                      selected ? null : id;
                });
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                      : Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                  borderRadius:
                      BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                        : Theme.of(context)
                            .colorScheme
                            .outlineVariant,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow:
                      TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        FontWeight.w600,
                    color: selected
                        ? Theme.of(context)
                            .colorScheme
                            .onPrimary
                        : Theme.of(context)
                            .colorScheme
                            .onSurface,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSearchField() {
    return SizedBox(
      height: 43,
      child: TextField(
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        decoration: InputDecoration(
          hintText: 'ابحث عن إعلان...',
          prefixIcon:
              const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  icon: const Icon(
                    Icons.clear,
                  ),
                )
              : null,
          filled: true,
          fillColor: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest,
          contentPadding:
              const EdgeInsets.symmetric(
            horizontal: 12,
          ),
          border: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final results = _filteredListings;

    if (_searchQuery.trim().isEmpty &&
        _selectedCategoryId == null) {
      return const SizedBox.shrink();
    }

    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text(
            'لا توجد إعلانات مطابقة',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: results.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return _buildListingCard(
            results[index],
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(
    String title,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 8,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildHomeSections() {
    final filtered = _filteredListings;

    if (_searchQuery.trim().isNotEmpty ||
        _selectedCategoryId != null) {
      return _buildSearchResults();
    }

    final featuredPreview =
        _listings.take(5).toList();

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.stretch,
      children: [
        if (featuredPreview.isNotEmpty) ...[
          _buildSectionTitle(
            'إعلانات مميزة أو تجارية',
          ),
          _buildHorizontalListings(
            featuredPreview,
          ),
          const SizedBox(height: 18),
        ],

        if (_listings.isNotEmpty) ...[
          _buildSectionTitle(
            'أحدث الإعلانات',
          ),
          _buildHorizontalListings(
            _listings,
          ),
          const SizedBox(height: 18),
        ],

        if (filtered.isNotEmpty) ...[
          _buildSectionTitle(
            'معروضات الأقسام',
          ),
          _buildHorizontalListings(
            filtered,
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 140),
            Center(
              child: Padding(
                padding:
                    const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 45,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'حدث خطأ أثناء تحميل الإعلانات',
                      textAlign:
                          TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _loadData,
                      child:
                          const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
          12,
          16,
          20,
        ),
        children: [
          Text(
            'في مكان واحد - تسوق واعلن بسهولة',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Theme.of(context)
                  .colorScheme
                  .primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _supabase.auth.currentUser != null
                ? 'مرحباً بك 👋'
                : 'مرحباً بك في دلالة شبشة 👋',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 14),
          _buildSearchField(),
          const SizedBox(height: 12),
          _buildCategories(),
          const SizedBox(height: 16),
          _buildHomeSections(),
        ],
      ),
    );
  }

  Widget _buildPostListingButton() {
    return TextButton.icon(
      onPressed: () async {
        final user =
            _supabase.auth.currentUser;

        if (user == null) {
          final result =
              await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  const AuthScreen(),
            ),
          );

          if (result == true && mounted) {
            await _loadData();
          }

          return;
        }

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                const AddListingScreen(),
          ),
        );

        if (mounted) {
          await _loadData();
        }
      },
      icon: const Icon(Icons.add, size: 18),
      label: const Text(
        'ضع إعلانك',
        style: TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildProfileButton() {
    return IconButton(
      tooltip: 'الملف الشخصي',
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                const ProfileScreen(),
          ),
        );

        if (mounted) {
          await _checkAdminStatus();
        }
      },
      icon: const Icon(
        Icons.person_outline,
      ),
    );
  }

  Widget _buildBottomNavigation() {
    final primary = Theme.of(context)
        .colorScheme
        .primary;

    return SafeArea(
      top: false,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context)
                  .colorScheme
                  .outlineVariant,
            ),
          ),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Expanded(
              child: _bottomItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: 'الرئيسية',
                selected: true,
                onTap: () {},
              ),
            ),
            Expanded(
              child: _bottomItem(
                icon: Icons.list_alt_outlined,
                activeIcon: Icons.list_alt,
                label: 'إعلاناتي',
                onTap: () async {
                  final user =
                      _supabase.auth.currentUser;

                  if (user == null) {
                    final result =
                        await Navigator.of(context)
                            .push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const AuthScreen(),
                      ),
                    );

                    if (result == true &&
                        mounted) {
                      await _loadData();
                    }

                    return;
                  }

                  await Navigator.of(context)
                      .push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const MyListingsScreen(),
                    ),
                  );

                  if (mounted) {
                    await _loadData();
                  }
                },
              ),
            ),
            Expanded(
              child: Center(
                child: Material(
                  color: primary,
                  elevation: 3,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder:
                        const CircleBorder(),
                    onTap: () async {
                      final user =
                          _supabase.auth.currentUser;

                      if (user == null) {
                        final result =
                            await Navigator.of(context)
                                .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const AuthScreen(),
                          ),
                        );

                        if (result == true &&
                            mounted) {
                          await _loadData();
                        }

                        return;
                      }

                      await Navigator.of(context)
                          .push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const AddListingScreen(),
                        ),
                      );

                      if (mounted) {
                        await _loadData();
                      }
                    },
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _bottomItem(
                icon: Icons.favorite_border,
                activeIcon: Icons.favorite,
                label: 'المفضلة',
                onTap: () async {
                  await Navigator.of(context)
                      .push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const FavoritesScreen(),
                    ),
                  );

                  if (mounted) {
                    await _loadData();
                  }
                },
              ),
            ),
            Expanded(
              child: _bottomItem(
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: 'الملف الشخصي',
                onTap: () async {
                  await Navigator.of(context)
                      .push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const ProfileScreen(),
                    ),
                  );

                  if (mounted) {
                    await _checkAdminStatus();
                    await _loadData();
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    bool selected = false,
    required VoidCallback onTap,
  }) {
    final color = selected
        ? Theme.of(context)
            .colorScheme
            .primary
        : Colors.grey.shade600;

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: [
          Icon(
            selected ? activeIcon : icon,
            size: 23,
            color: color,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          titleSpacing: 0,
          title: const Text(
            'دلالة شبشة',
            style: TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading
                  ? null
                  : _loadData,
              icon: const Icon(
                Icons.refresh,
              ),
            ),
            _buildPostListingButton(),
            _buildProfileButton(),
          ],
        ),
        drawer: Drawer(
          child: SafeArea(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                DrawerHeader(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    mainAxisAlignment:
                        MainAxisAlignment.end,
                    children: const [
                      Text(
                        'دلالة شبشة',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'في مكان واحد - تسوق واعلن بسهولة',
                      ),
                    ],
                  ),
                ),
                ListTile(
                  leading:
                      const Icon(Icons.home_outlined),
                  title:
                      const Text('الرئيسية'),
                  onTap: () {
                    Navigator.pop(context);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.list_alt_outlined,
                  ),
                  title:
                      const Text('إعلاناتي'),
                  onTap: () async {
                    Navigator.pop(context);

                    final user =
                        _supabase.auth.currentUser;

                    if (user == null) {
                      await Navigator.of(context)
                          .push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const AuthScreen(),
                        ),
                      );
                    } else {
                      await Navigator.of(context)
                          .push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const MyListingsScreen(),
                        ),
                      );
                    }

                    if (mounted) {
                      await _loadData();
                    }
                  },
                ),
                ListTile(
                  leading:
                      const Icon(Icons.favorite_border),
                  title:
                      const Text('المفضلة'),
                  onTap: () async {
                    Navigator.pop(context);

                    await Navigator.of(context)
                        .push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const FavoritesScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.person_outline,
                  ),
                  title:
                      const Text('الملف الشخصي'),
                  onTap: () async {
                    Navigator.pop(context);

                    await Navigator.of(context)
                        .push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const ProfileScreen(),
                      ),
                    );

                    if (mounted) {
                      await _checkAdminStatus();
                    }
                  },
                ),
                if (_isAdmin)
                  ListTile(
                    leading: const Icon(
                      Icons.admin_panel_settings_outlined,
                    ),
                    title:
                        const Text('لوحة الإدارة'),
                    onTap: () async {
                      Navigator.pop(context);

                      await Navigator.of(context)
                          .push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const AdminListingsScreen(),
                        ),
                      );

                      if (mounted) {
                        await _loadData();
                      }
                    },
                  ),
              ],
            ),
          ),
        ),
        body: _buildBody(),
        bottomNavigationBar:
            _buildBottomNavigation(),
      ),
    );
  }
}