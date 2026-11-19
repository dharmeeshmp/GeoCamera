import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MediaStorageService {
  static const String _mediaListPrefKey = 'saved_media_file_paths';

  /// Save composited PNG/JPEG bytes to the device gallery using the Gal package.
  /// Also stores the file in the app documents directory for in-app gallery access.
  static Future<File?> saveCompositedImage(Uint8List imageBytes) async {
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          debugPrint('Gallery access permission denied.');
        }
      }

      // Save locally to App Support / Documents folder for internal gallery preview
      final directory = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${directory.path}/GPSCamera');
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'GPS_IMG_$timestamp.jpg';
      final localFile = File('${mediaDir.path}/$fileName');
      await localFile.writeAsBytes(imageBytes);

      // Save to device public gallery using Gal
      await Gal.putImageBytes(
        imageBytes,
        name: 'GPS_IMG_$timestamp',
        album: 'GPS Map Camera',
      );

      // Record in preferences for quick in-app gallery display
      await _recordMediaFilePath(localFile.path);

      return localFile;
    } catch (e) {
      debugPrint('Error saving composited image: $e');
      return null;
    }
  }

  /// Save captured MP4 video to the device gallery
  static Future<File?> saveVideo(String videoPath) async {
    try {
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          debugPrint('Gallery access permission denied for video.');
        }
      }

      final directory = await getApplicationDocumentsDirectory();
      final mediaDir = Directory('${directory.path}/GPSCamera');
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'GPS_VID_$timestamp.mp4';
      final targetFile = File('${mediaDir.path}/$fileName');
      await File(videoPath).copy(targetFile.path);

      await Gal.putVideo(
        targetFile.path,
        album: 'GPS Map Camera',
      );

      await _recordMediaFilePath(targetFile.path);
      return targetFile;
    } catch (e) {
      debugPrint('Error saving video: $e');
      return null;
    }
  }

  /// Save stamped MP4 video to the device gallery
  static Future<File?> saveStampedVideo(String videoPath) => saveVideo(videoPath);

  /// Get the most recent media file for the camera screen's preview thumbnail
  static Future<File?> getLatestMediaFile() async {
    final all = await getAllMediaFiles();
    if (all.isNotEmpty) {
      return all.first;
    }
    return null;
  }

  /// Retrieve all recorded media files in reverse chronological order
  static Future<List<File>> getAllMediaFiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final paths = prefs.getStringList(_mediaListPrefKey) ?? [];
      final List<File> validFiles = [];
      final List<String> updatedPaths = [];

      for (final p in paths) {
        final file = File(p);
        if (await file.exists()) {
          validFiles.add(file);
          updatedPaths.add(p);
        }
      }

      // If missing files were filtered out, update prefs
      if (updatedPaths.length != paths.length) {
        await prefs.setStringList(_mediaListPrefKey, updatedPaths);
      }

      // Sort newest first based on file modified time or name
      validFiles.sort((a, b) {
        return b.path.compareTo(a.path);
      });

      return validFiles;
    } catch (e) {
      debugPrint('Error reading media files: $e');
      return [];
    }
  }

  /// Remove a media file from disk and preferences
  static Future<void> deleteMediaFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
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
      paths.remove(path); // Avoid duplicates
      paths.insert(0, path); // Newest first
      await prefs.setStringList(_mediaListPrefKey, paths);
    } catch (e) {
      debugPrint('Error recording media path: $e');
    }
  }
}
