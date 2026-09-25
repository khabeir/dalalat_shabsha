import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'brand_theme.dart';

class SupportContactCard extends StatelessWidget {
  final String title;
  final String subtitle;

  // ============================================================
  // √—ﬁ«„ «·œ⁄„
  // €Ì¯— «·—ﬁ„Ì‰ ≈·Ï √—ﬁ«„ «·œ⁄„ «·ÕﬁÌﬁÌ….
  //
  // «” Œœ„ «·—ﬁ„ «·œÊ·Ì »œÊ‰ + œ«Œ· wa.me
  // „À«· «·”Êœ«‰:
  // 249912345678
  // ============================================================
  static const String whatsappNumber = '249912345678';
  static const String phoneNumber = '+249912345678';

  const SupportContactCard({
    super.key,
    required this.title,
    required this.subtitle,
  });

  // ============================================================
  // › Õ Ê« ”«»
  // ============================================================
  Future<void> _openWhatsApp(BuildContext context) async {
    final message = Uri.encodeComponent(
      '«·”·«„ ⁄·Ìﬂ„° √Õ «Ã „”«⁄œ… ›Ì  ÿ»Ìﬁ œ·«·… ‘»‘….',
    );

    final uri = Uri.parse(
      'https://wa.me/$whatsappNumber?text=$message',
    );

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        _showError(context, ' ⁄–— › Õ Ê« ”«»');
      }
    } catch (_) {
      if (context.mounted) {
        _showError(context, ' ⁄–— › Õ Ê« ”«»');
      }
    }
  }

  // ============================================================
  // «·« ’«·
  // ============================================================
  Future<void> _makePhoneCall(BuildContext context) async {
    final uri = Uri.parse('tel:$phoneNumber');

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && context.mounted) {
        _showError(context, ' ⁄–— › Õ  ÿ»Ìﬁ «·« ’«·');
      }
    } catch (_) {
      if (context.mounted) {
        _showError(context, ' ⁄–— › Õ  ÿ»Ìﬁ «·« ’«·');
      }
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Brand.primary.withValues(alpha: 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Brand.primary.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // ==================================================
            // “Œ—›… Œ·›Ì… »”Ìÿ…
            // ==================================================
            Positioned(
              top: -35,
              left: -25,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Brand.primary.withValues(alpha: 0.045),
                ),
              ),
            ),

            Positioned(
              bottom: -45,
              right: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Brand.primary.withValues(alpha: 0.04),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ==================================================
                  // «·⁄‰Ê«‰ + «·√ÌﬁÊ‰…
                  // ==================================================
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topRight,
                            end: Alignment.bottomLeft,
                            colors: [
                              Brand.primary,
                              Brand.primary.withValues(alpha: 0.78),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(17),
                          boxShadow: [
                            BoxShadow(
                              color: Brand.primary.withValues(alpha: 0.22),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.support_agent_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),

                      const SizedBox(width: 13),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Brand.ink,
                                fontSize: 15.5,
                                fontWeight: FontWeight.w900,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              subtitle,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Brand.ink.withValues(alpha: 0.62),
                                fontSize: 12.5,
                                height: 1.55,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 17),

                  // ==================================================
                  // Œÿ ›«’·
                  // ==================================================
                  Container(
                    height: 1,
                    color: Brand.ink.withValues(alpha: 0.07),
                  ),

                  const SizedBox(height: 15),

                  // ==================================================
                  // √“—«— «· Ê«’·
                  // ==================================================
                  Row(
                    children: [
                      // ------------------------------
                      // Ê« ”«»
                      // ------------------------------
                      Expanded(
                        child: _SupportButton(
                          icon: Icons.chat_rounded,
                          label: 'Ê« ”«»',
                          filled: true,
                          onPressed: () => _openWhatsApp(context),
                        ),
                      ),

                      const SizedBox(width: 10),

                      // ------------------------------
                      // « ’«·
                      // ------------------------------
                      Expanded(
                        child: _SupportButton(
                          icon: Icons.phone_rounded,
                          label: '« ’«·',
                          filled: false,
                          onPressed: () => _makePhoneCall(context),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 11),

                  // ==================================================
                  // „·«ÕŸ… ’€Ì—…
                  // ==================================================
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: Brand.ink.withValues(alpha: 0.45),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '‰Õ‰ Â‰« ·„”«⁄œ ﬂ',
                        style: TextStyle(
                          color: Brand.ink.withValues(alpha: 0.48),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =================================================================
// “— «·œ⁄„
// =================================================================

class _SupportButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onPressed;

  const _SupportButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(15),
        child: Ink(
          height: 46,
          decoration: BoxDecoration(
            color: filled
                ? Brand.primary
                : Brand.soft.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(15),
            border: filled
                ? null
                : Border.all(
                    color: Brand.primary.withValues(alpha: 0.12),
                  ),
            boxShadow: filled
                ? [
                    BoxShadow(
                      color: Brand.primary.withValues(alpha: 0.18),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: filled ? Colors.white : Brand.primary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : Brand.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}