import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'models/app_settings.dart';
import 'screens/gallery_screen.dart';
import 'screens/permission_screen.dart';
import 'screens/settings_screen.dart';
import 'services/media_storage_service.dart';
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
  bool _isCameraReady = false;
  bool _isCameraInitializing = false;
  String? _cameraErrorMessage;

  // Capture Mode & Video Recording State
  CameraCaptureMode _captureMode = CameraCaptureMode.photo;
  bool _isRecordingVideo = false;
  bool _isProcessingCapture = false;
  int _recordDurationSeconds = 0;
  Timer? _recordTimer;

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
  bool _isBannerAdLoaded = false;
  static const String _adUnitId = 'ca-app-pub-3940256099942544/6300978111';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.settings.addListener(_onSettingsChanged);
    _initializeAll();
    _loadLatestThumbnail();
    _startClockTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.settings.removeListener(_onSettingsChanged);
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
      setState(() {});
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
        controller.dispose();
        _cameraController = null;
        if (mounted) {
          setState(() {
            _isCameraReady = false;
          });
        }
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
    _initAdMob();
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

  Future<void> _initCamera(CameraDescription description) async {
    final prevController = _cameraController;
    final newController = CameraController(
      description,
      ResolutionPreset.veryHigh,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    await prevController?.dispose();

    try {
      await newController.initialize();
      await newController.setFlashMode(_currentFlashMode);
      if (mounted) {
        setState(() {
          _cameraController = newController;
          _isCameraReady = true;
          _isCameraInitializing = false;
          _cameraErrorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
          _cameraErrorMessage = 'Failed to start camera: $e';
        });
      }
    }
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length < 2 || _cameraController == null) return;
    _selectedCameraIndex = (_selectedCameraIndex + 1) % _cameras.length;
    await _initCamera(_cameras[_selectedCameraIndex]);
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

        if (p.name != null &&
            p.name!.isNotEmpty &&
            p.name != p.thoroughfare &&
            p.name != p.subThoroughfare) {
          parts.add(p.name!);
        }
        if (p.street != null &&
            p.street!.isNotEmpty &&
            !parts.contains(p.street)) {
          parts.add(p.street!);
        }
        if (p.subLocality != null && p.subLocality!.isNotEmpty) {
          parts.add(p.subLocality!);
        }
        if (p.locality != null && p.locality!.isNotEmpty) {
          parts.add(p.locality!);
        }
        if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) {
          final postal =
              p.postalCode != null && p.postalCode!.isNotEmpty ? ' ${p.postalCode}' : '';
          parts.add('${p.administrativeArea}$postal');
        }
        if (p.country != null && p.country!.isNotEmpty) {
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
  // GOOGLE ADMOB BANNER
  // ==========================================
  void _initAdMob() {
    _bannerAd = BannerAd(
      adUnitId: _adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint('AdMob Banner successfully loaded.');
          if (mounted) {
            setState(() {
              _isBannerAdLoaded = true;
            });
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdMob Banner failed to load: $error');
          ad.dispose();
        },
      ),
    );
    _bannerAd!.load();
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
  Future<void> _startVideoRecording() async {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _isRecordingVideo) {
      return;
    }

    try {
      await _cameraController!.startVideoRecording();
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
      final file = await _cameraController!.stopVideoRecording();
      if (!isEmergency) {
        final saved = await MediaStorageService.saveVideo(file.path);
        if (mounted) {
          setState(() {
            _latestMediaFile = saved;
            _isRecordingVideo = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Video saved to gallery!'),
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ----------------------------------------------------
          // 1. FULL-SCREEN CAMERA PREVIEW
          // ----------------------------------------------------
          if (_isCameraReady && _cameraController != null)
            Center(
              child: AspectRatio(
                aspectRatio: 1 / _cameraController!.value.aspectRatio,
                child: CameraPreview(_cameraController!),
              ),
            )
          else
            Center(
              child: _cameraErrorMessage != null
                  ? Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
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
                      ),
                    )
                  : const CircularProgressIndicator(color: Colors.amberAccent),
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
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    SettingsScreen(settings: widget.settings),
                              ),
                            );
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
          // 3. LIVE GEO-STAMP OVERLAY (Anchored Above Shutter)
          // ----------------------------------------------------
          Positioned(
            left: 0,
            right: 0,
            bottom: 110,
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
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const GalleryScreen()),
                      );
                      _loadLatestThumbnail();
                    },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: ClipOval(
                        child: _latestMediaFile != null
                            ? Image.file(
                                _latestMediaFile!,
                                fit: BoxFit.cover,
                              )
                            : const Icon(Icons.photo_library,
                                color: Colors.white70, size: 24),
                      ),
                    ),
                  ),

                  // Center: Shutter Button
                  GestureDetector(
                    onTap: _handleCapture,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: Colors.black38,
                      ),
                      padding: const EdgeInsets.all(4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          shape: _isRecordingVideo
                              ? BoxShape.rectangle
                              : BoxShape.circle,
                          borderRadius: _isRecordingVideo
                              ? BorderRadius.circular(8)
                              : null,
                          color: _captureMode == CameraCaptureMode.video
                              ? Colors.redAccent
                              : Colors.white,
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
                  width: 1080,
                  height: 1080 / _capturedAspectRatio,
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
                        left: 0,
                        right: 0,
                        bottom: 24,
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
                          scale: 1.45,
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
      bottomNavigationBar: _isBannerAdLoaded && _bannerAd != null
          ? SafeArea(
              top: false,
              child: Container(
                width: _bannerAd!.size.width.toDouble(),
                height: _bannerAd!.size.height.toDouble(),
                color: Colors.black,
                alignment: Alignment.center,
                child: AdWidget(ad: _bannerAd!),
              ),
            )
          : null,
    );
  }
}
