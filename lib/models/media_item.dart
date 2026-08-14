/// 媒体类型
enum MediaType {
  video,   // 单视频
  album,   // 图集（一组图片中的一张）
  unknown; // 无法解析

  static MediaType fromRaw(String raw) {
    switch (raw) {
      case '视频':
        return MediaType.video;
      case '图集':
        return MediaType.album;
      default:
        return MediaType.unknown;
    }
  }
}

/// 单个媒体文件（视频或图片）的内存模型。
///
/// 文件系统即数据库：分类、星标、分组信息都来自文件名本身，
/// 本模型只是文件名解析结果的载体，不额外维护状态。
class MediaItem {
  /// 文件完整路径
  final String path;

  /// 文件名（不含目录）
  final String filename;

  /// 作者（dy1_ 结构的第二个字段），未解析时为空串
  final String author;

  /// 类型：视频 / 图集 / 未知
  final MediaType type;

  /// 标题（作品描述），可能含 #话题 @提及
  final String title;

  /// 14 位时间戳 YYYYMMDDHHMMSS，未解析时为 null
  final String? timestamp;

  /// 图集序号（第几张），未解析时为 null
  final int? index;

  /// 扩展名（含点，如 .mp4）
  final String ext;

  /// 星标等级（来自文件名 dy<N>）：1~5。
  /// dy1 为基线（未收藏），≥2 表示已收藏/标星；0 表示未解析。
  final int star;

  const MediaItem({
    required this.path,
    required this.filename,
    required this.author,
    required this.type,
    required this.title,
    required this.timestamp,
    required this.index,
    required this.ext,
    required this.star,
  });

  /// 是否成功解析出结构化信息
  bool get isParsed => author.isNotEmpty;

  /// 是否为图片（webp/jpg/jpeg/png 等）
  bool get isImage {
    final e = ext.toLowerCase();
    return e == '.webp' || e == '.jpg' || e == '.jpeg' || e == '.png' || e == '.gif';
  }

  /// 是否已标星/收藏（星级 ≥2 才算收藏，dy1 是基线不高亮）
  bool get isStarred => star >= 2;

  @override
  String toString() => 'MediaItem($author, $type, "$title", ★$star)';
}
