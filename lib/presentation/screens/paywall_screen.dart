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
class PaywallScreen extends StatefulWidget {
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
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _svc = SubscriptionService.instance;

  Map<String, String> _prices     = {};
  bool  _loadingPrices = true;
  bool  _purchasing    = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadPrices();
  }

  Future<void> _loadPrices() async {
    try {
      final p = await _svc.getPriceStrings();
      if (mounted) setState(() { _prices = p; _loadingPrices = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingPrices = false);
    }
  }

  String _price(String androidId, String iosId, String fallback) {
    return _prices[androidId] ?? _prices[iosId] ?? fallback;
  }

  String get _monthlyPrice =>
      _price(ProductIds.monthlyAndroid, ProductIds.monthlyIos, '\$4.99/mes');

  String get _yearlyPrice =>
      _price(ProductIds.yearlyAndroid, ProductIds.yearlyIos, '\$29.99/año');

  Future<void> _startTrial() async {
    if (_purchasing) return;
    setState(() { _purchasing = true; _errorMsg = null; });
    try {
      await _svc.startTrial();
      if (mounted) widget.onSubscribed?.call();
    } catch (e) {
      if (mounted) setState(() => _errorMsg = 'No se pudo iniciar la prueba.');
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _purchase(PurchasePlan plan) async {
    if (_purchasing) return;
    setState(() { _purchasing = true; _errorMsg = null; });
    try {
      final result = await _svc.purchase(plan);
      if (!mounted) return;
      switch (result) {
        case PurchaseResult.success:
          widget.onSubscribed?.call();
          break;
        case PurchaseResult.cancelled:
          break; // user cancelled — no error message
        case PurchaseResult.notFound:
        case PurchaseResult.error:
          setState(() => _errorMsg = 'Error al procesar el pago. Intenta de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    if (_purchasing) return;
    setState(() { _purchasing = true; _errorMsg = null; });
    try {
      final result = await _svc.restorePurchases();
      if (!mounted) return;
      if (result == PurchaseResult.success) {
        widget.onSubscribed?.call();
      } else {
        setState(() => _errorMsg = 'No se encontraron compras activas para restaurar.');
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: NavaTheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Center(child: Container(width: 40, height: 4,
                decoration: BoxDecoration(color: NavaTheme.textMuted,
                    borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 24),

            const Text('🥁', style: TextStyle(fontSize: 64))
                .animate().scale(duration: 500.ms, curve: Curves.elasticOut),

            const SizedBox(height: 12),
            const Text('NavaDrummer Pro',
                style: TextStyle(fontFamily: 'DrummerDisplay', fontSize: 28,
                    color: NavaTheme.neonCyan, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
              'Accede a todo el catálogo · Coach de IA · Sin límites',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'DrummerBody', fontSize: 13,
                  color: NavaTheme.textMuted),
            ),

            const SizedBox(height: 24),

            // ── Feature list ──────────────────────────────────────────────
            ..._kFeatures.map((f) => _FeatureRow(f)).toList(),

            const SizedBox(height: 28),

            // ── Error message ──────────────────────────────────────────────
            if (_errorMsg != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: NavaTheme.hitMiss.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: NavaTheme.hitMiss.withOpacity(0.4)),
                ),
                child: Text(_errorMsg!, textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'DrummerBody',
                        fontSize: 12, color: NavaTheme.hitMiss)),
              ),
              const SizedBox(height: 16),
            ],

            // ── Buttons ────────────────────────────────────────────────────
            if (widget.showTrialOption) ...[
              _PlanButton(
                label:    'Probar 7 días GRATIS',
                sublabel: 'Sin cargo hasta que venza',
                color:    NavaTheme.neonCyan,
                icon:     Icons.star_outline,
                loading:  _purchasing,
                onTap:    _startTrial,
              ),
              const SizedBox(height: 12),
            ],

            _PlanButton(
              label:    _loadingPrices ? 'Mensual' : '$_monthlyPrice / mes',
              sublabel: 'Facturado mensualmente',
              color:    NavaTheme.neonGold,
              icon:     Icons.calendar_month_outlined,
              loading:  _purchasing,
              onTap:    () => _purchase(PurchasePlan.monthly),
            ),
            const SizedBox(height: 12),

            _PlanButton(
              label:    _loadingPrices ? 'Anual' : '$_yearlyPrice / año',
              sublabel: '¡Ahorra más del 40%!',
              color:    NavaTheme.neonPurple,
              icon:     Icons.workspace_premium_outlined,
              badge:    'MEJOR VALOR',
              loading:  _purchasing,
              onTap:    () => _purchase(PurchasePlan.yearly),
            ),

            const SizedBox(height: 20),

            // ── Restore & Dismiss ──────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _purchasing ? null : _restore,
                  child: const Text('Restaurar compra',
                      style: TextStyle(fontFamily: 'DrummerBody',
                          fontSize: 12, color: NavaTheme.textSecondary)),
                ),
                const Text(' · ', style: TextStyle(color: NavaTheme.textMuted)),
                TextButton(
                  onPressed: _purchasing ? null
                      : (widget.onDismiss ?? () => Navigator.pop(context)),
                  child: const Text('Ahora no',
                      style: TextStyle(fontFamily: 'DrummerBody',
                          fontSize: 12, color: NavaTheme.textMuted)),
                ),
              ],
            ),

            const SizedBox(height: 4),
            const Text(
              'La suscripción se renueva automáticamente. Cancela en cualquier momento.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'DrummerBody', fontSize: 9,
                  color: NavaTheme.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Feature list ──────────────────────────────────────────────────────────────
const _kFeatures = [
  _Feature('🎵', 'Catálogo completo de canciones'),
  _Feature('🧠', 'Coach de IA con análisis por batería'),
  _Feature('📊', 'Gráficos de progreso semanales'),
  _Feature('⚡', 'Modo rápido sin anuncios'),
  _Feature('🔔', 'Notificaciones de racha personalizadas'),
];

class _Feature {
  final String icon, label;
  const _Feature(this.icon, this.label);
}

class _FeatureRow extends StatelessWidget {
  final _Feature f;
  const _FeatureRow(this.f);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Text(f.icon, style: const TextStyle(fontSize: 18)),
      const SizedBox(width: 12),
      Text(f.label, style: const TextStyle(fontFamily: 'DrummerBody',
          fontSize: 13, color: NavaTheme.textSecondary)),
    ]),
  );
}

// ── Plan button ───────────────────────────────────────────────────────────────
class _PlanButton extends StatelessWidget {
  final String   label, sublabel;
  final Color    color;
  final IconData icon;
  final String?  badge;
  final bool     loading;
  final VoidCallback onTap;

  const _PlanButton({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.icon,
    required this.loading,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: loading ? null : onTap,
    child: AnimatedOpacity(
      opacity: loading ? 0.6 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.55), width: 1.5),
          boxShadow: [BoxShadow(color: color.withOpacity(0.15), blurRadius: 12)],
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontFamily: 'DrummerBody', fontSize: 15,
                color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(sublabel, style: const TextStyle(fontFamily: 'DrummerBody',
                fontSize: 10, color: NavaTheme.textMuted)),
          ])),
          if (badge != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: color,
                  borderRadius: BorderRadius.circular(6)),
              child: Text(badge!, style: TextStyle(fontFamily: 'DrummerBody',
                  fontSize: 9, color: NavaTheme.background,
                  fontWeight: FontWeight.bold)),
            ),
          ] else if (loading) ...[
            SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: color)),
          ] else ...[
            Icon(Icons.chevron_right, color: color.withOpacity(0.6)),
          ],
        ]),
      ),
    ),
  );
}
