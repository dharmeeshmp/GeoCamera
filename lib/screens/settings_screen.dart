import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/ad_config.dart';
import '../models/app_settings.dart';

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
  late TextEditingController _noteController;
  late TextEditingController _nameController;

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
  void initState() {
    super.initState();
    _noteController =
        TextEditingController(text: widget.settings.customNote);
    _nameController =
        TextEditingController(text: widget.settings.personName);
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _noteController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Stamp & Camera Settings',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _buildSectionHeader('STAMP TEMPLATE'),
          Card(
            color: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                _buildTemplateRadio(
                  title: 'Modern Translucent (Default)',
                  subtitle: 'Translucent dark glass with crisp white typography',
                  value: StampTemplate.modernTranslucent,
                ),
                _buildDivider(),
                _buildTemplateRadio(
                  title: 'Classic Dark',
                  subtitle: 'Solid black background with gold & white highlights',
                  value: StampTemplate.classicDark,
                ),
                _buildDivider(),
                _buildTemplateRadio(
                  title: 'Clean White',
                  subtitle: 'Frosted high-contrast light card',
                  value: StampTemplate.cleanWhite,
                ),
                _buildDivider(),
                _buildTemplateRadio(
                  title: 'Minimal Overlay',
                  subtitle: 'Ultra-lightweight borderless card',
                  value: StampTemplate.minimalOverlay,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildSectionHeader('MAP THUMBNAIL STYLE'),
          Card(
            color: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                _buildMapRadio(
                  title: 'OpenStreetMap (Standard)',
                  value: MapStyle.openStreetMap,
                ),
                _buildDivider(),
                _buildMapRadio(
                  title: 'CartoDB Voyager (Clean Roads)',
                  value: MapStyle.cartoVoyager,
                ),
                _buildDivider(),
                _buildMapRadio(
                  title: 'Esri Satellite Imagery',
                  value: MapStyle.satellite,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildSectionHeader('DISPLAYED FIELDS'),
          Card(
            color: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                _buildSwitchTile(
                  title: 'Map Thumbnail',
                  subtitle: 'Square 100x100 preview with pin',
                  value: s.showMap,
                  onChanged: (v) => setState(() => s.update(showMap: v)),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  title: 'Street Address',
                  subtitle: 'Reverse geocoded location name',
                  value: s.showAddress,
                  onChanged: (v) => setState(() => s.update(showAddress: v)),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  title: 'Coordinates',
                  subtitle: 'Latitude and Longitude in degrees',
                  value: s.showCoordinates,
                  onChanged: (v) =>
                      setState(() => s.update(showCoordinates: v)),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  title: 'Date & Time Stamp',
                  subtitle: 'Includes timezone offset (e.g. GMT +5:30)',
                  value: s.showDateTime,
                  onChanged: (v) => setState(() => s.update(showDateTime: v)),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  title: 'Altitude Elevation',
                  subtitle: 'Above sea level in meters or feet',
                  value: s.showAltitude,
                  onChanged: (v) => setState(() => s.update(showAltitude: v)),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  title: 'GPS Accuracy',
                  subtitle: 'Real-time GPS margin of error',
                  value: s.showAccuracy,
                  onChanged: (v) => setState(() => s.update(showAccuracy: v)),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  title: 'Magnetic Field',
                  subtitle: 'Calculated in microteslas (µT)',
                  value: s.showMagnetic,
                  onChanged: (v) => setState(() => s.update(showMagnetic: v)),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  title: 'Compass Heading',
                  subtitle: 'Live degrees and 8-point cardinal direction',
                  value: s.showCompass,
                  onChanged: (v) => setState(() => s.update(showCompass: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildSectionHeader('UNITS & CUSTOM NOTES'),
          Card(
            color: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                _buildSwitchTile(
                  title: 'Use Feet for Altitude',
                  subtitle: s.useFeet ? 'Altitude in feet' : 'Altitude in meters',
                  value: s.useFeet,
                  onChanged: (v) => setState(() => s.update(useFeet: v)),
                ),
                _buildDivider(),
                _buildSwitchTile(
                  title: 'Enable Custom Note',
                  subtitle: 'Adds custom text to the bottom of the stamp',
                  value: s.showCustomNote,
                  onChanged: (v) =>
                      setState(() => s.update(showCustomNote: v)),
                ),
                if (s.showCustomNote)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _noteController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Enter custom project / site note...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (v) => s.update(customNote: v),
                    ),
                  ),
                _buildDivider(),
                _buildSwitchTile(
                  title: 'Photographer Name',
                  subtitle: 'Credit captured by info',
                  value: s.showPersonName,
                  onChanged: (v) =>
                      setState(() => s.update(showPersonName: v)),
                ),
                if (s.showPersonName)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: TextField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Enter your name...',
                        hintStyle: const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: Colors.black26,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (v) => s.update(personName: v),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          _buildSectionHeader('ABOUT'),
          Card(
            color: const Color(0xFF1E1E1E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.phone, color: Colors.blue),
              title: const Text(
                'Contact Support',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: const Text(
                'Get help or call support',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              onTap: () async {
                final uri = Uri(scheme: 'tel', path: '+910000000000');
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                }
              },
            ),
          ),
          const SizedBox(height: 30),
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

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.amberAccent,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildTemplateRadio({
    required String title,
    required String subtitle,
    required StampTemplate value,
  }) {
    return RadioListTile<StampTemplate>(
      value: value,
      groupValue: widget.settings.template,
      activeColor: Colors.amberAccent,
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      onChanged: (val) {
        if (val != null) {
          setState(() => widget.settings.update(template: val));
        }
      },
    );
  }

  Widget _buildMapRadio({
    required String title,
    required MapStyle value,
  }) {
    return RadioListTile<MapStyle>(
      value: value,
      groupValue: widget.settings.mapStyle,
      activeColor: Colors.amberAccent,
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
      onChanged: (val) {
        if (val != null) {
          setState(() => widget.settings.update(mapStyle: val));
        }
      },
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      activeColor: Colors.amberAccent,
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      onChanged: onChanged,
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, color: Colors.white10);
  }
}
