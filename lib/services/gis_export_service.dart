import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'media_storage_service.dart';

/// Service providing 1-tap GIS export to OGC KML 2.2 and RFC-4180 CSV formats.
/// Used for importing surveyed GPS photo locations and routes into Google Earth,
/// ArcGIS, QGIS, Civil 3D, and Excel.
class GisExportService {
  /// Exports selected photos to an OGC KML 2.2 XML file with Placemark pins
  /// and a connected Survey Route LineString.
  static Future<File> exportToKml(List<String> imagePaths) async {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(now);
    final fileTimestamp = now.millisecondsSinceEpoch;

    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buffer.writeln('  <Document>');
    buffer.writeln('    <name>GPS Camera Survey - $dateStr</name>');
    buffer.writeln('    <description>Exported from GPS Camera App with verified GPS coordinates and timestamps.</description>');

    // Styles for pins and route line
    buffer.writeln('    <Style id="cameraPin">');
    buffer.writeln('      <IconStyle>');
    buffer.writeln('        <color>ff00d7ff</color>'); // Yellow-gold in KML aabbggrr format
    buffer.writeln('        <scale>1.1</scale>');
    buffer.writeln('        <Icon>');
    buffer.writeln('          <href>https://maps.google.com/mapfiles/kml/shapes/camera.png</href>');
    buffer.writeln('        </Icon>');
    buffer.writeln('      </IconStyle>');
    buffer.writeln('    </Style>');

    buffer.writeln('    <Style id="surveyRoute">');
    buffer.writeln('      <LineStyle>');
    buffer.writeln('        <color>ff00aaff</color>'); // Orange-amber in KML
    buffer.writeln('        <width>3</width>');
    buffer.writeln('      </LineStyle>');
    buffer.writeln('    </Style>');

    buffer.writeln('    <Folder>');
    buffer.writeln('      <name>Survey Photos (${imagePaths.length})</name>');

    final List<Map<String, dynamic>> routePoints = [];

    for (int i = 0; i < imagePaths.length; i++) {
      final path = imagePaths[i];
      final file = File(path);
      final filename = path.split(Platform.pathSeparator).last;

      final meta = (await MediaStorageService.loadSidecarMetadata(file)) ??
          (await MediaStorageService.getMediaMetadata(file));

      final double? lat = meta['lat'] is num
          ? (meta['lat'] as num).toDouble()
          : (meta['latitude'] is num ? (meta['latitude'] as num).toDouble() : null);
      final double? lng = meta['lng'] is num
          ? (meta['lng'] as num).toDouble()
          : (meta['longitude'] is num ? (meta['longitude'] as num).toDouble() : null);
      final double alt = meta['altitude'] is num
          ? (meta['altitude'] as num).toDouble()
          : (double.tryParse(meta['altitude']?.toString() ?? '') ?? 0.0);

      final String timeStr = meta['satelliteTimestampUtc']?.toString() ??
          meta['timestamp']?.toString() ??
          (file.existsSync() ? file.lastModifiedSync().toIso8601String() : '');
      final String address = meta['address']?.toString() ?? 'N/A';
      final String note = meta['customNote']?.toString() ?? '';
      final String surveyor = meta['personName']?.toString() ?? '';
      final String hash = meta['verificationHash']?.toString() ?? '';
      final bool isMock = meta['isMockLocation'] == true;

      if (lat != null && lng != null && (lat != 0.0 || lng != 0.0)) {
        routePoints.add({
          'lat': lat,
          'lng': lng,
          'alt': alt,
          'name': filename,
        });

        final mapsUrl = 'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';

        buffer.writeln('      <Placemark>');
        buffer.writeln('        <name>${_xmlEscape(filename)}</name>');
        buffer.writeln('        <styleUrl>#cameraPin</styleUrl>');
        buffer.writeln('        <description><![CDATA[');
        buffer.writeln('          <div style="font-family:sans-serif;font-size:13px;line-height:1.5;">');
        buffer.writeln('            <h3 style="margin:0 0 8px;color:#1a73e8;">Photo #${i + 1}: ${_xmlEscape(filename)}</h3>');
        buffer.writeln('            <table style="border-collapse:collapse;width:100%;">');
        buffer.writeln('              <tr><td><b>Timestamp:</b></td><td>${_xmlEscape(timeStr)}</td></tr>');
        buffer.writeln('              <tr><td><b>Coordinates:</b></td><td>${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}</td></tr>');
        buffer.writeln('              <tr><td><b>Altitude:</b></td><td>${alt.toStringAsFixed(1)} m</td></tr>');
        if (address.isNotEmpty && address != 'N/A') {
          buffer.writeln('              <tr><td><b>Address:</b></td><td>${_xmlEscape(address)}</td></tr>');
        }
        if (surveyor.isNotEmpty) {
          buffer.writeln('              <tr><td><b>Surveyor:</b></td><td>${_xmlEscape(surveyor)}</td></tr>');
        }
        if (note.isNotEmpty) {
          buffer.writeln('              <tr><td><b>Note:</b></td><td>${_xmlEscape(note)}</td></tr>');
        }
        if (hash.isNotEmpty) {
          buffer.writeln('              <tr><td><b>Verification:</b></td><td><code>${_xmlEscape(hash)}</code> (${isMock ? 'MOCK DETECTED' : 'VERIFIED'})</td></tr>');
        }
        buffer.writeln('              <tr><td><b>Google Maps:</b></td><td><a href="$mapsUrl" target="_blank">Open Location</a></td></tr>');
        buffer.writeln('            </table>');
        buffer.writeln('          </div>');
        buffer.writeln('        ]]></description>');
        // In KML, coordinates order is: longitude, latitude, altitude
        buffer.writeln('        <Point>');
        buffer.writeln('          <coordinates>$lng,$lat,$alt</coordinates>');
        buffer.writeln('        </Point>');
        buffer.writeln('      </Placemark>');
      }
    }

    buffer.writeln('    </Folder>');

    // If there are 2 or more points, generate a Survey Route path
    if (routePoints.length >= 2) {
      buffer.writeln('    <Placemark>');
      buffer.writeln('      <name>Survey Route Path</name>');
      buffer.writeln('      <description>Sequential survey traversal route connecting ${routePoints.length} photo locations.</description>');
      buffer.writeln('      <styleUrl>#surveyRoute</styleUrl>');
      buffer.writeln('      <LineString>');
      buffer.writeln('        <extrude>1</extrude>');
      buffer.writeln('        <tessellate>1</tessellate>');
      buffer.writeln('        <altitudeMode>clampToGround</altitudeMode>');
      buffer.writeln('        <coordinates>');
      final coordsStr = routePoints
          .map((p) => '${p['lng']},${p['lat']},${p['alt']}')
          .join(' ');
      buffer.writeln('          $coordsStr');
      buffer.writeln('        </coordinates>');
      buffer.writeln('      </LineString>');
      buffer.writeln('    </Placemark>');
    }

    buffer.writeln('  </Document>');
    buffer.writeln('</kml>');

    final tempDir = await getTemporaryDirectory();
    final exportFile = File('${tempDir.path}/survey_export_$fileTimestamp.kml');
    await exportFile.writeAsString(buffer.toString(), encoding: utf8);
    return exportFile;
  }

  /// Exports selected photos to an RFC-4180 compliant CSV file with a UTF-8 BOM.
  static Future<File> exportToCsv(List<String> imagePaths) async {
    final fileTimestamp = DateTime.now().millisecondsSinceEpoch;
    final buffer = StringBuffer();

    // UTF-8 BOM (\uFEFF) ensures Microsoft Excel opens the CSV with UTF-8 character encoding
    buffer.write('\uFEFF');

    // CSV Header
    buffer.writeln(
      'Index,Filename,Latitude,Longitude,Altitude_m,Heading_deg,Timestamp,Address,Note,Surveyor,Verification_Status,Verification_Hash,Google_Maps_URL',
    );

    for (int i = 0; i < imagePaths.length; i++) {
      final path = imagePaths[i];
      final file = File(path);
      final filename = path.split(Platform.pathSeparator).last;

      final meta = (await MediaStorageService.loadSidecarMetadata(file)) ??
          (await MediaStorageService.getMediaMetadata(file));

      final double? lat = meta['lat'] is num
          ? (meta['lat'] as num).toDouble()
          : (meta['latitude'] is num ? (meta['latitude'] as num).toDouble() : null);
      final double? lng = meta['lng'] is num
          ? (meta['lng'] as num).toDouble()
          : (meta['longitude'] is num ? (meta['longitude'] as num).toDouble() : null);
      final double alt = meta['altitude'] is num
          ? (meta['altitude'] as num).toDouble()
          : (double.tryParse(meta['altitude']?.toString() ?? '') ?? 0.0);
      final double heading = meta['heading'] is num
          ? (meta['heading'] as num).toDouble()
          : (double.tryParse(meta['heading']?.toString() ?? '') ?? 0.0);

      final String timeStr = meta['satelliteTimestampUtc']?.toString() ??
          meta['timestamp']?.toString() ??
          (file.existsSync() ? file.lastModifiedSync().toIso8601String() : '');
      final String address = meta['address']?.toString() ?? '';
      final String note = meta['customNote']?.toString() ?? '';
      final String surveyor = meta['personName']?.toString() ?? '';
      final String hash = meta['verificationHash']?.toString() ?? '';
      final bool isMock = meta['isMockLocation'] == true;
      final String status = isMock
          ? 'MOCK_DETECTED'
          : (hash.isNotEmpty ? 'VERIFIED' : 'STANDARD');

      final mapsUrl = (lat != null && lng != null && (lat != 0.0 || lng != 0.0))
          ? 'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}'
          : '';

      final row = [
        (i + 1).toString(),
        _csvEscape(filename),
        lat != null ? lat.toStringAsFixed(6) : '',
        lng != null ? lng.toStringAsFixed(6) : '',
        alt.toStringAsFixed(1),
        heading.toStringAsFixed(1),
        _csvEscape(timeStr),
        _csvEscape(address),
        _csvEscape(note),
        _csvEscape(surveyor),
        status,
        hash,
        _csvEscape(mapsUrl),
      ];

      buffer.writeln(row.join(','));
    }

    final tempDir = await getTemporaryDirectory();
    final exportFile = File('${tempDir.path}/survey_export_$fileTimestamp.csv');
    await exportFile.writeAsString(buffer.toString(), encoding: utf8);
    return exportFile;
  }

  /// Escapes CSV field per RFC-4180 rules
  static String _csvEscape(String input) {
    if (input.contains(',') ||
        input.contains('"') ||
        input.contains('\n') ||
        input.contains('\r')) {
      final escaped = input.replaceAll('"', '""');
      return '"$escaped"';
    }
    return input;
  }

  /// Escapes special XML characters for KML
  static String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
