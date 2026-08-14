import 'package:shared_preferences/shared_preferences.dart';

/// 应用设置持久化（扫描目录列表等）。
class SettingsService {
  SettingsService._();

  static const _keyScanDirs = 'scan_dirs';
  static const _defaultDirs = <String>['/storage/emulated/0/Download'];

  /// 获取扫描目录列表。
  static Future<List<String>> getScanDirs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyScanDirs) ?? List.of(_defaultDirs);
  }

  /// 保存扫描目录列表。
  static Future<void> saveScanDirs(List<String> dirs) async {
    final prefs = await SharedPreferences.getInstance();
    // 去重 + 过滤空项
    final cleaned = dirs.where((d) => d.trim().isNotEmpty).map((d) => d.trim()).toSet().toList();
    await prefs.setStringList(_keyScanDirs, cleaned);
  }
}
