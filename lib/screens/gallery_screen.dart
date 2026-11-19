import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../models/ad_config.dart';
import '../services/media_storage_service.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  List<File> _mediaFiles = [];
  bool _isLoading = true;
  BannerAd? _galleryBannerAd;
  bool _isGalleryAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadInlineAdaptiveBanner();
  }

  Future<void> _loadInlineAdaptiveBanner() async {
    if (_galleryBannerAd != null) return;

    final int adWidth = (MediaQuery.sizeOf(context).width - 24).truncate();
    final AdSize adaptiveSize =
        AdSize.getCurrentOrientationInlineAdaptiveBannerAdSize(adWidth);

    if (!mounted) return;

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
            _galleryBannerAd = ad as BannerAd;
            _isGalleryAdLoaded = true;
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
    _galleryBannerAd?.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF101010),
      appBar: AppBar(
        title: const Text('Captured Media',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
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

                    return GestureDetector(
                      onTap: () async {
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
                      },
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
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 3),
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
                    );
                  },
                ),
      bottomNavigationBar: (_isGalleryAdLoaded && _galleryBannerAd != null)
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.white12),
                  ),
                ),
                height: _galleryBannerAd!.size.height.toDouble() + 16,
                alignment: Alignment.center,
                child: SizedBox(
                  width: _galleryBannerAd!.size.width.toDouble(),
                  height: _galleryBannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _galleryBannerAd!),
                ),
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
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
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
