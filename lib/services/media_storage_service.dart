import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:gal/gal.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:native_exif/native_exif.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../widgets/geo_stamp_overlay.dart';

class MediaStorageService {
  static const String _mediaListPrefKey = 'saved_media_file_paths';

  /// Save composited PNG/JPEG bytes to the device gallery using the Gal package.
  /// Embeds true EXIF GPS & Compass tags, stores the file in the app documents directory
  /// for in-app gallery access, and writes a matching JSON sidecar metadata file (<photo_path_without_ext>.json).
  static Future<File?> saveStampedPhoto(
    Uint8List imageBytes, {
    Map<String, dynamic>? metadata,
    double? latitude,
    double? longitude,
    double? altitude,
    double? heading,
    bool isOfflinePending = false,
    double? accuracy,
    double? magneticField,
    int? templateIndex,
    String? mapType,
    bool? isMockLocation,
    DateTime? verifiedTimestamp,
    String? verificationHash,
  }) async {
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          debugPrint('Gallery access permission denied.');
        }
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${docsDir.path}/GPSCameraMedia');
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }

      final bool compressImages =
          (await SharedPreferences.getInstance()).getBool('compress_images') ??
              true;
      final int quality = compressImages ? 88 : 98;

      final Uint8List finalJpegBytes =
          (imageBytes.length >= 2 && imageBytes[0] == 0xFF && imageBytes[1] == 0xD8)
              ? imageBytes
              : await FlutterImageCompress.compressWithList(
                  imageBytes,
                  quality: quality,
                  format: CompressFormat.jpeg,
                );

      final effectiveTimestamp = verifiedTimestamp ??
          (metadata?['satelliteTimestampUtc'] != null
              ? DateTime.tryParse(metadata!['satelliteTimestampUtc'])?.toLocal()
              : null) ??
          (metadata?['timestamp'] != null
              ? DateTime.tryParse(metadata!['timestamp'])?.toLocal()
              : null) ??
          DateTime.now();

      final timestamp = effectiveTimestamp.millisecondsSinceEpoch;
      final fileName = 'GPSCAM_$timestamp.jpg';
      final localFile = File('${mediaDir.path}/$fileName');
      await localFile.writeAsBytes(finalJpegBytes);

      // Resolve coordinates from direct parameters or metadata map fallback
      final effLat = latitude ??
          (metadata?['lat'] is num
              ? (metadata!['lat'] as num).toDouble()
              : null);
      final effLng = longitude ??
          (metadata?['lng'] is num
              ? (metadata!['lng'] as num).toDouble()
              : null);
      final effAlt = altitude ??
          (metadata?['altitude'] is num
              ? (metadata!['altitude'] as num).toDouble()
              : null);
      final effHeading = heading ??
          (metadata?['heading'] is num
              ? (metadata!['heading'] as num).toDouble()
              : null);

      // Write true machine-readable EXIF GPS + Compass tags
      if (effLat != null && effLng != null) {
        try {
          final exif = await Exif.fromPath(localFile.path);
          try {
            await exif.writeAttributes({
              'GPSLatitude': effLat.abs().toString(),
              'GPSLatitudeRef': effLat >= 0 ? 'N' : 'S',
              'GPSLongitude': effLng.abs().toString(),
              'GPSLongitudeRef': effLng >= 0 ? 'E' : 'W',
              if (effAlt != null)
                'GPSAltitude': effAlt.abs().toStringAsFixed(1),
              if (effAlt != null) 'GPSAltitudeRef': effAlt >= 0 ? '0' : '1',
              if (effHeading != null)
                'GPSImgDirection': effHeading.toStringAsFixed(1),
              if (effHeading != null) 'GPSImgDirectionRef': 'M',
              'DateTimeOriginal':
                  DateFormat('yyyy:MM:dd HH:mm:ss').format(effectiveTimestamp),
              'Software': 'GPS Map Camera',
            });
          } finally {
            await exif.close();
          }
        } catch (e) {
          debugPrint('Error writing EXIF attributes: $e');
        }
      }

      // Save matching JSON sidecar metadata
      try {
        final sidecarPath =
            localFile.path.replaceAll(RegExp(r'\.[^.]+$'), '.json');
        final prefs = await SharedPreferences.getInstance();
        final personName = metadata?['personName'] ??
            prefs.getString('person_name') ??
            '';
        final customNote = metadata?['customNote'] ??
            prefs.getString('custom_note') ??
            '';
        final address = metadata?['address'] ??
            prefs.getString('custom_address') ??
            '';
        final altitudeStr = metadata?['altitude'] ??
            (effAlt != null ? '${effAlt.toStringAsFixed(1)}m' : '');
        final String? satTimeUtc = verifiedTimestamp?.toUtc().toIso8601String() ??
            metadata?['satelliteTimestampUtc'] as String?;
        final timeStr = metadata?['timestamp'] ??
            satTimeUtc ??
            effectiveTimestamp.toIso8601String();
        final String? vHash =
            verificationHash ?? metadata?['verificationHash'] as String?;

        final bool isMocked = isMockLocation ??
            (metadata?['isMocked'] is bool
                ? metadata!['isMocked'] as bool
                : false);

        final metaJson = {
          'timestamp': timeStr,
          'address': address,
          'lat': effLat,
          'lng': effLng,
          'altitude': altitudeStr,
          'heading': effHeading,
          'accuracy': accuracy ?? metadata?['accuracy'],
          'magneticField': magneticField ?? metadata?['magneticField'],
          'templateIndex': templateIndex ?? metadata?['templateIndex'],
          'mapType': mapType ?? metadata?['mapType'],
          'personName': personName,
          'customNote': customNote,
          'pendingOfflineSync': isOfflinePending,
          'isMocked': isMocked,
          if (satTimeUtc != null) 'satelliteTimestampUtc': satTimeUtc,
          if (vHash != null) 'verificationHash': vHash,
        };
        await File(sidecarPath).writeAsString(jsonEncode(metaJson));
      } catch (e) {
        debugPrint('Error writing metadata sidecar: $e');
      }

      // CRITICAL ORDER: Save the file containing written EXIF headers to public gallery
      await Gal.putImage(
        localFile.path,
        album: 'GPS Camera',
      );

      // Record in preferences for fast tracking
      await _recordMediaFilePath(localFile.path);

      return localFile;
    } catch (e) {
      debugPrint('Error saving composited image: $e');
      return null;
    }
  }

  /// Backward-compatible alias for saveStampedPhoto
  static Future<File?> saveCompositedImage(
    Uint8List imageBytes, {
    Map<String, dynamic>? metadata,
    double? latitude,
    double? longitude,
    double? altitude,
    double? heading,
    bool isOfflinePending = false,
    double? accuracy,
    double? magneticField,
    int? templateIndex,
    String? mapType,
  }) =>
      saveStampedPhoto(
        imageBytes,
        metadata: metadata,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        heading: heading,
        isOfflinePending: isOfflinePending,
        accuracy: accuracy,
        magneticField: magneticField,
        templateIndex: templateIndex,
        mapType: mapType,
      );

  /// Returns true if this media file is a photo waiting for offline sync.
  static Future<bool> isPendingOfflineSync(File file) async {
    if (file.path.toLowerCase().endsWith('.mp4')) return false;
    try {
      final sidecarPath = file.path.replaceAll(RegExp(r'\.[^.]+$'), '.json');
      final sidecarFile = File(sidecarPath);
      if (await sidecarFile.exists()) {
        final content = await sidecarFile.readAsString();
        final data = jsonDecode(content);
        if (data is Map<String, dynamic>) {
          return data['pendingOfflineSync'] == true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// Composites live map and fetched street address onto a deferred offline photo.
  static Future<bool> syncAndStampOfflinePhoto({
    required File rawPhotoFile,
    required BuildContext context,
  }) async {
    final sidecarPath =
        rawPhotoFile.path.replaceAll(RegExp(r'\.[^.]+$'), '.json');
    final sidecarFile = File(sidecarPath);
    if (!await sidecarFile.exists()) {
      throw Exception('Missing metadata sidecar for offline photo.');
    }

    final sidecarJson = await sidecarFile.readAsString();
    final sidecarData = jsonDecode(sidecarJson) as Map<String, dynamic>;

    final double? lat = sidecarData['lat'] is num
        ? (sidecarData['lat'] as num).toDouble()
        : null;
    final double? lng = sidecarData['lng'] is num
        ? (sidecarData['lng'] as num).toDouble()
        : null;

    if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) {
      throw Exception('No GPS coordinates found in offline metadata.');
    }

    final double alt = sidecarData['altitude'] is num
        ? (sidecarData['altitude'] as num).toDouble()
        : double.tryParse(sidecarData['altitude']
                ?.toString()
                .replaceAll(RegExp(r'[^0-9.]'), '') ??
            '') ??
        0.0;
    final double accuracy = sidecarData['accuracy'] is num
        ? (sidecarData['accuracy'] as num).toDouble()
        : 5.0;
    final double heading = sidecarData['heading'] is num
        ? (sidecarData['heading'] as num).toDouble()
        : 0.0;
    final double? magneticField = sidecarData['magneticField'] is num
        ? (sidecarData['magneticField'] as num).toDouble()
        : null;
    final String timeStr = sidecarData['satelliteTimestampUtc'] ??
        sidecarData['timestamp'] ??
        DateTime.now().toIso8601String();
    final String personName = sidecarData['personName'] ?? '';
    final String customNote = sidecarData['customNote'] ?? '';
    final int? templateIndex = sidecarData['templateIndex'] is int
        ? sidecarData['templateIndex'] as int
        : null;
    final String? mapType = sidecarData['mapType'] as String?;

    // 2. Reverse-geocode (lat, lng) to build full street address
    List<Placemark> placemarks;
    try {
      placemarks = await placemarkFromCoordinates(lat, lng);
    } catch (_) {
      throw Exception('Still offline — please connect to internet and retry.');
    }

    if (placemarks.isEmpty) {
      throw Exception('Still offline — please connect to internet and retry.');
    }

    final p = placemarks.first;
    final addressParts = [
      p.street,
      p.subLocality,
      p.locality,
      p.subAdministrativeArea,
      p.administrativeArea,
      p.postalCode,
      p.country,
    ].where((part) => part != null && part.trim().isNotEmpty).toList();

    final address = addressParts.isNotEmpty
        ? addressParts.join(', ')
        : 'Location: $lat, $lng';

    // 3. Composite original raw photo with GeoStampOverlay off-screen
    final rawBytes = await rawPhotoFile.readAsBytes();
    final codec = await ui.instantiateImageCodec(rawBytes);
    final frame = await codec.getNextFrame();
    final double imgWidth = frame.image.width.toDouble();
    final double imgHeight = frame.image.height.toDouble();
    final double aspectRatio = imgWidth / (imgHeight > 0 ? imgHeight : 1.0);

    const double targetWidth = 412.0;
    final double targetHeight = targetWidth / aspectRatio;

    final settings = await AppSettings.loadFromPrefs();
    if (templateIndex != null) {
      settings.update(templateIndex: templateIndex);
    }
    if (mapType != null) {
      settings.update(mapType: mapType);
    }
    if (personName.isNotEmpty) {
      settings.update(personName: personName);
    }
    if (customNote.isNotEmpty) {
      settings.update(customNote: customNote);
    }

    DateTime parsedTime;
    try {
      parsedTime = DateTime.parse(timeStr);
    } catch (_) {
      parsedTime = DateTime.now();
    }
    final formattedDateTime = settings.formatDateTime(parsedTime);

    final overlayState = Overlay.of(context);
    final GlobalKey boundaryKey = GlobalKey();

    final entry = OverlayEntry(
      builder: (_) => Positioned(
        left: -99999,
        top: -99999,
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox(
            width: targetWidth,
            height: targetHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  rawPhotoFile,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 16,
                  child: GeoStampOverlay(
                    latitude: lat,
                    longitude: lng,
                    altitude: alt,
                    accuracy: accuracy,
                    address: address,
                    formattedDateTime: formattedDateTime,
                    magneticField: magneticField,
                    heading: heading,
                    cardinalDirection: _getCardinalDirection(heading),
                    settings: settings,
                    margin: EdgeInsets.zero,
                    showVerifiedBadge: sidecarData['verificationHash'] != null ||
                        sidecarData['isMocked'] != null,
                    isMockLocation: sidecarData['isMocked'] == true,
                    isSatelliteTime: sidecarData['satelliteTimestampUtc'] != null,
                    verificationHash:
                        sidecarData['verificationHash'] as String?,
                    includeMapsLink: settings.includeMapsLink,
                    isClockTampered: sidecarData['isClockTampered'] == true,
                    timeSourceLabel: sidecarData['timeSource'] as String?,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlayState.insert(entry);

    try {
      // Wait ~1200ms for FlutterMap tiles to finish loading
      await Future.delayed(const Duration(milliseconds: 1200));

      final boundary = boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Failed to render stamp boundary.');
      }

      final ui.Image compositedUiImage =
          await boundary.toImage(pixelRatio: 2.0);
      final byteData = await compositedUiImage.toByteData(
          format: ui.ImageByteFormat.png);
      compositedUiImage.dispose();
      if (byteData == null) {
        throw Exception('Failed to generate image bytes.');
      }

      final stampedBytes = byteData.buffer.asUint8List();

      final bool compressImages =
          (await SharedPreferences.getInstance()).getBool('compress_images') ??
              true;
      final int quality = compressImages ? 88 : 98;

      final Uint8List finalJpegBytes =
          (stampedBytes.length >= 2 && stampedBytes[0] == 0xFF && stampedBytes[1] == 0xD8)
              ? stampedBytes
              : await FlutterImageCompress.compressWithList(
                  stampedBytes,
                  quality: quality,
                  format: CompressFormat.jpeg,
                );

      // Overwrite rawPhotoFile with finished stamped bytes
      await rawPhotoFile.writeAsBytes(finalJpegBytes);

      // Write true EXIF GPS + Compass attributes
      try {
        final exif = await Exif.fromPath(rawPhotoFile.path);
        try {
          await exif.writeAttributes({
            'GPSLatitude': lat.abs().toString(),
            'GPSLatitudeRef': lat >= 0 ? 'N' : 'S',
            'GPSLongitude': lng.abs().toString(),
            'GPSLongitudeRef': lng >= 0 ? 'E' : 'W',
            if (alt != 0.0) 'GPSAltitude': alt.abs().toStringAsFixed(1),
            if (alt != 0.0) 'GPSAltitudeRef': alt >= 0 ? '0' : '1',
            if (heading != 0.0)
              'GPSImgDirection': heading.toStringAsFixed(1),
            if (heading != 0.0) 'GPSImgDirectionRef': 'M',
            'DateTimeOriginal':
                DateFormat('yyyy:MM:dd HH:mm:ss').format(parsedTime),
            'Software': 'GPS Map Camera',
          });
        } finally {
          await exif.close();
        }
      } catch (e) {
        debugPrint('Error writing EXIF attributes: $e');
      }

      // Export finished stamped photo to public album
      await Gal.putImage(rawPhotoFile.path, album: 'GPS Camera');

      // Update .json sidecar with pendingOfflineSync: false and resolved address
      sidecarData['pendingOfflineSync'] = false;
      sidecarData['address'] = address;
      await sidecarFile.writeAsString(jsonEncode(sidecarData));

      return true;
    } finally {
      entry.remove();
    }
  }

  static String _getCardinalDirection(double heading) {
    const directions = [
      'N', 'NNE', 'NE', 'ENE', 'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW', 'W', 'WNW', 'NW', 'NNW'
    ];
    final index = ((heading + 11.25) % 360 / 22.5).floor();
    return directions[index.clamp(0, 15)];
  }

  /// Public helper to load raw sidecar JSON metadata for a media file
  static Future<Map<String, dynamic>?> loadSidecarMetadata(File imageFile) async {
    try {
      final dotIndex = imageFile.path.lastIndexOf('.');
      final basePath = dotIndex != -1 ? imageFile.path.substring(0, dotIndex) : imageFile.path;
      final candidates = [
        File('$basePath.json'),
        File('${imageFile.path}.json'),
      ];
      for (final file in candidates) {
        if (await file.exists()) {
          final raw = await file.readAsString();
          final decoded = jsonDecode(raw);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Read metadata from the JSON sidecar if present, with fallback to file timestamp
  static Future<Map<String, dynamic>> getMediaMetadata(File photoFile) async {
    try {
      final sidecarPath =
          photoFile.path.replaceAll(RegExp(r'\.[^.]+$'), '.json');
      final sidecarFile = File(sidecarPath);
      if (await sidecarFile.exists()) {
        final jsonStr = await sidecarFile.readAsString();
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('Error reading media metadata: $e');
    }

    String fallbackTime = '';
    try {
      fallbackTime = photoFile.lastModifiedSync().toIso8601String();
    } catch (_) {
      fallbackTime = DateTime.now().toIso8601String();
    }

    return {
      'timestamp': fallbackTime,
      'address': '',
      'lat': null,
      'lng': null,
      'altitude': '',
      'personName': '',
      'customNote': '',
    };
  }

  /// Save stamped MP4 video to app documents directory and device gallery
  static Future<File?> saveStampedVideo(String sourceVideoPath) async {
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          debugPrint('Gallery access permission denied for video.');
        }
      }

      final docsDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${docsDir.path}/GPSCameraMedia');
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'GPSCAM_$timestamp.mp4';
      final savedAppFile = File('${mediaDir.path}/$fileName');

      // Copy source video into GPSCameraMedia before any temp cache files are deleted
      await File(sourceVideoPath).copy(savedAppFile.path);

      // Export to the public device album via Gal
      await Gal.putVideo(
        savedAppFile.path,
        album: 'GPS Camera',
      );

      await _recordMediaFilePath(savedAppFile.path);
      return savedAppFile;
    } catch (e) {
      debugPrint('Error saving stamped video: $e');
      return null;
    }
  }

  /// Backward-compatible alias for saveStampedVideo
  static Future<File?> saveVideo(String videoPath) =>
      saveStampedVideo(videoPath);

  /// Return all files inside GPSCameraMedia/ whose lowercase extension ends with
  /// .png, .jpg, .jpeg, or .mp4, sorted newest-first by lastModifiedSync()
  static Future<List<File>> getAppMediaFiles() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${docsDir.path}/GPSCameraMedia');
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }

      final List<FileSystemEntity> entities = mediaDir.listSync();
      final List<File> files = [];

      for (final entity in entities) {
        if (entity is File) {
          final ext = entity.path.toLowerCase();
          if (ext.endsWith('.png') ||
              ext.endsWith('.jpg') ||
              ext.endsWith('.jpeg') ||
              ext.endsWith('.mp4')) {
            files.add(entity);
          }
        }
      }

      // Check legacy directory if files were saved previously under GPSCamera/
      final legacyDir = Directory('${docsDir.path}/GPSCamera');
      if (await legacyDir.exists()) {
        for (final entity in legacyDir.listSync()) {
          if (entity is File) {
            final ext = entity.path.toLowerCase();
            if (ext.endsWith('.png') ||
                ext.endsWith('.jpg') ||
                ext.endsWith('.jpeg') ||
                ext.endsWith('.mp4')) {
              if (!files.any((f) => f.path == entity.path)) {
                files.add(entity);
              }
            }
          }
        }
      }

      // Sort newest-first by lastModifiedSync()
      files.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return b.path.compareTo(a.path);
        }
      });

      return files;
    } catch (e) {
      debugPrint('Error reading media files: $e');
      return [];
    }
  }

  /// Alias for backward compatibility
  static Future<List<File>> getAllMediaFiles() => getAppMediaFiles();

  /// Get the most recent media file for the camera screen's preview thumbnail
  static Future<File?> getLatestMediaFile() async {
    final all = await getAppMediaFiles();
    if (all.isNotEmpty) {
      return all.first;
    }
    return null;
  }

  /// Remove a media file from disk and preferences
  static Future<void> deleteMediaFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
      final sidecarPath = file.path.replaceAll(RegExp(r'\.[^.]+$'), '.json');
      final sidecarFile = File(sidecarPath);
      if (await sidecarFile.exists()) {
        await sidecarFile.delete();
      }

      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_mediaListPrefKey) ?? [];
      paths.remove(file.path);
      await prefs.setStringList(_mediaListPrefKey, paths);
    } catch (e) {
      debugPrint('Error deleting media file: $e');
    }
  }

  static Future<void> _recordMediaFilePath(String path) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_mediaListPrefKey) ?? [];
      paths.remove(path);
      paths.insert(0, path);
      await prefs.setStringList(_mediaListPrefKey, paths);
    } catch (e) {
      debugPrint('Error recording media path: $e');
    }
  }
}
