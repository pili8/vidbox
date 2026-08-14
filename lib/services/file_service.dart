import 'dart:typed_data';

import 'package:flutter/services.dart';

/// 文件操作服务（Dart 侧）。
///
/// 所有真实文件系统操作（扫描、移动、重命名、删除）都通过 MethodChannel
/// 下沉到 Kotlin 原生层实现，Dart 层只负责调用和解析。
class FileService {
  FileService._();

  static const MethodChannel _channel = MethodChannel('vidbox/file');

  /// 列出目录下所有媒体文件（视频/图片）的完整路径。
  static Future<List<String>> listMediaFiles(String dir) async {
    final result = await _channel.invokeListMethod<String>(
      'listMediaFiles',
      {'dir': dir},
    );
    return result ?? const [];
  }

  /// 重命名文件（文件名不含目录），返回新的完整路径；失败返回 null。
  static Future<String?> renameFile(String srcPath, String newName) async {
    return await _channel.invokeMethod<String>(
      'renameFile',
      {'src': srcPath, 'newName': newName},
    );
  }

  /// 移动文件到目标目录，返回是否成功。
  static Future<bool> moveFile(String srcPath, String dstDir) async {
    return await _channel.invokeMethod<bool>(
          'moveFile',
          {'src': srcPath, 'dstDir': dstDir},
        ) ??
        false;
  }

  /// 删除文件到回收站（.trash 隐藏目录），返回是否成功。
  static Future<bool> deleteToTrash(String srcPath) async {
    return await _channel.invokeMethod<bool>(
          'deleteToTrash',
          {'src': srcPath},
        ) ??
        false;
  }

  /// 获取视频首帧缩略图（JPEG 字节），失败或图片返回 null。
  static Future<Uint8List?> getThumbnail(String path) async {
    return await _channel.invokeMethod<Uint8List>(
      'getThumbnail',
      {'path': path},
    );
  }
}
