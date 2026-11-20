import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/ad_config.dart';
import 'models/app_settings.dart';
import 'screens/gallery_screen.dart';
import 'screens/permission_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_localizations.dart';
import 'services/media_storage_service.dart';
import 'services/review_service.dart';
import 'widgets/camera_grid_overlay.dart';
import 'widgets/geo_stamp_overlay.dart';
import 'widgets/horizon_level_overlay.dart';

final ValueNotifier<ThemeMode> appThemeNotifier =
    ValueNotifier(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  final isDark = prefs.getBool('is_dark_mode') ?? false;
  appThemeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  await AppLocaleController.loadSavedLocale();
  final settings = await AppSettings.loadFromPrefs();
  runApp(GPSMapCameraApp(settings: settings));
}

class GPSMapCameraApp extends StatelessWidget {
  final AppSettings settings;

  const GPSMapCameraApp({
    super.key,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appThemeNotifier,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Locale>(
          valueListenable: AppLocaleController.localeNotifier,
          builder: (context, currentLocale, _) {
            return MaterialApp(
              title: 'GPS Map Camera',
              debugShowCheckedModeBanner: false,
              themeMode: themeMode,
              locale: currentLocale,
              supportedLocales: AppLocaleController.supportedLocales,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.light,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF1565C0),
                  brightness: Brightness.light,
                ),
                scaffoldBackgroundColor: const Color(0xFFF5F7FA),
                cardColor: Colors.white,
                appBarTheme: const AppBarTheme(
                  backgroundColor: Colors.white,
                  foregroundColor: Color(0xFF1A1C1E),
                  elevation: 0.5,
                ),
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                brightness: Brightness.dark,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF1565C0),
                  brightness: Brightness.dark,
                ),
                scaffoldBackgroundColor: const Color(0xFF121212),
                cardColor: const Color(0xFF1E1E1E),
                appBarTheme: const AppBarTheme(
                  backgroundColor: Color(0xFF1E1E1E),
                  foregroundColor: Colors.white,
                  elevation: 0.5,
                ),
              ),
              home: PermissionScreen(settings: settings),
            );
          },
        );
      },
    );
  }
}

enum CameraCaptureMode { photo, video }

typedef CameraScreen = GPSCameraScreen;

class GPSCameraScreen extends StatefulWidget {
  final AppSettings settings;

  const GPSCameraScreen({
    super.key,
    required this.settings,
  });

  @override
  State<GPSCameraScreen> createState() => _GPSCameraScreenState();
}

class _GPSCameraScreenState extends State<GPSCameraScreen>
    with WidgetsBindingObserver {
  // Camera State
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  int _selectedCameraIndex = 0;
  FlashMode _currentFlashMode = FlashMode.auto;
  bool _isCameraInitialized = false;
  bool _isCameraInitializing = false;
  bool _isSwitchingCamera = false;
  String? _cameraErrorMessage;

  // Multi-Lens Rear Camera & Ultra-Wide State
  CameraDescription? _mainBackCamera;
  CameraDescription? _ultraWideBackCamera;
  bool _isUsingUltraWide = false;

  // Zoom Capabilities & State
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  double _baseZoom = 1.0;

  // Tap-to-Focus & Exposure Lock State
  Offset? _focusPoint;
  Timer? _focusRingTimer;

  // Capture Mode & Video Recording State
  CameraCaptureMode _captureMode = CameraCaptureMode.photo;
  bool _isRecordingVideo = false;
  bool _isProcessingCapture = false;
  int _recordDurationSeconds = 0;
  Timer? _recordTimer;

  // Guidance Grid State
  String _gridMode = 'off';

  // Horizon Level State
  bool _showHorizonLevel = true;

  // Image Compression State
  bool _compressImages = true;

  // Verified Capture & Anti-Mock State
  bool _isMockLocation = false;
  bool _showVerifiedBadge = true;
  bool _includeMapsLink = true;

  // In-App Gallery Thumbnail State
  File? _latestMediaFile;

  // Sensor & Telemetry State
  Position? _currentPosition;
  double _latitude = 0.0;
  double _longitude = 0.0;
  double _altitude = 0.0;
  double _accuracy = 0.0;
  String _currentAddress = 'Acquiring GPS location...';
  Position? _lastGeocodedPosition;
  Timer? _clockTimer;
  DateTime? _lastGpsFixTime;
  bool _isRefreshingGps = false;
  final MapController _mapController = MapController();

  // Magnetic Field with Exponential Moving Average Low-Pass Smoothing
  double? _smoothedMagneticField;
  static const double _filterAlpha = 0.15;

  // Compass Heading & 16-Point Cardinal Direction
  double? _heading;
  String _cardinalDirection = '--';
  bool _showTelemetry = true;

  // Stream Subscriptions & Sensor Readings
  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  AccelerometerEvent? _lastAccelerometer;
  MagnetometerEvent? _lastMagnetometer;

  // Photo Capture & Compositing Keys
  final GlobalKey _compositingBoundaryKey = GlobalKey();
  final GlobalKey _liveStampKey = GlobalKey();
  Uint8List? _capturedPhotoBytes;
  double _capturedAspectRatio = 3 / 4;

  // Snapshot State for Photo Stamp Burning
  double _snapLat = 0.0;
  double _snapLng = 0.0;
  double _snapAltitude = 0.0;
  double _snapAccuracy = 0.0;
  String _snapAddress = '';
  DateTime _snapTime = DateTime.utc(2026);
  double? _snapMagnetic;
  double? _snapHeading;
  String _snapCardinal = '--';
  bool _snapTelemetry = true;
  bool _snapIsMocked = false;
  bool _snapIsSatelliteTime = false;
  bool _snapIsClockTampered = false;
  String _snapTimeSourceLabel = 'SYS';
  String? _snapVerificationHash;

  // Monotonic Satellite & Atomic Network Clock Anchor & Stopwatch
  DateTime? _satelliteAnchorUtc;
  final Stopwatch _satelliteElapsed = Stopwatch();
  String _timeSourceLabel = 'SYS';
  String _liveFormattedDateTime = '';

  bool get _isSatelliteTimeLocked =>
      _satelliteAnchorUtc != null && _satelliteElapsed.isRunning;

  bool get _isClockTampered {
    if (_satelliteAnchorUtc == null) return false;
    final trueUtc = _satelliteAnchorUtc!.add(_satelliteElapsed.elapsed);
    return DateTime.now().toUtc().difference(trueUtc).abs().inMinutes >= 2;
  }

  /// Helper getter locking timestamp to atomic GPS satellite/network time whenever an anchor is active.
  DateTime get _verifiedTimestamp {
    if (_satelliteAnchorUtc != null) {
      return _satelliteAnchorUtc!.add(_satelliteElapsed.elapsed).toLocal();
    }
    return DateTime.now();
  }

  /// Builds a deterministic 12-character uppercase SHA-256 verification hash.
  String _buildVerificationHash(
      double lat, double lng, DateTime ts, bool isMocked,
      [bool isTampered = false]) {
    final raw =
        '${lat.toStringAsFixed(6)}|${lng.toStringAsFixed(6)}|${ts.toUtc().toIso8601String()}|$isMocked|$isTampered';
    return sha256
        .convert(utf8.encode(raw))
        .toString()
        .substring(0, 12)
        .toUpperCase();
  }

  Future<void> _syncClocksInParallel() async {
    _syncAtomicHttpClock();
    _syncNativeGnssNmeaClock();
  }

  Future<void> _syncAtomicHttpClock() async {
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);

      DateTime? serverUtc;

      // Primary: Google
      try {
        final request = await client
            .headUrl(Uri.parse('https://www.google.com'))
            .timeout(const Duration(seconds: 4));
        final response =
            await request.close().timeout(const Duration(seconds: 4));
        final dateHeader = response.headers.value('date');
        if (dateHeader != null && dateHeader.isNotEmpty) {
          serverUtc = HttpDate.parse(dateHeader).toUtc();
        }
      } catch (e) {
        debugPrint('Google atomic HTTP clock check failed: $e');
      }

      // Fallback: Cloudflare 1.1.1.1
      if (serverUtc == null) {
        try {
          final request = await client
              .headUrl(Uri.parse('https://1.1.1.1'))
              .timeout(const Duration(seconds: 4));
          final response =
              await request.close().timeout(const Duration(seconds: 4));
          final dateHeader = response.headers.value('date');
          if (dateHeader != null && dateHeader.isNotEmpty) {
            serverUtc = HttpDate.parse(dateHeader).toUtc();
          }
        } catch (e) {
          debugPrint('Cloudflare atomic HTTP clock check failed: $e');
        }
      }

      client.close();

      if (serverUtc != null && mounted) {
        // Only set if GNSS hasn't already claimed it
        if (_timeSourceLabel != 'GNSS-SAT') {
          _satelliteAnchorUtc = serverUtc;
          _satelliteElapsed
            ..reset()
            ..start();
          _timeSourceLabel = 'ATOMIC-NET';
          debugPrint('Atomic HTTP clock locked to server UTC: $serverUtc');
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      debugPrint('Http atomic clock sync error: $e');
    }
  }

  Future<void> _syncNativeGnssNmeaClock() async {
    try {
      const platform = MethodChannel('com.example.gps_camera_app/gnss_clock');
      final String? isoUtc =
          await platform.invokeMethod<String>('getTrueSatelliteTimeUtc');
      if (isoUtc != null && isoUtc.isNotEmpty && mounted) {
        final parsedUtc = DateTime.tryParse(isoUtc)?.toUtc();
        if (parsedUtc != null) {
          _satelliteAnchorUtc = parsedUtc;
          _satelliteElapsed
            ..reset()
            ..start();
          _timeSourceLabel = 'GNSS-SAT';
          debugPrint(
              'Native GNSS clock upgraded to true satellite UTC: $parsedUtc');
          if (mounted) setState(() {});
        }
      }
    } catch (e) {
      debugPrint('GNSS NMEA clock sync error: $e');
    }
  }

  // AdMob Banner State
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;
  bool _hasScheduledBanner = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_onSettingsChanged);
    _loadGridMode();
    _loadHorizonLevel();
    _loadCompressionSetting();
    _loadVerifiedBadgeSetting();
    _loadMapsLinkSetting();
    _initializeAll();
    _loadLatestThumbnail();
    _startClockTimer();
    _syncClocksInParallel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_onSettingsChanged);
    _focusRingTimer?.cancel();
    _recordTimer?.cancel();
    _clockTimer?.cancel();
    _cameraController?.dispose();
    _positionSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) {
      setState(() {
        _gridMode = widget.settings.cameraGridMode;
        _showHorizonLevel = widget.settings.showHorizonLevel;
        _compressImages = widget.settings.compressImages;
        _showVerifiedBadge = widget.settings.showVerifiedBadge;
        _includeMapsLink = widget.settings.includeMapsLink;
      });
    }
  }

  Future<void> _loadMapsLinkSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final link =
        prefs.getBool('include_maps_link') ?? widget.settings.includeMapsLink;
    if (mounted) {
      setState(() {
        _includeMapsLink = link;
      });
    }
  }

  Future<void> _loadVerifiedBadgeSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final show =
        prefs.getBool('show_verified_badge') ?? widget.settings.showVerifiedBadge;
    if (mounted) {
      setState(() {
        _showVerifiedBadge = show;
      });
    }
  }

  Future<void> _loadCompressionSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final compress =
        prefs.getBool('compress_images') ?? widget.settings.compressImages;
    if (mounted) {
      setState(() {
        _compressImages = compress;
      });
    }
  }

  Future<void> _loadHorizonLevel() async {
    final prefs = await SharedPreferences.getInstance();
    final show =
        prefs.getBool('show_horizon_level') ?? widget.settings.showHorizonLevel;
    if (mounted) {
      setState(() {
        _showHorizonLevel = show;
      });
    }
  }

  Future<void> _loadGridMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode =
        prefs.getString('camera_grid_mode') ?? widget.settings.cameraGridMode;
    if (mounted) {
      setState(() {
        _gridMode = mode;
      });
    }
  }

  Future<void> _cycleGridMode() async {
    final nextMode = switch (_gridMode) {
      'off' => '3x3',
      '3x3' => '4x4',
      _ => 'off',
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('camera_grid_mode', nextMode);
    widget.settings.update(cameraGridMode: nextMode);
    if (mounted) {
      setState(() {
        _gridMode = nextMode;
      });
    }
  }

  void _startClockTimer() {
    _liveFormattedDateTime = _getFormattedTimestamp(_verifiedTimestamp);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _liveFormattedDateTime = _getFormattedTimestamp(_verifiedTimestamp);
        setState(() {});
      }
    });
  }

  Future<void> _loadLatestThumbnail() async {
    final latest = await MediaStorageService.getLatestMediaFile();
    if (mounted) {
      setState(() {
        _latestMediaFile = latest;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? controller = _cameraController;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_isRecordingVideo) {
        _stopVideoRecording(isEmergency: true);
      } else if (controller != null) {
        if (mounted) {
          setState(() {
            _cameraController = null;
            _isCameraInitialized = false;
          });
        }
        controller.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_cameraController == null ||
          !_cameraController!.value.isInitialized) {
        if (_cameras.isNotEmpty) {
          _initCamera(_cameras[_selectedCameraIndex]);
        } else {
          _initCameras();
        }
      }
      _initLocation();
      _loadLatestThumbnail();
      _syncClocksInParallel();
      if (_lastGpsFixTime == null ||
          _verifiedTimestamp.difference(_lastGpsFixTime!).inSeconds > 30) {
        _forceRefreshGps();
      }
    }
  }

  void _initializeAll() {
    _initLocation();
    _initSensors();
    _initCameras();
  }

  // ==========================================
  // CAMERA INITIALIZATION & LOGIC
  // ==========================================
  Future<void> _initCameras() async {
    if (_isCameraInitializing) return;
    setState(() {
      _isCameraInitializing = true;
      _cameraErrorMessage = null;
    });

    try {
      final camGranted = await Permission.camera.isGranted;
      final micGranted = await Permission.microphone.isGranted;
      if (!camGranted || !micGranted) {
        if (!mounted) return;
        setState(() {
          _isCameraInitializing = false;
          _cameraErrorMessage =
              'Camera and Microphone permissions are required.';
        });
        return;
      }

      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }

      if (_cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _isCameraInitializing = false;
          _cameraErrorMessage = 'No cameras found on this device.';
        });
        return;
      }

      CameraDescription? mainBack;
      CameraDescription? ultraWideBack;
      for (final cam in _cameras) {
        if (cam.lensDirection == CameraLensDirection.back) {
          if (mainBack == null) {
            mainBack = cam;
          } else if (ultraWideBack == null &&
              cam.name != mainBack.name &&
              cam.sensorOrientation == mainBack.sensorOrientation) {
            ultraWideBack = cam;
          }
        }
      }
      _mainBackCamera = mainBack;
      _ultraWideBackCamera = ultraWideBack;

      if (_mainBackCamera != null && !_isUsingUltraWide) {
        _selectedCameraIndex = _cameras.indexOf(_mainBackCamera!);
        if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
      }

      await _initCamera(_cameras[_selectedCameraIndex]);
    } catch (e) {
      debugPrint('Error retrieving cameras: $e');
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
          _cameraErrorMessage = 'Failed to find cameras: $e';
        });
      }
    }
  }

  Future<void> _initCamera(CameraDescription cameraDescription) async {
    _isSwitchingCamera = true;
    final oldController = _cameraController;

    if (mounted) {
      setState(() {
        _cameraController = null;
        _isCameraInitialized = false;
      });
    }

    await oldController?.dispose();

    try {
      CameraController newController = CameraController(
        cameraDescription,
        ResolutionPreset.high,
        enableAudio: true,
      );

      try {
        await newController.initialize();
      } on CameraException catch (_) {
        await newController.dispose();
        newController = CameraController(
          cameraDescription,
          ResolutionPreset.medium,
          enableAudio: true,
        );
        await newController.initialize();
      }
      await newController.setFlashMode(_currentFlashMode);
      try {
        await newController.setFocusMode(FocusMode.auto);
      } catch (e) {
        debugPrint('Focus mode error: $e');
      }

      double minZoom = 1.0;
      double maxZoom = 1.0;
      try {
        minZoom = await newController.getMinZoomLevel();
        maxZoom = await newController.getMaxZoomLevel();
      } catch (e) {
        debugPrint('Error querying zoom levels: $e');
      }

      final currentZoom = _isUsingUltraWide
          ? minZoom.clamp(minZoom, maxZoom)
          : 1.0.clamp(minZoom, maxZoom);
      try {
        await newController.setZoomLevel(currentZoom);
      } catch (e) {
        debugPrint('Error setting initial zoom level: $e');
      }

      if (mounted && newController.value.isInitialized) {
        setState(() {
          _cameraController = newController;
          _minZoom = minZoom;
          _maxZoom = maxZoom;
          _currentZoom = currentZoom;
          _isCameraInitialized = true;
          _isSwitchingCamera = false;
          _isCameraInitializing = false;
          _cameraErrorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (_isUsingUltraWide && _mainBackCamera != null) {
        _isUsingUltraWide = false;
        _selectedCameraIndex = _cameras.indexOf(_mainBackCamera!);
        if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
        await _initCamera(_mainBackCamera!);
        return;
      }
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
          _isSwitchingCamera = false;
          _cameraErrorMessage = 'Failed to start camera: $e';
        });
      }
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2 || _isSwitchingCamera || _cameraController == null) {
      return;
    }

    final currentCam = _cameras[_selectedCameraIndex];
    CameraDescription nextCam;

    if (currentCam.lensDirection == CameraLensDirection.back) {
      // Currently on any rear camera -> switch to front camera
      final frontCam = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras[(_selectedCameraIndex + 1) % _cameras.length],
      );
      nextCam = frontCam;
      _isUsingUltraWide = false;
    } else {
      // Currently on front camera -> switch back to main back camera
      nextCam = _mainBackCamera ??
          _cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
            orElse: () => _cameras[0],
          );
      _isUsingUltraWide = false;
    }

    _selectedCameraIndex = _cameras.indexOf(nextCam);
    if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;

    await _initCamera(nextCam);
  }

  Future<void> _setZoom(double zoom) async {
    final clamped = zoom.clamp(_minZoom, _maxZoom);
    if (mounted) {
      setState(() {
        _currentZoom = clamped;
      });
    }
    try {
      await _cameraController?.setZoomLevel(clamped);
    } catch (e) {
      debugPrint('Error setting zoom level: $e');
    }
  }

  Future<void> _onUltraWideTapped() async {
    if (_isSwitchingCamera) return;

    if (_minZoom < 1.0) {
      await _setZoom(_minZoom);
    } else if (_ultraWideBackCamera != null && !_isUsingUltraWide) {
      _isUsingUltraWide = true;
      _selectedCameraIndex = _cameras.indexOf(_ultraWideBackCamera!);
      if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
      await _initCamera(_ultraWideBackCamera!);
      await _setZoom(_minZoom.clamp(_minZoom, _maxZoom));
    }
  }

  Future<void> _onStandardZoomTapped(double targetZoom) async {
    if (_isSwitchingCamera) return;

    if (_isUsingUltraWide && _mainBackCamera != null) {
      _isUsingUltraWide = false;
      _selectedCameraIndex = _cameras.indexOf(_mainBackCamera!);
      if (_selectedCameraIndex == -1) _selectedCameraIndex = 0;
      await _initCamera(_mainBackCamera!);
      await _setZoom(targetZoom.clamp(_minZoom, _maxZoom));
    } else {
      await _setZoom(targetZoom.clamp(_minZoom, _maxZoom));
    }
  }

  Future<void> _cycleFlashMode() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    FlashMode nextMode;
    switch (_currentFlashMode) {
      case FlashMode.off:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.always;
        break;
      case FlashMode.always:
        nextMode = FlashMode.off;
        break;
      default:
        nextMode = FlashMode.auto;
        break;
    }

    try {
      await _cameraController!.setFlashMode(nextMode);
      setState(() {
        _currentFlashMode = nextMode;
      });
    } catch (e) {
      debugPrint('Flash mode error: $e');
    }
  }

  void _applyNewPosition(Position pos, {bool isLiveStream = false}) {
    if (!mounted) return;
    if (_timeSourceLabel != 'GNSS-SAT') {
      _syncNativeGnssNmeaClock();
    }
    setState(() {
      _currentPosition = pos;
      _latitude = pos.latitude;
      _longitude = pos.longitude;
      _altitude = pos.altitude;
      _accuracy = pos.accuracy;
      _isMockLocation = pos.isMocked;
      _lastGpsFixTime = _verifiedTimestamp;
    });
  }

  Future<void> _forceRefreshGps() async {
    if (_isRefreshingGps || !mounted) return;

    setState(() {
      _isRefreshingGps = true;
    });

    try {
      final freshPos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      if (!mounted) return;

      if (_timeSourceLabel != 'GNSS-SAT') {
        _syncNativeGnssNmeaClock();
      }
      setState(() {
        _currentPosition = freshPos;
        _latitude = freshPos.latitude;
        _longitude = freshPos.longitude;
        _altitude = freshPos.altitude;
        _accuracy = freshPos.accuracy;
        _isMockLocation = freshPos.isMocked;
        _lastGpsFixTime = _verifiedTimestamp;
      });

      try {
        _mapController.move(
          LatLng(freshPos.latitude, freshPos.longitude),
          16.0,
        );
      } catch (e) {
        debugPrint('MapController move error: $e');
      }

      await _geocodePosition(freshPos);
    } catch (e) {
      debugPrint('Force refresh GPS error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshingGps = false;
        });
      }
    }
  }

  // ==========================================
  // GPS LOCATION & REVERSE GEOCODING
  // ==========================================
  Future<void> _initLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _currentAddress = 'Please enable GPS Location Services';
        });
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _currentAddress = 'Location permissions permanently denied';
        });
        return;
      }

      // Initial fast location fix (filter out stale cached fixes > 60s old)
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        final age = _verifiedTimestamp.difference(lastKnown.timestamp);
        if (age.inSeconds <= 60) {
          _applyNewPosition(lastKnown, isLiveStream: false);
          _geocodePosition(lastKnown);
        }
        // If > 60s old, discard it completely so Site A's address is never shown at Site B
      }

      // Continuous high-accuracy location stream
      await _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
        ),
      ).listen(
        (Position pos) {
          if (!mounted) return;
          _applyNewPosition(pos, isLiveStream: true);
          _throttleGeocoding(pos);
        },
        onError: (err) {
          debugPrint('Location stream error: $err');
        },
      );

      // Trigger fresh lock if no fresh cached fix was available
      if (_lastGpsFixTime == null) {
        _forceRefreshGps();
      }
    } catch (e) {
      debugPrint('Error starting location stream: $e');
    }
  }

  void _throttleGeocoding(Position pos) {
    if (_lastGeocodedPosition == null) {
      _geocodePosition(pos);
      return;
    }

    final distance = Geolocator.distanceBetween(
      _lastGeocodedPosition!.latitude,
      _lastGeocodedPosition!.longitude,
      pos.latitude,
      pos.longitude,
    );

    // Re-geocode only if moved more than 15 meters
    if (distance > 15) {
      _geocodePosition(pos);
    }
  }

  Future<void> _geocodePosition(Position pos) async {
    try {
      final placemarks =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final parts = <String>[];

        final street = p.street;
        final thoroughfare = p.thoroughfare;

        if (p.name != null &&
            p.name!.isNotEmpty &&
            p.name != thoroughfare &&
            p.name != p.subThoroughfare &&
            (street == null || !street.toLowerCase().contains(p.name!.toLowerCase()))) {
          parts.add(p.name!);
        }

        // Deduplicate: if thoroughfare is already contained inside street, skip appending it separately
        if (street != null && street.isNotEmpty) {
          if (!parts.contains(street)) {
            parts.add(street);
          }
        } else if (thoroughfare != null && thoroughfare.isNotEmpty) {
          if (!parts.contains(thoroughfare)) {
            parts.add(thoroughfare);
          }
        }

        if (p.subLocality != null &&
            p.subLocality!.isNotEmpty &&
            !parts.contains(p.subLocality)) {
          parts.add(p.subLocality!);
        }
        if (p.locality != null &&
            p.locality!.isNotEmpty &&
            !parts.contains(p.locality)) {
          parts.add(p.locality!);
        }
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) {
          final postal =
              p.postalCode != null && p.postalCode!.isNotEmpty ? ' ${p.postalCode}' : '';
          final admin = '${p.administrativeArea}$postal';
          if (!parts.contains(admin)) {
            parts.add(admin);
          }
        }
        if (p.country != null && p.country!.isNotEmpty && !parts.contains(p.country)) {
          parts.add(p.country!);
        }

        final addressStr = parts.join(', ');
        setState(() {
          _currentAddress = addressStr.isNotEmpty
              ? addressStr
              : '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
          _lastGeocodedPosition = pos;
        });
      }
    } catch (e) {
      debugPrint('Reverse geocoding error: $e');
    }
  }

  // ==========================================
  // SENSORS: MAGNETOMETER, ACCELEROMETER & COMPASS
  // ==========================================
  void _initSensors() {
    // 1. Magnetometer Stream (Magnetic field strength in µT)
    _magnetometerSubscription = magnetometerEventStream().listen(
      (MagnetometerEvent event) {
        _lastMagnetometer = event;
        // Magnitude = sqrt(x^2 + y^2 + z^2)
        final rawMagnitude =
            sqrt(event.x * event.x + event.y * event.y + event.z * event.z);

        if (_smoothedMagneticField == null) {
          _smoothedMagneticField = rawMagnitude;
        } else {
          _smoothedMagneticField = (_filterAlpha * rawMagnitude) +
              ((1.0 - _filterAlpha) * _smoothedMagneticField!);
        }

        _calculateHeadingFromRaw();
      },
      onError: (err) => debugPrint('Magnetometer stream error: $err'),
    );

    // 2. Accelerometer Stream (Tilt & Orientation)
    _accelerometerSubscription = accelerometerEventStream().listen(
      (AccelerometerEvent event) {
        _lastAccelerometer = event;
        _calculateHeadingFromRaw();
      },
      onError: (err) => debugPrint('Accelerometer stream error: $err'),
    );
  }

  void _calculateHeadingFromRaw() {
    if (_lastAccelerometer == null || _lastMagnetometer == null) return;
    final ax = _lastAccelerometer!.x;
    final ay = _lastAccelerometer!.y;
    final az = _lastAccelerometer!.z;
    final normA = sqrt(ax * ax + ay * ay + az * az);
    if (normA == 0) return;

    final pitch = asin((-ay / normA).clamp(-1.0, 1.0));
    final roll = atan2(ax, az);

    final mx = _lastMagnetometer!.x;
    final my = _lastMagnetometer!.y;
    final mz = _lastMagnetometer!.z;

    final xh = mx * cos(pitch) + mz * sin(pitch);
    final yh = mx * sin(roll) * sin(pitch) +
        my * cos(roll) -
        mz * sin(roll) * cos(pitch);

    var headingRad = atan2(-yh, xh);
    var headingDeg = headingRad * (180.0 / pi);
    if (headingDeg < 0) headingDeg += 360.0;

    if (mounted) {
      setState(() {
        _heading = headingDeg;
        _cardinalDirection = _getCardinalDirection(headingDeg);
      });
    }
  }

  String _getCardinalDirection(double heading) {
    const directions = [
      'N', 'NNE', 'NE', 'ENE',
      'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW',
      'W', 'WNW', 'NW', 'NNW'
    ];
    final index = ((heading + 11.25) % 360 / 22.5).floor();
    return directions[index % 16];
  }

  String _getFormattedTimestamp(DateTime dt) {
    return widget.settings.formatDateTime(dt);
  }

  // ==========================================
  // GOOGLE ADMOB ADAPTIVE BANNER
  // ==========================================
  Future<void> _loadAdaptiveBanner() async {
    if (_bannerAd != null || !mounted) return;

    // Await lazy SDK initialization without blocking cold start or camera preview
    await AdConfig.ensureInitialized();
    if (!mounted) return;

    final size = MediaQuery.sizeOf(context);
    final int adWidth = size.width.truncate();
    final int maxAdHeight = (size.height * 0.12).round().clamp(60, 115);

    final AdSize adaptiveSize = AdSize.getInlineAdaptiveBannerAdSize(
      adWidth,
      maxAdHeight,
    );

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

  // ==========================================
  // PHOTO CAPTURE & STAMP BURNING LOGIC
  // ==========================================
  Future<void> _handleCapture() async {
    if (_captureMode == CameraCaptureMode.photo) {
      await _captureAndBurnPhoto();
    } else {
      if (_isRecordingVideo) {
        await _stopVideoRecording();
      } else {
        await _startVideoRecording();
      }
    }
  }

  Future<void> _captureAndBurnPhoto() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isProcessingCapture) {
      return;
    }

    HapticFeedback.mediumImpact();

    // Freeze snapshot data at the exact instant of shutter tap
    _snapLat = _currentPosition?.latitude ?? _latitude;
    _snapLng = _currentPosition?.longitude ?? _longitude;
    _snapAltitude = _currentPosition?.altitude ?? _altitude;
    _snapAccuracy = _currentPosition?.accuracy ?? _accuracy;
    _snapAddress = _currentAddress;
    _snapTime = _verifiedTimestamp;
    _snapIsSatelliteTime = _isSatelliteTimeLocked;
    _snapIsClockTampered = _isClockTampered;
    _snapTimeSourceLabel = _timeSourceLabel;
    _snapMagnetic = _smoothedMagneticField;
    _snapHeading = _heading;
    _snapCardinal = _cardinalDirection;
    _snapTelemetry = _showTelemetry;
    _snapIsMocked = _isMockLocation;
    _snapVerificationHash = _buildVerificationHash(
      _snapLat,
      _snapLng,
      _snapTime,
      _snapIsMocked,
      _snapIsClockTampered,
    );

    setState(() {
      _isProcessingCapture = true;
    });

    try {
      final isOffline = _currentAddress.isEmpty ||
          _currentAddress.contains('Fetching') ||
          _currentAddress.contains('Offline') ||
          _currentAddress.contains('unavailable') ||
          _currentAddress.contains('Acquiring');

      // 1. Capture raw photo file from CameraX
      final xFile = await _cameraController!.takePicture();
      final rawBytes = await xFile.readAsBytes();

      if (isOffline && _currentPosition != null) {
        final savedFile = await MediaStorageService.saveStampedPhoto(
          rawBytes,
          isOfflinePending: true,
          latitude: _currentPosition?.latitude ?? _snapLat,
          longitude: _currentPosition?.longitude ?? _snapLng,
          altitude: _currentPosition?.altitude ?? _snapAltitude,
          accuracy: _currentPosition?.accuracy ?? _snapAccuracy,
          heading: _heading ?? _snapHeading,
          magneticField: _snapMagnetic,
          templateIndex: widget.settings.templateIndex,
          mapType: widget.settings.mapType,
          isMockLocation: _snapIsMocked,
          verifiedTimestamp: _snapTime,
          verificationHash: _snapVerificationHash,
          metadata: {
            'timestamp': _snapTime.toIso8601String(),
            'address': '',
            'lat': _snapLat,
            'lng': _snapLng,
            'altitude': '$_snapAltitude m',
            'heading': _snapHeading,
            'accuracy': _snapAccuracy,
            'magneticField': _snapMagnetic,
            'templateIndex': widget.settings.templateIndex,
            'mapType': widget.settings.mapType,
            'personName': widget.settings.personName,
            'customNote': widget.settings.customNote,
            'pendingOfflineSync': true,
            'isMocked': _snapIsMocked,
            'isClockTampered': _snapIsClockTampered,
            'timeSource': _snapTimeSourceLabel,
            'satelliteTimestampUtc': _snapTime.toUtc().toIso8601String(),
            'verificationHash': _snapVerificationHash,
          },
        );

        try {
          await File(xFile.path).delete();
        } catch (_) {}

        if (mounted) {
          setState(() {
            _latestMediaFile = savedFile;
            _isProcessingCapture = false;
          });

          ReviewService.recordSuccessfulCapture();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF1E293B),
              content: Row(
                children: [
                  const Icon(Icons.cloud_off, color: Colors.amberAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('offline_saved'),
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // 2. Decode raw photo dimensions to get exact natural aspect ratio
      final codec = await ui.instantiateImageCodec(rawBytes);
      final frame = await codec.getNextFrame();
      final imgWidth = frame.image.width.toDouble();
      final imgHeight = frame.image.height.toDouble();
      final imgAspectRatio = imgWidth / imgHeight;

      if (!mounted) return;
      setState(() {
        _capturedPhotoBytes = rawBytes;
        _capturedAspectRatio = imgAspectRatio;
      });

      // 3. Allow Flutter render pipeline to lay out the off-screen compositor
      await Future.delayed(const Duration(milliseconds: 200));

      // 4. Capture the RepaintBoundary as high-resolution composited image
      final boundary = _compositingBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;

      if (boundary == null) {
        throw Exception('Compositing render boundary not ready.');
      }

      final double captureRatio = _compressImages
          ? MediaQuery.devicePixelRatioOf(context).clamp(1.5, 2.5)
          : MediaQuery.devicePixelRatioOf(context).clamp(2.5, 3.5);
      final int jpegQuality = _compressImages ? 88 : 98;

      final ui.Image image = await boundary.toImage(pixelRatio: captureRatio);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();

      if (byteData == null) {
        throw Exception('Failed to generate PNG byte data.');
      }

      final Uint8List jpegBytes = await FlutterImageCompress.compressWithList(
        byteData.buffer.asUint8List(),
        quality: jpegQuality,
        format: CompressFormat.jpeg,
      );

      // 5. Save composited image into gallery with true EXIF metadata
      final savedFile = await MediaStorageService.saveStampedPhoto(
        jpegBytes,
        latitude: _currentPosition?.latitude ??
            (_snapLat != 0.0 ? _snapLat : null),
        longitude: _currentPosition?.longitude ??
            (_snapLng != 0.0 ? _snapLng : null),
        altitude: _currentPosition?.altitude ??
            (_snapAltitude != 0.0 ? _snapAltitude : null),
        heading: _heading ?? _snapHeading,
        isMockLocation: _snapIsMocked,
        verifiedTimestamp: _snapTime,
        verificationHash: _snapVerificationHash,
        metadata: {
          'timestamp': _snapTime.toIso8601String(),
          'address': _snapAddress,
          'lat': _snapLat,
          'lng': _snapLng,
          'altitude': '$_snapAltitude m',
          'heading': _snapHeading,
          'personName': widget.settings.personName,
          'customNote': widget.settings.customNote,
          'isMocked': _snapIsMocked,
          'isClockTampered': _snapIsClockTampered,
          'timeSource': _snapTimeSourceLabel,
          'satelliteTimestampUtc': _snapTime.toUtc().toIso8601String(),
          'verificationHash': _snapVerificationHash,
        },
      );

      // Clean up temporary camera cache file
      try {
        await File(xFile.path).delete();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _latestMediaFile = savedFile;
          _capturedPhotoBytes = null;
          _isProcessingCapture = false;
        });

        ReviewService.recordSuccessfulCapture();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('Photo saved to gallery with GPS Stamp!'),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF1E1E1E),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error capturing photo with stamp: $e');
      if (mounted) {
        setState(() {
          _capturedPhotoBytes = null;
          _isProcessingCapture = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // ==========================================
  // VIDEO RECORDING LOGIC
  // ==========================================
  Future<String?> _captureLiveStampToPng() async {
    try {
      final boundary = _liveStampKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return null;
      final tempDir = await getTemporaryDirectory();
      final stampFile = File('${tempDir.path}/video_stamp.png');
      await stampFile.writeAsBytes(byteData.buffer.asUint8List());
      return stampFile.path;
    } catch (e) {
      debugPrint('Error capturing live stamp for video: $e');
      return null;
    }
  }

  Future<void> _startVideoRecording() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isRecordingVideo) {
      return;
    }

    try {
      await _cameraController!.startVideoRecording();
      _captureLiveStampToPng(); // Pre-cache live stamp at start
      _recordDurationSeconds = 0;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordDurationSeconds++;
          });
        }
      });
      setState(() {
        _isRecordingVideo = true;
      });
    } catch (e) {
      debugPrint('Error starting video recording: $e');
    }
  }

  Future<void> _stopVideoRecording({bool isEmergency = false}) async {
    if (_cameraController == null || !_isRecordingVideo) return;

    _recordTimer?.cancel();
    _recordTimer = null;

    try {
      // Capture live stamp right before stopping
      final stampPngPath = await _captureLiveStampToPng();

      final rawVideo = await _cameraController!.stopVideoRecording();
      if (!isEmergency) {
        if (mounted) {
          setState(() {
            _isProcessingCapture = true;
          });
        }

        String finalVideoPath = rawVideo.path;

        if (stampPngPath != null && await File(stampPngPath).exists()) {
          final tempDir = await getTemporaryDirectory();
          final timestamp = _verifiedTimestamp.millisecondsSinceEpoch;
          final stampedVideoPath = '${tempDir.path}/stamped_$timestamp.mp4';

          final cmd = '-y -i "${rawVideo.path}" -i "$stampPngPath" '
              '-filter_complex "[1:v][0:v]scale2ref=w=iw*0.94:h=ow/mdar[stamp][vid];[vid][stamp]overlay=(W-w)/2:H-h-24" '
              '-c:v libx264 -preset ultrafast -crf 23 -c:a copy "$stampedVideoPath"';

          final session = await FFmpegKit.execute(cmd);
          final returnCode = await session.getReturnCode();

          if (ReturnCode.isSuccess(returnCode)) {
            finalVideoPath = stampedVideoPath;
          } else {
            final output = await session.getOutput();
            debugPrint('FFmpeg video burning failed: $output');
          }
        }

        final saved =
            await MediaStorageService.saveStampedVideo(finalVideoPath);

        // Clean up temporary raw video file if stamped was created
        try {
          if (finalVideoPath != rawVideo.path) {
            await File(rawVideo.path).delete();
          }
        } catch (_) {}

        if (mounted) {
          setState(() {
            _latestMediaFile = saved;
            _isRecordingVideo = false;
            _isProcessingCapture = false;
          });

          ReviewService.recordSuccessfulCapture();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video saved to gallery with GPS Stamp!'),
              backgroundColor: Color(0xFF1E1E1E),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error stopping video recording: $e');
      if (mounted) {
        setState(() {
          _isRecordingVideo = false;
          _isProcessingCapture = false;
        });
      }
    }
  }

  // ==========================================
  // UI BUILD & SCREEN LAYOUT
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final liveLat = _currentPosition?.latitude ?? _latitude;
    final liveLng = _currentPosition?.longitude ?? _longitude;
    final liveTimestamp = _verifiedTimestamp;
    final liveFormattedDateTime = _liveFormattedDateTime.isNotEmpty
        ? _liveFormattedDateTime
        : _getFormattedTimestamp(liveTimestamp);
    final liveVerificationHash = _buildVerificationHash(
      liveLat,
      liveLng,
      liveTimestamp,
      _isMockLocation,
      _isClockTampered,
    );

    final controller = _cameraController;
    final bool canShowPreview = controller != null &&
        !_isSwitchingCamera &&
        _isCameraInitialized &&
        controller.value.isInitialized;

    if ((canShowPreview || _cameraErrorMessage != null) && !_hasScheduledBanner) {
      _hasScheduledBanner = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadAdaptiveBanner();
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ----------------------------------------------------
          // 1. FULL-SCREEN CAMERA PREVIEW (With Tap-to-Focus & Pinch-to-Zoom)
          // ----------------------------------------------------
          if (canShowPreview)
            Center(
              child: AspectRatio(
                aspectRatio: 1 / controller.value.aspectRatio,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (TapUpDetails details) async {
                        final offset = Offset(
                          (details.localPosition.dx / constraints.maxWidth)
                              .clamp(0.0, 1.0),
                          (details.localPosition.dy / constraints.maxHeight)
                              .clamp(0.0, 1.0),
                        );

                        try {
                          await controller.setFocusPoint(offset);
                          await controller.setExposurePoint(offset);
                        } catch (e) {
                          debugPrint('Focus/Exposure point error: $e');
                        }

                        setState(() {
                          _focusPoint = details.localPosition;
                        });

                        _focusRingTimer?.cancel();
                        _focusRingTimer =
                            Timer(const Duration(milliseconds: 1200), () {
                          if (mounted) {
                            setState(() {
                              _focusPoint = null;
                            });
                          }
                        });
                      },
                      onScaleStart: (_) {
                        _baseZoom = _currentZoom;
                      },
                      onScaleUpdate: (ScaleUpdateDetails details) async {
                        if (details.scale != 1.0 &&
                            controller.value.isInitialized) {
                          final newZoom = (_baseZoom * details.scale)
                              .clamp(_minZoom, _maxZoom);
                          setState(() {
                            _currentZoom = newZoom;
                          });
                          try {
                            await controller.setZoomLevel(newZoom);
                          } catch (e) {
                            debugPrint('Zoom level error: $e');
                          }
                        }
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CameraPreview(controller),
                          Positioned.fill(
                            child: CameraGridOverlay(gridMode: _gridMode),
                          ),
                          Positioned.fill(
                            child:
                                HorizonLevelOverlay(enabled: _showHorizonLevel),
                          ),
                          // 64x64 rounded focus square at tapped spot
                          if (_focusPoint != null)
                            Positioned(
                              left: _focusPoint!.dx - 32,
                              top: _focusPoint!.dy - 32,
                              child: IgnorePointer(
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.amberAccent,
                                      width: 1.8,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            )
          else
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 80.0),
                child: _cameraErrorMessage != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 48),
                          const SizedBox(height: 12),
                          Text(
                            _cameraErrorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.amberAccent),
                            onPressed: _initCameras,
                            child: const Text('Retry Camera',
                                style: TextStyle(color: Colors.black)),
                          ),
                        ],
                      )
                    : const CircularProgressIndicator(color: Colors.amberAccent),
              ),
            ),

          // ----------------------------------------------------
          // 2. TOP FLOATING TOOLBAR
          // ----------------------------------------------------
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.black.withOpacity(0.6),
                      Colors.transparent,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Flash Mode Toggle
                    IconButton(
                      icon: Icon(
                        _currentFlashMode == FlashMode.auto
                            ? Icons.flash_auto
                            : _currentFlashMode == FlashMode.always
                                ? Icons.flash_on
                                : Icons.flash_off,
                        color: _currentFlashMode != FlashMode.off
                            ? Colors.amberAccent
                            : Colors.white,
                      ),
                      onPressed: _cycleFlashMode,
                    ),

                    // Video Duration Badge (when recording)
                    if (_isRecordingVideo)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fiber_manual_record,
                                color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${(_recordDurationSeconds ~/ 60).toString().padLeft(2, '0')}:${(_recordDurationSeconds % 60).toString().padLeft(2, '0')}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),

                    // 1-Tap GPS Refresh & Status Pill Button
                    Builder(
                      builder: (context) {
                        final int? secAgo = _lastGpsFixTime != null
                            ? _verifiedTimestamp
                                .difference(_lastGpsFixTime!)
                                .inSeconds
                                .clamp(0, 999)
                            : null;
                        final bool isFresh = _lastGpsFixTime != null &&
                            _verifiedTimestamp
                                    .difference(_lastGpsFixTime!)
                                    .inSeconds <=
                                15;

                        return GestureDetector(
                          onTap: _isRefreshingGps ? null : _forceRefreshGps,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white24,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isRefreshingGps)
                                  const SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.8,
                                      color: Colors.amberAccent,
                                    ),
                                  )
                                else ...[
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: isFresh
                                          ? Colors.greenAccent
                                          : Colors.amberAccent,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.refresh,
                                    size: 15,
                                    color: Colors.white,
                                  ),
                                ],
                                const SizedBox(width: 5),
                                Text(
                                  _isRefreshingGps
                                      ? 'Locating...'
                                      : (_lastGpsFixTime != null
                                          ? '${secAgo}s'
                                          : 'GPS'),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    // Right Toolbar Actions (Flip, Telemetry, Settings)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Telemetry Visibility Toggle
                        IconButton(
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            _showTelemetry
                                ? Icons.sensors
                                : Icons.sensors_off,
                            color: _showTelemetry
                                ? Colors.cyanAccent
                                : Colors.white60,
                          ),
                          onPressed: () {
                            setState(() {
                              _showTelemetry = !_showTelemetry;
                            });
                          },
                        ),
                        // Guidance Grid Toggle
                        IconButton(
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                          icon: Icon(
                            _gridMode != 'off' ? Icons.grid_on : Icons.grid_off,
                            color: _gridMode != 'off'
                                ? Colors.amberAccent
                                : Colors.white,
                          ),
                          onPressed: _cycleGridMode,
                        ),
                        // Camera Flip (Front/Back)
                        IconButton(
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.flip_camera_ios_rounded,
                              color: Colors.white),
                          onPressed: _toggleCamera,
                        ),
                        // Settings Button
                        IconButton(
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.settings_outlined,
                              color: Colors.white),
                          onPressed: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SettingsScreen(settings: widget.settings),
                              ),
                            );
                            await _loadGridMode();
                            await _loadHorizonLevel();
                            await _loadCompressionSetting();
                            await _loadVerifiedBadgeSetting();
                            await _loadMapsLinkSetting();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ----------------------------------------------------
          // 3. LIVE GEO-STAMP OVERLAY & COMPACT QUICK-ZOOM PILLS
          // ----------------------------------------------------
          Positioned(
            left: 0,
            right: 0,
            bottom: 110,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Compact translucent quick-zoom pill bar (with 6px bottom margin)
                if (canShowPreview &&
                    (_maxZoom > 1.0 ||
                        _minZoom < 1.0 ||
                        (_ultraWideBackCamera != null &&
                            _cameraController?.description.lensDirection ==
                                CameraLensDirection.back)))
                  Builder(
                    builder: (context) {
                      final bool isRearCamera = _cameraController != null &&
                          _cameraController!.description.lensDirection ==
                              CameraLensDirection.back;
                      final bool showUltraWidePill = isRearCamera &&
                          (_minZoom < 1.0 || _ultraWideBackCamera != null);
                      final String ultraWideLabel = _minZoom < 1.0
                          ? '${_minZoom.toStringAsFixed(1)}x'
                          : '0.5x';
                      final bool isUltraWideActive =
                          _isUsingUltraWide || _currentZoom < 0.95;

                      final presets = [1.0, 2.0, 3.0, 5.0]
                          .where((z) => z <= _maxZoom || z == 1.0)
                          .toList();

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (showUltraWidePill)
                              GestureDetector(
                                onTap: _onUltraWideTapped,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isUltraWideActive
                                        ? Colors.black54
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    ultraWideLabel,
                                    style: TextStyle(
                                      color: isUltraWideActive
                                          ? Colors.amberAccent
                                          : Colors.white,
                                      fontSize: 12,
                                      fontWeight: isUltraWideActive
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                            ...presets.map((preset) {
                              final bool isActive = !_isUsingUltraWide &&
                                  (_currentZoom - preset).abs() < 0.25;
                              return GestureDetector(
                                onTap: () => _onStandardZoomTapped(preset),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? Colors.black54
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    isActive
                                        ? '${_currentZoom.toStringAsFixed(1)}x'
                                        : '${preset.toStringAsFixed(1)}x',
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.amberAccent
                                          : Colors.white,
                                      fontSize: 12,
                                      fontWeight: isActive
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),

                // Live Geo-Stamp Overlay
                RepaintBoundary(
                  key: _liveStampKey,
                  child: GeoStampOverlay(
                    latitude: liveLat,
                    longitude: liveLng,
                    altitude: _altitude,
                    accuracy: _accuracy,
                    address: _currentAddress,
                    formattedDateTime: liveFormattedDateTime,
                    magneticField: _smoothedMagneticField,
                    heading: _heading ?? 0.0,
                    cardinalDirection: _cardinalDirection,
                    showTelemetry: _showTelemetry,
                    settings: widget.settings,
                    mapController: _mapController,
                    showVerifiedBadge: _showVerifiedBadge,
                    isMockLocation: _isMockLocation,
                    isSatelliteTime: _isSatelliteTimeLocked,
                    verificationHash: liveVerificationHash,
                    includeMapsLink: _includeMapsLink,
                    isClockTampered: _isClockTampered,
                    timeSourceLabel: _timeSourceLabel,
                  ),
                ),
              ],
            ),
          ),

          // ----------------------------------------------------
          // 4. BOTTOM SHUTTER CONTROLS ROW
          // ----------------------------------------------------
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Recent Media Gallery Thumbnail
                  Builder(
                    builder: (context) {
                      final bool isLatestVideo = _latestMediaFile != null &&
                          _latestMediaFile!.path.toLowerCase().endsWith('.mp4');

                      return GestureDetector(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const GalleryScreen()),
                          );
                          _loadLatestThumbnail();
                        },
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: ClipOval(
                            child: isLatestVideo
                                ? Container(
                                    color: Colors.grey.shade900,
                                    child: const Center(
                                      child: Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 26,
                                      ),
                                    ),
                                  )
                                : (_latestMediaFile != null
                                    ? Image.file(
                                        _latestMediaFile!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                          Icons.photo_library,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.photo_library,
                                        color: Colors.white,
                                        size: 22,
                                      )),
                          ),
                        ),
                      );
                    },
                  ),

                  // Center: Shutter Button
                  GestureDetector(
                    onTap: _handleCapture,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: Colors.black38,
                      ),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _isRecordingVideo ? 26 : 56,
                          height: _isRecordingVideo ? 26 : 56,
                          decoration: BoxDecoration(
                            shape: _isRecordingVideo
                                ? BoxShape.rectangle
                                : BoxShape.circle,
                            borderRadius: _isRecordingVideo
                                ? BorderRadius.circular(6)
                                : null,
                            color: _captureMode == CameraCaptureMode.video
                                ? Colors.redAccent
                                : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Right: Photo / Video Mode Switcher
                  IconButton(
                    iconSize: 32,
                    icon: Icon(
                      _captureMode == CameraCaptureMode.photo
                          ? Icons.videocam_outlined
                          : Icons.camera_alt_outlined,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (_isRecordingVideo) return;
                      setState(() {
                        _captureMode = _captureMode == CameraCaptureMode.photo
                            ? CameraCaptureMode.video
                            : CameraCaptureMode.photo;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),

          // ----------------------------------------------------
          // 5. PROCESSING / FLASH INDICATOR
          // ----------------------------------------------------
          if (_isProcessingCapture)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.amberAccent),
                    SizedBox(height: 14),
                    Text(
                      'Burning Geo-Stamp & Saving...',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

          // ----------------------------------------------------
          // 6. OFFSCREEN REPAINT BOUNDARY FOR STAMP COMPOSITING
          // ----------------------------------------------------
          if (_capturedPhotoBytes != null)
            Transform.translate(
              offset: const Offset(-99999, -99999),
              child: RepaintBoundary(
                key: _compositingBoundaryKey,
                child: SizedBox(
                  width: 412.0,
                  height: 412.0 / _capturedAspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Raw Captured Photo
                      Image.memory(
                        _capturedPhotoBytes!,
                        fit: BoxFit.cover,
                      ),
                      // Burned Geo-Stamp Overlay at the bottom
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 16,
                        child: GeoStampOverlay(
                          latitude: _snapLat,
                          longitude: _snapLng,
                          altitude: _snapAltitude,
                          accuracy: _snapAccuracy,
                          address: _snapAddress,
                          formattedDateTime:
                              _getFormattedTimestamp(_snapTime),
                          magneticField: _snapMagnetic,
                          heading: _snapHeading ?? 0.0,
                          cardinalDirection: _snapCardinal,
                          showTelemetry: _snapTelemetry,
                          settings: widget.settings,
                          margin: EdgeInsets.zero,
                          showVerifiedBadge: _showVerifiedBadge,
                          isMockLocation: _snapIsMocked,
                          isSatelliteTime: _snapIsSatelliteTime,
                          verificationHash: _snapVerificationHash,
                          includeMapsLink: _includeMapsLink,
                          isClockTampered: _snapIsClockTampered,
                          timeSourceLabel: _snapTimeSourceLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),

      // ----------------------------------------------------
      // BOTTOM NAVIGATION BAR: GOOGLE ADMOB BANNER
      // ----------------------------------------------------
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: Colors.black,
          height: _bannerAd?.size.height.toDouble() ??
              (MediaQuery.sizeOf(context).height * 0.12)
                  .round()
                  .clamp(60, 115)
                  .toDouble(),
          width: double.infinity,
          alignment: Alignment.center,
          child: (_isBannerLoaded && _bannerAd != null)
              ? AdWidget(ad: _bannerAd!)
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
