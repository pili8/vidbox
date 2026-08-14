import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../core/filename_parser.dart';
import '../core/grouper.dart';
import '../models/media_item.dart';
import 'file_service.dart';
import 'index_service.dart';

/// 单一数据源：持有全部媒体项，承载所有修改操作并通知各页面。
///
/// 全屏流 / 网格 / 首页都从它读写，解决"跨页面修改不同步"的问题。
/// 用 [ChangeNotifier] 实现，不引入额外状态管理框架。
class MediaStore extends ChangeNotifier {
  MediaStore._();
  static final MediaStore instance = MediaStore._();

  List<MediaItem> _items = [];
  List<MediaItem> get items => List.unmodifiable(_items);

  /// 作者分组结果（缓存，_items 变更时重建）
  GroupingResult? _grouping;
  GroupingResult? get grouping => _grouping;

  /// 已看记录（仅内存，不持久化到文件名；会话内有效）
  final Set<String> _seenPaths = {};

  /// 重新扫描（增量索引），并重建分组。
  Future<List<MediaItem>> rescan(List<String> dirs) async {
    _items = await IndexService.scanAndIndex(dirs);
    _rebuildGrouping();
    notifyListeners();
    return _items;
  }

  void _rebuildGrouping() {
    _grouping = Grouper.group(_items);
  }

  /// 通过 path 定位项索引；未找到返回 -1。
  int indexOf(String path) {
    for (var i = 0; i < _items.length; i++) {
      if (_items[i].path == path) return i;
    }
    return -1;
  }

  /// 设置星级（改文件名 dy 数字），成功后更新内存与索引。
  /// 返回是否成功。
  Future<bool> setStar(int index, int star) async {
    if (index < 0 || index >= _items.length) return false;
    final item = _items[index];
    final newName = FilenameParser.buildStarredFilename(item.filename, star);
    if (newName == item.filename) return true;
    final newPath = await FileService.renameFile(item.path, newName);
    if (newPath == null) return false;
    await IndexService.updatePath(item.path, newPath);
    _items[index] = FilenameParser.parse(newPath);
    _rebuildGrouping();
    notifyListeners();
    return true;
  }

  /// 删除到回收站，返回是否成功。
  Future<bool> delete(int index) async {
    if (index < 0 || index >= _items.length) return false;
    final item = _items[index];
    final ok = await FileService.deleteToTrash(item.path);
    if (!ok) return false;
    await IndexService.updatePath(item.path, '');
    await IndexService.removeThumbnail(item.path);
    _items.removeAt(index);
    _seenPaths.remove(item.path);
    _rebuildGrouping();
    notifyListeners();
    return true;
  }

  /// 移动到目标目录，返回是否成功。
  Future<bool> move(int index, String targetDir) async {
    if (index < 0 || index >= _items.length) return false;
    final item = _items[index];
    final ok = await FileService.moveFile(item.path, targetDir);
    if (!ok) return false;
    final newPath = '$targetDir/${item.filename}';
    await IndexService.updatePath(item.path, newPath);
    _items.removeAt(index);
    _seenPaths.remove(item.path);
    _rebuildGrouping();
    notifyListeners();
    return true;
  }

  /// 重命名（待整理归位等），返回是否成功。
  Future<bool> rename(int index, String newName) async {
    if (index < 0 || index >= _items.length) return false;
    final item = _items[index];
    final newPath = await FileService.renameFile(item.path, newName);
    if (newPath == null) return false;
    await IndexService.updatePath(item.path, newPath);
    _items[index] = FilenameParser.parse(newPath);
    _rebuildGrouping();
    notifyListeners();
    return true;
  }

  /// 批量设置星级，返回 (成功数, 失败数)。
  Future<(int, int)> batchStar(List<String> paths, int star) async {
    var ok = 0, fail = 0;
    for (final p in paths) {
      final i = indexOf(p);
      if (i < 0) {
        fail++;
        continue;
      }
      if (await setStar(i, star)) {
        ok++;
      } else {
        fail++;
      }
    }
    return (ok, fail);
  }

  /// 批量删除，返回 (成功数, 失败数)。
  Future<(int, int)> batchDelete(List<String> paths) async {
    var ok = 0, fail = 0;
    // 从后往前删，避免索引错位
    final sorted = paths.map(indexOf).where((i) => i >= 0).toList()..sort((a, b) => b.compareTo(a));
    for (final i in sorted) {
      if (await delete(i)) {
        ok++;
      } else {
        fail++;
      }
    }
    return (ok, fail);
  }

  /// 批量移动，返回 (成功数, 失败数)。
  Future<(int, int)> batchMove(List<String> paths, String targetDir) async {
    var ok = 0, fail = 0;
    final sorted = paths.map(indexOf).where((i) => i >= 0).toList()..sort((a, b) => b.compareTo(a));
    for (final i in sorted) {
      if (await move(i, targetDir)) {
        ok++;
      } else {
        fail++;
      }
    }
    return (ok, fail);
  }

  // ---- 已看记录 ----
  void markSeen(String path) => _seenPaths.add(path);
  bool isSeen(String path) => _seenPaths.contains(path);
  void clearSeen() {
    _seenPaths.clear();
    notifyListeners();
  }

  /// 获取缩略图（走索引磁盘缓存），供各页面复用。
  Future<Uint8List?> thumbFor(String path) => IndexService.getThumbnail(path);

  // ---- 筛选辅助 ----
  /// 所有已收藏（星级 ≥2）项
  List<MediaItem> starredItems() => _items.where((it) => it.isStarred).toList();

  /// 所有图集项
  List<MediaItem> albumItems() => _items.where((it) => it.type == MediaType.album).toList();
}
