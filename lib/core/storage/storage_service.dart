import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only presentation preferences go here. Twitter credentials use secure storage.
class StorageService {
  StorageService(this.preferences);
  final SharedPreferences preferences;
  static const keyThemeMode = 'theme_mode';
  static const keyUseDynamicColor = 'use_dynamic_color';
  static Future<StorageService> init() async =>
      StorageService(await SharedPreferences.getInstance());
  int getInt(String key, {int defaultValue = 0}) =>
      preferences.getInt(key) ?? defaultValue;
  bool getBool(String key, {bool defaultValue = false}) =>
      preferences.getBool(key) ?? defaultValue;
  Future<bool> setInt(String key, int value) => preferences.setInt(key, value);
  Future<bool> setBool(String key, bool value) =>
      preferences.setBool(key, value);
  bool getEnableHaptics() => getBool('haptics', defaultValue: true);
  Future<bool> setEnableHaptics(bool value) => setBool('haptics', value);
  bool getUseFloatingNavBar() => getBool('floating_nav', defaultValue: true);
  Future<bool> setUseFloatingNavBar(bool value) =>
      setBool('floating_nav', value);
  bool getUseCustomFontWeight() => getBool('custom_font_weight');
  Future<bool> setUseCustomFontWeight(bool value) =>
      setBool('custom_font_weight', value);
  int getCustomFontWeightDelta() => getInt('font_weight_delta');
  Future<bool> setCustomFontWeightDelta(int value) =>
      setInt('font_weight_delta', value);
  int getScreenRefreshRateMode() => getInt('refresh_rate');
  Future<bool> setScreenRefreshRateMode(int value) =>
      setInt('refresh_rate', value);
}

final storageServiceProvider =
    Provider<StorageService>((ref) => throw UnimplementedError());
