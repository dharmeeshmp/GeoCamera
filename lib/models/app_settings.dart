import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum StampTemplate {
  modernTranslucent,
  classicDark,
  cleanWhite,
  minimalOverlay,
}

enum MapStyle {
  openStreetMap,
  cartoVoyager,
  satellite,
}

class AppSettings extends ChangeNotifier {
  int _templateIndex = 0;
  StampTemplate _template = StampTemplate.modernTranslucent;

  // Camera Settings
  bool _captureSound = true;
  bool _saveOriginal = false;
  String _cameraGridMode = 'off';

  // Picture Settings
  String _mapType = 'Normal';
  MapStyle _mapStyle = MapStyle.openStreetMap;
  String _customNote = '';
  bool _showCustomNote = false;
  String _personName = '';
  bool _showPersonName = false;

  // App Settings
  String _customAddress = '';
  String _dateFormat = '12-Hour';
  String _appLanguage = 'English';

  // Display Fields & Units
  bool _showMap = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  bool _showDateTime = true;
  bool _showAltitude = true;
  bool _showAccuracy = true;
  bool _showMagnetic = true;
  bool _showCompass = true;
  bool _useFeet = false;

  // Getters
  int get templateIndex => _templateIndex;
  StampTemplate get template => _template;
  bool get captureSound => _captureSound;
  bool get saveOriginal => _saveOriginal;
  String get cameraGridMode => _cameraGridMode;

  String get mapType => _mapType;
  MapStyle get mapStyle => _mapStyle;
  String get customNote => _customNote;
  bool get showCustomNote => _showCustomNote;
  String get personName => _personName;
  bool get showPersonName => _showPersonName;

  String get customAddress => _customAddress;
  String get dateFormat => _dateFormat;
  String get appLanguage => _appLanguage;

  bool get showMap => _showMap;
  bool get showAddress => _showAddress;
  bool get showCoordinates => _showCoordinates;
  bool get showDateTime => _showDateTime;
  bool get showAltitude => _showAltitude;
  bool get showAccuracy => _showAccuracy;
  bool get showMagnetic => _showMagnetic;
  bool get showCompass => _showCompass;
  bool get useFeet => _useFeet;

  String get tileUrl {
    switch (_mapType) {
      case 'Satellite':
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case 'Terrain':
        return 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
      case 'Normal':
      default:
        switch (_mapStyle) {
          case MapStyle.satellite:
            return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
          case MapStyle.cartoVoyager:
            return 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
          case MapStyle.openStreetMap:
          default:
            return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
        }
    }
  }

  String formatDateTime([DateTime? dt]) {
    final time = dt ?? DateTime.now();
    switch (_dateFormat) {
      case '24-Hour':
        final base = DateFormat('EEE, MMM d, yyyy, HH:mm').format(time);
        final offset = time.timeZoneOffset;
        final sign = offset.isNegative ? '-' : '+';
        final hours = offset.inHours.abs();
        final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
        return '$base (GMT $sign$hours:$minutes)';
      case 'ISO':
        return time.toIso8601String();
      case '12-Hour':
      default:
        final base = DateFormat('EEE, MMM d, yyyy, hh:mm a').format(time);
        final offset = time.timeZoneOffset;
        final sign = offset.isNegative ? '-' : '+';
        final hours = offset.inHours.abs();
        final minutes = (offset.inMinutes.abs() % 60).toString().padLeft(2, '0');
        return '$base (GMT $sign$hours:$minutes)';
    }
  }

  void update({
    int? templateIndex,
    StampTemplate? template,
    bool? captureSound,
    bool? saveOriginal,
    String? cameraGridMode,
    String? mapType,
    MapStyle? mapStyle,
    String? customNote,
    bool? showCustomNote,
    String? personName,
    bool? showPersonName,
    String? customAddress,
    String? dateFormat,
    String? appLanguage,
    bool? showMap,
    bool? showAddress,
    bool? showCoordinates,
    bool? showDateTime,
    bool? showAltitude,
    bool? showAccuracy,
    bool? showMagnetic,
    bool? showCompass,
    bool? useFeet,
  }) {
    if (templateIndex != null) {
      _templateIndex = templateIndex;
      _template = templateIndex == 1
          ? StampTemplate.classicDark
          : StampTemplate.modernTranslucent;
    } else if (template != null) {
      _template = template;
      _templateIndex = template == StampTemplate.classicDark ? 1 : 0;
    }

    if (captureSound != null) _captureSound = captureSound;
    if (saveOriginal != null) _saveOriginal = saveOriginal;
    if (cameraGridMode != null) _cameraGridMode = cameraGridMode;

    if (mapType != null) {
      _mapType = mapType;
      if (mapType == 'Satellite') {
        _mapStyle = MapStyle.satellite;
      } else if (mapType == 'Terrain') {
        _mapStyle = MapStyle.cartoVoyager;
      } else {
        _mapStyle = MapStyle.openStreetMap;
      }
    } else if (mapStyle != null) {
      _mapStyle = mapStyle;
      if (mapStyle == MapStyle.satellite) {
        _mapType = 'Satellite';
      } else if (mapStyle == MapStyle.cartoVoyager) {
        _mapType = 'Terrain';
      } else {
        _mapType = 'Normal';
      }
    }

    if (customNote != null) {
      _customNote = customNote;
      _showCustomNote = customNote.isNotEmpty;
    }
    if (showCustomNote != null) _showCustomNote = showCustomNote;

    if (personName != null) {
      _personName = personName;
      _showPersonName = personName.isNotEmpty;
    }
    if (showPersonName != null) _showPersonName = showPersonName;

    if (customAddress != null) _customAddress = customAddress;
    if (dateFormat != null) _dateFormat = dateFormat;
    if (appLanguage != null) _appLanguage = appLanguage;

    if (showMap != null) _showMap = showMap;
    if (showAddress != null) _showAddress = showAddress;
    if (showCoordinates != null) _showCoordinates = showCoordinates;
    if (showDateTime != null) _showDateTime = showDateTime;
    if (showAltitude != null) _showAltitude = showAltitude;
    if (showAccuracy != null) _showAccuracy = showAccuracy;
    if (showMagnetic != null) _showMagnetic = showMagnetic;
    if (showCompass != null) _showCompass = showCompass;
    if (useFeet != null) _useFeet = useFeet;

    notifyListeners();
    saveToPrefs();
  }

  static Future<AppSettings> loadFromPrefs() async {
    final settings = AppSettings();
    try {
      final prefs = await SharedPreferences.getInstance();

      final templateIdx = prefs.getInt('template_index') ?? prefs.getInt('stamp_template') ?? 0;
      settings._templateIndex = templateIdx;
      if (templateIdx >= 0 && templateIdx < StampTemplate.values.length) {
        settings._template = StampTemplate.values[templateIdx];
      }

      settings._captureSound = prefs.getBool('capture_sound') ?? true;
      settings._saveOriginal = prefs.getBool('save_original') ?? false;
      settings._cameraGridMode = prefs.getString('camera_grid_mode') ?? 'off';

      settings._mapType = prefs.getString('map_type') ?? 'Normal';
      final mapStyleIndex = prefs.getInt('map_style') ?? 0;
      if (mapStyleIndex >= 0 && mapStyleIndex < MapStyle.values.length) {
        settings._mapStyle = MapStyle.values[mapStyleIndex];
      }

      settings._customNote = prefs.getString('custom_note') ?? '';
      settings._showCustomNote = prefs.getBool('show_custom_note') ?? settings._customNote.isNotEmpty;

      settings._personName = prefs.getString('person_name') ?? '';
      settings._showPersonName = prefs.getBool('show_person_name') ?? settings._personName.isNotEmpty;

      settings._customAddress = prefs.getString('custom_address') ?? '';
      settings._dateFormat = prefs.getString('date_format') ?? '12-Hour';
      settings._appLanguage = prefs.getString('app_language') ?? 'English';

      settings._showMap = prefs.getBool('show_map') ?? true;
      settings._showAddress = prefs.getBool('show_address') ?? true;
      settings._showCoordinates = prefs.getBool('show_coordinates') ?? true;
      settings._showDateTime = prefs.getBool('show_datetime') ?? true;
      settings._showAltitude = prefs.getBool('show_altitude') ?? true;
      settings._showAccuracy = prefs.getBool('show_accuracy') ?? true;
      settings._showMagnetic = prefs.getBool('show_magnetic') ?? true;
      settings._showCompass = prefs.getBool('show_compass') ?? true;
      settings._useFeet = prefs.getBool('use_feet') ?? false;
    } catch (e) {
      debugPrint('Error loading settings from prefs: $e');
    }
    return settings;
  }

  Future<void> saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('template_index', _templateIndex);
      await prefs.setInt('stamp_template', _template.index);

      await prefs.setBool('capture_sound', _captureSound);
      await prefs.setBool('save_original', _saveOriginal);
      await prefs.setString('camera_grid_mode', _cameraGridMode);

      await prefs.setString('map_type', _mapType);
      await prefs.setInt('map_style', _mapStyle.index);

      await prefs.setString('custom_note', _customNote);
      await prefs.setBool('show_custom_note', _showCustomNote);

      await prefs.setString('person_name', _personName);
      await prefs.setBool('show_person_name', _showPersonName);

      await prefs.setString('custom_address', _customAddress);
      await prefs.setString('date_format', _dateFormat);
      await prefs.setString('app_language', _appLanguage);

      await prefs.setBool('show_map', _showMap);
      await prefs.setBool('show_address', _showAddress);
      await prefs.setBool('show_coordinates', _showCoordinates);
      await prefs.setBool('show_datetime', _showDateTime);
      await prefs.setBool('show_altitude', _showAltitude);
      await prefs.setBool('show_accuracy', _showAccuracy);
      await prefs.setBool('show_magnetic', _showMagnetic);
      await prefs.setBool('show_compass', _showCompass);
      await prefs.setBool('use_feet', _useFeet);
    } catch (e) {
      debugPrint('Error saving settings to prefs: $e');
    }
  }
}
