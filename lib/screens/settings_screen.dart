import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/ad_config.dart';
import '../models/app_settings.dart';
import '../services/app_localizations.dart';
import '../services/review_service.dart';
import '../widgets/geo_stamp_overlay.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;

  // Custom B2B & Support Contact Information
  static const String businessEmail = 'sales@yourcompany.com';
  static const String businessWhatsApp = '919000000000'; // Country code + number without '+'

  const SettingsScreen({
    super.key,
    required this.settings,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _businessEmail = SettingsScreen.businessEmail;
  static const String _businessWhatsApp = SettingsScreen.businessWhatsApp;

  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAdaptiveBanner();
  }

  Future<void> _loadAdaptiveBanner() async {
    if (_bannerAd != null) return;

    await AdConfig.ensureInitialized();
    if (!mounted) return;

    final int width = MediaQuery.sizeOf(context).width.truncate();
    final AdSize? adaptiveSize =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(width);

    if (adaptiveSize == null || !mounted) return;

    final banner = BannerAd(
      adUnitId: AdConfig.bannerAdUnitId,
      size: adaptiveSize,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _bannerAd = ad as BannerAd;
            _isBannerLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );

    await banner.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: AppLocaleController.localeNotifier,
      builder: (context, locale, _) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final s = widget.settings;

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: Text(
              tr('settings'),
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            backgroundColor: theme.appBarTheme.backgroundColor,
            foregroundColor: theme.colorScheme.onSurface,
            elevation: 0.5,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // ====================================================
              // SECTION 0: APPEARANCE (Theme Mode Toggle)
              // ====================================================
              _buildSectionHeader(tr('appearance').toUpperCase()),
              _buildCard(
                children: [
                  _buildSwitchTile(
                    icon: isDark ? Icons.dark_mode : Icons.light_mode,
                    iconColor: isDark ? Colors.blueAccent : Colors.amber,
                    title: tr('dark_mode'),
                    subtitle: tr('dark_mode_desc'),
                    value: appThemeNotifier.value == ThemeMode.dark,
                    onChanged: (val) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('is_dark_mode', val);
                      appThemeNotifier.value =
                          val ? ThemeMode.dark : ThemeMode.light;
                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ====================================================
              // SECTION 1: SELECT TEMPLATE (2 Visual Preview Cards)
              // ====================================================
              _buildSectionHeader(tr('stamp_template').toUpperCase()),
              _buildTemplatePreviewCard(
                title: 'Template 1 (Translucent Dark)',
                subtitle: 'Translucent dark glass card with white telemetry',
                index: 0,
                isSelected: s.templateIndex == 0,
              ),
              const SizedBox(height: 8),
              _buildTemplatePreviewCard(
                title: 'Template 2 (Solid High-Contrast Dark)',
                subtitle: 'Solid black background with high-contrast amber accents',
                index: 1,
                isSelected: s.templateIndex == 1,
              ),
              const SizedBox(height: 20),

              // ====================================================
              // SECTION 2: CAMERA SETTINGS
              // ====================================================
              _buildSectionHeader(tr('camera_settings').toUpperCase()),
          _buildCard(
            children: [
              _buildSwitchTile(
                icon: Icons.volume_up,
                title: 'Capture Sound',
                subtitle: 'Turn sound on/off when capturing',
                value: s.captureSound,
                onChanged: (v) => setState(() => s.update(captureSound: v)),
              ),
              _buildDivider(),
              _buildSwitchTile(
                icon: Icons.photo_library,
                title: 'Save Original Photos',
                subtitle: 'Keep original photos without metadata',
                value: s.saveOriginal,
                onChanged: (v) => setState(() => s.update(saveOriginal: v)),
              ),
              _buildDivider(),
              _buildActionTile(
                icon: Icons.grid_on,
                title: tr('grid_overlay'),
                subtitle: _getGridModeSubtitle(s.cameraGridMode),
                onTap: _showGridModeDialog,
              ),
              _buildDivider(),
              _buildSwitchTile(
                icon: Icons.straighten,
                title: tr('horizon_level'),
                subtitle: 'Show live horizon & tilt bubble level',
                value: s.showHorizonLevel,
                onChanged: (v) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('show_horizon_level', v);
                  setState(() => s.update(showHorizonLevel: v));
                },
              ),
              _buildDivider(),
              _buildSwitchTile(
                icon: Icons.compress,
                title: tr('high_quality_capture'),
                subtitle: tr('high_quality_desc'),
                value: s.compressImages,
                onChanged: (v) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('compress_images', v);
                  setState(() => s.update(compressImages: v));
                },
              ),
              _buildDivider(),
              _buildSwitchTile(
                icon: Icons.verified_user,
                iconColor: Colors.greenAccent,
                title: tr('verified_capture_badge'),
                subtitle: tr('verified_badge_desc'),
                value: s.showVerifiedBadge,
                onChanged: (v) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('show_verified_badge', v);
                  setState(() => s.update(showVerifiedBadge: v));
                },
              ),
              _buildDivider(),
              _buildSwitchTile(
                icon: Icons.map_outlined,
                iconColor: Colors.blueAccent,
                title: tr('include_maps_link'),
                subtitle: tr('include_maps_desc'),
                value: s.includeMapsLink,
                onChanged: (v) async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('include_maps_link', v);
                  setState(() => s.update(includeMapsLink: v));
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ====================================================
          // SECTION 3: PICTURE SETTINGS
          // ====================================================
          _buildSectionHeader(tr('map_stamp_settings').toUpperCase()),
          _buildCard(
            children: [
              _buildActionTile(
                icon: Icons.map,
                title: 'Map Type',
                subtitle: s.mapType,
                onTap: _showMapTypeDialog,
              ),
              _buildDivider(),
              _buildActionTile(
                icon: Icons.description,
                title: 'Custom Note',
                subtitle: s.customNote.isNotEmpty ? s.customNote : 'Not Set',
                onTap: _showCustomNoteDialog,
              ),
              _buildDivider(),
              _buildActionTile(
                icon: Icons.person,
                title: 'Person Name',
                subtitle: s.personName.isNotEmpty ? s.personName : 'Not Set',
                onTap: _showPersonNameDialog,
              ),
              _buildDivider(),
              // Preserved Display Fields & Telemetry Toggles
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  leading: const Icon(Icons.tune, color: Colors.blue),
                  title: const Text(
                    'Stamp Fields & Telemetry',
                    style: TextStyle(
                      color: Color(0xFF1E293B),
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: const Text(
                    'Customize displayed rows and units',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                  ),
                  children: [
                    _buildSwitchTile(
                      icon: Icons.map_outlined,
                      title: 'Map Thumbnail',
                      subtitle: '100x100 square map preview',
                      value: s.showMap,
                      onChanged: (v) => setState(() => s.update(showMap: v)),
                    ),
                    _buildDivider(),
                    _buildSwitchTile(
                      icon: Icons.place,
                      title: 'Street Address',
                      subtitle: 'Reverse geocoded location',
                      value: s.showAddress,
                      onChanged: (v) => setState(() => s.update(showAddress: v)),
                    ),
                    _buildDivider(),
                    _buildSwitchTile(
                      icon: Icons.my_location,
                      title: 'Coordinates',
                      subtitle: 'Latitude and Longitude',
                      value: s.showCoordinates,
                      onChanged: (v) => setState(() => s.update(showCoordinates: v)),
                    ),
                    _buildDivider(),
                    _buildSwitchTile(
                      icon: Icons.access_time,
                      title: 'Date & Time Stamp',
                      subtitle: 'Timestamp and timezone',
                      value: s.showDateTime,
                      onChanged: (v) => setState(() => s.update(showDateTime: v)),
                    ),
                    _buildDivider(),
                    _buildSwitchTile(
                      icon: Icons.terrain,
                      title: 'Altitude Elevation',
                      subtitle: 'Above sea level in meters or feet',
                      value: s.showAltitude,
                      onChanged: (v) => setState(() => s.update(showAltitude: v)),
                    ),
                    _buildDivider(),
                    _buildSwitchTile(
                      icon: Icons.straighten,
                      title: 'Use Feet for Altitude',
                      subtitle: s.useFeet ? 'Altitude in feet' : 'Altitude in meters',
                      value: s.useFeet,
                      onChanged: (v) => setState(() => s.update(useFeet: v)),
                    ),
                    _buildDivider(),
                    _buildSwitchTile(
                      icon: Icons.gps_fixed,
                      title: 'GPS Accuracy',
                      subtitle: 'Margin of error in meters',
                      value: s.showAccuracy,
                      onChanged: (v) => setState(() => s.update(showAccuracy: v)),
                    ),
                    _buildDivider(),
                    _buildSwitchTile(
                      icon: Icons.sensors,
                      title: 'Magnetic Field',
                      subtitle: 'Calculated in microteslas (µT)',
                      value: s.showMagnetic,
                      onChanged: (v) => setState(() => s.update(showMagnetic: v)),
                    ),
                    _buildDivider(),
                    _buildSwitchTile(
                      icon: Icons.explore,
                      title: 'Compass Heading',
                      subtitle: 'Degrees & cardinal direction',
                      value: s.showCompass,
                      onChanged: (v) => setState(() => s.update(showCompass: v)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ====================================================
          // SECTION 4: APP SETTINGS
          // ====================================================
          _buildSectionHeader(tr('settings').toUpperCase()),
          _buildCard(
            children: [
              _buildActionTile(
                icon: Icons.location_on,
                title: tr('custom_address'),
                subtitle: s.customAddress.isNotEmpty
                    ? s.customAddress
                    : 'Display your address here',
                onTap: _showAddressDialog,
              ),
              _buildDivider(),
              _buildActionTile(
                icon: Icons.calendar_today,
                title: 'Date Time',
                subtitle: s.formatDateTime(),
                onTap: _showDateTimeDialog,
              ),
              _buildDivider(),
              _buildActionTile(
                icon: Icons.language,
                title: tr('language'),
                subtitle: AppLocaleController.currentLanguageOption.nativeName,
                onTap: _showLanguageDialog,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ====================================================
          // SECTION 5: ENTERPRISE & TEAMS
          // ====================================================
          _buildSectionHeader(tr('business_branding').toUpperCase()),
          _buildCard(
            children: [
              _buildActionTile(
                icon: Icons.business_center,
                iconColor: isDark ? Colors.amberAccent : Colors.orange.shade800,
                title: tr('business_branding'),
                subtitle: tr('business_branding_desc'),
                onTap: _showBusinessInquirySheet,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ====================================================
          // SECTION 6: ABOUT
          // ====================================================
          _buildSectionHeader(tr('about_support').toUpperCase()),
          _buildCard(
            children: [
              _buildActionTile(
                icon: Icons.star,
                title: 'Rate App',
                subtitle: 'If you enjoy using this app, please rate it',
                onTap: () async {
                  await ReviewService.openStoreListing();
                },
              ),
              _buildDivider(),
              _buildActionTile(
                icon: Icons.share,
                title: 'Share App',
                subtitle: 'Share this app with friends',
                onTap: () async {
                  await Share.share(
                    'Check out GPS Map Camera! Capture photos & videos stamped with real-time GPS coordinates, map thumbnail, and sensor telemetry.',
                  );
                },
              ),
              _buildDivider(),
              _buildActionTile(
                icon: Icons.info,
                title: tr('privacy_policy'),
                subtitle: 'Read our privacy policy',
                onTap: _showPrivacyPolicyDialog,
              ),
              _buildDivider(),
              _buildActionTile(
                icon: Icons.article,
                title: tr('terms_service'),
                subtitle: 'Read our terms & conditions',
                onTap: _showTermsDialog,
              ),
              _buildDivider(),
              _buildActionTile(
                icon: Icons.support_agent,
                title: 'Contact Support',
                subtitle: 'Get help or send us feedback',
                onTap: () async {
                  final uri = Uri(
                    scheme: 'mailto',
                    path: _businessEmail,
                    query: 'subject=GPS%20Map%20Camera%20Support',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: SizedBox(
          height: _bannerAd?.size.height.toDouble() ?? 60,
          width: double.infinity,
          child: (_isBannerLoaded && _bannerAd != null)
              ? AdWidget(ad: _bannerAd!)
              : const SizedBox.shrink(),
        ),
      ),
    );
      },
    );
  }

  // ====================================================
  // UI HELPERS & COMPONENTS
  // ====================================================

  Widget _buildSectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: children,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      endIndent: 16,
      color: isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF1F5F9),
    );
  }

  Widget _buildTemplatePreviewCard({
    required String title,
    required String subtitle,
    required int index,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Generate a dedicated template settings object for preview
    final previewSettings = AppSettings();
    previewSettings.update(
      templateIndex: index,
      mapType: widget.settings.mapType,
      showMap: true,
      showAddress: true,
      showCoordinates: true,
      showDateTime: true,
      showAltitude: true,
      showAccuracy: true,
      showMagnetic: true,
      showCompass: true,
      useFeet: widget.settings.useFeet,
    );

    return GestureDetector(
      onTap: () {
        setState(() {
          widget.settings.update(templateIndex: index);
        });
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.lightBlueAccent : Colors.blue)
                : (isDark
                    ? Colors.white.withOpacity(0.12)
                    : Colors.grey.shade300),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? (isDark
                      ? Colors.lightBlueAccent.withOpacity(0.18)
                      : Colors.blue.withOpacity(0.12))
                  : Colors.black.withOpacity(isDark ? 0.25 : 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isSelected
                        ? (isDark ? Colors.lightBlueAccent : Colors.blue)
                        : (isDark ? Colors.white38 : Colors.grey.shade400),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? (isDark
                                    ? Colors.lightBlueAccent
                                    : Colors.blue.shade900)
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: IgnorePointer(
                child: GeoStampOverlay(
                  latitude: 37.7749,
                  longitude: -122.4194,
                  altitude: 16.0,
                  accuracy: 4.0,
                  address: 'San Francisco, California, USA',
                  formattedDateTime: 'Mon, Oct 24, 2026, 10:30 AM (GMT -7:00)',
                  magneticField: 48.0,
                  heading: 215.0,
                  cardinalDirection: 'SW',
                  settings: previewSettings,
                  margin: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return SwitchListTile.adaptive(
      secondary: Icon(
        icon,
        color: iconColor ?? (isDark ? Colors.lightBlueAccent : Colors.blue),
      ),
      activeColor: isDark ? Colors.lightBlueAccent : Colors.blue,
      title: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? (isDark ? Colors.lightBlueAccent : Colors.blue),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: isDark ? Colors.white38 : Colors.grey,
      ),
      onTap: onTap,
    );
  }

  // ====================================================
  // MODAL DIALOGS
  // ====================================================

  String _getGridModeSubtitle(String mode) {
    switch (mode) {
      case '3x3':
        return '3×3 (Rule of Thirds)';
      case '4x4':
        return '4×4';
      case 'off':
      default:
        return 'Off';
    }
  }

  void _showGridModeDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Camera Grid',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildGridModeOption(ctx, 'off', 'Off', 'No grid lines on viewfinder'),
              _buildGridModeOption(ctx, '3x3', '3×3 (Rule of Thirds)', 'Standard composition grid'),
              _buildGridModeOption(ctx, '4x4', '4×4', 'Detailed alignment grid'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGridModeOption(BuildContext ctx, String mode, String title, String desc) {
    return RadioListTile<String>(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
      value: mode,
      groupValue: widget.settings.cameraGridMode,
      activeColor: Colors.blue,
      onChanged: (val) async {
        if (val != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('camera_grid_mode', val);
          setState(() {
            widget.settings.update(cameraGridMode: val);
          });
          if (ctx.mounted) {
            Navigator.of(ctx).pop();
          }
        }
      },
    );
  }

  void _showMapTypeDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Select Map Type',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMapTypeOption(ctx, 'Normal', 'Standard OpenStreetMap tiles'),
              _buildMapTypeOption(ctx, 'Satellite', 'Esri World Imagery satellite view'),
              _buildMapTypeOption(ctx, 'Terrain', 'Carto Voyager clean topographical map'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMapTypeOption(BuildContext ctx, String type, String desc) {
    return RadioListTile<String>(
      title: Text(type, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(desc, style: const TextStyle(fontSize: 12)),
      value: type,
      groupValue: widget.settings.mapType,
      activeColor: Colors.blue,
      onChanged: (val) {
        if (val != null) {
          setState(() {
            widget.settings.update(mapType: val);
          });
          Navigator.of(ctx).pop();
        }
      },
    );
  }

  void _showCustomNoteDialog() {
    final controller = TextEditingController(text: widget.settings.customNote);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Custom Note',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: TextField(
            controller: controller,
            maxLines: 2,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter project, job site, or inspect note...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            if (widget.settings.customNote.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() {
                    widget.settings.update(customNote: '');
                  });
                  Navigator.of(ctx).pop();
                },
                child: const Text('Clear', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                setState(() {
                  widget.settings.update(customNote: controller.text.trim());
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showPersonNameDialog() {
    final controller = TextEditingController(text: widget.settings.personName);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Person Name',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Enter surveyor or photographer name...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            if (widget.settings.personName.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() {
                    widget.settings.update(personName: '');
                  });
                  Navigator.of(ctx).pop();
                },
                child: const Text('Clear', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                setState(() {
                  widget.settings.update(personName: controller.text.trim());
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showAddressDialog() {
    final controller = TextEditingController(text: widget.settings.customAddress);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Address Display',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: TextField(
            controller: controller,
            maxLines: 2,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Leave empty to use automatic live GPS address...',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            if (widget.settings.customAddress.isNotEmpty)
              TextButton(
                onPressed: () {
                  setState(() {
                    widget.settings.update(customAddress: '');
                  });
                  Navigator.of(ctx).pop();
                },
                child: const Text('Reset to Live GPS', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                setState(() {
                  widget.settings.update(customAddress: controller.text.trim());
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  void _showDateTimeDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Select Date Time Format',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDateTimeOption(ctx, '12-Hour', 'e.g. Mon, Oct 24, 2026, 10:30 AM (GMT +5:30)'),
              _buildDateTimeOption(ctx, '24-Hour', 'e.g. Mon, Oct 24, 2026, 22:30 (GMT +5:30)'),
              _buildDateTimeOption(ctx, 'ISO', 'e.g. 2026-10-24T22:30:00.000'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.blue)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDateTimeOption(BuildContext ctx, String format, String example) {
    return RadioListTile<String>(
      title: Text(format, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(example, style: const TextStyle(fontSize: 12)),
      value: format,
      groupValue: widget.settings.dateFormat,
      activeColor: Colors.blue,
      onChanged: (val) {
        if (val != null) {
          setState(() {
            widget.settings.update(dateFormat: val);
          });
          Navigator.of(ctx).pop();
        }
      },
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            tr('select_language'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: AppLocaleController.supportedLanguages.length,
              itemBuilder: (context, index) {
                final lang = AppLocaleController.supportedLanguages[index];
                final isSelected =
                    AppLocaleController.localeNotifier.value.languageCode ==
                        lang.code;
                return RadioListTile<String>(
                  title: Text(
                    '${lang.nativeName} (${lang.name})',
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  value: lang.code,
                  groupValue:
                      AppLocaleController.localeNotifier.value.languageCode,
                  activeColor: Colors.blue,
                  onChanged: (val) async {
                    if (val != null) {
                      await AppLocaleController.setLocale(val);
                      widget.settings.update(appLanguage: val);
                      if (mounted) setState(() {});
                      Navigator.of(ctx).pop();
                    }
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child:
                  Text(tr('cancel'), style: const TextStyle(color: Colors.blue)),
            ),
          ],
        );
      },
    );
  }

  void _showPrivacyPolicyDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.privacy_tip, color: Colors.blue),
              SizedBox(width: 8),
              Text('Privacy Policy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'Your privacy is extremely important to us.\n\n'
              '1. Camera & Audio: Camera and microphone access are used exclusively within the app to capture photos and record videos.\n\n'
              '2. Location & Sensors: GPS location, altitude, compass orientation, and magnetometer data are gathered solely in real-time to stamp geographical metadata onto your photos and videos.\n\n'
              '3. Data Storage: All photos and videos remain on your local device. We do not transmit or store your personal media on external servers without your explicit action.\n\n'
              '4. Analytics & Ads: Non-personally identifiable diagnostic information and standard AdMob advertisements may be shown in accordance with Google Play policies.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.gavel, color: Colors.blue),
              SizedBox(width: 8),
              Text('Terms & Conditions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              'By using GPS Map Camera, you agree to the following terms:\n\n'
              '1. License: You are granted a personal, non-exclusive license to use the application for capturing geostamped media.\n\n'
              '2. GPS Accuracy: Telemetry (coordinates, altitude, compass, magnetic field) is provided as-is from your hardware sensors. We do not guarantee precision for safety-critical or survey-certified applications.\n\n'
              '3. Lawful Use: You agree to comply with all applicable local privacy and photographic laws when capturing people and locations.\n\n'
              '4. Modifications: We reserve the right to update the application features and terms as needed to enhance user experience.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _showBusinessInquirySheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.business_center,
                          color: Colors.amber, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Custom Branding & Team License',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Equip your field surveyors, site engineers, and inspection teams with custom company watermarks, logos, tailored stamp templates, and volume licensing.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.chat, color: Colors.green, size: 22),
                  ),
                  title: Text(
                    'Chat on WhatsApp',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    '+$_businessWhatsApp',
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final message = Uri.encodeComponent(
                        'Hi! I am interested in Custom Company Branding / Team Licensing for GPS Map Camera.');
                    final uri = Uri.parse(
                        'https://wa.me/$_businessWhatsApp?text=$message');
                    try {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } catch (e) {
                      debugPrint('Error launching WhatsApp: $e');
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.email_outlined,
                        color: Colors.blue, size: 22),
                  ),
                  title: Text(
                    'Email Sales Team',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    _businessEmail,
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12.5,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final subject = Uri.encodeComponent(
                        'Enterprise Inquiry - GPS Map Camera');
                    final body = Uri.encodeComponent(
                        'Hello Sales Team,\n\nI am interested in Custom Company Branding and Team Licensing for GPS Map Camera.\n\nCompany Name:\nTeam Size:\nRequirements:\n');
                    final uri =
                        Uri.parse('mailto:$_businessEmail?subject=$subject&body=$body');
                    try {
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    } catch (e) {
                      debugPrint('Error launching Email: $e');
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
