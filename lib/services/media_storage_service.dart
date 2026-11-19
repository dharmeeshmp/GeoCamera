import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MediaStorageService {
  static const String _mediaListPrefKey = 'saved_media_file_paths';

  /// Save composited PNG/JPEG bytes to the device gallery using the Gal package.
  /// Also stores the file in the app documents directory for in-app gallery access,
  /// and writes a matching JSON sidecar metadata file (<photo_path_without_ext>.json).
  static Future<File?> saveCompositedImage(
    Uint8List imageBytes, {
    Map<String, dynamic>? metadata,
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

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'GPSCAM_$timestamp.jpg';
      final localFile = File('${mediaDir.path}/$fileName');
      await localFile.writeAsBytes(imageBytes);

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
        final lat = metadata?['lat'];
        final lng = metadata?['lng'];
        final altitude = metadata?['altitude'] ?? '';
        final timeStr =
            metadata?['timestamp'] ?? DateTime.now().toIso8601String();

        final metaJson = {
          'timestamp': timeStr,
          'address': address,
          'lat': lat,
          'lng': lng,
          'altitude': altitude,
          'personName': personName,
          'customNote': customNote,
        };
        await File(sidecarPath).writeAsString(jsonEncode(metaJson));
      } catch (e) {
        debugPrint('Error writing metadata sidecar: $e');
      }

      // Save to device public gallery using Gal
      await Gal.putImageBytes(
        imageBytes,
        name: 'GPSCAM_$timestamp',
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

  /// Backward-compatible alias for saveCompositedImage
  static Future<File?> saveStampedPhoto(
    Uint8List imageBytes, {
    Map<String, dynamic>? metadata,
  }) =>
      saveCompositedImage(imageBytes, metadata: metadata);

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
