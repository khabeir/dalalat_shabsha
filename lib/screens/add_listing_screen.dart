import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_decorations.dart';
import 'listing_form_widgets.dart';

class AddListingScreen extends StatefulWidget {
  const AddListingScreen({super.key});

  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}

class _AddListingScreenState extends State<AddListingScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _areaController = TextEditingController();
  final _phoneController = TextEditingController();

  final _supabase = Supabase.instance.client;
  final _imagePicker = ImagePicker();

  List<Map<String, dynamic>> _categories = [];
  final List<ListingImageItem> _images = [];

  int? _selectedCategoryId;
  String _priceType = 'negotiable';
  String _condition = 'used';

  bool _loadingCategories = true;
  bool _saving = false;
  String? _progress;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadDefaults();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _areaController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // =========================
  // أدوات مساعدة
  // =========================

  void _showSnack(
    String message, {
    int seconds = 4,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: seconds),
          backgroundColor: AppColors.ink,
          elevation: 4,
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
  }

  bool get _hasChanges {
    return _titleController.text.trim().isNotEmpty ||
        _descriptionController.text.trim().isNotEmpty ||
        _priceController.text.trim().isNotEmpty ||
        _images.isNotEmpty ||
        _selectedCategoryId != null;
  }

  Future<void> _onBackPressed() async {
    if (_saving) return;

    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    final leave = await confirmListingDialog(
      context,
      title: 'تجاهل الإعلان؟',
      message: 'لديك بيانات لم تُنشر. هل تريد الخروج وتجاهلها؟',
      confirmLabel: 'خروج',
      destructive: true,
    );

    if (leave && mounted) {
      Navigator.pop(context);
    }
  }

  // =========================
  // تحميل البيانات
  // =========================

  Future<void> _loadCategories() async {
    try {
      final response = await _supabase
          .from('categories')
          .select('id, name, icon')
          .eq('is_active', true)
          .order('sort_order');

      if (!mounted) return;

      setState(() {
        _categories = List<Map<String, dynamic>>.from(response);
        _loadingCategories = false;
      });
    } catch (e) {
      debugPrint('loadCategories error: $e');

      if (!mounted) return;

      setState(() {
        _loadingCategories = false;
      });

      _showSnack('تعذر تحميل التصنيفات');
    }
  }

  Future<void> _loadDefaults() async {
    try {
      final user = _supabase.auth.currentUser;

      if (user == null) return;

      final profile = await _supabase
          .from('profiles')
          .select('phone, area')
          .eq('id', user.id)
          .maybeSingle();

      var phone = profile?['phone']?.toString().trim() ?? '';

      if (phone.isEmpty) {
        phone = user.userMetadata?['phone']?.toString().trim() ?? '';
      }

      if (phone.isEmpty) {
        phone = user.phone?.trim() ?? '';
      }

      final area = profile?['area']?.toString().trim() ?? '';

      if (!mounted) return;

      if (_phoneController.text.trim().isEmpty && phone.isNotEmpty) {
        _phoneController.text = phone;
      }

      if (_areaController.text.trim().isEmpty && area.isNotEmpty) {
        _areaController.text = area;
      }
    } catch (e) {
      debugPrint('loadDefaults error: $e');
    }
  }

  // =========================
  // الصور
  // =========================

  Future<void> _addImages() async {
    final picked = await pickListingImages(
      context,
      _imagePicker,
      remaining: kMaxListingImages - _images.length,
    );

    if (picked.isEmpty || !mounted) return;

    setState(() {
      _images.addAll(
        picked.map(ListingImageItem.local),
      );
    });
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  void _makeCover(int index) {
    setState(() {
      final item = _images.removeAt(index);
      _images.insert(0, item);
    });

    _showSnack(
      'تم تعيين الصورة كغلاف للإعلان',
      seconds: 2,
    );
  }

  // =========================
  // الحفظ
  // =========================

  Future<void> _rollbackListing(int listingId) async {
    try {
      await _supabase
          .from('listings')
          .delete()
          .eq('id', listingId);
    } catch (e) {
      debugPrint('rollbackListing error: $e');
    }
  }

  Future<void> _saveListing() async {
    if (_saving) return;

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final categoryId = _selectedCategoryId;

    if (categoryId == null) {
      _showSnack('اختر تصنيف الإعلان');
      return;
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      _showSnack('يجب تسجيل الدخول أولاً');
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _progress = 'جاري حفظ الإعلان...';
    });

    int? listingId;

    try {
      final response = await _supabase
          .from('listings')
          .insert({
            'seller_id': user.id,
            'category_id': categoryId,
            'title': _titleController.text.trim(),
            'description': _descriptionController.text.trim(),
            'price': _priceType == 'contact'
                ? null
                : parsePrice(_priceController.text),
            'currency': 'SDG',
            'price_type': _priceType,
            'condition': _condition,
            'area': _areaController.text.trim(),
            'contact_phone': cleanPhone(_phoneController.text),
            'status': 'pending',
          })
          .select('id')
          .single();

      final id = response['id'];

      if (id is! int) {
        throw Exception('تعذر الحصول على رقم الإعلان');
      }

      listingId = id;

      var failed = 0;

      for (var i = 0; i < _images.length; i++) {
        final file = _images[i].file;

        if (file == null) continue;

        if (mounted) {
          setState(() {
            _progress =
                'جاري رفع الصورة ${i + 1} من ${_images.length}...';
          });
        }

        try {
          await uploadListingImage(
            supabase: _supabase,
            listingId: id,
            image: file,
            fileIndex: i,
            sortOrder: i,
          );
        } catch (e) {
          debugPrint('upload image $i failed: $e');
          failed++;
        }
      }

      if (_images.isNotEmpty && failed == _images.length) {
        await _rollbackListing(id);
        listingId = null;

        _showSnack(
          'تعذر رفع الصور فلم يُحفظ الإعلان. '
          'تحقق من اتصال الإنترنت وحاول مرة أخرى.',
          seconds: 6,
        );

        return;
      }

      if (!mounted) return;

      final buffer = StringBuffer(
        'تم إرسال الإعلان بنجاح، وهو الآن بانتظار المراجعة.',
      );

      if (failed > 0) {
        buffer.write(
          '\nتعذر رفع $failed من الصور، '
          'يمكنك إضافتها من "تعديل الإعلان".',
        );
      }

      _showSnack(
        buffer.toString(),
        seconds: failed > 0 ? 7 : 4,
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('saveListing error: $e');

      if (listingId != null) {
        await _rollbackListing(listingId);
      }

      _showSnack(
        'تعذر حفظ الإعلان. '
        'تحقق من اتصال الإنترنت وحاول مرة أخرى.',
        seconds: 5,
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _progress = null;
        });
      }
    }
  }

  // =========================
  // الواجهة
  // =========================

  Widget _buildReviewNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brandSoft,
            AppColors.brandSoft.withValues(alpha: 0.55),
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: AppColors.brand.withValues(alpha: 0.10),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.verified_outlined,
              size: 20,
              color: AppColors.brand,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مراجعة الإعلان',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'سيُراجع الإعلان من الإدارة قبل ظهوره للمستخدمين.',
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsSection() {
    return ListingSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListingSectionTitle(
            icon: Icons.edit_note_outlined,
            title: 'بيانات الإعلان',
            subtitle: 'أدخل المعلومات الأساسية',
          ),
          const SizedBox(height: 14),
          ListingCategoryField(
            categories: _categories,
            value: _selectedCategoryId,
            onChanged: (value) {
              setState(() {
                _selectedCategoryId = value;
              });
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _titleController,
            textInputAction: TextInputAction.next,
            maxLength: kMaxTitleLength,
            decoration: listingInputDecoration(
              context,
              label: 'عنوان الإعلان',
              hint: 'مثال: هاتف سامسونج للبيع',
              icon: Icons.title_outlined,
            ),
            validator: validateListingTitle,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descriptionController,
            maxLines: 5,
            maxLength: kMaxDescriptionLength,
            decoration: listingInputDecoration(
              context,
              label: 'وصف الإعلان',
              hint: 'اكتب تفاصيل السلعة وحالتها...',
              icon: Icons.description_outlined,
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactSection() {
    return ListingSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListingSectionTitle(
            icon: Icons.location_on_outlined,
            title: 'الموقع والتواصل',
            subtitle: 'كيف يمكن الوصول إليك؟',
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _areaController,
            textInputAction: TextInputAction.next,
            decoration: listingInputDecoration(
              context,
              label: 'المنطقة',
              hint: 'مثال: الحي الثاني',
              icon: Icons.location_on_outlined,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            decoration: listingInputDecoration(
              context,
              label: 'رقم التواصل',
              hint: 'رقم الهاتف أو الواتساب',
              icon: Icons.phone_outlined,
              helper: 'يظهر للمشترين للاتصال بك',
            ),
            validator: validateContactPhone,
          ),
        ],
      ),
    );
  }

  Widget _buildPublishButton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _saving ? null : _saveListing,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  AppColors.brand.withValues(alpha: 0.45),
              disabledForegroundColor: Colors.white70,
              elevation: 3,
              shadowColor: AppColors.brand.withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 21,
                    height: 21,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.publish_outlined,
                    size: 22,
                  ),
            label: Text(
              _saving ? 'جاري الحفظ...' : 'نشر الإعلان',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        if (_saving && _progress != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 9,
            ),
            decoration: AppDecorations.softCard(),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.brand,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _progress!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _onBackPressed();
          }
        },
        child: Scaffold(
          backgroundColor: AppColors.pageBackground,
          appBar: AppBar(
            backgroundColor: AppColors.pageBackground,
            foregroundColor: AppColors.ink,
            elevation: 0,
            surfaceTintColor: Colors.transparent,
            centerTitle: true,
            title: const Text(
              'إضافة إعلان',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
          ),
          body: _loadingCategories
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.brand,
                  ),
                )
              : Form(
                  key: _formKey,
                  autovalidateMode:
                      AutovalidateMode.onUserInteraction,
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      14,
                      8,
                      14,
                      28,
                    ),
                    children: [
                      _buildReviewNotice(),
                      const SizedBox(height: 14),
                      _buildDetailsSection(),
                      const SizedBox(height: 12),
                      ListingSectionCard(
                        child: ListingImagesSection(
                          items: _images,
                          enabled: !_saving,
                          onAdd: _addImages,
                          onRemove: _removeImage,
                          onMakeCover: _makeCover,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListingSectionCard(
                        child: ListingPriceSection(
                          priceType: _priceType,
                          controller: _priceController,
                          onPriceTypeChanged: (value) {
                            setState(() {
                              _priceType = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      ListingSectionCard(
                        child: ListingConditionSection(
                          condition: _condition,
                          onChanged: (value) {
                            setState(() {
                              _condition = value;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildContactSection(),
                      const SizedBox(height: 18),
                      _buildPublishButton(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}