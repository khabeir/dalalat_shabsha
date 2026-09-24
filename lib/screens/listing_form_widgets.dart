import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

// =============================================================
// عناصر مشتركة بين شاشة إضافة الإعلان وشاشة تعديله
// =============================================================

const int kMaxListingImages = 6;
const int kMaxTitleLength = 80;
const int kMaxDescriptionLength = 1000;
const String kListingImagesBucket = 'listing-images';

// قيم عمود condition في قاعدة البيانات.
const Map<String, String> kConditionOptions = {
  'new': 'جديد',
  'used': 'مستعمل',
  'not_applicable': 'لا ينطبق',
};

// =========================
// الأرقام والتحقق
// =========================

// تحويل الأرقام العربية (٠١٢) والفارسية إلى غربية، وفواصلها إلى , و .
String toWesternDigits(String input) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const easternPersian = '۰۱۲۳۴۵۶۷۸۹';

  final buffer = StringBuffer();

  for (final char in input.split('')) {
    var index = arabicIndic.indexOf(char);

    if (index == -1) index = easternPersian.indexOf(char);

    if (index != -1) {
      buffer.write(index);
      continue;
    }

    switch (char) {
      case '٫':
        buffer.write('.');
        break;
      case '٬':
      case '،':
        buffer.write(',');
        break;
      default:
        buffer.write(char);
    }
  }

  return buffer.toString();
}

// يقبل 250000 و 250,000 و ٢٥٠٠٠٠.
double? parsePrice(String input) {
  final cleaned = toWesternDigits(input).replaceAll(RegExp(r'[,\s]'), '');

  if (cleaned.isEmpty) return null;

  return double.tryParse(cleaned);
}

String? validatePriceInput(String? value) {
  final text = value?.trim() ?? '';

  if (text.isEmpty) return 'أدخل السعر';

  final price = parsePrice(text);

  if (price == null || price <= 0) return 'أدخل سعراً صحيحاً';
  if (price > 1000000000000) return 'السعر كبير جداً';

  return null;
}

String? validateContactPhone(String? value) {
  final digits =
      toWesternDigits(value ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  if (digits.isEmpty) return 'أدخل رقم التواصل';

  if (digits.length < 9 || digits.length > 15) {
    return 'رقم الهاتف غير صحيح';
  }

  return null;
}

String? validateListingTitle(String? value) {
  final text = value?.trim() ?? '';

  if (text.isEmpty) return 'أدخل عنوان الإعلان';
  if (text.length < 3) return 'العنوان قصير جداً';

  return null;
}

// رقم بأرقام غربية مع إبقاء علامة + إن وُجدت.
String cleanPhone(String value) {
  return toWesternDigits(value).replaceAll(RegExp(r'[^0-9+]'), '');
}

// =========================
// الصور
// =========================
String imageExtension(String path) {
  final ext = path.contains('.') ? path.split('.').last.toLowerCase() : 'jpg';

  switch (ext) {
    case 'jpeg':
      return 'jpg';
    case 'png':
    case 'webp':
    case 'heic':
    case 'gif':
    case 'jpg':
      return ext;
    default:
      return 'jpg';
  }
}

String imageContentType(String extension) {
  switch (extension) {
    case 'png':
      return 'image/png';
    case 'webp':
      return 'image/webp';
    case 'heic':
      return 'image/heic';
    case 'gif':
      return 'image/gif';
    default:
      return 'image/jpeg';
  }
}

// رفع صورة وتسجيلها في listing_images (مع محاولة ثانية عند تعثر الشبكة).
// إن فشل التسجيل بعد الرفع يُحذف الملف حتى لا يبقى يتيماً.
Future<void> uploadListingImage({
  required SupabaseClient supabase,
  required int listingId,
  required XFile image,
  required int fileIndex,
  required int sortOrder,
}) async {
  final extension = imageExtension(image.path);

  final path =
      '$listingId/${DateTime.now().millisecondsSinceEpoch}_$fileIndex.$extension';

  final bytes = await image.readAsBytes();

  Object? lastError;

  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      await supabase.storage.from(kListingImagesBucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              contentType: imageContentType(extension),
              upsert: false,
            ),
          );

      lastError = null;
      break;
    } catch (e) {
      // في المحاولة الثانية قد يكون الرفع الأول نجح فعلاً.
      final alreadyExists = attempt > 0 &&
          e is StorageException &&
          (e.statusCode == '409' ||
              e.message.toLowerCase().contains('exist'));

      if (alreadyExists) {
        lastError = null;
        break;
      }

      lastError = e;

      await Future.delayed(const Duration(milliseconds: 700));
    }
  }

  if (lastError != null) throw lastError;

  try {
    await supabase.from('listing_images').insert({
      'listing_id': listingId,
      'image_path': path,
      'sort_order': sortOrder,
    });
  } catch (e) {
    try {
      await supabase.storage.from(kListingImagesBucket).remove([path]);
    } catch (_) {}

    rethrow;
  }
}

// اختيار الصور من الكاميرا أو المعرض.
Future<List<XFile>> pickListingImages(
  BuildContext context,
  ImagePicker picker, {
  required int remaining,
}) async {
  void snack(String message) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  if (remaining <= 0) {
    snack('الحد الأقصى $kMaxListingImages صور للإعلان');
    return [];
  }

  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('التقاط صورة بالكاميرا'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('اختيار من المعرض'),
                onTap: () => Navigator.pop(sheetContext, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );

  if (source == null) return [];

  try {
    if (source == ImageSource.camera) {
      final image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
        maxHeight: 1600,
      );

      return image == null ? [] : [image];
    }

    final images = await picker.pickMultiImage(
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1600,
    );

    if (images.length > remaining) {
      snack('تمت إضافة $remaining صور فقط، فالحد الأقصى $kMaxListingImages');
    }

    return images.take(remaining).toList();
  } catch (e) {
    debugPrint('pickListingImages error: $e');
    snack('تعذر اختيار الصور');
    return [];
  }
}

// صورة في نموذج الإعلان: جديدة من الجهاز أو موجودة على الخادم.
class ListingImageItem {
  final XFile? file;
  final String? url;
  final int? id;
  final String? path;
  final int? sortOrder;

  const ListingImageItem.local(XFile this.file)
      : url = null,
        id = null,
        path = null,
        sortOrder = null;

  const ListingImageItem.remote({
    required this.id,
    required this.path,
    required this.url,
    this.sortOrder,
  }) : file = null;

  bool get isLocal => file != null;

  // مفتاح ثابت لمقارنة الحالة قبل التعديل وبعده.
  String get key => isLocal ? 'new:${file!.path}' : 'img:$id';
}

// =========================
// شكل الحقول والأقسام
// =========================
InputDecoration listingInputDecoration(
  BuildContext context, {
  required String label,
  required IconData icon,
  String? hint,
  String? helper,
  bool alignLabelWithHint = false,
}) {
  final colorScheme = Theme.of(context).colorScheme;

  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    alignLabelWithHint: alignLabelWithHint,
    prefixIcon: Icon(icon, size: 21),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    labelStyle: const TextStyle(fontSize: 14),
    hintStyle: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
  );
}

class ListingSectionCard extends StatelessWidget {
  final Widget child;

  const ListingSectionCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class ListingSectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;

  const ListingSectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: colorScheme.primary),
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
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// =========================
// حقل التصنيف
// =========================
class ListingCategoryField extends StatelessWidget {
  final List<Map<String, dynamic>> categories;
  final int? value;
  final ValueChanged<int?> onChanged;

  const ListingCategoryField({
    super.key,
    required this.categories,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasValue =
        value != null && categories.any((category) => category['id'] == value);

    return DropdownButtonFormField<int>(
      initialValue: hasValue ? value : null,
      isExpanded: true,
      decoration: listingInputDecoration(
        context,
        label: 'التصنيف',
        icon: Icons.category_outlined,
      ),
      items: categories.where((category) => category['id'] is int).map((c) {
        final icon = c['icon']?.toString().trim() ?? '';
        final name = c['name']?.toString() ?? '';

        return DropdownMenuItem<int>(
          value: c['id'] as int,
          child: Text(
            icon.isEmpty ? name : '$icon $name',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
        );
      }).toList(),
      onChanged: onChanged,
      validator: (selected) => selected == null ? 'اختر التصنيف' : null,
    );
  }
}

// =========================
// قسم السعر
// =========================
class ListingPriceSection extends StatelessWidget {
  final String priceType;
  final ValueChanged<String> onPriceTypeChanged;
  final TextEditingController controller;

  const ListingPriceSection({
    super.key,
    required this.priceType,
    required this.onPriceTypeChanged,
    required this.controller,
  });

  static final _numberFormat = NumberFormat('#,##0.##', 'en');

  String? _helper(String text) {
    final price = parsePrice(text);

    if (price == null || price <= 0) return null;

    return 'السعر: ${_numberFormat.format(price)} جنيه';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListingSectionTitle(
          icon: Icons.payments_outlined,
          title: 'السعر',
          subtitle: 'حدد طريقة عرض السعر',
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'fixed',
                label: Text('ثابت', style: TextStyle(fontSize: 12)),
              ),
              ButtonSegment(
                value: 'negotiable',
                label: Text('قابل للتفاوض', style: TextStyle(fontSize: 12)),
              ),
              ButtonSegment(
                value: 'contact',
                label: Text('عند التواصل', style: TextStyle(fontSize: 12)),
              ),
            ],
            selected: {priceType},
            showSelectedIcon: false,
            onSelectionChanged: (selection) {
              onPriceTypeChanged(selection.first);
            },
          ),
        ),
        if (priceType != 'contact') ...[
          const SizedBox(height: 12),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              return TextFormField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[0-9٠-٩۰-۹.,٫٬]'),
                  ),
                ],
                decoration: listingInputDecoration(
                  context,
                  label: 'السعر بالجنيه السوداني',
                  hint: 'مثال: 250000',
                  icon: Icons.price_change_outlined,
                  helper: _helper(value.text),
                ),
                validator: validatePriceInput,
              );
            },
          ),
        ],
      ],
    );
  }
}

// =========================
// قسم حالة السلعة
// =========================
class ListingConditionSection extends StatelessWidget {
  final String condition;
  final ValueChanged<String> onChanged;

  const ListingConditionSection({
    super.key,
    required this.condition,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected =
        kConditionOptions.containsKey(condition) ? condition : 'used';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListingSectionTitle(
          icon: Icons.inventory_2_outlined,
          title: 'حالة السلعة',
          subtitle: 'اختر "لا ينطبق" للخدمات والوظائف',
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            segments: [
              for (final option in kConditionOptions.entries)
                ButtonSegment(
                  value: option.key,
                  label: Text(
                    option.value,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
            selected: {selected},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ),
      ],
    );
  }
}

// =========================
// قسم الصور
// =========================
class ListingImagesSection extends StatelessWidget {
  final List<ListingImageItem> items;
  final bool enabled;
  final bool showNewBadge;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onMakeCover;

  const ListingImagesSection({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRemove,
    required this.onMakeCover,
    this.enabled = true,
    this.showNewBadge = false,
  });

  static const double _size = 96;

  Widget _buildImage(BuildContext context, ListingImageItem item) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget placeholder() {
      return Container(
        color: colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (item.isLocal) {
      return Image.file(
        File(item.file!.path),
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        cacheWidth: 300,
        errorBuilder: (_, __, ___) => placeholder(),
      );
    }

    return CachedNetworkImage(
      imageUrl: item.url ?? '',
      width: _size,
      height: _size,
      fit: BoxFit.cover,
      memCacheWidth: 300,
      placeholder: (_, __) => Container(
        color: colorScheme.surfaceContainerHighest,
      ),
      errorWidget: (_, __, ___) => placeholder(),
    );
  }

  Widget _buildThumb(BuildContext context, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final item = items[index];

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: index == 0
                      ? colorScheme.primary
                      : colorScheme.outlineVariant,
                  width: index == 0 ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildImage(context, item),
            ),
          ),

          // زر الحذف
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: Colors.red,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? () => onRemove(index) : null,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, color: Colors.white, size: 16),
                ),
              ),
            ),
          ),

          // الغلاف أو زر تعيين الغلاف
          if (index == 0)
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  'الغلاف',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colorScheme.onPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else
            Positioned(
              bottom: 4,
              left: 4,
              child: Tooltip(
                message: 'تعيين كصورة غلاف',
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: enabled ? () => onMakeCover(index) : null,
                    child: const Padding(
                      padding: EdgeInsets.all(5),
                      child: Icon(
                        Icons.star_outline,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          if (showNewBadge && item.isLocal)
            Positioned(
              top: 4,
              left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text(
                  'جديدة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddTile(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: enabled ? onAdd : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 28,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 4),
            Text(
              'إضافة',
              style: TextStyle(fontSize: 12, color: colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListingSectionTitle(
          icon: Icons.photo_library_outlined,
          title: 'صور الإعلان',
          subtitle: 'أضف حتى $kMaxListingImages صور، والأولى تظهر كغلاف',
        ),
        const SizedBox(height: 14),

        if (items.isEmpty)
          InkWell(
            onTap: enabled ? onAdd : null,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 36,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'اضغط لإضافة صور',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'الإعلانات المصورة تحصل على تواصل أكثر',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          SizedBox(
            height: _size + 10,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(top: 8, right: 6, left: 6),
              itemCount:
                  items.length + (items.length < kMaxListingImages ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index == items.length) return _buildAddTile(context);

                return _buildThumb(context, index);
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${items.length} / $kMaxListingImages صور',
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

// =========================
// حوارات مشتركة
// =========================
Future<bool> confirmListingDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: destructive
                  ? FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700,
                    )
                  : null,
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );
    },
  );

  return result == true;
}
