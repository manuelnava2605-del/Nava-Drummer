// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Monetización  (Fase 6)
// Suscripción · Paywall · Trial 7 días · GateKeeper
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/subscription_service.dart';
import '../../domain/entities/entities.dart';
import '../theme/nava_theme.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SubscriptionService  — gestiona estado de suscripción localmente
// En producción conectar con RevenueCat / in_app_purchase
// ═══════════════════════════════════════════════════════════════════════════

class GateKeeper {
  /// Returns true if user can play. If false, shows paywall.
  static Future<bool> checkAccess(
      BuildContext context, Song song) async {
    final svc = SubscriptionService.instance;
    await svc.init();
    if (svc.canPlay(song)) return true;

    // Show paywall
    final subscribed = await showModalBottomSheet<bool>(
      context:      context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.92,
        child: PaywallScreen(
          onSubscribed: () => Navigator.pop(context, true),
          onDismiss:    () => Navigator.pop(context, false),
          showTrialOption: !svc.trialUsed,
        ),
      ),
    );

    return subscribed == true;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Trial Reminder Banner
// ═══════════════════════════════════════════════════════════════════════════
class TrialReminderBanner extends StatelessWidget {
  const TrialReminderBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final svc  = SubscriptionService.instance;
    final days = svc.trialDaysLeft;
    if (svc.status != SubscriptionStatus.trial) return const SizedBox();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: NavaTheme.neonGold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NavaTheme.neonGold.withOpacity(0.4)),
      ),
      child: Row(children: [
        const Text('⏳', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Text(
          days > 1
              ? 'Tu prueba gratuita vence en $days días'
              : days == 1
                  ? '¡Tu prueba vence mañana!'
                  : '¡Tu prueba vence hoy!',
          style: const TextStyle(fontFamily: 'DrummerBody', fontSize: 12,
              color: NavaTheme.neonGold))),
        GestureDetector(
          onTap: () => showModalBottomSheet(
            context: context, isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => SizedBox(
              height: MediaQuery.of(context).size.height * 0.9,
              child: PaywallScreen(
                onSubscribed: () => Navigator.pop(context),
                showTrialOption: false,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: NavaTheme.neonGold,
                borderRadius: BorderRadius.circular(6)),
            child: const Text('SUSCRIBIR', style: TextStyle(fontFamily: 'DrummerBody',
                fontSize: 10, color: NavaTheme.background, fontWeight: FontWeight.bold)),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PaywallScreen
// ═══════════════════════════════════════════════════════════════════════════
class PaywallScreen extends StatelessWidget {
  final VoidCallback? onSubscribed;
  final VoidCallback? onDismiss;
  final bool showTrialOption;

  const PaywallScreen({
    super.key,
    this.onSubscribed,
    this.onDismiss,
    this.showTrialOption = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: NavaTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: NavaTheme.textMuted,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 24),
          const Text('🥁', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          const Text('NavaDrummer Pro',
              style: TextStyle(fontFamily: 'DrummerDisplay', fontSize: 28,
                  color: NavaTheme.neonCyan, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Accede a todo el catálogo de canciones\ny funciones premium.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'DrummerBody', fontSize: 14,
                  color: NavaTheme.textMuted)),
          const SizedBox(height: 32),
          if (showTrialOption) ...[
            _ProButton(
              label: 'Iniciar prueba de 7 días GRATIS',
              color: NavaTheme.neonCyan,
              onTap: () async {
                await SubscriptionService.instance.startTrial();
                onSubscribed?.call();
              },
            ),
            const SizedBox(height: 12),
          ],
          _ProButton(
            label: 'Suscribirse — \$4.99 / mes',
            color: NavaTheme.neonGold,
            onTap: () async {
              await SubscriptionService.instance.purchase(PurchasePlan.monthly);
              onSubscribed?.call();
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onDismiss ?? () => Navigator.pop(context),
            child: const Text('Ahora no',
                style: TextStyle(fontFamily: 'DrummerBody',
                    color: NavaTheme.textMuted)),
          ),
        ],
      ),
    );
  }
}

class _ProButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ProButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      alignment: Alignment.center,
      child: Text(label,
          style: TextStyle(fontFamily: 'DrummerBody', fontSize: 15,
              color: color, fontWeight: FontWeight.bold)),
    ),
  );
}
