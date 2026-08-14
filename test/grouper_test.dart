import 'package:flutter_test/flutter_test.dart';
import 'package:vidbox/core/grouper.dart';
import 'package:vidbox/models/media_item.dart';

MediaItem _item({
  required String path,
  required String author,
  MediaType type = MediaType.video,
  String title = '',
  String? timestamp,
  int? index,
  String ext = '.mp4',
  int star = 1,
}) {
  return MediaItem(
    path: path,
    filename: path.split('/').last,
    author: author,
    type: type,
    title: title,
    timestamp: timestamp,
    index: index,
    ext: ext,
    star: star,
  );
}

void main() {
  group('Grouper.group 作者分组', () {
    test('同作者归入一组', () {
      final items = [
        _item(path: '/d/dy1_张三_视频_a_20260101120000_1.mp4', author: '张三', timestamp: '20260101120000'),
        _item(path: '/d/dy1_张三_视频_b_20260101130000_1.mp4', author: '张三', timestamp: '20260101130000'),
        _item(path: '/d/dy1_李四_视频_c_20260101120000_1.mp4', author: '李四', timestamp: '20260101120000'),
      ];
      final r = Grouper.group(items);
      expect(r.authors.length, 2);
      expect(r.authors['张三']!.videos.length, 2);
      expect(r.authors['李四']!.videos.length, 1);
      expect(r.unparsed, isEmpty);
    });

    test('视频按时间戳升序', () {
      final items = [
        _item(path: '/d/dy1_张_视频_late_20260101130000_1.mp4', author: '张', timestamp: '20260101130000'),
        _item(path: '/d/dy1_张_视频_early_20260101120000_1.mp4', author: '张', timestamp: '20260101120000'),
      ];
      final r = Grouper.group(items);
      expect(r.authors['张']!.videos.first.timestamp, '20260101120000');
    });
  });

  group('Grouper.group 图集聚组', () {
    test('同作者同标题图集聚成一组', () {
      final items = [
        _item(path: '/d/dy1_张_图集_景_20260101120000_1.jpg', author: '张', type: MediaType.album, title: '景', timestamp: '20260101120000', index: 1, ext: '.jpg'),
        _item(path: '/d/dy1_张_图集_景_20260101120005_2.jpg', author: '张', type: MediaType.album, title: '景', timestamp: '20260101120005', index: 2, ext: '.jpg'),
      ];
      final r = Grouper.group(items);
      final g = r.authors['张']!;
      expect(g.albumSets.length, 1);
      final set = g.albumSets.values.first;
      expect(set.length, 2);
      expect(set.first.index, 1);
      expect(set.last.index, 2);
    });

    test('空标题退化到时间戳到分钟', () {
      final items = [
        _item(path: '/d/dy1_张_图集__20260101120000_1.jpg', author: '张', type: MediaType.album, title: '', timestamp: '20260101120000', index: 1, ext: '.jpg'),
        _item(path: '/d/dy1_张_图集__20260101120001_2.jpg', author: '张', type: MediaType.album, title: '', timestamp: '20260101120001', index: 2, ext: '.jpg'),
      ];
      final r = Grouper.group(items);
      final g = r.authors['张']!;
      expect(g.albumSets.length, 1);
      expect(g.albumSets.values.first.length, 2);
    });
  });

  group('Grouper.group 待整理', () {
    test('未解析文件进 unparsed', () {
      final items = [
        _item(path: '/d/夏日街拍  街拍.mp4', author: ''),
        _item(path: '/d/dy1_张三_视频_a_20260101120000_1.mp4', author: '张三', timestamp: '20260101120000'),
      ];
      final r = Grouper.group(items);
      expect(r.unparsed.length, 1);
      expect(r.authors.length, 1);
    });
  });

  group('Grouper.group totalCount', () {
    test('视频+图集总数正确', () {
      final items = [
        _item(path: '/d/dy1_张_视频_a_20260101120000_1.mp4', author: '张', timestamp: '20260101120000'),
        _item(path: '/d/dy1_张_图集_景_20260101130000_1.jpg', author: '张', type: MediaType.album, title: '景', timestamp: '20260101130000', index: 1, ext: '.jpg'),
        _item(path: '/d/dy1_张_图集_景_20260101130005_2.jpg', author: '张', type: MediaType.album, title: '景', timestamp: '20260101130005', index: 2, ext: '.jpg'),
      ];
      final r = Grouper.group(items);
      final g = r.authors['张']!;
      expect(g.totalCount, 3);
    });
  });
}
