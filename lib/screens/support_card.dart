import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// بيانات الدعم في مكان واحد: عدّلها هنا فتتغير في كل الشاشات.
const String kSupportPhone = '0914111214';
const String kSupportWhatsApp = '249914111214';

// بطاقة "تواصل معنا" (اتصال + واتساب) تُستخدم في التسجيل وإضافة الإعلان.
class SupportContactCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String phoneNumber;
  final String whatsappNumber;

  const SupportContactCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.phoneNumber = kSupportPhone,
    this.whatsappNumber = kSupportWhatsApp,
  });

  Future<void> _launch(BuildContext context, Uri uri, String error) async {
    var ok = false;

    try {
      ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _launch(
                    context,
                    Uri(scheme: 'tel', path: phoneNumber),
                    'تعذر فتح تطبيق الاتصال',
                  ),
                  icon: const Icon(Icons.phone_outlined),
                  label: const Text('اتصال'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _launch(
                    context,
                    Uri.parse('https://wa.me/$whatsappNumber'),
                    'تعذر فتح واتساب',
                  ),
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('واتساب'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            phoneNumber,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}
