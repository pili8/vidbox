import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/filename_parser.dart';
import '../models/media_item.dart';
import 'file_service.dart';

/// SQLite 索引服务：只做缓存、随时可重建，不违反"文件系统即真相"。
///
/// 用途：
/// 1. 增量索引——按 path+mtime+size 判断文件是否变化，只重新解析变化的文件；
/// 2. 缩略图磁盘缓存——视频首帧提取后存为 JPG，下次直接读文件。
///
/// 真相仍在文件名/文件系统里，本索引可整体删除重建。
class IndexService {
  IndexService._();

  static Database? _db;
  static String? _thumbDir;

  static const _table = 'media_index';

  /// 初始化数据库与缩略图目录。
  static Future<void> _ensureInit() async {
    if (_db != null) return;
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, 'vidbox_index.db'),
      version: 1,
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE $_table (
            path TEXT PRIMARY KEY,
            mtime INTEGER NOT NULL,
            size INTEGER NOT NULL,
            author TEXT NOT NULL DEFAULT '',
            type TEXT NOT NULL DEFAULT '',
            title TEXT NOT NULL DEFAULT '',
            timestamp TEXT,
            idx INTEGER,
            ext TEXT NOT NULL DEFAULT '',
            star INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );
    final appDir = await getApplicationDocumentsDirectory();
    _thumbDir = p.join(appDir.path, 'thumbs');
    await Directory(_thumbDir!).create(recursive: true);
  }

  /// 扫描目录并增量索引，返回全部 [MediaItem]。
  ///
  /// 未变化的文件直接从索引读取；新增/变化的文件重新解析并写入索引；
  /// 已删除的文件从索引移除。
  static Future<List<MediaItem>> scanAndIndex(List<String> dirs) async {
    await _ensureInit();
    final db = _db!;
    final allItems = <MediaItem>[];

    // 收集当前磁盘上的文件元数据
    final diskFiles = <String, Map<String, int>>{};
    for (final dir in dirs) {
      final metas = await FileService.listMediaFilesMeta(dir);
      for (final m in metas) {
        diskFiles[m['path'] as String] = {
          'mtime': m['mtime'] as int,
          'size': m['size'] as int,
        };
      }
    }

    // 读取索引中已有记录
    final rows = await db.query(_table);
    final indexed = <String, Map<String, Object?>>{};
    for (final r in rows) {
      indexed[r['path'] as String] = r;
    }

    // 1) 删除索引中已不存在的文件
    for (final path in indexed.keys.toList()) {
      if (!diskFiles.containsKey(path)) {
        await db.delete(_table, where: 'path = ?', whereArgs: [path]);
        indexed.remove(path);
      }
    }

    // 2) 处理磁盘上的每个文件
    for (final entry in diskFiles.entries) {
      final path = entry.key;
      final meta = entry.value;
      final mtime = meta['mtime'] as int;
      final size = meta['size'] as int;

      final cached = indexed[path];
      if (cached != null &&
          cached['mtime'] == mtime &&
          cached['size'] == size) {
        // 未变化，直接用索引
        allItems.add(_rowToItem(cached));
      } else {
        // 新增或变化，重新解析
        final item = FilenameParser.parse(path);
        await db.insert(
          _table,
          {
            'path': path,
            'mtime': mtime,
            'size': size,
            'author': item.author,
            'type': item.type.name,
            'title': item.title,
            'timestamp': item.timestamp,
            'idx': item.index,
            'ext': item.ext,
            'star': item.star,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        allItems.add(item);
      }
    }

    return allItems;
  }

  static MediaItem _rowToItem(Map<String, Object?> row) {
    return MediaItem(
      path: row['path'] as String,
      filename: p.basename(row['path'] as String),
      author: row['author'] as String? ?? '',
      type: _typeFromName(row['type'] as String? ?? ''),
      title: row['title'] as String? ?? '',
      timestamp: row['timestamp'] as String?,
      index: row['idx'] as int?,
      ext: row['ext'] as String? ?? '',
      star: row['star'] as int? ?? 0,
    );
  }

  static MediaType _typeFromName(String name) {
    for (final t in MediaType.values) {
      if (t.name == name) return t;
    }
    return MediaType.unknown;
  }

  /// 文件改名/移动/删除后，同步更新索引。
  static Future<void> updatePath(String oldPath, String newPath) async {
    await _ensureInit();
    final db = _db!;
    await db.delete(_table, where: 'path = ?', whereArgs: [oldPath]);
    if (newPath.isNotEmpty) {
      final f = File(newPath);
      if (f.existsSync()) {
        final item = FilenameParser.parse(newPath);
        await db.insert(
          _table,
          {
            'path': newPath,
            'mtime': f.lastModifiedSync().millisecondsSinceEpoch,
            'size': f.lengthSync(),
            'author': item.author,
            'type': item.type.name,
            'title': item.title,
            'timestamp': item.timestamp,
            'idx': item.index,
            'ext': item.ext,
            'star': item.star,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  /// 获取视频缩略图：先查磁盘缓存，未命中再提取并缓存。
  /// 图片文件直接返回 null（调用方用原图）。
  static Future<Uint8List?> getThumbnail(String path) async {
    await _ensureInit();
    final ext = p.extension(path).toLowerCase();
    const imageExts = {'.webp', '.jpg', '.jpeg', '.png', '.gif'};
    if (imageExts.contains(ext)) return null;

    final key = md5.convert(utf8.encode(path)).toString();
    final cacheFile = File(p.join(_thumbDir!, '$key.jpg'));
    if (cacheFile.existsSync()) {
      return cacheFile.readAsBytes();
    }

    final bytes = await FileService.getThumbnail(path);
    if (bytes != null) {
      await cacheFile.writeAsBytes(bytes);
    }
    return bytes;
  }

  /// 文件被删除/移动后，清理对应缩略图缓存。
  static Future<void> removeThumbnail(String path) async {
    await _ensureInit();
    final key = md5.convert(utf8.encode(path)).toString();
    final cacheFile = File(p.join(_thumbDir!, '$key.jpg'));
    if (cacheFile.existsSync()) {
      await cacheFile.delete();
    }
  }
}
