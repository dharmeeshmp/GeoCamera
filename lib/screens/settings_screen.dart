import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/ad_config.dart';
import '../models/app_settings.dart';
import '../services/review_service.dart';
import '../widgets/geo_stamp_overlay.dart';

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;

  const SettingsScreen({
    super.key,
    required this.settings,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAdaptiveBanner();
  }

  Future<void> _loadAdaptiveBanner() async {
    if (_bannerAd != null) return;

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
    final s = widget.settings;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
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
          // SECTION 1: SELECT TEMPLATE (2 Visual Preview Cards)
          // ====================================================
          _buildSectionHeader('SELECT TEMPLATE'),
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
          _buildSectionHeader('CAMERA SETTINGS'),
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
                title: 'Camera Grid',
                subtitle: _getGridModeSubtitle(s.cameraGridMode),
                onTap: _showGridModeDialog,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ====================================================
          // SECTION 3: PICTURE SETTINGS
          // ====================================================
          _buildSectionHeader('PICTURE SETTINGS'),
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
          _buildSectionHeader('APP SETTINGS'),
          _buildCard(
            children: [
              _buildActionTile(
                icon: Icons.location_on,
                title: 'Address',
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
                title: 'Language',
                subtitle: 'Current: ${s.appLanguage}',
                onTap: _showLanguageDialog,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ====================================================
          // SECTION 5: ABOUT
          // ====================================================
          _buildSectionHeader('ABOUT'),
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
                title: 'Privacy Policy',
                subtitle: 'Read our privacy policy',
                onTap: _showPrivacyPolicyDialog,
              ),
              _buildDivider(),
              _buildActionTile(
                icon: Icons.article,
                title: 'Terms & Conditions',
                subtitle: 'Read our terms & conditions',
                onTap: _showTermsDialog,
              ),
              _buildDivider(),
              _buildActionTile(
                icon: Icons.phone,
                title: 'Contact Support',
                subtitle: 'Get help or send us feedback',
                onTap: () async {
                  final uri = Uri(scheme: 'tel', path: '+910000000000');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
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
  }

  // ====================================================
  // UI HELPERS & COMPONENTS
  // ====================================================

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
    return const Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      endIndent: 16,
      color: Color(0xFFF1F5F9),
    );
  }

  Widget _buildTemplatePreviewCard({
    required String title,
    required String subtitle,
    required int index,
    required bool isSelected,
  }) {
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? Colors.blue.withOpacity(0.12)
                  : Colors.black.withOpacity(0.03),
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
                    color: isSelected ? Colors.blue : Colors.grey.shade400,
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
                                ? Colors.blue.shade900
                                : const Color(0xFF1E293B),
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
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
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile.adaptive(
      secondary: Icon(icon, color: Colors.blue),
      activeColor: Colors.blue,
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF1E293B),
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF1E293B),
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey),
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
    final isSelected = widget.settings.mapType == type;
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Select App Language',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLanguageOption(ctx, 'English'),
              _buildLanguageOption(ctx, 'Tamil'),
              _buildLanguageOption(ctx, 'Hindi'),
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

  Widget _buildLanguageOption(BuildContext ctx, String lang) {
    return RadioListTile<String>(
      title: Text(lang, style: const TextStyle(fontWeight: FontWeight.w600)),
      value: lang,
      groupValue: widget.settings.appLanguage,
      activeColor: Colors.blue,
      onChanged: (val) {
        if (val != null) {
          setState(() {
            widget.settings.update(appLanguage: val);
          });
          Navigator.of(ctx).pop();
        }
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
          content: const SingleChildScrollView(
            child: Text(
              'Your privacy is extremely important to us.\n\n'
              '1. Camera & Audio: Camera and microphone access are used exclusively within the app to capture photos and record videos.\n\n'
              '2. Location & Sensors: GPS location, altitude, compass orientation, and magnetometer data are gathered solely in real-time to stamp geographical metadata onto your photos and videos.\n\n'
              '3. Data Storage: All photos and videos remain on your local device. We do not transmit or store your personal media on external servers without your explicit action.\n\n'
              '4. Analytics & Ads: Non-personally identifiable diagnostic information and standard AdMob advertisements may be shown in accordance with Google Play policies.',
              style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF334155)),
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
          content: const SingleChildScrollView(
            child: Text(
              'By using GPS Map Camera, you agree to the following terms:\n\n'
              '1. License: You are granted a personal, non-exclusive license to use the application for capturing geostamped media.\n\n'
              '2. GPS Accuracy: Telemetry (coordinates, altitude, compass, magnetic field) is provided as-is from your hardware sensors. We do not guarantee precision for safety-critical or survey-certified applications.\n\n'
              '3. Lawful Use: You agree to comply with all applicable local privacy and photographic laws when capturing people and locations.\n\n'
              '4. Modifications: We reserve the right to update the application features and terms as needed to enhance user experience.',
              style: TextStyle(fontSize: 13, height: 1.4, color: Color(0xFF334155)),
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
}
