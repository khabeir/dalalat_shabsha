import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'listing_form_widgets.dart';

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
  // إن كانت true: تعديل العنوان أو الوصف أو الصور أو المنطقة أو الهاتف
  // أو التصنيف لإعلان "متاح" يعيده إلى "قيد المراجعة".
  // غيّرها إلى false إن أردت أن تُطبَّق التعديلات فوراً دون مراجعة.
  static const bool _reviewOnEdit = true;

  static const _priceTypes = ['fixed', 'negotiable', 'contact'];

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

  // الصور الأصلية من الخادم، والصور الحالية في النموذج (مع الجديدة).
  List<ListingImageItem> _originalImages = [];
  List<ListingImageItem> _images = [];

  // لقطة الحالة عند فتح الشاشة، لمعرفة هل تغيّر شيء.
  String? _initialSnapshot;

  bool _loadingCategories = true;
  bool _loadingImages = true;
  bool _saving = false;
  String? _progress;

  int? get _listingId {
    final id = widget.listing['id'];
    return id is int ? id : null;
  }

  String? get _status => widget.listing['status']?.toString();

  @override
  void initState() {
    super.initState();

    final listing = widget.listing;

    _titleController = TextEditingController(
      text: listing['title']?.toString() ?? '',
    );
    _descriptionController = TextEditingController(
      text: listing['description']?.toString() ?? '',
    );
    _priceController = TextEditingController(text: _initialPriceText());
    _areaController = TextEditingController(
      text: listing['area']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: listing['contact_phone']?.toString() ?? '',
    );

    final categoryId = listing['category_id'];

    if (categoryId is int) _selectedCategoryId = categoryId;

    final priceType = listing['price_type']?.toString();
    _priceType = _priceTypes.contains(priceType) ? priceType! : 'negotiable';

    final condition = listing['condition']?.toString();
    _condition =
        kConditionOptions.containsKey(condition) ? condition! : 'not_applicable';

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

  // السعر بدون ".0" الزائدة (250000.0 → 250000).
  String _initialPriceText() {
    final price = widget.listing['price'];

    if (price == null) return '';

    final number = num.tryParse(price.toString());

    if (number == null) return price.toString();

    return number == number.truncate()
        ? number.toInt().toString()
        : number.toString();
  }

  // =========================
  // أدوات مساعدة
  // =========================
  void _showSnack(String message, {int seconds = 4}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: seconds),
        ),
      );
  }

  String _snapshot() {
    return [
      _titleController.text.trim(),
      _descriptionController.text.trim(),
      _priceController.text.trim(),
      _areaController.text.trim(),
      _phoneController.text.trim(),
      '$_selectedCategoryId',
      _priceType,
      _condition,
      _images.map((image) => image.key).join(','),
    ].join('\u0001');
  }

  bool get _hasChanges {
    final initial = _initialSnapshot;

    return initial != null && initial != _snapshot();
  }

  // هل تغيّرت حقول يراجعها المشرف؟ (السعر والحالة لا تحتاج مراجعة)
  bool get _contentChanged {
    final listing = widget.listing;

    return _titleController.text.trim() !=
            (listing['title']?.toString().trim() ?? '') ||
        _descriptionController.text.trim() !=
            (listing['description']?.toString().trim() ?? '') ||
        _areaController.text.trim() !=
            (listing['area']?.toString().trim() ?? '') ||
        cleanPhone(_phoneController.text) !=
            cleanPhone(listing['contact_phone']?.toString() ?? '') ||
        _selectedCategoryId != listing['category_id'];
  }

  bool get _imagesChanged {
    return _images.map((image) => image.key).join(',') !=
        _originalImages.map((image) => image.key).join(',');
  }

  bool get _needsReview {
    if (_status == 'rejected') return true;

    if (_status == 'approved' && _reviewOnEdit) {
      return _contentChanged || _imagesChanged;
    }

    return false;
  }

  Future<void> _onBackPressed() async {
    if (_saving) return;

    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    final leave = await confirmListingDialog(
      context,
      title: 'تعديلات غير محفوظة',
      message: 'لديك تعديلات لم تُحفظ. هل تريد الخروج وتجاهلها؟',
      confirmLabel: 'خروج',
      destructive: true,
    );

    if (leave && mounted) Navigator.pop(context);
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

      setState(() => _loadingCategories = false);

      _showSnack('تعذر تحميل الأقسام');
    }
  }

  Future<void> _loadImages() async {
    final listingId = _listingId;

    if (listingId == null) {
      setState(() => _loadingImages = false);
      return;
    }

    try {
      final response = await _supabase
          .from('listing_images')
          .select('id, image_path, sort_order')
          .eq('listing_id', listingId)
          .order('sort_order');

      final items = <ListingImageItem>[];

      for (final row in List<Map<String, dynamic>>.from(response)) {
        final id = row['id'];
        final path = row['image_path']?.toString().trim() ?? '';

        if (id is! int || path.isEmpty) continue;

        final url = path.startsWith('http')
            ? path
            : _supabase.storage.from(kListingImagesBucket).getPublicUrl(path);

        items.add(
          ListingImageItem.remote(
            id: id,
            path: path,
            url: url,
            sortOrder: row['sort_order'] is int ? row['sort_order'] as int : null,
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        _originalImages = List.of(items);
        _images = List.of(items);
        _loadingImages = false;
        _initialSnapshot = _snapshot();
      });
    } catch (e) {
      debugPrint('loadImages error: $e');

      if (!mounted) return;

      // نسمح بتعديل النصوص، لكن الصور لن تُمَس عند الحفظ.
      setState(() {
        _loadingImages = false;
        _initialSnapshot = _snapshot();
      });

      _showSnack('تعذر تحميل صور الإعلان');
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
      _images.addAll(picked.map(ListingImageItem.local));
    });
  }

  // الحذف هنا يخص النموذج فقط، ولا يُنفَّذ على الخادم إلا عند "حفظ".
  void _removeImage(int index) {
    setState(() => _images.removeAt(index));
  }

  void _makeCover(int index) {
    setState(() {
      final item = _images.removeAt(index);
      _images.insert(0, item);
    });

    _showSnack('تم تعيين الصورة كغلاف للإعلان', seconds: 2);
  }

  Future<void> _deleteRemovedImages(List<ListingImageItem> removed) async {
    final ids = removed.map((image) => image.id).whereType<int>().toList();

    if (ids.isNotEmpty) {
      await _supabase.from('listing_images').delete().inFilter('id', ids);
    }

    final paths = removed
        .map((image) => image.path)
        .whereType<String>()
        .where((path) => path.isNotEmpty && !path.startsWith('http'))
        .toList();

    if (paths.isEmpty) return;

    try {
      await _supabase.storage.from(kListingImagesBucket).remove(paths);
    } catch (e) {
      debugPrint('remove storage files error: $e');
    }
  }

  // =========================
  // الحفظ
  // =========================
  Future<void> _saveChanges() async {
    if (_saving) return;

    if (_loadingImages) {
      _showSnack('يتم تحميل الصور، انتظر لحظة');
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) return;

    final categoryId = _selectedCategoryId;

    if (categoryId == null) {
      _showSnack('اختر القسم أولاً');
      return;
    }

    final listingId = _listingId;

    if (listingId == null) {
      _showSnack('رقم الإعلان غير صحيح');
      return;
    }

    if (!_hasChanges) {
      _showSnack('لم تُجرِ أي تغيير');
      return;
    }

    final needsReview = _needsReview;

    if (needsReview && _status == 'approved') {
      final confirmed = await confirmListingDialog(
        context,
        title: 'سيعود الإعلان للمراجعة',
        message: 'تعديل هذه البيانات يتطلب مراجعة الإدارة. سيختفي الإعلان '
            'مؤقتاً حتى تتم الموافقة على التعديلات. هل تريد المتابعة؟',
        confirmLabel: 'متابعة',
      );

      if (!confirmed || !mounted) return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _progress = 'جاري حفظ البيانات...';
    });

    try {
      await _supabase.from('listings').update({
        'category_id': categoryId,
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': _priceType == 'contact' ? null : parsePrice(_priceController.text),
        'price_type': _priceType,
        'condition': _condition,
        'area': _areaController.text.trim(),
        'contact_phone': cleanPhone(_phoneController.text),
        if (needsReview) 'status': 'pending',
        if (needsReview && widget.listing.containsKey('rejection_reason'))
          'rejection_reason': null,
      }).eq('id', listingId);

      // الصور: رفع الجديدة وترتيب الكل حسب مكانها في النموذج.
      final finalImages = List<ListingImageItem>.from(_images);

      var failedUploads = 0;
      var warning = false;

      for (var i = 0; i < finalImages.length; i++) {
        final item = finalImages[i];

        if (item.isLocal) {
          if (mounted) {
            setState(() {
              _progress = 'جاري رفع الصورة ${i + 1} من ${finalImages.length}...';
            });
          }

          try {
            await uploadListingImage(
              supabase: _supabase,
              listingId: listingId,
              image: item.file!,
              fileIndex: i,
              sortOrder: i,
            );
          } catch (e) {
            debugPrint('upload image $i failed: $e');
            failedUploads++;
          }
        } else if (item.id != null && item.sortOrder != i) {
          try {
            await _supabase
                .from('listing_images')
                .update({'sort_order': i}).eq('id', item.id!);
          } catch (e) {
            debugPrint('update sort_order failed: $e');
            warning = true;
          }
        }
      }

      final keptIds = finalImages
          .where((image) => !image.isLocal)
          .map((image) => image.id)
          .toSet();

      final removed = _originalImages
          .where((image) => !keptIds.contains(image.id))
          .toList();

      if (removed.isNotEmpty) {
        if (mounted) setState(() => _progress = 'جاري حذف الصور المحذوفة...');

        try {
          await _deleteRemovedImages(removed);
        } catch (e) {
          debugPrint('delete removed images failed: $e');
          warning = true;
        }
      }

      if (!mounted) return;

      final buffer = StringBuffer(
        needsReview
            ? 'تم حفظ التعديلات، والإعلان الآن بانتظار المراجعة.'
            : 'تم تعديل الإعلان بنجاح.',
      );

      if (failedUploads > 0) {
        buffer.write('\nتعذر رفع $failedUploads من الصور، حاول إضافتها مرة أخرى.');
      }

      if (warning) {
        buffer.write('\nتعذر تحديث بعض الصور، تحقق منها لاحقاً.');
      }

      _showSnack(
        buffer.toString(),
        seconds: (failedUploads > 0 || warning) ? 7 : 4,
      );

      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('saveChanges error: $e');

      _showSnack(
        'تعذر حفظ التعديلات. تحقق من اتصال الإنترنت وحاول مرة أخرى.',
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
  Widget _buildStatusBanner() {
    final colorScheme = Theme.of(context).colorScheme;

    String? message;
    Color background = colorScheme.tertiaryContainer;
    Color foreground = colorScheme.onTertiaryContainer;

    switch (_status) {
      case 'rejected':
        final reason = widget.listing['rejection_reason']?.toString().trim() ?? '';
        message = reason.isEmpty
            ? 'تم رفض هذا الإعلان. عدّله ثم احفظ ليُعاد إرساله للمراجعة.'
            : 'سبب الرفض: $reason\nعدّل الإعلان ثم احفظ ليُعاد إرساله للمراجعة.';
        background = colorScheme.errorContainer;
        foreground = colorScheme.onErrorContainer;
        break;
      case 'approved':
        if (_reviewOnEdit) {
          message = 'تعديل العنوان أو الوصف أو الصور أو المنطقة أو رقم التواصل '
              'يعيد الإعلان إلى المراجعة. تعديل السعر والحالة لا يحتاج مراجعة.';
        }
        break;
      case 'pending':
        message = 'الإعلان قيد المراجعة حالياً، وسيظهر بعد موافقة الإدارة.';
        break;
    }

    if (message == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: foreground),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: foreground,
                fontWeight: FontWeight.w500,
              ),
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
          ),

          const SizedBox(height: 14),

          ListingCategoryField(
            categories: _categories,
            value: _selectedCategoryId,
            onChanged: (value) => setState(() => _selectedCategoryId = value),
          ),

          const SizedBox(height: 12),

          TextFormField(
            controller: _titleController,
            textInputAction: TextInputAction.next,
            maxLength: kMaxTitleLength,
            decoration: listingInputDecoration(
              context,
              label: 'عنوان الإعلان',
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
              icon: Icons.description_outlined,
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagesSection() {
    if (_loadingImages) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return ListingImagesSection(
      items: _images,
      enabled: !_saving,
      showNewBadge: true,
      onAdd: _addImages,
      onRemove: _removeImage,
      onMakeCover: _makeCover,
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
          ),

          const SizedBox(height: 14),

          TextFormField(
            controller: _areaController,
            textInputAction: TextInputAction.next,
            decoration: listingInputDecoration(
              context,
              label: 'المنطقة',
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
              icon: Icons.phone_outlined,
            ),
            validator: validateContactPhone,
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    final colorScheme = Theme.of(context).colorScheme;

    // يتحدث عنوان الزر مع الكتابة دون إعادة بناء النموذج كله.
    return ListenableBuilder(
      listenable: Listenable.merge([
        _titleController,
        _descriptionController,
        _priceController,
        _areaController,
        _phoneController,
      ]),
      builder: (context, _) {
        final resubmit = _needsReview && _hasChanges;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: (_saving || _loadingImages) ? null : _saveChanges,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        resubmit ? Icons.send_outlined : Icons.save_outlined,
                        size: 21,
                      ),
                label: Text(
                  _saving
                      ? 'جاري الحفظ...'
                      : (resubmit ? 'حفظ وإرسال للمراجعة' : 'حفظ التعديلات'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            if (_saving && _progress != null) ...[
              const SizedBox(height: 10),
              Text(
                _progress!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _onBackPressed();
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text(
              'تعديل الإعلان',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
            ),
            centerTitle: true,
          ),
          body: _loadingCategories
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                    children: [
                      _buildStatusBanner(),

                      _buildDetailsSection(),

                      const SizedBox(height: 12),

                      ListingSectionCard(child: _buildImagesSection()),

                      const SizedBox(height: 12),

                      ListingSectionCard(
                        child: ListingPriceSection(
                          priceType: _priceType,
                          controller: _priceController,
                          onPriceTypeChanged: (value) {
                            setState(() => _priceType = value);
                          },
                        ),
                      ),

                      const SizedBox(height: 12),

                      ListingSectionCard(
                        child: ListingConditionSection(
                          condition: _condition,
                          onChanged: (value) {
                            setState(() => _condition = value);
                          },
                        ),
                      ),

                      const SizedBox(height: 12),

                      _buildContactSection(),

                      const SizedBox(height: 18),

                      _buildSaveButton(),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
