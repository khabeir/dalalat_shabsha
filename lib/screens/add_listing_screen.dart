import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final List<XFile> _selectedImages = [];

  int? _selectedCategoryId;
  String _priceType = 'negotiable';
  String _condition = 'used';

  bool _loadingCategories = true;
  bool _saving = false;

  static const int _maxImages = 6;

  @override
  void initState() {
    super.initState();
    _loadCategories();
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
      if (!mounted) return;

      setState(() {
        _loadingCategories = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر تحميل التصنيفات'),
        ),
      );
    }
  }

  Future<void> _pickImages() async {
    if (_selectedImages.length >= _maxImages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يمكنك اختيار 6 صور كحد أقصى'),
        ),
      );
      return;
    }

    try {
      final images = await _imagePicker.pickMultiImage(
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      if (images.isEmpty) return;

      final remaining = _maxImages - _selectedImages.length;

      setState(() {
        _selectedImages.addAll(
          images.take(remaining),
        );
      });

      if (images.length > remaining && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت إضافة 6 صور فقط كحد أقصى'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر اختيار الصور: $e'),
        ),
      );
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  Future<void> _uploadImages(int listingId) async {
    for (int i = 0; i < _selectedImages.length; i++) {
      final image = _selectedImages[i];

      final originalExtension = image.path.contains('.')
          ? image.path.split('.').last.toLowerCase()
          : 'jpg';

      final extension = originalExtension == 'jpeg'
          ? 'jpg'
          : originalExtension;

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_$i.$extension';

      final imagePath = '$listingId/$fileName';

      final fileBytes = await image.readAsBytes();

      await _supabase.storage
          .from('listing-images')
          .uploadBinary(
            imagePath,
            fileBytes,
            fileOptions: FileOptions(
              contentType: _contentType(extension),
              upsert: false,
            ),
          );

      await _supabase.from('listing_images').insert({
        'listing_id': listingId,
        'image_path': imagePath,
        'sort_order': i,
      });
    }
  }

  String _contentType(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'gif':
        return 'image/gif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _saveListing() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر تصنيف الإعلان'),
        ),
      );
      return;
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب تسجيل الدخول أولاً'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final listingResponse = await _supabase
          .from('listings')
          .insert({
            'seller_id': user.id,
            'category_id': _selectedCategoryId,
            'title': _titleController.text.trim(),
            'description': _descriptionController.text.trim(),
            'price': _priceType == 'contact'
                ? null
                : double.tryParse(
                    _priceController.text.trim(),
                  ),
            'currency': 'SDG',
            'price_type': _priceType,
            'condition': _condition,
            'area': _areaController.text.trim(),
            'contact_phone': _phoneController.text.trim(),
            'status': 'pending',
          })
          .select('id')
          .single();

      final listingId = listingResponse['id'];

      if (listingId is! int) {
        throw Exception('تعذر الحصول على رقم الإعلان');
      }

      if (_selectedImages.isNotEmpty) {
        await _uploadImages(listingId);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _selectedImages.isEmpty
                ? 'تم إرسال الإعلان بنجاح، وهو الآن بانتظار المراجعة.'
                : 'تم إرسال الإعلان مع الصور بنجاح، وهو الآن بانتظار المراجعة.',
          ),
        ),
      );

      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر حفظ الإعلان: ${e.message}',
          ),
        ),
      );
    } on StorageException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم إنشاء الإعلان، لكن تعذر رفع إحدى الصور: ${e.message}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'حدث خطأ أثناء حفظ الإعلان: $e',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(
        icon,
        size: 21,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Colors.grey.withValues(alpha: 0.35),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 1.5,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 13,
      ),
      labelStyle: const TextStyle(
        fontSize: 14,
      ),
      hintStyle: TextStyle(
        fontSize: 13,
        color: Colors.grey.shade500,
      ),
    );
  }

  Widget _buildSectionTitle({
    required IconData icon,
    required String title,
    String? subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 19,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          icon: Icons.photo_library_outlined,
          title: 'صور الإعلان',
          subtitle: 'أضف حتى $_maxImages صور',
        ),

        const SizedBox(height: 12),

        if (_selectedImages.isEmpty)
          InkWell(
            onTap: _saving ? null : _pickImages,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 105,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.25),
                  width: 1.2,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 32,
                    color: Theme.of(context)
                        .colorScheme
                        .primary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'اضغط لإضافة صور',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context)
                          .colorScheme
                          .primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'الصور تساعد المشترين على معرفة السلعة',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final image = _selectedImages[index];

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        borderRadius:
                            BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.file(
                        File(image.path),
                        width: 92,
                        height: 92,
                        fit: BoxFit.cover,
                      ),
                    ),

                    Positioned(
                      top: -6,
                      right: -6,
                      child: Material(
                        color: Colors.red,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: InkWell(
                          customBorder:
                              const CircleBorder(),
                          onTap: () => _removeImage(index),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius:
                              BorderRadius.circular(7),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 9),

          if (_selectedImages.length < _maxImages)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _pickImages,
                icon: const Icon(
                  Icons.add_photo_alternate_outlined,
                  size: 18,
                ),
                label: Text(
                  'إضافة صور أخرى '
                  '(${_selectedImages.length}/$_maxImages)',
                  style: const TextStyle(
                    fontSize: 13,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildReviewNotice() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 20,
            color: Colors.amber.shade800,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'سيتم مراجعة الإعلان من الإدارة قبل ظهوره للمستخدمين.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Colors.grey.shade800,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          icon: Icons.payments_outlined,
          title: 'السعر',
          subtitle: 'حدد طريقة عرض السعر',
        ),

        const SizedBox(height: 11),

        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'fixed',
              label: Text(
                'ثابت',
                style: TextStyle(fontSize: 12),
              ),
            ),
            ButtonSegment(
              value: 'negotiable',
              label: Text(
                'قابل للتفاوض',
                style: TextStyle(fontSize: 12),
              ),
            ),
            ButtonSegment(
              value: 'contact',
              label: Text(
                'عند التواصل',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
          selected: {_priceType},
          onSelectionChanged: (selection) {
            setState(() {
              _priceType = selection.first;
            });
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 9,
              ),
            ),
          ),
        ),

        if (_priceType != 'contact') ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration(
              label: 'السعر بالجنيه السوداني',
              hint: 'مثال: 250000',
              icon: Icons.price_change_outlined,
            ),
            validator: (value) {
              if (_priceType == 'contact') {
                return null;
              }

              if (value == null ||
                  value.trim().isEmpty) {
                return 'أدخل السعر';
              }

              final price =
                  double.tryParse(value.trim());

              if (price == null || price < 0) {
                return 'أدخل سعراً صحيحاً';
              }

              return null;
            },
          ),
        ],
      ],
    );
  }

  Widget _buildConditionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(
          icon: Icons.inventory_2_outlined,
          title: 'حالة السلعة',
        ),

        const SizedBox(height: 11),

        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'new',
              label: Text(
                'جديد',
                style: TextStyle(fontSize: 13),
              ),
              icon: Icon(
                Icons.new_releases_outlined,
                size: 18,
              ),
            ),
            ButtonSegment(
              value: 'used',
              label: Text(
                'مستعمل',
                style: TextStyle(fontSize: 13),
              ),
              icon: Icon(
                Icons.recycling_outlined,
                size: 18,
              ),
            ),
          ],
          selected: {_condition},
          onSelectionChanged: (selection) {
            setState(() {
              _condition = selection.first;
            });
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outline
              .withValues(alpha: 0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'إضافة إعلان',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w600,
            ),
          ),
          centerTitle: true,
        ),
        body: _loadingCategories
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : Form(
                key: _formKey,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(
                    14,
                    10,
                    14,
                    24,
                  ),
                  children: [
                    // ملاحظة المراجعة في بداية الصفحة.
                    _buildReviewNotice(),

                    const SizedBox(height: 14),

                    // بيانات الإعلان.
                    _buildSectionCard(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle(
                            icon: Icons.edit_note_outlined,
                            title: 'بيانات الإعلان',
                            subtitle:
                                'أدخل المعلومات الأساسية',
                          ),

                          const SizedBox(height: 14),

                          // التصنيف.
                          DropdownButtonFormField<int>(
                            initialValue:
                                _selectedCategoryId,
                            decoration: _inputDecoration(
                              label: 'التصنيف',
                              icon: Icons.category_outlined,
                            ),
                            items: _categories.map(
                              (category) {
                                final id =
                                    category['id'] as int;
                                final name =
                                    category['name'] as String;
                                final icon =
                                    category['icon'] as String?;

                                return DropdownMenuItem<int>(
                                  value: id,
                                  child: Text(
                                    '${icon ?? '📦'} $name',
                                    style:
                                        const TextStyle(
                                      fontSize: 14,
                                    ),
                                  ),
                                );
                              },
                            ).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedCategoryId =
                                    value;
                              });
                            },
                            validator: (value) {
                              if (value == null) {
                                return 'اختر التصنيف';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 12),

                          // العنوان.
                          TextFormField(
                            controller: _titleController,
                            textInputAction:
                                TextInputAction.next,
                            decoration: _inputDecoration(
                              label: 'عنوان الإعلان',
                              hint:
                                  'مثال: هاتف سامسونج للبيع',
                              icon: Icons.title_outlined,
                            ),
                            validator: (value) {
                              if (value == null ||
                                  value.trim().isEmpty) {
                                return 'أدخل عنوان الإعلان';
                              }

                              if (value.trim().length < 3) {
                                return 'العنوان قصير جداً';
                              }

                              return null;
                            },
                          ),

                          const SizedBox(height: 12),

                          // الوصف.
                          TextFormField(
                            controller:
                                _descriptionController,
                            maxLines: 4,
                            decoration: _inputDecoration(
                              label: 'وصف الإعلان',
                              hint:
                                  'اكتب تفاصيل السلعة وحالتها...',
                              icon:
                                  Icons.description_outlined,
                            ).copyWith(
                              alignLabelWithHint: true,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // الصور.
                    _buildSectionCard(
                      child: _buildImagesSection(),
                    ),

                    const SizedBox(height: 12),

                    // السعر.
                    _buildSectionCard(
                      child: _buildPriceSection(),
                    ),

                    const SizedBox(height: 12),

                    // حالة السلعة.
                    _buildSectionCard(
                      child: _buildConditionSection(),
                    ),

                    const SizedBox(height: 12),

                    // الموقع والتواصل.
                    _buildSectionCard(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          _buildSectionTitle(
                            icon: Icons.location_on_outlined,
                            title: 'الموقع والتواصل',
                            subtitle:
                                'كيف يمكن الوصول إليك؟',
                          ),

                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _areaController,
                            textInputAction:
                                TextInputAction.next,
                            decoration: _inputDecoration(
                              label: 'المنطقة',
                              hint: 'مثال: شبشة',
                              icon:
                                  Icons.location_on_outlined,
                            ),
                          ),

                          const SizedBox(height: 12),

                          TextFormField(
                            controller: _phoneController,
                            keyboardType:
                                TextInputType.phone,
                            textInputAction:
                                TextInputAction.done,
                            decoration: _inputDecoration(
                              label: 'رقم التواصل',
                              hint: 'رقم الهاتف',
                              icon: Icons.phone_outlined,
                            ),
                            validator: (value) {
                              if (value == null ||
                                  value.trim().isEmpty) {
                                return 'أدخل رقم التواصل';
                              }

                              return null;
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),

                    // زر النشر.
                    SizedBox(
                      height: 50,
                      child: FilledButton.icon(
                        onPressed:
                            _saving ? null : _saveListing,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.publish_outlined,
                                size: 21,
                              ),
                        label: Text(
                          _saving
                              ? 'جاري الحفظ والرفع...'
                              : 'نشر الإعلان',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'سيظهر الإعلان بعد مراجعته والموافقة عليه من الإدارة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}