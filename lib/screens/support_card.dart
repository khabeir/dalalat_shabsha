import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand_theme.dart';

class SupportContactCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String whatsappNumber;
  final String phoneNumber;

  const SupportContactCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.whatsappNumber = '',
    this.phoneNumber = '',
  });

  Future<void> _openWhatsApp(BuildContext context) async {
    final number = whatsappNumber.replaceAll(RegExp(r'[^0-9]'), '');

    if (number.isEmpty) {
      _message(context, 'لم يتم إعداد رقم واتساب الدعم بعد.');
      return;
    }

    final uri = Uri.parse('https://wa.me/$number');

    try {
      if (!await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      )) {
        _message(context, 'تعذر فتح واتساب.');
      }
    } catch (_) {
      _message(context, 'تعذر فتح واتساب.');
    }
  }

  Future<void> _call(BuildContext context) async {
    if (phoneNumber.trim().isEmpty) {
      _message(context, 'لم يتم إعداد رقم هاتف الدعم بعد.');
      return;
    }

    final uri = Uri(
      scheme: 'tel',
      path: phoneNumber.trim(),
    );

    try {
      if (!await launchUrl(uri)) {
        _message(context, 'تعذر فتح تطبيق الاتصال.');
      }
    } catch (_) {
      _message(context, 'تعذر إجراء الاتصال.');
    }
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            textDirection: TextDirection.rtl,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final hasWhatsApp = whatsappNumber.trim().isNotEmpty;
    final hasPhone = phoneNumber.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Brand.soft,
            Theme.of(context).cardColor,
          ],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Brand.primary.withValues(alpha: 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Brand.primary.withValues(alpha: 0.10),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Brand.primary,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: Colors.white,
                  size: 29,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Brand.ink,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Brand.ink.withValues(alpha: 0.62),
                        fontSize: 12.5,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Container(
            height: 1,
            color: Brand.primary.withValues(alpha: 0.08),
          ),

          const SizedBox(height: 15),

          Row(
            children: [
              if (hasWhatsApp)
                Expanded(
                  child: _SupportButton(
                    icon: Icons.chat_rounded,
                    label: 'واتساب',
                    filled: true,
                    onTap: () => _openWhatsApp(context),
                  ),
                ),

              if (hasWhatsApp && hasPhone)
                const SizedBox(width: 10),

              if (hasPhone)
                Expanded(
                  child: _SupportButton(
                    icon: Icons.phone_rounded,
                    label: 'اتصال',
                    filled: false,
                    onTap: () => _call(context),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _SupportButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Material(
        color: filled ? Brand.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: filled
                  ? null
                  : Border.all(
                      color: Brand.primary.withValues(alpha: 0.25),
                    ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: filled ? Colors.white : Brand.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: filled ? Colors.white : Brand.primary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
