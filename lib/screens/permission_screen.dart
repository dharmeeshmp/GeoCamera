import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../models/app_settings.dart';
import '../services/app_localizations.dart';

class PermissionScreen extends StatefulWidget {
  final AppSettings settings;

  const PermissionScreen({
    super.key,
    required this.settings,
  });

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen>
    with WidgetsBindingObserver {
  bool _cameraGranted = false;
  bool _locationGranted = false;
  bool _microphoneGranted = false;
  bool _isChecking = true;
  bool _isPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    setState(() => _isChecking = true);

    final cam = await Permission.camera.status;
    final loc = await Permission.locationWhenInUse.status;
    final mic = await Permission.microphone.status;

    final camOk = cam.isGranted;
    final locOk = loc.isGranted;
    final micOk = mic.isGranted;

    final permDenied = cam.isPermanentlyDenied ||
        loc.isPermanentlyDenied ||
        mic.isPermanentlyDenied;

    if (mounted) {
      setState(() {
        _cameraGranted = camOk;
        _locationGranted = locOk;
        _microphoneGranted = micOk;
        _isPermanentlyDenied = permDenied;
        _isChecking = false;
      });

      if (camOk && locOk && micOk) {
        _navigateToCamera();
      }
    }
  }

  Future<void> _requestPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.locationWhenInUse,
      Permission.microphone,
    ].request();

    final camOk = statuses[Permission.camera]?.isGranted ?? false;
    final locOk = statuses[Permission.locationWhenInUse]?.isGranted ?? false;
    final micOk = statuses[Permission.microphone]?.isGranted ?? false;

    final permDenied = (statuses[Permission.camera]?.isPermanentlyDenied ?? false) ||
        (statuses[Permission.locationWhenInUse]?.isPermanentlyDenied ?? false) ||
        (statuses[Permission.microphone]?.isPermanentlyDenied ?? false);

    if (mounted) {
      setState(() {
        _cameraGranted = camOk;
        _locationGranted = locOk;
        _microphoneGranted = micOk;
        _isPermanentlyDenied = permDenied;
      });

      if (camOk && locOk && micOk) {
        _navigateToCamera();
      }
    }
  }

  void _navigateToCamera() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GPSCameraScreen(settings: widget.settings),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: AppLocaleController.localeNotifier,
      builder: (context, locale, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: SafeArea(
            child: _isChecking
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.amberAccent),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24.0, vertical: 20.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        Center(
                          child: Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              color: Colors.amberAccent.withOpacity(0.12),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.amberAccent.withOpacity(0.4),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 46,
                              color: Colors.amberAccent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'GPS Map Camera',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          tr('permissions_desc'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 36),

                        _buildPermissionTile(
                          icon: Icons.camera_alt_outlined,
                          title: tr('camera_permission'),
                          subtitle: tr('camera_permission_desc'),
                          isGranted: _cameraGranted,
                        ),
                        const SizedBox(height: 14),
                        _buildPermissionTile(
                          icon: Icons.location_on_outlined,
                          title: tr('location_permission'),
                          subtitle: tr('location_permission_desc'),
                          isGranted: _locationGranted,
                        ),
                        const SizedBox(height: 14),
                        _buildPermissionTile(
                          icon: Icons.mic_none_outlined,
                          title: tr('microphone_permission'),
                          subtitle: tr('microphone_permission_desc'),
                          isGranted: _microphoneGranted,
                        ),

                        const Spacer(),

                        if (_isPermanentlyDenied)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.settings),
                            label: Text(
                              tr('open_settings'),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            onPressed: openAppSettings,
                          )
                        else
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amberAccent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _requestPermissions,
                            child: Text(
                              tr('grant_permissions'),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isGranted,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isGranted ? Colors.green.withOpacity(0.5) : Colors.white12,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 26,
            color: isGranted ? Colors.greenAccent : Colors.white60,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            isGranted ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: isGranted ? Colors.greenAccent : Colors.white24,
            size: 22,
          ),
        ],
      ),
    );
  }
}
