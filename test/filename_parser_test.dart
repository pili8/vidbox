import 'package:flutter_test/flutter_test.dart';
import 'package:vidbox/core/filename_parser.dart';
import 'package:vidbox/models/media_item.dart';

void main() {
  group('FilenameParser.parse 标准命名', () {
    test('完整标准命名', () {
      final item = FilenameParser.parse(
          '/sdcard/Download/dy1_全球超模_视频_秀场花絮潮汕服博会@申雪儿_20260812000107_1.mp4');
      expect(item.isParsed, isTrue);
      expect(item.star, 1);
      expect(item.author, '全球超模');
      expect(item.type, MediaType.video);
      expect(item.title, '秀场花絮潮汕服博会@申雪儿');
      expect(item.timestamp, '20260812000107');
      expect(item.index, 1);
      expect(item.ext, '.mp4');
    });

    test('星级数字提取 dy5', () {
      final item = FilenameParser.parse(
          '/sdcard/Download/dy5_小研妍_视频_#穿搭_20260808073925_1.mp4');
      expect(item.star, 5);
      expect(item.author, '小研妍');
    });

    test('图集类型与序号', () {
      final item = FilenameParser.parse(
          '/sdcard/Download/dy1_今天也要自律呀_图集_晚酌时刻_20260807134343_2.webp');
      expect(item.type, MediaType.album);
      expect(item.index, 2);
      expect(item.isImage, isTrue);
    });

    test('空标题（连续下划线）', () {
      final item = FilenameParser.parse(
          '/sdcard/Download/dy1_是香墨呀_视频__20260813125122_1.mp4');
      expect(item.isParsed, isTrue);
      expect(item.author, '是香墨呀');
      expect(item.title, '');
      expect(item.type, MediaType.video);
    });

    test('作者名含下划线', () {
      final item = FilenameParser.parse(
          '/sdcard/Download/dy1_张三_美食博主_视频_标题_20260812000107_1.mp4');
      expect(item.isParsed, isTrue);
      expect(item.author, '张三_美食博主');
      expect(item.type, MediaType.video);
      expect(item.title, '标题');
    });

    test('作者名含 emoji', () {
      final item = FilenameParser.parse(
          '/sdcard/Download/dy1_美女推荐官📷_视频_#穿搭_20260807142740_1.mp4');
      expect(item.author, '美女推荐官📷');
    });

    test('旧版 [★n] 前缀被防御性剥离且不覆盖 dy 星级', () {
      final item = FilenameParser.parse(
          '/sdcard/Download/[★3]dy1_全球超模_视频_标题_20260812000107_1.mp4');
      expect(item.isParsed, isTrue);
      // 星级来源是 dy 数字，而非 [★3]
      expect(item.star, 1);
      expect(item.author, '全球超模');
    });
  });

  group('FilenameParser.parse 待整理', () {
    test('裸标题（无 dy 结构）', () {
      final item = FilenameParser.parse(
          '/sdcard/Download/夏日街拍  街拍穿搭  黄色战裙(1).mp4');
      expect(item.isParsed, isFalse);
      expect(item.type, MediaType.unknown);
      expect(item.star, 0);
    });

    test('纯数字命名 VID_xxx', () {
      final item = FilenameParser.parse('/sdcard/Download/VID_20240101_120000.mp4');
      expect(item.isParsed, isFalse);
    });

    test('图片裸文件', () {
      final item = FilenameParser.parse('/sdcard/Download/随手拍.jpg');
      expect(item.isParsed, isFalse);
      expect(item.isImage, isTrue);
    });
  });

  group('FilenameParser.buildStarredFilename', () {
    test('从 dy1 改到 dy5', () {
      final name = 'dy1_全球超模_视频_标题_20260812000107_1.mp4';
      expect(FilenameParser.buildStarredFilename(name, 5),
          'dy5_全球超模_视频_标题_20260812000107_1.mp4');
    });

    test('改回基线 dy1', () {
      final name = 'dy4_全球超模_视频_标题_20260812000107_1.mp4';
      expect(FilenameParser.buildStarredFilename(name, 1),
          'dy1_全球超模_视频_标题_20260812000107_1.mp4');
    });

    test('星级越界 clamp 到 1~5', () {
      final name = 'dy1_作者_视频_标题_20260812000107_1.mp4';
      expect(FilenameParser.buildStarredFilename(name, 0),
          'dy1_作者_视频_标题_20260812000107_1.mp4');
      expect(FilenameParser.buildStarredFilename(name, 9),
          'dy5_作者_视频_标题_20260812000107_1.mp4');
    });

    test('无 dy 前缀的文件原样返回', () {
      final name = '夏日街拍  街拍穿搭.mp4';
      expect(FilenameParser.buildStarredFilename(name, 5), name);
    });

    test('其余部分一字不动', () {
      final name = 'dy1_作者_图集_标题_20260812000107_3.webp';
      final out = FilenameParser.buildStarredFilename(name, 2);
      expect(out, 'dy2_作者_图集_标题_20260812000107_3.webp');
    });
  });
}
