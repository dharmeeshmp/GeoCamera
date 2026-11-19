import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ReviewService {
  static const String _keySuccessfulCaptures = 'successful_captures_count';
  static const String _keyHasRequestedReview = 'has_requested_in_app_review';

  /// Records a successful photo or video capture.
  /// Automatically prompts for an in-app review on the 3rd successful capture.
  static Future<void> recordSuccessfulCapture() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentCount = (prefs.getInt(_keySuccessfulCaptures) ?? 0) + 1;
      await prefs.setInt(_keySuccessfulCaptures, currentCount);

      final hasRequested = prefs.getBool(_keyHasRequestedReview) ?? false;

      if (currentCount == 3 && !hasRequested) {
        final InAppReview inAppReview = InAppReview.instance;
        if (await inAppReview.isAvailable()) {
          // Wait 800ms so the save SnackBar settles cleanly before prompting
          await Future.delayed(const Duration(milliseconds: 800));
          await prefs.setBool(_keyHasRequestedReview, true);
          await inAppReview.requestReview();
        }
      }
    } catch (e) {
      debugPrint('ReviewService error recording capture: $e');
    }
  }

  /// Opens the store listing for manual rating in Settings
  static Future<void> openStoreListing() async {
    try {
      final InAppReview inAppReview = InAppReview.instance;
      if (await inAppReview.isAvailable()) {
        await inAppReview.openStoreListing();
      } else {
        await inAppReview.requestReview();
      }
    } catch (e) {
      debugPrint('ReviewService error opening store listing: $e');
      try {
        await InAppReview.instance.requestReview();
      } catch (_) {}
    }
  }
}
