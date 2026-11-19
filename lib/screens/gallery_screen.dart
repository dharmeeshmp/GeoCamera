import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../models/ad_config.dart';
import '../services/media_storage_service.dart';
import '../services/pdf_report_service.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<File> _mediaFiles = [];
  bool _isLoading = true;

  // Multi-select for PDF Site Inspection Report
  bool _isSelectionMode = false;
  final Set<String> _selectedPhotoPaths = {};

  // AdMob Native & Inline Adaptive Banner Ads
  NativeAd? _nativeAd;
  bool _isNativeAdLoaded = false;
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadMedia();
    _loadNativeAd();
  }

  void _loadNativeAd() {
    _nativeAd = NativeAd(
      adUnitId: AdConfig.galleryNativeAdUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _nativeAd = ad as NativeAd;
            _isNativeAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint(
              'Gallery Native Ad failed to load: $error. Falling back to Inline Adaptive Banner.');
          ad.dispose();
          _loadInlineAdaptiveBanner();
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFF1E1E1E),
        cornerRadius: 12.0,
      ),
    )..load();
  }

  Future<void> _loadInlineAdaptiveBanner() async {
    if (_bannerAd != null || !mounted) return;

    final int adWidth = (MediaQuery.sizeOf(context).width - 24).truncate();
    final AdSize adaptiveSize =
        AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(adWidth);

    final banner = BannerAd(
      adUnitId: AdConfig.galleryBannerAdUnitId,
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
            _isBannerAdLoaded = true;
          });
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Gallery Inline Adaptive Ad failed to load: $error');
          ad.dispose();
        },
      ),
    );

    await banner.load();
  }

  @override
  void dispose() {
    _nativeAd?.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadMedia() async {
    setState(() => _isLoading = true);
    final files = await MediaStorageService.getAppMediaFiles();
    if (mounted) {
      setState(() {
        _mediaFiles = files;
        _isLoading = false;
      });
    }
  }

  Future<void> _showGenerateReportDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final defaultName = prefs.getString('person_name') ?? '';
    final defaultNote = prefs.getString('custom_note') ?? '';

    final titleController =
        TextEditingController(text: 'Site Inspection Report');
    final inspectorController = TextEditingController(text: defaultName);
    final noteController = TextEditingController(text: defaultNote);

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.picture_as_pdf, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text(
              'Generate PDF Report',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Report Title',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: inspectorController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Company / Inspector Name',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                style: const TextStyle(color: Colors.white),
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Project Note',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate & Share'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Show loading spinner dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          color: Color(0xFF1E1E1E),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.blueAccent),
                SizedBox(height: 16),
                Text(
                  'Building PDF Report...',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final selectedFiles = _mediaFiles
          .where((f) => _selectedPhotoPaths.contains(f.path))
          .toList();

      final pdfFile = await PdfReportService.generateInspectionReport(
        selectedPhotos: selectedFiles,
        reportTitle: titleController.text.trim(),
        inspectorName: inspectorController.text.trim(),
        projectNote: noteController.text.trim(),
      );

      if (mounted) {
        Navigator.pop(context); // Dismiss loading spinner
      }

      await Share.shareXFiles(
        [XFile(pdfFile.path)],
        text: 'GPS Site Inspection Report',
      );

      if (mounted) {
        setState(() {
          _isSelectionMode = false;
          _selectedPhotoPaths.clear();
        });
      }
    } catch (e) {
      debugPrint('Error generating PDF report: $e');
      if (mounted) {
        Navigator.pop(context); // Dismiss loading spinner
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoCount =
        _mediaFiles.where((f) => !f.path.toLowerCase().endsWith('.mp4')).length;

    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        title: Text(
          _isSelectionMode
              ? '${_selectedPhotoPaths.length} Selected'
              : 'Captured Media',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedPhotoPaths.clear();
                  });
                },
              )
            : null,
        actions: [
          if (!_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'Create PDF Report',
              onPressed: () {
                setState(() {
                  _isSelectionMode = true;
                });
              },
            )
          else ...[
            TextButton(
              onPressed: () {
                setState(() {
                  final photoFiles = _mediaFiles
                      .where((f) => !f.path.toLowerCase().endsWith('.mp4'))
                      .toList();
                  if (_selectedPhotoPaths.length == photoFiles.length) {
                    _selectedPhotoPaths.clear();
                  } else {
                    _selectedPhotoPaths.addAll(photoFiles.map((f) => f.path));
                  }
                });
              },
              child: Text(
                _selectedPhotoPaths.length == photoCount
                    ? 'Deselect All'
                    : 'Select All',
                style: const TextStyle(
                  color: Colors.blueAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.amberAccent),
            )
          : _mediaFiles.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.photo_library_outlined,
                          size: 64, color: Colors.white24),
                      SizedBox(height: 12),
                      Text(
                        'No captured media yet',
                        style: TextStyle(
                            color: Colors.white60, fontSize: 16),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'Photos and videos with GPS stamps will appear here.',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                    childAspectRatio: 1.0,
                  ),
                  itemCount: _mediaFiles.length,
                  itemBuilder: (context, index) {
                    final file = _mediaFiles[index];
                    final bool isVideo =
                        file.path.toLowerCase().endsWith('.mp4');
                    final bool isSelected =
                        _selectedPhotoPaths.contains(file.path);

                    return GestureDetector(
                      onLongPress: () {
                        if (isVideo) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('PDF Report supports photos only.'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                          return;
                        }
                        if (!_isSelectionMode) {
                          setState(() {
                            _isSelectionMode = true;
                            _selectedPhotoPaths.add(file.path);
                          });
                        }
                      },
                      onTap: () async {
                        if (_isSelectionMode) {
                          if (isVideo) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('PDF Report supports photos only.'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            if (isSelected) {
                              _selectedPhotoPaths.remove(file.path);
                            } else {
                              _selectedPhotoPaths.add(file.path);
                            }
                          });
                        } else {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MediaViewerScreen(
                                file: file,
                                isVideo: isVideo,
                              ),
                            ),
                          );
                          _loadMedia();
                        }
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: isVideo
                                  ? Container(
                                      color: Colors.grey.shade900,
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          const Icon(
                                            Icons.play_circle_fill,
                                            color: Colors.white,
                                            size: 42,
                                          ),
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            bottom: 0,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 3),
                                              color: Colors.black54,
                                              child: const Text(
                                                'VIDEO',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : Image.file(
                                      file,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: Colors.grey.shade900,
                                        child: const Icon(Icons.broken_image,
                                            color: Colors.white38),
                                      ),
                                    ),
                            ),
                          ),
                          // Multi-selection indicators
                          if (_isSelectionMode && !isVideo)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.blueAccent
                                      : Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(2),
                                child: Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            )
                          else if (_isSelectionMode && isVideo)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Photos only',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
      bottomNavigationBar: ((_isSelectionMode &&
                  _selectedPhotoPaths.isNotEmpty) ||
              _isNativeAdLoaded ||
              _isBannerAdLoaded)
          ? SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. PDF Action Bar (when photos selected in selection mode)
                  if (_isSelectionMode && _selectedPhotoPaths.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: const Color(0xFF1E1E1E),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.picture_as_pdf),
                          label: Text(
                            'Generate PDF Report (${_selectedPhotoPaths.length})',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          onPressed: _showGenerateReportDialog,
                        ),
                      ),
                    ),

                  // 2. High-Revenue Native Ad or Inline Adaptive Banner Ad
                  if (_isNativeAdLoaded && _nativeAd != null) ...[
                    const Divider(height: 1, color: Colors.white12),
                    SizedBox(
                      height: 260,
                      width: double.infinity,
                      child: AdWidget(ad: _nativeAd!),
                    ),
                  ] else if (_isBannerAdLoaded && _bannerAd != null) ...[
                    const Divider(height: 1, color: Colors.white12),
                    Container(
                      color: const Color(0xFF101010),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      height: _bannerAd!.size.height.toDouble() + 16,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: _bannerAd!.size.width.toDouble(),
                        height: _bannerAd!.size.height.toDouble(),
                        child: AdWidget(ad: _bannerAd!),
                      ),
                    ),
                  ],
                ],
              ),
            )
          : null,
    );
  }
}

class MediaViewerScreen extends StatefulWidget {
  final File file;
  final bool isVideo;

  const MediaViewerScreen({
    super.key,
    required this.file,
    required this.isVideo,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.file(widget.file);
    _videoController = controller;
    try {
      await controller.initialize();
      await controller.setLooping(true);
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
        controller.play();
      }
    } catch (e) {
      debugPrint('Error initializing VideoPlayerController: $e');
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _shareMedia() async {
    await Share.shareXFiles(
      [XFile(widget.file.path)],
      text: widget.isVideo
          ? 'Video captured with GPS Map Camera'
          : 'Photo captured with GPS Map Camera',
    );
  }

  Future<void> _deleteMedia() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          widget.isVideo ? 'Delete Video' : 'Delete Photo',
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          widget.isVideo
              ? 'Are you sure you want to delete this video file?'
              : 'Are you sure you want to delete this photo file?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            child:
                const Text('Cancel', style: TextStyle(color: Colors.white60)),
            onPressed: () => Navigator.pop(ctx, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await MediaStorageService.deleteMediaFile(widget.file);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.isVideo ? 'Video' : 'Photo',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: _shareMedia,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.redAccent),
            onPressed: _deleteMedia,
          ),
        ],
      ),
      body: Center(
        child: widget.isVideo
            ? (_isVideoInitialized && _videoController != null)
                ? GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_videoController!.value.isPlaying) {
                          _videoController!.pause();
                        } else {
                          _videoController!.play();
                        }
                      });
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                        if (!_videoController!.value.isPlaying)
                          Container(
                            decoration: const BoxDecoration(
                              color: Colors.black45,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(12),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              size: 54,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  )
                : const CircularProgressIndicator(color: Colors.amberAccent)
            : InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.file(widget.file),
              ),
      ),
    );
  }
}

/// Backward compatibility alias
typedef MediaDetailScreen = MediaViewerScreen;
