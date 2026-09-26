import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_decorations.dart';

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

String toWesternDigits(String input) {
  const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
  const easternPersian = '۰۱۲۳۴۵۶۷۸۹';

  final buffer = StringBuffer();

  for (final char in input.split('')) {
    var index = arabicIndic.indexOf(char);

    if (index == -1) {
      index = easternPersian.indexOf(char);
    }

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

  if (price == null || price <= 0) {
    return 'أدخل سعراً صحيحاً';
  }

  if (price > 1000000000000) {
    return 'السعر كبير جداً';
  }

  return null;
}

String? validateContactPhone(String? value) {
  final digits =
      toWesternDigits(value ?? '').replaceAll(RegExp(r'[^0-9]'), '');

  if (digits.isEmpty) {
    return 'أدخل رقم التواصل';
  }

  if (digits.length < 9 || digits.length > 15) {
    return 'رقم الهاتف غير صحيح';
  }

  return null;
}

String? validateListingTitle(String? value) {
  final text = value?.trim() ?? '';

  if (text.isEmpty) {
    return 'أدخل عنوان الإعلان';
  }

  if (text.length < 3) {
    return 'العنوان قصير جداً';
  }

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
  final ext =
      path.contains('.') ? path.split('.').last.toLowerCase() : 'jpg';

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

// رفع صورة وتسجيلها في listing_images.
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

  if (lastError != null) {
    throw lastError;
  }

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
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.ink,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
  }

  if (remaining <= 0) {
    snack('الحد الأقصى $kMaxListingImages صور للإعلان');
    return [];
  }

  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(24),
      ),
    ),
    builder: (sheetContext) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'إضافة صور الإعلان',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'اختر مصدر الصور',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                _ImageSourceTile(
                  icon: Icons.photo_camera_outlined,
                  title: 'التقاط صورة بالكاميرا',
                  subtitle: 'التقاط صورة جديدة الآن',
                  onTap: () =>
                      Navigator.pop(sheetContext, ImageSource.camera),
                ),
                const SizedBox(height: 8),
                _ImageSourceTile(
                  icon: Icons.photo_library_outlined,
                  title: 'اختيار من المعرض',
                  subtitle: 'اختيار صور موجودة في الهاتف',
                  onTap: () =>
                      Navigator.pop(sheetContext, ImageSource.gallery),
                ),
              ],
            ),
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
      snack(
        'تمت إضافة $remaining صور فقط، '
        'فالحد الأقصى $kMaxListingImages',
      );
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

  final enabledBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(
      color: AppColors.brand.withValues(alpha: 0.14),
      width: 1,
    ),
  );

  final focusedBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: const BorderSide(
      color: AppColors.brand,
      width: 1.7,
    ),
  );

  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    alignLabelWithHint: alignLabelWithHint,
    prefixIcon: Icon(
      icon,
      size: 21,
      color: colorScheme.onSurfaceVariant,
    ),
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    ),
    enabledBorder: enabledBorder,
    focusedBorder: focusedBorder,
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: colorScheme.error.withValues(alpha: 0.65),
      ),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: colorScheme.error,
        width: 1.7,
      ),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 14,
    ),
    labelStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    ),
    floatingLabelStyle: const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w800,
      color: AppColors.brand,
    ),
    hintStyle: TextStyle(
      fontSize: 13,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
    ),
    helperStyle: const TextStyle(
      fontSize: 11.5,
      color: AppColors.ink,
    ),
    errorStyle: TextStyle(
      fontSize: 11.5,
      color: colorScheme.error,
      fontWeight: FontWeight.w600,
    ),
  );
}

class ListingSectionCard extends StatelessWidget {
  final Widget child;

  const ListingSectionCard({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppDecorations.card(),
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
    this.subtitle,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                AppColors.brand,
                AppColors.brandDark,
              ],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: AppColors.brand.withValues(alpha: 0.16),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 20,
            color: Colors.white,
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
                  height: 1.25,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
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
        hint: 'اختر تصنيف الإعلان',
      ),
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(14),
      items: categories
          .where((category) => category['id'] is int)
          .map((c) {
        final icon = c['icon']?.toString().trim() ?? '';
        final name = c['name']?.toString() ?? '';

        return DropdownMenuItem<int>(
          value: c['id'] as int,
          child: Text(
            icon.isEmpty ? name : '$icon $name',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
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
        _buildSegmentedButton(context),
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

  Widget _buildSegmentedButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
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
        selected: {priceType},
        showSelectedIcon: false,
        style: ButtonStyle(
          side: WidgetStateProperty.resolveWith(
            (states) {
              if (states.contains(WidgetState.selected)) {
                return const BorderSide(
                  color: AppColors.brand,
                  width: 1.2,
                );
              }

              return BorderSide(
                color: AppColors.brand.withValues(alpha: 0.15),
              );
            },
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.brandSoft;
              }

              return Colors.white;
            },
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) {
              if (states.contains(WidgetState.selected)) {
                return AppColors.brandDark;
              }

              return AppColors.ink;
            },
          ),
          textStyle: WidgetStateProperty.all(
            const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
        onSelectionChanged: (selection) {
          onPriceTypeChanged(selection.first);
        },
      ),
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
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
            selected: {selected},
            showSelectedIcon: false,
            style: ButtonStyle(
              side: WidgetStateProperty.resolveWith(
                (states) {
                  if (states.contains(WidgetState.selected)) {
                    return const BorderSide(
                      color: AppColors.brand,
                      width: 1.2,
                    );
                  }

                  return BorderSide(
                    color: AppColors.brand.withValues(alpha: 0.15),
                  );
                },
              ),
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.brandSoft;
                  }

                  return Colors.white;
                },
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) {
                  if (states.contains(WidgetState.selected)) {
                    return AppColors.brandDark;
                  }

                  return AppColors.ink;
                },
              ),
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
            onSelectionChanged: (selection) {
              onChanged(selection.first);
            },
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

  Widget _buildImage(
    BuildContext context,
    ListingImageItem item,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget placeholder() {
      return Container(
        color: AppColors.brandSoft,
        child: const Icon(
          Icons.broken_image_outlined,
          color: AppColors.brand,
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
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.brand,
            ),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => placeholder(),
    );
  }

  Widget _buildThumb(
    BuildContext context,
    int index,
  ) {
    final item = items[index];
    final isCover = index == 0;

    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isCover
                      ? AppColors.brand
                      : AppColors.brand.withValues(alpha: 0.16),
                  width: isCover ? 2.2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.brand.withValues(
                      alpha: isCover ? 0.12 : 0.05,
                    ),
                    blurRadius: isCover ? 8 : 5,
                    offset: const Offset(0, 2),
                  ),
                ],
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
              color: Colors.red.shade600,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: enabled ? () => onRemove(index) : null,
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

          // الغلاف أو زر تعيين الغلاف
          if (isCover)
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      AppColors.brandDark,
                      AppColors.brand,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text(
                  'الغلاف',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
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
                  color: AppColors.ink.withValues(alpha: 0.72),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Text(
                  'جديدة',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddTile(BuildContext context) {
    return InkWell(
      onTap: enabled ? onAdd : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          color: AppColors.brandSoft.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.brand.withValues(alpha: 0.22),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.add_photo_alternate_outlined,
              size: 28,
              color: AppColors.brand,
            ),
            const SizedBox(height: 4),
            const Text(
              'إضافة',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.brandDark,
                fontWeight: FontWeight.w800,
              ),
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
        const ListingSectionTitle(
          icon: Icons.photo_library_outlined,
          title: 'صور الإعلان',
          subtitle: 'أضف حتى $kMaxListingImages صور، والأولى تظهر كغلاف',
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          InkWell(
            onTap: enabled ? onAdd : null,
            borderRadius: BorderRadius.circular(15),
            child: Container(
              height: 120,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.brandSoft.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: AppColors.brand.withValues(alpha: 0.18),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.brand.withValues(alpha: 0.10),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 30,
                      color: AppColors.brand,
                    ),
                  ),
                  const SizedBox(height: 7),
                  const Text(
                    'اضغط لإضافة صور',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brandDark,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'الإعلانات المصورة تحصل على تواصل أكثر',
                    style: TextStyle(
                      fontSize: 11.5,
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
              padding: const EdgeInsets.only(
                top: 8,
                right: 6,
                left: 6,
              ),
              itemCount:
                  items.length + (items.length < kMaxListingImages ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                if (index == items.length) {
                  return _buildAddTile(context);
                }

                return _buildThumb(context, index);
              },
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.photo_library_outlined,
                size: 15,
                color: AppColors.brand,
              ),
              const SizedBox(width: 5),
              Text(
                '${items.length} / $kMaxListingImages صور',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// =========================
// حوار مصدر الصور
// =========================

class _ImageSourceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ImageSourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.brandSoft.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: AppColors.brand,
                  size: 23,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_left_rounded,
                color: AppColors.brand,
              ),
            ],
          ),
        ),
      ),
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
      final colorScheme = Theme.of(dialogContext).colorScheme;

      return Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: AppColors.brandSoft,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: destructive
                      ? colorScheme.errorContainer
                      : AppColors.brandSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  destructive
                      ? Icons.warning_amber_rounded
                      : Icons.help_outline_rounded,
                  size: 21,
                  color: destructive
                      ? colorScheme.onErrorContainer
                      : AppColors.brand,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ink,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(
                'إلغاء',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor:
                    destructive ? colorScheme.error : AppColors.brand,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 11,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                confirmLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  return result == true;
}