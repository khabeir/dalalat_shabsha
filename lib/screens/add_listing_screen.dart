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
                : double.tryParse(_priceController.text.trim()),
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
          content: Text('تعذر حفظ الإعلان: ${e.message}'),
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
          content: Text('حدث خطأ أثناء حفظ الإعلان: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _buildImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'صور الإعلان',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),

        const SizedBox(height: 6),

        Text(
          'يمكنك إضافة حتى $_maxImages صور',
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 13,
          ),
        ),

        const SizedBox(height: 12),

        if (_selectedImages.isNotEmpty)
          SizedBox(
            height: 105,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final image = _selectedImages[index];

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(image.path),
                        width: 105,
                        height: 105,
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
                          onTap: () => _removeImage(index),
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

        if (_selectedImages.isNotEmpty)
          const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: _saving ? null : _pickImages,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(
            _selectedImages.isEmpty
                ? 'إضافة صور'
                : 'إضافة صور أخرى (${_selectedImages.length}/$_maxImages)',
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
          title: const Text('إضافة إعلان'),
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
                    const Text(
                      'بيانات الإعلان',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 20),

                    DropdownButtonFormField<int>(
                      initialValue: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'التصنيف',
                        prefixIcon: Icon(Icons.category_outlined),
                        border: OutlineInputBorder(),
                      ),
                      items: _categories.map((category) {
                        final id = category['id'] as int;
                        final name = category['name'] as String;
                        final icon = category['icon'] as String?;

                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text(
                            '${icon ?? '📦'} $name',
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedCategoryId = value;
                        });
                      },
                      validator: (value) {
                        if (value == null) {
                          return 'اختر التصنيف';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'عنوان الإعلان',
                        hintText: 'مثال: هاتف سامسونج للبيع',
                        prefixIcon: Icon(Icons.title),
                        border: OutlineInputBorder(),
                      ),
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
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'الوصف',
                        hintText: 'اكتب تفاصيل الإعلان...',
                        prefixIcon: Icon(Icons.description_outlined),
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                    ),

                    const SizedBox(height: 16),

                    _buildImagesSection(),

                    const SizedBox(height: 20),

                    const Text(
                      'نوع السعر',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'fixed',
                          label: Text('ثابت'),
                        ),
                        ButtonSegment(
                          value: 'negotiable',
                          label: Text('قابل للتفاوض'),
                        ),
                        ButtonSegment(
                          value: 'contact',
                          label: Text('عند التواصل'),
                        ),
                      ],
                      selected: {_priceType},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _priceType = selection.first;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    if (_priceType != 'contact')
                      TextFormField(
                        controller: _priceController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'السعر بالجنيه السوداني',
                          prefixIcon: Icon(Icons.payments_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (_priceType == 'contact') return null;

                          if (value == null || value.trim().isEmpty) {
                            return 'أدخل السعر';
                          }

                          final price = double.tryParse(value.trim());

                          if (price == null || price < 0) {
                            return 'أدخل سعراً صحيحاً';
                          }

                          return null;
                        },
                      ),

                    if (_priceType != 'contact')
                      const SizedBox(height: 16),

                    const Text(
                      'حالة السلعة',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 8),

                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'new',
                          label: Text('جديد'),
                          icon: Icon(Icons.new_releases_outlined),
                        ),
                        ButtonSegment(
                          value: 'used',
                          label: Text('مستعمل'),
                          icon: Icon(Icons.recycling_outlined),
                        ),
                      ],
                      selected: {_condition},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _condition = selection.first;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _areaController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'المنطقة',
                        hintText: 'مثال: شبشة',
                        prefixIcon: Icon(Icons.location_on_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),

                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'رقم التواصل',
                        hintText: 'رقم الهاتف',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'أدخل رقم التواصل';
                        }

                        return null;
                      },
                    ),

                    const SizedBox(height: 28),

                    SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _saveListing,
                        icon: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.publish),
                        label: Text(
                          _saving
                              ? 'جاري الحفظ والرفع...'
                              : 'نشر الإعلان',
                          style: const TextStyle(fontSize: 17),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    const Text(
                      'سيتم مراجعة الإعلان قبل ظهوره للمستخدمين.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}