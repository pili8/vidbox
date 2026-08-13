import '../models/media_item.dart';

/// 抖音下载文件名解析器。
///
/// 识别 `dy1_<作者>_<类型>_<标题>_<14位时间戳>_<序号>.<扩展名>` 结构化命名，
/// 以及可选的星标前缀 `[★1]`~`[★5]`。
///
/// 解析策略从尾部反推，稳健抗标题内下划线。
class FilenameParser {
  FilenameParser._();

  /// 星标前缀，如 [★3]
  static final RegExp _starRe = RegExp(r'^\[★([1-5])\]');

  /// 其他方括号标记前缀，如 [已收藏]，剥离但不提取
  static final RegExp _tagRe = RegExp(r'^(\[[^\]]*\])+');

  /// dy1_ 结构化命名主体
  static final RegExp _structRe = RegExp(r'^dy1_(.*)_(\d{14})_(\d+)$');

  /// 解析单个文件路径。
  ///
  /// 无论成功与否都返回 [MediaItem]；失败时 `author` 为空、`type` 为 unknown，
  /// 调用方可用 [MediaItem.isParsed] 判断，未解析的归入「待整理」组。
  static MediaItem parse(String path) {
    final filename = _basename(path);
    final dot = filename.lastIndexOf('.');
    String base;
    String ext;
    if (dot > 0) {
      base = filename.substring(0, dot);
      ext = filename.substring(dot);
    } else {
      base = filename;
      ext = '';
    }

    // 1. 提取星标
    var star = 0;
    final starM = _starRe.firstMatch(base);
    if (starM != null) {
      star = int.parse(starM.group(1)!);
      base = base.substring(starM.end);
    }

    // 2. 剥离其他标记前缀
    base = base.replaceFirst(_tagRe, '');

    // 3. 匹配 dy1_ 结构
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
        star: star,
      );
    }

    final head = m.group(1)!;
    final timestamp = m.group(2)!;
    final index = int.parse(m.group(3)!);

    // head = 作者_类型_标题，按前两个下划线切，剩余为标题
    final parts = head.split('_');
    if (parts.length < 2) {
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

    final author = parts[0];
    final type = MediaType.fromRaw(parts[1]);
    final title = parts.length > 2 ? parts.sublist(2).join('_') : '';

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

  /// 生成新的文件名（加星标后）。
  ///
  /// 在原始文件名（不含目录）前插入 `[★n]`，保持其余部分不变。
  /// `star = 0` 表示去掉星标。
  static String buildStarredFilename(String filename, int star) {
    // 先剥离现有星标，避免重复
    final clean = filename.replaceFirst(_starRe, '');
    if (star <= 0) return clean;
    return '[★$star]' + clean;
  }

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final idx = normalized.lastIndexOf('/');
    return idx < 0 ? normalized : normalized.substring(idx + 1);
  }
}
