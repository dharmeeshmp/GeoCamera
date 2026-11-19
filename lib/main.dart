import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/ad_config.dart';
import 'models/app_settings.dart';
import 'screens/gallery_screen.dart';
import 'screens/permission_screen.dart';
import 'screens/settings_screen.dart';
import 'services/media_storage_service.dart';
import 'services/review_service.dart';
import 'widgets/camera_grid_overlay.dart';
import 'widgets/geo_stamp_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await MobileAds.instance.initialize();
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
    return MaterialApp(
      title: 'GPS Map Camera',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: PermissionScreen(settings: settings),
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
  bool _isCameraReady = false;
  bool _isCameraInitializing = false;
  bool _isSwitchingCamera = false;
  String? _cameraErrorMessage;

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

  // In-App Gallery Thumbnail State
  File? _latestMediaFile;

  // Sensor & Telemetry State
  bool _isGpsLocked = false;
  Position? _currentPosition;
  double _latitude = 0.0;
  double _longitude = 0.0;
  double _altitude = 0.0;
  double _accuracy = 0.0;
  String _currentAddress = 'Acquiring GPS location...';
  Position? _lastGeocodedPosition;
  Timer? _clockTimer;

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
  DateTime _snapTime = DateTime.now();
  double? _snapMagnetic;
  double? _snapHeading;
  String _snapCardinal = '--';
  bool _snapTelemetry = true;

  // AdMob Banner State
  BannerAd? _bannerAd;
  bool _isBannerLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAdaptiveBanner();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_onSettingsChanged);
    _loadGridMode();
    _initializeAll();
    _loadLatestThumbnail();
    _startClockTimer();
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
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
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
            _isCameraReady = false;
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
        _isCameraReady = false;
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

      final currentZoom = 1.0.clamp(minZoom, maxZoom);
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
          _isCameraReady = true;
          _isSwitchingCamera = false;
          _isCameraInitializing = false;
          _cameraErrorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
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
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _initCamera(_cameras[_selectedCameraIndex]);
  }

  /// Alias for camera switching
  Future<void> _switchCamera() => _toggleCamera();

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

      // Initial fast location fix
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null && mounted) {
        setState(() {
          _currentPosition = lastPos;
          _latitude = lastPos.latitude;
          _longitude = lastPos.longitude;
          _altitude = lastPos.altitude;
          _accuracy = lastPos.accuracy;
          _isGpsLocked = true;
        });
        _geocodePosition(lastPos);
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
          setState(() {
            _currentPosition = pos;
            _latitude = pos.latitude;
            _longitude = pos.longitude;
            _altitude = pos.altitude;
            _accuracy = pos.accuracy;
            _isGpsLocked = true;
          });
          _throttleGeocoding(pos);
        },
        onError: (err) {
          debugPrint('Location stream error: $err');
        },
      );
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
    final base = DateFormat('EEE, MMM d, yyyy, hh:mm a').format(dt);
    final offset = dt.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final hours = offset.inHours.abs();
    final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '$base, GMT $sign$hours:$minutes';
  }

  // ==========================================
  // GOOGLE ADMOB ADAPTIVE BANNER
  // ==========================================
  Future<void> _loadAdaptiveBanner() async {
    if (_bannerAd != null || !mounted) return;

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
    _snapLat = _latitude;
    _snapLng = _longitude;
    _snapAltitude = _altitude;
    _snapAccuracy = _accuracy;
    _snapAddress = _currentAddress;
    _snapTime = DateTime.now();
    _snapMagnetic = _smoothedMagneticField;
    _snapHeading = _heading;
    _snapCardinal = _cardinalDirection;
    _snapTelemetry = _showTelemetry;

    setState(() {
      _isProcessingCapture = true;
    });

    try {
      // 1. Capture raw photo file from CameraX
      final xFile = await _cameraController!.takePicture();
      final rawBytes = await xFile.readAsBytes();

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

      final ui.Image compositedUiImage =
          await boundary.toImage(pixelRatio: 2.5);
      final byteData = await compositedUiImage.toByteData(
          format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('Failed to generate PNG byte data.');
      }

      final pngBytes = byteData.buffer.asUint8List();

      // 5. Save composited image into gallery using Gal
      final savedFile =
          await MediaStorageService.saveCompositedImage(pngBytes);

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
          final timestamp = DateTime.now().millisecondsSinceEpoch;
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
    final now = DateTime.now();
    final liveFormattedDateTime = _getFormattedTimestamp(now);

    final controller = _cameraController;
    final bool canShowPreview = controller != null &&
        !_isSwitchingCamera &&
        _isCameraInitialized &&
        controller.value.isInitialized;

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

                    // Right Toolbar Actions (Flip, Telemetry, Settings)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Telemetry Visibility Toggle
                        IconButton(
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
                          icon: const Icon(Icons.flip_camera_ios_rounded,
                              color: Colors.white),
                          onPressed: _toggleCamera,
                        ),
                        // Settings Button
                        IconButton(
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
                if (canShowPreview && _maxZoom > 1.0)
                  Builder(
                    builder: (context) {
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
                          children: presets.map((preset) {
                            final bool isActive =
                                (_currentZoom - preset).abs() < 0.25;
                            return GestureDetector(
                              onTap: () async {
                                setState(() {
                                  _currentZoom = preset;
                                });
                                try {
                                  await _cameraController?.setZoomLevel(preset);
                                } catch (e) {
                                  debugPrint('Error setting zoom: $e');
                                }
                              },
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
                          }).toList(),
                        ),
                      );
                    },
                  ),

                // Live Geo-Stamp Overlay
                RepaintBoundary(
                  key: _liveStampKey,
                  child: GeoStampOverlay(
                    latitude: _latitude,
                    longitude: _longitude,
                    altitude: _altitude,
                    accuracy: _accuracy,
                    address: _currentAddress,
                    formattedDateTime: liveFormattedDateTime,
                    magneticField: _smoothedMagneticField,
                    heading: _heading,
                    cardinalDirection: _cardinalDirection,
                    showTelemetry: _showTelemetry,
                    settings: widget.settings,
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
                          heading: _snapHeading,
                          cardinalDirection: _snapCardinal,
                          showTelemetry: _snapTelemetry,
                          settings: widget.settings,
                          margin: EdgeInsets.zero,
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
        child: SizedBox(
          height: _bannerAd?.size.height.toDouble() ??
              (MediaQuery.sizeOf(context).height * 0.12)
                  .round()
                  .clamp(60, 115)
                  .toDouble(),
          width: double.infinity,
          child: (_isBannerLoaded && _bannerAd != null)
              ? AdWidget(ad: _bannerAd!)
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}
