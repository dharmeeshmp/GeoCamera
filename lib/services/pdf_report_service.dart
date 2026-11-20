import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'media_storage_service.dart';

class PdfReportService {
  /// Generates a professional multi-page PDF Site Inspection Report from selected photos.
  static Future<File> generateInspectionReport({
    required List<File> selectedPhotos,
    required String reportTitle,
    required String inspectorName,
    required String projectNote,
  }) async {
    final doc = pw.Document();

    final effectiveTitle = reportTitle.trim().isNotEmpty
        ? reportTitle.trim()
        : 'GPS Site Inspection Report';

    // Preload image bytes and metadata asynchronously
    final List<Map<String, dynamic>> items = [];
    for (int i = 0; i < selectedPhotos.length; i++) {
      final photo = selectedPhotos[i];
      try {
        final bytes = await photo.readAsBytes();
        final meta = await MediaStorageService.getMediaMetadata(photo);
        items.add({
          'index': i + 1,
          'image': pw.MemoryImage(bytes),
          'meta': meta,
        });
      } catch (e) {
        debugPrint('Error reading photo for PDF: $e');
      }
    }

    // Build 2-column rows of photo evidence
    final List<pw.Widget> evidenceRows = [];
    for (int i = 0; i < items.length; i += 2) {
      final item1 = items[i];
      final item2 = (i + 1 < items.length) ? items[i + 1] : null;

      evidenceRows.add(
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: _buildPhotoCard(item1)),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: item2 != null ? _buildPhotoCard(item2) : pw.SizedBox(),
              ),
            ],
          ),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context context) {
          // Cover Header Banner on Page 1
          if (context.pageNumber == 1) {
            return pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 16),
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#1A73E8'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    effectiveTitle,
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Generated via GPS Map Camera',
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 10,
                    ),
                  ),
                  pw.Divider(color: PdfColors.white, height: 14, thickness: 0.5),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (inspectorName.trim().isNotEmpty)
                            pw.Text(
                              'Inspector / Company: $inspectorName',
                              style: pw.TextStyle(
                                color: PdfColors.white,
                                fontSize: 9.5,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          if (projectNote.trim().isNotEmpty)
                            pw.Text(
                              'Project Note: $projectNote',
                              style: const pw.TextStyle(
                                color: PdfColors.white,
                                fontSize: 9.5,
                              ),
                            ),
                        ],
                      ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                            style: const pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 9.5,
                            ),
                          ),
                          pw.Text(
                            'Total Photos: ${selectedPhotos.length}',
                            style: pw.TextStyle(
                              color: PdfColors.white,
                              fontSize: 9.5,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          return pw.SizedBox();
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 8),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Verified GPS Photo Evidence',
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return evidenceRows;
        },
      ),
    );

    final docsDir = await getApplicationDocumentsDirectory();
    final reportsDir = Directory('${docsDir.path}/GPSCameraMedia/Reports');
    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }
    final pdfFile = File(
      '${reportsDir.path}/Site_Inspection_Report_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
    await pdfFile.writeAsBytes(await doc.save());
    return pdfFile;
  }

  /// Lists all permanently saved inspection reports inside GPSCameraMedia/Reports/
  /// sorted newest-first by lastModifiedSync().
  static Future<List<File>> getSavedPdfReports() async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final reportsDir = Directory('${docsDir.path}/GPSCameraMedia/Reports');
      if (!await reportsDir.exists()) {
        return [];
      }
      final files = reportsDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.pdf'))
          .toList();
      files.sort((a, b) {
        try {
          return b.lastModifiedSync().compareTo(a.lastModifiedSync());
        } catch (_) {
          return 0;
        }
      });
      return files;
    } catch (e) {
      debugPrint('Error getting saved PDF reports: $e');
      return [];
    }
  }

  static pw.Widget _buildPhotoCard(Map<String, dynamic> item) {
    final int index = item['index'];
    final pw.MemoryImage image = item['image'];
    final Map<String, dynamic> meta = item['meta'] ?? {};

    final String address = meta['address']?.toString() ?? '';
    final lat = meta['lat'];
    final lng = meta['lng'];
    final String coords = (lat != null && lng != null)
        ? '${(lat as num).toStringAsFixed(4)}°, ${(lng as num).toStringAsFixed(4)}°'
        : 'GPS Coordinates N/A';
    final String altitude = meta['altitude']?.toString() ?? '';
    final String timestamp = meta['timestamp']?.toString() ?? '';

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          // Photo with fixed height 210
          pw.ClipRRect(
            horizontalRadius: 6,
            verticalRadius: 6,
            child: pw.Container(
              height: 210,
              width: double.infinity,
              color: PdfColors.black,
              child: pw.Image(
                image,
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
          // Metadata Box
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Evidence #$index',
                      style: pw.TextStyle(
                        fontSize: 9.5,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromHex('#1A73E8'),
                      ),
                    ),
                    if (altitude.isNotEmpty)
                      pw.Text(
                        'Alt: $altitude',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey700,
                        ),
                      ),
                  ],
                ),
                pw.SizedBox(height: 3),
                if (address.isNotEmpty)
                  pw.Text(
                    address,
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                    maxLines: 2,
                    overflow: pw.TextOverflow.clip,
                  ),
                pw.SizedBox(height: 2),
                pw.Text(
                  coords,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey800,
                  ),
                ),
                if (timestamp.isNotEmpty) ...[
                  pw.SizedBox(height: 1),
                  pw.Text(
                    timestamp,
                    style: const pw.TextStyle(
                      fontSize: 7.5,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
