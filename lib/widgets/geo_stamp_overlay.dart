import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../models/app_settings.dart';

class GeoStampOverlay extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final String address;
  final String formattedDateTime;
  final double? magneticField;
  final double heading;
  final String cardinalDirection;
  final bool showTelemetry;
  final AppSettings? settings;
  final double scale;
  final EdgeInsetsGeometry? margin;
  final DateTime? lastGpsFixTime;
  final bool isRefreshingGps;
  final VoidCallback? onRefreshGps;
  final MapController? mapController;

  const GeoStampOverlay({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.address,
    required this.formattedDateTime,
    this.magneticField,
    this.heading = 0.0,
    this.cardinalDirection = '--',
    this.showTelemetry = true,
    this.settings,
    this.scale = 1.0,
    this.margin,
    this.lastGpsFixTime,
    this.isRefreshingGps = false,
    this.onRefreshGps,
    this.mapController,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSettings = settings ?? AppSettings();
    final tileUrl = effectiveSettings.tileUrl;

    final hasValidGps = latitude != 0.0 && longitude != 0.0;
    final altitudeUnit = effectiveSettings.useFeet ? 'ft' : 'm';
    final altitudeValue = effectiveSettings.useFeet
        ? (altitude * 3.28084).round()
        : altitude.round();

    final effectiveAddress = effectiveSettings.customAddress.trim().isNotEmpty
        ? effectiveSettings.customAddress.trim()
        : (address.isNotEmpty ? address : 'Acquiring GPS location...');

    final effectiveDateTime =
        (effectiveSettings.dateFormat == '12-Hour' && formattedDateTime.isNotEmpty)
            ? formattedDateTime
            : effectiveSettings.formatDateTime();

    // Template Styling
    Color cardBgColor;
    Color textColor;
    Color iconColor;
    Border? border;

    final isTemplate2 = effectiveSettings.templateIndex == 1 ||
        effectiveSettings.template == StampTemplate.classicDark;

    if (isTemplate2) {
      cardBgColor = const Color(0xFF101010);
      textColor = Colors.white;
      iconColor = Colors.amberAccent;
      border =
          Border.all(color: Colors.amberAccent.withOpacity(0.55), width: 1.2);
    } else {
      switch (effectiveSettings.template) {
        case StampTemplate.cleanWhite:
          cardBgColor = Colors.white.withOpacity(0.85);
          textColor = Colors.black87;
          iconColor = Colors.blueGrey;
          border = Border.all(color: Colors.black12, width: 1.0);
          break;
        case StampTemplate.minimalOverlay:
          cardBgColor = Colors.black.withOpacity(0.5);
          textColor = Colors.white;
          iconColor = Colors.white70;
          border = null;
          break;
        case StampTemplate.modernTranslucent:
        default:
          cardBgColor = Colors.black.withOpacity(0.65);
          textColor = Colors.white;
          iconColor = Colors.white70;
          border =
              Border.all(color: Colors.white.withOpacity(0.18), width: 1.0);
          break;
      }
    }

    return Transform.scale(
      scale: scale,
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: margin ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(12),
          border: border,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ----------------------------------------------------
                // LEFT SECTION: Square Map Thumbnail (100x100)
                // ----------------------------------------------------
                if (effectiveSettings.showMap)
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: Stack(
                      children: [
                        if (hasValidGps)
                          FlutterMap(
                            mapController: mapController,
                            key: ValueKey(
                                '${latitude.toStringAsFixed(4)},${longitude.toStringAsFixed(4)}'),
                            options: MapOptions(
                              initialCenter: LatLng(latitude, longitude),
                              initialZoom: 15.0,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: tileUrl,
                                userAgentPackageName: 'com.example.gps_camera_app',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(latitude, longitude),
                                    width: 72,
                                    height: 72,
                                    alignment: Alignment.center,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // 1. Rotating FOV Radar Cone (Bottom layer)
                                        Transform.rotate(
                                          angle: heading * (math.pi / 180.0),
                                          child: const CustomPaint(
                                            size: Size(72, 72),
                                            painter: _FovConePainter(),
                                          ),
                                        ),
                                        // 2. White circular halo/dot at apex base
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.4),
                                                blurRadius: 2,
                                              ),
                                            ],
                                          ),
                                        ),
                                        // 3. Location pin anchored at apex of the cone
                                        Transform.translate(
                                          offset: const Offset(0, -7),
                                          child: const Icon(
                                            Icons.location_on,
                                            color: Colors.redAccent,
                                            size: 22,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        else
                          Container(
                            color: Colors.black54,
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.location_searching,
                                      color: Colors.white54, size: 24),
                                  SizedBox(height: 4),
                                  Text(
                                    'Acquiring...',
                                    style: TextStyle(
                                      color: Colors.white60,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // Inner border overlay for crisp thumbnail look
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border(
                                right: BorderSide(
                                  color: Colors.white.withOpacity(0.15),
                                  width: 1.0,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // ----------------------------------------------------
                // RIGHT SECTION: Semi-Transparent Dark Info Box (5 Rows)
                // ----------------------------------------------------
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ROW 1: Full Address & GPS Freshness / 1-Tap Refresh
                        if (effectiveSettings.showAddress)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.place,
                                size: 12,
                                color: iconColor == Colors.white70
                                    ? Colors.amberAccent
                                    : iconColor,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  effectiveAddress,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    height: 1.15,
                                  ),
                                  softWrap: true,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (lastGpsFixTime != null || onRefreshGps != null) ...[
                                const SizedBox(width: 4),
                                _buildGpsFreshnessWidget(),
                              ],
                            ],
                          )
                        else if (lastGpsFixTime != null || onRefreshGps != null)
                          Align(
                            alignment: Alignment.topRight,
                            child: _buildGpsFreshnessWidget(),
                          ),

                        // ROW 2: Coordinates (Lat / Lon)
                        if (effectiveSettings.showCoordinates)
                          Row(
                            children: [
                              Icon(
                                Icons.my_location,
                                size: 11,
                                color: iconColor == Colors.white70
                                    ? Colors.lightBlueAccent
                                    : iconColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hasValidGps
                                    ? '${latitude.toStringAsFixed(4)}°, ${longitude.toStringAsFixed(4)}°'
                                    : '--.----°, --.----°',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 11.0,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),

                        // ROW 3: Date & Time with Timezone
                        if (effectiveSettings.showDateTime)
                          Row(
                            children: [
                              Icon(
                                Icons.access_time_filled,
                                size: 11,
                                color: iconColor == Colors.white70
                                    ? Colors.orangeAccent
                                    : iconColor,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  effectiveDateTime,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 11.0,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),

                        // ROW 4: Altitude above sea level
                        if (effectiveSettings.showAltitude)
                          Row(
                            children: [
                              Icon(
                                Icons.terrain,
                                size: 11,
                                color: iconColor == Colors.white70
                                    ? Colors.greenAccent
                                    : iconColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$altitudeValue$altitudeUnit above sea level',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 11.0,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),

                        // ROW 5: 3-Column Sensor Telemetry Row
                        if (showTelemetry)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                // Col 1: GPS Accuracy
                                if (effectiveSettings.showAccuracy)
                                  Expanded(
                                    flex: 3,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.gps_fixed,
                                          size: 10,
                                          color: iconColor == Colors.white70
                                              ? Colors.tealAccent
                                              : iconColor,
                                        ),
                                        const SizedBox(width: 2),
                                        Flexible(
                                          child: Text(
                                            '±${accuracy.round()}m acc',
                                            style: TextStyle(
                                              color: textColor.withOpacity(0.9),
                                              fontSize: 10.0,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                // Col 2: Magnetic Field (µT)
                                if (effectiveSettings.showMagnetic)
                                  Expanded(
                                    flex: 3,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.sensors,
                                          size: 10,
                                          color: iconColor == Colors.white70
                                              ? Colors.purpleAccent
                                              : iconColor,
                                        ),
                                        const SizedBox(width: 2),
                                        Flexible(
                                          child: Text(
                                            magneticField != null
                                                ? '${magneticField!.round()} µT'
                                                : '-- µT',
                                            style: TextStyle(
                                              color: textColor.withOpacity(0.9),
                                              fontSize: 10.0,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                // Col 3: Compass Heading & Direction
                                if (effectiveSettings.showCompass)
                                  Expanded(
                                    flex: 4,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.explore,
                                          size: 10,
                                          color: iconColor == Colors.white70
                                              ? Colors.redAccent
                                              : iconColor,
                                        ),
                                        const SizedBox(width: 2),
                                        Flexible(
                                          child: Text(
                                            heading > 0.0 || cardinalDirection != '--'
                                                ? '${heading.round()}° $cardinalDirection'
                                                : '--',
                                            style: TextStyle(
                                              color: textColor.withOpacity(0.9),
                                              fontSize: 10.0,
                                              fontWeight: FontWeight.w500,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),

                        // Optional Custom Note & Person Stamp (if configured)
                        if (effectiveSettings.customNote.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.description,
                                  size: 10,
                                  color: iconColor == Colors.white70
                                      ? Colors.lightGreenAccent
                                      : iconColor,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Note: ${effectiveSettings.customNote.trim()}',
                                    style: TextStyle(
                                      color: textColor.withOpacity(0.9),
                                      fontSize: 9.5,
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (effectiveSettings.personName.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 10,
                                  color: iconColor == Colors.white70
                                      ? Colors.cyanAccent
                                      : iconColor,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'By: ${effectiveSettings.personName.trim()}',
                                    style: TextStyle(
                                      color: textColor.withOpacity(0.9),
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGpsFreshnessWidget() {
    final int secAgo = lastGpsFixTime != null
        ? DateTime.now().difference(lastGpsFixTime!).inSeconds.clamp(0, 999)
        : 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (lastGpsFixTime != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: (secAgo <= 15 && !isRefreshingGps)
                        ? Colors.greenAccent
                        : Colors.amberAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  isRefreshingGps ? 'Locating...' : 'Updated ${secAgo}s ago',
                  style: const TextStyle(
                    fontSize: 9.5,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        if (onRefreshGps != null) ...[
          const SizedBox(width: 2),
          GestureDetector(
            onTap: isRefreshingGps ? null : onRefreshGps,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: isRefreshingGps
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.amberAccent,
                      ),
                    )
                  : const Icon(
                      Icons.my_location,
                      size: 14,
                      color: Colors.amberAccent,
                    ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Smooth 60° camera direction / field-of-view radar cone with radial gradient fill.
class _FovConePainter extends CustomPainter {
  const _FovConePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const double radius = 34.0;
    const double startAngle = -math.pi / 2 - (math.pi / 6); // -120° (60° cone centered on North)
    const double sweepAngle = math.pi / 3; // 60°

    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1. Sector path for soft radial gradient fill
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(rect, startAngle, sweepAngle, false)
      ..close();

    final fillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.blueAccent.withOpacity(0.42),
          Colors.blueAccent.withOpacity(0.0),
        ],
        stops: const [0.0, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, fillPaint);

    // 2. Thin 1.2px curved outer stroke along the arc
    final arcPath = Path()..addArc(rect, startAngle, sweepAngle);
    final arcPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(arcPath, arcPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
