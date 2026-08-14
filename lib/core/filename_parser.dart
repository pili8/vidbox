import 'dart:convert';

import '../models/media_item.dart';

/// 抖音下载文件名解析器。
///
/// 识别 `dy<N>_<作者>_<类型>_<标题>_<14位时间戳>_<序号>.<扩展名>` 结构化命名。
/// 其中 `dy` 后的数字 N 即星级（1~5），`dy1` 为默认基线。
///
/// 解析策略从尾部反推时间戳与序号，再靠「视频/图集」类型词定位作者边界，
/// 稳健抗标题与作者名中的下划线。
class FilenameParser {
  FilenameParser._();

  /// 结构化命名主体：dy<星级>_..._<14位时间戳>_<序号>
  static final RegExp _structRe = RegExp(r'^dy(\d)_(.*)_(\d{14})_(\d+)$');

  /// 遗留的方括号标记前缀（如旧版 [★3]、[已收藏]），剥离但不作为星级来源
  static final RegExp _tagRe = RegExp(r'^(\[[^\]]*\])+');

  /// 类型词，用于定位作者与标题的边界
  static const _typeTokens = {'视频', '图集'};

  /// 解析单个文件路径。
  ///
  /// 无论成功与否都返回 [MediaItem]；失败时 `author` 为空、`type` 为 unknown、
  /// `star` 为 0，调用方可用 [MediaItem.isParsed] 判断，未解析的归入「待整理」组。
  static MediaItem parse(String path) {
    final filename = _basename(path);
    final dot = filename.lastIndexOf('.');
    String base = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot) : '';

    // 剥离遗留的方括号标记前缀（防御旧版命名）
    base = base.replaceFirst(_tagRe, '');

    final m = _structRe.firstMatch(base);
    if (m == null) {
      return MediaItem(
        path: path,
        filename: filename,
        author: '',
        type: MediaType.unknown,
        title: '',
        timestamp: null,
        index: null,
        ext: ext,
        star: 0,
      );
    }

    final star = int.parse(m.group(1)!);
    final head = m.group(2)!;
    final timestamp = m.group(3)!;
    final index = int.parse(m.group(4)!);

    // head = 作者_类型_标题。用类型词定位边界，作者名可含下划线。
    final parts = head.split('_');
    final typeIdx = parts.indexWhere(_typeTokens.contains);

    String author;
    MediaType type;
    String title;
    if (typeIdx > 0) {
      author = parts.sublist(0, typeIdx).join('_');
      type = MediaType.fromRaw(parts[typeIdx]);
      title = parts.sublist(typeIdx + 1).join('_');
    } else if (parts.length >= 2) {
      // 兜底：找不到类型词时按前两段切
      author = parts[0];
      type = MediaType.fromRaw(parts[1]);
      title = parts.length > 2 ? parts.sublist(2).join('_') : '';
    } else {
      return MediaItem(
        path: path,
        filename: filename,
        author: '',
        type: MediaType.unknown,
        title: '',
        timestamp: timestamp,
        index: index,
        ext: ext,
        star: star,
      );
    }

    return MediaItem(
      path: path,
      filename: filename,
      author: author,
      type: type,
      title: title,
      timestamp: timestamp,
      index: index,
      ext: ext,
      star: star,
    );
  }

  /// 生成设置星级后的新文件名：把 `dy` 后的数字改为目标星级。
  ///
  /// 保持文件名其余部分不变（原风格）。星级限制在 1~5。
  /// 若文件名无 `dy` 前缀（未解析文件），原样返回（无法用此方式标星）。
  static String buildStarredFilename(String filename, int star) {
    final s = star.clamp(1, 5);
    return filename.replaceFirst(RegExp(r'^dy\d'), 'dy$s');
  }

  /// 校验文件名（不含目录）的字节长度是否合法（≤255，UTF-8 中文占 3 字节）。
  /// 返回 null 表示合法，否则返回错误信息。
  static String? validateFilenameLength(String filename) {
    final bytes = utf8.encode(filename).length;
    if (bytes > 255) {
      return '文件名过长（$bytes/255 字节）';
    }
    return null;
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx < 0 ? normalized : normalized.substring(idx + 1);
  }
}
