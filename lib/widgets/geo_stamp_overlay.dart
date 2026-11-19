import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/app_settings.dart';

class GeoStampOverlay extends StatelessWidget {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final String address;
  final String formattedDateTime;
  final double? magneticField;
  final double? heading;
  final String cardinalDirection;
  final bool showTelemetry;
  final AppSettings? settings;
  final double scale;

  const GeoStampOverlay({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.address,
    required this.formattedDateTime,
    this.magneticField,
    this.heading,
    this.cardinalDirection = '--',
    this.showTelemetry = true,
    this.settings,
    this.scale = 1.0,
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

    // Template Styling
    Color cardBgColor;
    Color textColor;
    Color iconColor;
    Border? border;

    switch (effectiveSettings.template) {
      case StampTemplate.classicDark:
        cardBgColor = Colors.black.withOpacity(0.85);
        textColor = Colors.white;
        iconColor = Colors.amber;
        border = Border.all(color: Colors.amber.withOpacity(0.5), width: 1.0);
        break;
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
        border = Border.all(color: Colors.white.withOpacity(0.18), width: 1.0);
        break;
    }

    return Transform.scale(
      scale: scale,
      alignment: Alignment.bottomCenter,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.redAccent,
                                      size: 24,
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
                        // ROW 1: Full Address
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
                                  address.isNotEmpty
                                      ? address
                                      : 'Acquiring GPS location...',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    height: 1.15,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
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
                                  formattedDateTime,
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
                                            heading != null
                                                ? '${heading!.round()}° $cardinalDirection'
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
                        if (effectiveSettings.showCustomNote &&
                            effectiveSettings.customNote.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'Note: ${effectiveSettings.customNote}',
                              style: TextStyle(
                                color: textColor.withOpacity(0.85),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
