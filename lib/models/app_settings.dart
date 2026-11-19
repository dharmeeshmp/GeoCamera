import 'package:flutter/foundation.dart';
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
  StampTemplate _template = StampTemplate.modernTranslucent;
  MapStyle _mapStyle = MapStyle.openStreetMap;
  bool _showMap = true;
  bool _showAddress = true;
  bool _showCoordinates = true;
  bool _showDateTime = true;
  bool _showAltitude = true;
  bool _showAccuracy = true;
  bool _showMagnetic = true;
  bool _showCompass = true;
  bool _showCustomNote = false;
  String _customNote = '';
  bool _showPersonName = false;
  String _personName = '';
  bool _useFeet = false;

  StampTemplate get template => _template;
  MapStyle get mapStyle => _mapStyle;
  bool get showMap => _showMap;
  bool get showAddress => _showAddress;
  bool get showCoordinates => _showCoordinates;
  bool get showDateTime => _showDateTime;
  bool get showAltitude => _showAltitude;
  bool get showAccuracy => _showAccuracy;
  bool get showMagnetic => _showMagnetic;
  bool get showCompass => _showCompass;
  bool get showCustomNote => _showCustomNote;
  String get customNote => _customNote;
  bool get showPersonName => _showPersonName;
  String get personName => _personName;
  bool get useFeet => _useFeet;

  String get tileUrl {
    switch (_mapStyle) {
      case MapStyle.openStreetMap:
        return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
      case MapStyle.cartoVoyager:
        return 'https://basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';
      case MapStyle.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    }
  }

  void update({
    StampTemplate? template,
    MapStyle? mapStyle,
    bool? showMap,
    bool? showAddress,
    bool? showCoordinates,
    bool? showDateTime,
    bool? showAltitude,
    bool? showAccuracy,
    bool? showMagnetic,
    bool? showCompass,
    bool? showCustomNote,
    String? customNote,
    bool? showPersonName,
    String? personName,
    bool? useFeet,
  }) {
    if (template != null) _template = template;
    if (mapStyle != null) _mapStyle = mapStyle;
    if (showMap != null) _showMap = showMap;
    if (showAddress != null) _showAddress = showAddress;
    if (showCoordinates != null) _showCoordinates = showCoordinates;
    if (showDateTime != null) _showDateTime = showDateTime;
    if (showAltitude != null) _showAltitude = showAltitude;
    if (showAccuracy != null) _showAccuracy = showAccuracy;
    if (showMagnetic != null) _showMagnetic = showMagnetic;
    if (showCompass != null) _showCompass = showCompass;
    if (showCustomNote != null) _showCustomNote = showCustomNote;
    if (customNote != null) _customNote = customNote;
    if (showPersonName != null) _showPersonName = showPersonName;
    if (personName != null) _personName = personName;
    if (useFeet != null) _useFeet = useFeet;

    notifyListeners();
    saveToPrefs();
  }

  static Future<AppSettings> loadFromPrefs() async {
    final settings = AppSettings();
    try {
      final prefs = await SharedPreferences.getInstance();
      final templateIndex = prefs.getInt('stamp_template') ?? 0;
      if (templateIndex >= 0 && templateIndex < StampTemplate.values.length) {
        settings._template = StampTemplate.values[templateIndex];
      }

      final mapStyleIndex = prefs.getInt('map_style') ?? 0;
      if (mapStyleIndex >= 0 && mapStyleIndex < MapStyle.values.length) {
        settings._mapStyle = MapStyle.values[mapStyleIndex];
      }

      settings._showMap = prefs.getBool('show_map') ?? true;
      settings._showAddress = prefs.getBool('show_address') ?? true;
      settings._showCoordinates = prefs.getBool('show_coordinates') ?? true;
      settings._showDateTime = prefs.getBool('show_datetime') ?? true;
      settings._showAltitude = prefs.getBool('show_altitude') ?? true;
      settings._showAccuracy = prefs.getBool('show_accuracy') ?? true;
      settings._showMagnetic = prefs.getBool('show_magnetic') ?? true;
      settings._showCompass = prefs.getBool('show_compass') ?? true;
      settings._showCustomNote = prefs.getBool('show_custom_note') ?? false;
      settings._customNote = prefs.getString('custom_note') ?? '';
      settings._showPersonName = prefs.getBool('show_person_name') ?? false;
      settings._personName = prefs.getString('person_name') ?? '';
      settings._useFeet = prefs.getBool('use_feet') ?? false;
    } catch (e) {
      debugPrint('Error loading settings from prefs: $e');
    }
    return settings;
  }

  Future<void> saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('stamp_template', _template.index);
      await prefs.setInt('map_style', _mapStyle.index);
      await prefs.setBool('show_map', _showMap);
      await prefs.setBool('show_address', _showAddress);
      await prefs.setBool('show_coordinates', _showCoordinates);
      await prefs.setBool('show_datetime', _showDateTime);
      await prefs.setBool('show_altitude', _showAltitude);
      await prefs.setBool('show_accuracy', _showAccuracy);
      await prefs.setBool('show_magnetic', _showMagnetic);
      await prefs.setBool('show_compass', _showCompass);
      await prefs.setBool('show_custom_note', _showCustomNote);
      await prefs.setString('custom_note', _customNote);
      await prefs.setBool('show_person_name', _showPersonName);
      await prefs.setString('person_name', _personName);
      await prefs.setBool('use_feet', _useFeet);
    } catch (e) {
      debugPrint('Error saving settings to prefs: $e');
    }
  }
}
