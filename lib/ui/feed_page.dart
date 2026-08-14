import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/filename_parser.dart';
import '../models/media_item.dart';
import '../services/file_service.dart';
import '../services/index_service.dart';
import 'move_dialog.dart';

/// 全屏流浏览：上下滑切换，双击星标，底部操作条。
class FeedPage extends StatefulWidget {
  final List<MediaItem> items;
  final int startIndex;

  const FeedPage({super.key, required this.items, required this.startIndex});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  late final PageController _controller;
  late List<MediaItem> _items;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex;
    _items = List.of(widget.items);
    _controller = PageController(initialPage: widget.startIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleStar(int i) async {
    final item = _items[i];
    // 未收藏（dy1）→ 收藏（dy5）；已收藏 → 回到 dy1
    final newStar = item.isStarred ? 1 : 5;
    final newName = FilenameParser.buildStarredFilename(item.filename, newStar);
    final newPath = await FileService.renameFile(item.path, newName);
    if (newPath != null) {
      await IndexService.updatePath(item.path, newPath);
      if (mounted) {
        setState(() => _items[i] = FilenameParser.parse(newPath));
      }
    }
  }

  Future<void> _setStar(int i, int star) async {
    final item = _items[i];
    final newName = FilenameParser.buildStarredFilename(item.filename, star);
    final newPath = await FileService.renameFile(item.path, newName);
    if (newPath != null) {
      await IndexService.updatePath(item.path, newPath);
      if (mounted) {
        setState(() => _items[i] = FilenameParser.parse(newPath));
      }
    }
  }

  Future<void> _delete(int i) async {
    final ok = await FileService.deleteToTrash(_items[i].path);
    if (ok) {
      await IndexService.updatePath(_items[i].path, '');
      await IndexService.removeThumbnail(_items[i].path);
      if (mounted) {
        setState(() {
          _items.removeAt(i);
          if (_items.isEmpty) Navigator.of(context).pop();
        });
      }
    }
  }

  Future<void> _move(int i) async {
    final item = _items[i];
    final parentDir = dirnameOf(item.path);
    final target = await showMoveDialog(context, parentDir);
    if (target == null) return;
    final ok = await FileService.moveFile(item.path, '$parentDir/$target');
    if (ok) {
      await IndexService.updatePath(item.path, '$parentDir/$target/${item.filename}');
      if (mounted) {
        setState(() {
          _items.removeAt(i);
          if (_items.isEmpty) Navigator.of(context).pop();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) {
      return const Scaffold(body: Center(child: Text('没有内容')));
    }

    final item = _items[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            scrollDirection: Axis.vertical,
            itemCount: _items.length,
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemBuilder: (context, i) => _FeedItem(
              item: _items[i],
              isActive: i == _currentIndex,
              onDoubleTap: () => _toggleStar(i),
            ),
          ),
          // 底部信息 + 操作条
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomBar(item),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(MediaItem item) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.isParsed) ...[
            Text(
              item.author,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (item.title.isNotEmpty)
              Text(
                item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
          ] else
            Text(
              item.filename,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              // 星标按钮
              IconButton(
                onPressed: () => _toggleStar(_currentIndex),
                icon: Icon(
                  item.isStarred ? Icons.star : Icons.star_border,
                  color: item.isStarred ? Colors.amber : Colors.white,
                ),
              ),
              // 星级选择
              for (var s = 1; s <= 5; s++)
                GestureDetector(
                  onTap: () => _setStar(_currentIndex, s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(
                      s <= item.star ? Icons.star : Icons.star_border,
                      size: 18,
                      color: s <= item.star ? Colors.amber : Colors.white54,
                    ),
                  ),
                ),
              const Spacer(),
              // 移动
              IconButton(
                onPressed: () => _move(_currentIndex),
                icon: const Icon(Icons.drive_file_move, color: Colors.white),
              ),
              // 删除
              IconButton(
                onPressed: () => _delete(_currentIndex),
                icon: const Icon(Icons.delete_outline, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单个 feed 项：视频自动循环播放，图片静态展示。
class _FeedItem extends StatefulWidget {
  final MediaItem item;
  final bool isActive;
  final VoidCallback onDoubleTap;

  const _FeedItem({
    required this.item,
    required this.isActive,
    required this.onDoubleTap,
  });

  @override
  State<_FeedItem> createState() => _FeedItemState();
}

class _FeedItemState extends State<_FeedItem> {
  VideoPlayerController? _videoController;
  bool _inited = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.item.isImage) return;
    final controller = VideoPlayerController.file(File(widget.item.path));
    _videoController = controller;
    await controller.initialize();
    await controller.setLooping(true);
    await controller.setVolume(1.0);
    if (mounted) {
      setState(() => _inited = true);
      if (widget.isActive) controller.play();
    }
  }

  @override
  void didUpdateWidget(covariant _FeedItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final c = _videoController;
    if (c == null || !_inited) return;
    if (widget.isActive && !oldWidget.isActive) {
      c.play();
    } else if (!widget.isActive && oldWidget.isActive) {
      c.pause();
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.isImage) {
      return GestureDetector(
        onDoubleTap: widget.onDoubleTap,
        child: Center(
          child: Image.file(
            File(widget.item.path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.white54, size: 48),
          ),
        ),
      );
    }

    if (!_inited) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onDoubleTap: widget.onDoubleTap,
      child: Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      ),
    );
  }
}
