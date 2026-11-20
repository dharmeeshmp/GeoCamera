import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdConfig {
  /// Google AdMob official test banner ad unit ID
  static const String bannerAdUnitId = 'ca-app-pub-3940256099942544/6300978111';

  /// Google AdMob official test native ad unit ID (defaulting to test ID in kDebugMode)
  static String get galleryNativeAdUnitId => kDebugMode
      ? 'ca-app-pub-3940256099942544/2247696110'
      : 'ca-app-pub-3940256099942544/2247696110';

  /// Google AdMob official test gallery banner ad unit ID
  static String get galleryBannerAdUnitId => kDebugMode
      ? 'ca-app-pub-3940256099942544/6300978111'
      : 'ca-app-pub-3940256099942544/6300978111';

  static Future<void>? _adsInitFuture;

  /// Thread-safe lazy AdMob SDK initialization ensuring initialization happens once
  /// and never blocks cold start or camera preview initialization.
  static Future<void> ensureInitialized() {
    return _adsInitFuture ??= () async {
      await MobileAds.instance.initialize();
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(testDeviceIds: const []),
      );
    }();
  }
}
