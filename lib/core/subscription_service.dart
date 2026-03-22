// ─────────────────────────────────────────────────────────────────────────────
// NavaDrummer — Subscription Service (RevenueCat)
// Replace TODO with real RevenueCat integration.
// ─────────────────────────────────────────────────────────────────────────────
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/entities/entities.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Product IDs — match exactly what you create in App Store / Play Console
// ─────────────────────────────────────────────────────────────────────────────
abstract class ProductIds {
  // iOS (App Store Connect)
  static const String monthlyIos = 'com.navadrummer.premium.monthly';
  static const String yearlyIos  = 'com.navadrummer.premium.yearly';

  // Android (Play Console)
  static const String monthlyAndroid = 'navadrummer_premium_monthly';
  static const String yearlyAndroid  = 'navadrummer_premium_yearly';

  // RevenueCat entitlement ID (configure in RevenueCat dashboard)
  static const String premiumEntitlement = 'premium';
}

// ─────────────────────────────────────────────────────────────────────────────
// RevenueCat API Keys — replace with yours from app.revenuecat.com
// ─────────────────────────────────────────────────────────────────────────────
abstract class RevenueCatKeys {
  static const String ios     = 'YOUR_REVENUECAT_IOS_KEY';      // appl_xxxxx
  static const String android = 'YOUR_REVENUECAT_ANDROID_KEY';  // goog_xxxxx
}

// ─────────────────────────────────────────────────────────────────────────────
class SubscriptionService {
  static final SubscriptionService instance = SubscriptionService._();
  SubscriptionService._();

  static const _kTrialUsed     = 'trial_used_v2';
  static const _kTrialStart    = 'trial_start_ms_v2';
  static const _kSessionCount  = 'session_count_v2';
  static const int trialDays   = 7;

  bool _initialized = false;
  CustomerInfo? _customerInfo;
  late SharedPreferences _prefs;

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<void> init({String? userId}) async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();

    try {
      await Purchases.setLogLevel(
          kDebugMode ? LogLevel.debug : LogLevel.error);

      final config = PurchasesConfiguration(
        defaultTargetPlatform == TargetPlatform.iOS
            ? RevenueCatKeys.ios
            : RevenueCatKeys.android,
      );

      await Purchases.configure(config);

      if (userId != null) {
        await Purchases.logIn(userId);
      }

      _customerInfo = await Purchases.getCustomerInfo();
      _initialized  = true;

      // Listen for subscription changes
      Purchases.addCustomerInfoUpdateListener((info) {
        _customerInfo = info;
      });
    } catch (e) {
      // RevenueCat unavailable — fall back to local state
      debugPrint('RevenueCat init failed: $e');
      _initialized = true; // mark as init so we don't retry every call
    }
  }

  // ── Status ─────────────────────────────────────────────────────────────────
  SubscriptionStatus get status {
    // 1. Check RevenueCat entitlement
    if (_hasPremiumEntitlement) return SubscriptionStatus.premium;
    // 2. Check local trial
    if (_isInTrial)              return SubscriptionStatus.trial;
    return SubscriptionStatus.free;
  }

  bool get _hasPremiumEntitlement {
    try {
      return _customerInfo
              ?.entitlements
              .active
              .containsKey(ProductIds.premiumEntitlement) ??
          false;
    } catch (_) {
      return _prefs.getBool('is_premium_local') ?? false;
    }
  }

  bool get _isInTrial {
    if (!(_prefs.getBool(_kTrialUsed) ?? false)) return false;
    final startMs = _prefs.getInt(_kTrialStart);
    if (startMs == null) return false;
    return DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(startMs))
            .inDays <
        trialDays;
  }

  bool get isPremium    => status != SubscriptionStatus.free;
  bool get trialUsed    => _prefs.getBool(_kTrialUsed) ?? false;
  int  get trialDaysLeft {
    final startMs = _prefs.getInt(_kTrialStart);
    if (startMs == null) return trialDays;
    return (trialDays -
            DateTime.now()
                .difference(DateTime.fromMillisecondsSinceEpoch(startMs))
                .inDays)
        .clamp(0, trialDays);
  }

  int  get sessionCount => _prefs.getInt(_kSessionCount) ?? 0;
  bool get shouldShowPaywall => !isPremium && sessionCount >= 3;
  bool canPlay(Song song)    => song.isUnlocked || isPremium;

  // ── Purchase ───────────────────────────────────────────────────────────────
  Future<PurchaseResult> purchase(PurchasePlan plan) async {
    await init();
    try {
      final productId = plan == PurchasePlan.monthly
          ? (defaultTargetPlatform == TargetPlatform.iOS
              ? ProductIds.monthlyIos
              : ProductIds.monthlyAndroid)
          : (defaultTargetPlatform == TargetPlatform.iOS
              ? ProductIds.yearlyIos
              : ProductIds.yearlyAndroid);

      final packages = await _getOfferings();
      final pkg      = packages.firstWhere(
        (p) => p.storeProduct.identifier == productId,
        orElse: () => packages.first,
      );

      _customerInfo = await Purchases.getCustomerInfo();
      await Purchases.purchasePackage(pkg);
      _customerInfo = await Purchases.getCustomerInfo();

      // Save local fallback
      await _prefs.setBool('is_premium_local', true);

      return PurchaseResult.success;
    } on PurchasesErrorCode catch (e) {
      if (e == PurchasesErrorCode.purchaseCancelledError) {
        return PurchaseResult.cancelled;
      }
      return PurchaseResult.error;
    } catch (_) {
      return PurchaseResult.error;
    }
  }

  Future<List<Package>> _getOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<PurchaseResult> restorePurchases() async {
    await init();
    try {
      _customerInfo = await Purchases.restorePurchases();
      return _hasPremiumEntitlement
          ? PurchaseResult.success
          : PurchaseResult.notFound;
    } catch (_) {
      return PurchaseResult.error;
    }
  }

  // ── Trial ──────────────────────────────────────────────────────────────────
  Future<void> startTrial() async {
    if (trialUsed) return;
    await _prefs.setBool(_kTrialUsed, true);
    await _prefs.setInt(
        _kTrialStart, DateTime.now().millisecondsSinceEpoch);
  }

  // ── Analytics helpers ──────────────────────────────────────────────────────
  Future<void> incrementSession() async {
    await _prefs.setInt(_kSessionCount, sessionCount + 1);
  }

  Future<void> setUserId(String uid) async {
    await init();
    try { await Purchases.logIn(uid); } catch (_) {}
  }

  // ── Pricing strings (from RevenueCat or fallback) ─────────────────────────
  Future<Map<String, String>> getPriceStrings() async {
    await init();
    try {
      final pkgs = await _getOfferings();
      final prices = <String, String>{};
      for (final p in pkgs) {
        final id = p.storeProduct.identifier;
        prices[id] = p.storeProduct.priceString;
      }
      return prices;
    } catch (_) {
      return {
        ProductIds.monthlyIos:     'USD \$4.99/mes',
        ProductIds.yearlyIos:      'USD \$29.99/año',
        ProductIds.monthlyAndroid: 'USD \$4.99/mes',
        ProductIds.yearlyAndroid:  'USD \$29.99/año',
      };
    }
  }
}

enum SubscriptionStatus { free, trial, premium }
enum PurchasePlan       { monthly, yearly }
enum PurchaseResult     { success, cancelled, notFound, error }
