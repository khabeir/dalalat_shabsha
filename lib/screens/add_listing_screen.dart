import 'package:flutter/material.dart';
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

  List<Map<String, dynamic>> _categories = [];

  int? _selectedCategoryId;
  String _priceType = 'negotiable';
  String _condition = 'used';

  bool _loadingCategories = true;
  bool _saving = false;

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
      await _supabase.from('listings').insert({
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
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم إرسال الإعلان بنجاح، وهو الآن بانتظار المراجعة.',
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
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('حدث خطأ غير متوقع أثناء حفظ الإعلان'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
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
                      value: _selectedCategoryId,
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
                              ? 'جاري الحفظ...'
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
