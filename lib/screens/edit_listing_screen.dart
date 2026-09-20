import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class EditListingScreen extends StatefulWidget {
  final Map<String, dynamic> listing;

  const EditListingScreen({
    super.key,
    required this.listing,
  });

  @override
  State<EditListingScreen> createState() => _EditListingScreenState();
}

class _EditListingScreenState extends State<EditListingScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _imagePicker = ImagePicker();

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _priceController;
  late final TextEditingController _areaController;
  late final TextEditingController _phoneController;

  int? _selectedCategoryId;
  late String _priceType;
  late String _condition;

  List<Map<String, dynamic>> _categories = [];

  List<Map<String, dynamic>> _existingImages = [];
  final List<XFile> _newImages = [];

  bool _loadingCategories = true;
  bool _loadingImages = true;
  bool _saving = false;

  static const int _maxImages = 6;

  @override
  void initState() {
    super.initState();

    _titleController = TextEditingController(
      text: widget.listing['title']?.toString() ?? '',
    );

    _descriptionController = TextEditingController(
      text: widget.listing['description']?.toString() ?? '',
    );

    _priceController = TextEditingController(
      text: widget.listing['price']?.toString() ?? '',
    );

    _areaController = TextEditingController(
      text: widget.listing['area']?.toString() ?? '',
    );

    _phoneController = TextEditingController(
      text: widget.listing['contact_phone']?.toString() ?? '',
    );

    final categoryId = widget.listing['category_id'];

    if (categoryId is int) {
      _selectedCategoryId = categoryId;
    }

    _priceType = widget.listing['price_type']?.toString() ?? 'negotiable';

    _condition =
        widget.listing['condition']?.toString() ?? 'not_applicable';

    _loadCategories();
    _loadImages();
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
        SnackBar(
          content: Text('تعذر تحميل الأقسام: $e'),
        ),
      );
    }
  }

  Future<void> _loadImages() async {
    try {
      final listingId = widget.listing['id'];

      if (listingId is! int) {
        throw Exception('رقم الإعلان غير صحيح');
      }

      final response = await _supabase
          .from('listing_images')
          .select('id, image_path, sort_order')
          .eq('listing_id', listingId)
          .order('sort_order');

      if (!mounted) return;

      setState(() {
        _existingImages = List<Map<String, dynamic>>.from(response);
        _loadingImages = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _loadingImages = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحميل صور الإعلان: $e'),
        ),
      );
    }
  }

  int get _totalImages {
    return _existingImages.length + _newImages.length;
  }

  Future<void> _pickImages() async {
    final remaining = _maxImages - _totalImages;

    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يمكنك الاحتفاظ بـ 6 صور كحد أقصى للإعلان'),
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

      final selected = images.take(remaining).toList();

      setState(() {
        _newImages.addAll(selected);
      });

      if (images.length > remaining && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت إضافة $remaining صورة فقط لأن الحد الأقصى هو $_maxImages صور',
            ),
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

  Future<void> _deleteExistingImage(int index) async {
    if (_saving) return;

    final image = _existingImages[index];

    final imageId = image['id'];
    final imagePath = image['image_path']?.toString();

    if (imageId is! int || imagePath == null || imagePath.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('حذف الصورة'),
            content: const Text(
              'هل تريد حذف هذه الصورة من الإعلان؟',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext, false);
                },
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext, true);
                },
                child: const Text('حذف'),
              ),
            ],
          ),
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      setState(() {
        _saving = true;
      });

      await _supabase
          .from('listing_images')
          .delete()
          .eq('id', imageId);

      try {
        await _supabase.storage
            .from('listing-images')
            .remove([imagePath]);
      } catch (_) {
        // إذا كان ملف Storage غير موجود، لا نمنع حذف سجل الصورة.
      }

      if (!mounted) return;

      setState(() {
        _existingImages.removeAt(index);
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الصورة'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر حذف الصورة: $e'),
        ),
      );
    }
  }

  void _removeNewImage(int index) {
    if (_saving) return;

    setState(() {
      _newImages.removeAt(index);
    });
  }

  String _contentType(String extension) {
    switch (extension.toLowerCase()) {
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

  Future<void> _uploadNewImages(int listingId) async {
    for (int i = 0; i < _newImages.length; i++) {
      final image = _newImages[i];

      final originalExtension = image.path.contains('.')
          ? image.path.split('.').last.toLowerCase()
          : 'jpg';

      final extension =
          originalExtension == 'jpeg' ? 'jpg' : originalExtension;

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

      final sortOrder = _existingImages.length + i;

      await _supabase.from('listing_images').insert({
        'listing_id': listingId,
        'image_path': imagePath,
        'sort_order': sortOrder,
      });
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر القسم أولاً.'),
        ),
      );
      return;
    }

    if (_priceType != 'contact' &&
        _priceController.text.trim().isNotEmpty &&
        double.tryParse(_priceController.text.trim()) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل سعراً صحيحاً.'),
        ),
      );
      return;
    }

    final listingId = widget.listing['id'];

    if (listingId is! int) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رقم الإعلان غير صحيح.'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final price = _priceType == 'contact'
          ? null
          : double.tryParse(_priceController.text.trim());

      await _supabase
          .from('listings')
          .update({
            'category_id': _selectedCategoryId,
            'title': _titleController.text.trim(),
            'description': _descriptionController.text.trim(),
            'price': price,
            'price_type': _priceType,
            'condition': _condition,
            'area': _areaController.text.trim(),
            'contact_phone': _phoneController.text.trim(),
          })
          .eq('id', listingId);

      if (_newImages.isNotEmpty) {
        await _uploadNewImages(listingId);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تعديل الإعلان بنجاح.'),
        ),
      );

      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تعديل الإعلان: ${e.message}'),
        ),
      );
    } on StorageException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم تعديل بيانات الإعلان، لكن تعذر رفع إحدى الصور: ${e.message}',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('حدث خطأ أثناء تعديل الإعلان: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: const OutlineInputBorder(),
    );
  }

  Widget _buildImagesSection() {
    if (_loadingImages) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'صور الإعلان',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          '$_totalImages / $_maxImages صور',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 12),

        if (_existingImages.isNotEmpty)
          SizedBox(
            height: 115,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _existingImages.length,
              separatorBuilder: (_, __) {
                return const SizedBox(width: 10);
              },
              itemBuilder: (context, index) {
                final image = _existingImages[index];
                final imagePath = image['image_path']?.toString() ?? '';

                final imageUrl = imagePath.isEmpty
                    ? ''
                    : _supabase.storage
                        .from('listing-images')
                        .getPublicUrl(imagePath);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: imageUrl.isEmpty
                          ? Container(
                              width: 110,
                              height: 110,
                              color: Colors.grey.shade200,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                size: 35,
                              ),
                            )
                          : Image.network(
                              imageUrl,
                              width: 110,
                              height: 110,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Container(
                                  width: 110,
                                  height: 110,
                                  color: Colors.grey.shade200,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    size: 35,
                                  ),
                                );
                              },
                            ),
                    ),

                    Positioned(
                      top: -7,
                      right: -7,
                      child: Material(
                        color: Colors.red,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _saving
                              ? null
                              : () => _deleteExistingImage(index),
                          child: const Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      bottom: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

        if (_newImages.isNotEmpty) ...[
          const SizedBox(height: 12),

          SizedBox(
            height: 115,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _newImages.length,
              separatorBuilder: (_, __) {
                return const SizedBox(width: 10);
              },
              itemBuilder: (context, index) {
                final image = _newImages[index];

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(image.path),
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                      ),
                    ),

                    Positioned(
                      top: -7,
                      right: -7,
                      child: Material(
                        color: Colors.red,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _saving
                              ? null
                              : () => _removeNewImage(index),
                          child: const Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),

                    Positioned(
                      bottom: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'جديدة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],

        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed:
              _saving || _totalImages >= _maxImages ? null : _pickImages,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _totalImages >= _maxImages
                ? 'تم الوصول إلى الحد الأقصى'
                : 'إضافة صور',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تعديل الإعلان'),
          centerTitle: true,
        ),
        body: _loadingCategories
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _selectedCategoryId,
                      decoration: _decoration(
                        'القسم',
                        Icons.category_outlined,
                      ),
                      items: _categories.map((category) {
                        final id = category['id'];

                        return DropdownMenuItem<int>(
                          value: id is int ? id : null,
                          child: Text(
                            '${category['icon'] ?? ''} ${category['name']}',
                          ),
                        );
                      }).toList(),
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(() {
                                _selectedCategoryId = value;
                              });
                            },
                      validator: (value) {
                        if (value == null) {
                          return 'اختر القسم';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _titleController,
                      decoration: _decoration(
                        'عنوان الإعلان',
                        Icons.title,
                      ),
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'أدخل عنوان الإعلان';
                        }

                        if (value.trim().length < 3) {
                          return 'العنوان قصير جداً';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _descriptionController,
                      decoration: _decoration(
                        'الوصف',
                        Icons.description_outlined,
                      ),
                      minLines: 4,
                      maxLines: 7,
                    ),

                    const SizedBox(height: 20),

                    _buildImagesSection(),

                    const SizedBox(height: 20),

                    DropdownButtonFormField<String>(
                      initialValue: _priceType,
                      decoration: _decoration(
                        'نوع السعر',
                        Icons.payments_outlined,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'fixed',
                          child: Text('سعر ثابت'),
                        ),
                        DropdownMenuItem(
                          value: 'negotiable',
                          child: Text('قابل للتفاوض'),
                        ),
                        DropdownMenuItem(
                          value: 'contact',
                          child: Text('السعر عند التواصل'),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value == null) return;

                              setState(() {
                                _priceType = value;

                                if (value == 'contact') {
                                  _priceController.clear();
                                }
                              });
                            },
                    ),

                    const SizedBox(height: 16),

                    if (_priceType != 'contact')
                      TextFormField(
                        controller: _priceController,
                        decoration: _decoration(
                          'السعر',
                          Icons.attach_money,
                        ),
                        keyboardType:
                            const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),

                    if (_priceType != 'contact')
                      const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: _condition,
                      decoration: _decoration(
                        'الحالة',
                        Icons.info_outline,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'new',
                          child: Text('جديد'),
                        ),
                        DropdownMenuItem(
                          value: 'used',
                          child: Text('مستعمل'),
                        ),
                        DropdownMenuItem(
                          value: 'not_applicable',
                          child: Text('لا ينطبق'),
                        ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value == null) return;

                              setState(() {
                                _condition = value;
                              });
                            },
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _areaController,
                      decoration: _decoration(
                        'المنطقة',
                        Icons.location_on_outlined,
                      ),
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _phoneController,
                      decoration: _decoration(
                        'رقم التواصل',
                        Icons.phone_outlined,
                      ),
                      keyboardType: TextInputType.phone,
                    ),

                    const SizedBox(height: 24),

                    SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _saveChanges,
                        icon: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(
                          _saving
                              ? 'جاري الحفظ والرفع...'
                              : 'حفظ التعديلات',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}