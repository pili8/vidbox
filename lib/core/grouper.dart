import '../models/media_item.dart';

/// 单个作者的媒体集合。
class AuthorGroup {
  final String author;

  /// 单视频列表（已按时间戳升序）
  final List<MediaItem> videos;

  /// 图集子组：key -> 该组图片列表（已按序号升序）。
  /// key 优先用标题（同一图集标题相同），标题为空时退化为时间戳到分钟。
  final Map<String, List<MediaItem>> albumSets;

  AuthorGroup(this.author)
      : videos = [],
        albumSets = {};

  int get totalCount => videos.length + albumSets.values.fold(0, (s, l) => s + l.length);
}

/// 分组结果：作者组 + 待整理列表。
class GroupingResult {
  final Map<String, AuthorGroup> authors;
  final List<MediaItem> unparsed;

  GroupingResult(this.authors, this.unparsed);
}

/// 分组引擎：把解析后的媒体项按「作者 → 图集」确定性分组。
class Grouper {
  Grouper._();

  static GroupingResult group(List<MediaItem> items) {
    final authors = <String, AuthorGroup>{};
    final unparsed = <MediaItem>[];

    for (final item in items) {
      if (!item.isParsed) {
        unparsed.add(item);
        continue;
      }

      final g = authors.putIfAbsent(item.author, () => AuthorGroup(item.author));

      if (item.type == MediaType.album) {
        final key = item.title.isNotEmpty
            ? item.title
            : (item.timestamp?.substring(0, 12) ?? '');
        g.albumSets.putIfAbsent(key, () => []).add(item);
      } else {
        g.videos.add(item);
      }
    }

    // 排序：视频按时间戳，图集内按序号
    for (final g in authors.values) {
      g.videos.sort((a, b) => (a.timestamp ?? '').compareTo(b.timestamp ?? ''));
      for (final list in g.albumSets.values) {
        list.sort((a, b) => (a.index ?? 0).compareTo(b.index ?? 0));
      }
    }

    return GroupingResult(authors, unparsed);
  }
}
