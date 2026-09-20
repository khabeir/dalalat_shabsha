import 'package:flutter/material.dart';
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

  bool _loadingCategories = true;
  bool _saving = false;

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
          .eq('id', widget.listing['id']);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تعديل الإعلان بنجاح.'),
        ),
      );

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تعديل الإعلان: $e'),
        ),
      );
    }
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: const OutlineInputBorder(),
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

                    const SizedBox(height: 16),

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
                        keyboardType: const TextInputType.numberWithOptions(
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
                          _saving ? 'جاري الحفظ...' : 'حفظ التعديلات',
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