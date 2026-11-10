import 'package:flutter/material.dart';
import '../services/storage_service.dart';

class SettingsProvider extends ChangeNotifier {
  static const List<String> qualities = ['Auto', '1080p', '720p', '480p', '360p'];

  String _preferredQuality = 'Auto';

  String get preferredQuality => _preferredQuality;

  SettingsProvider() {
    loadSettings();
  }

  Future<void> loadSettings() async {
    _preferredQuality = await StorageService.getPreferredQuality();
    notifyListeners();
  }

  Future<void> updateQuality(String quality) async {
    _preferredQuality = quality;
    await StorageService.setPreferredQuality(quality);
    notifyListeners();
  }
}
