import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/media_item.dart';
import '../services/media_store.dart';
import 'move_dialog.dart';

/// 全屏流浏览：上下滑切换视频/图集，双击星标，底部操作条。
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

  MediaStore get _store => MediaStore.instance;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex;
    _items = List.of(widget.items);
    _controller = PageController(initialPage: widget.startIndex);
    _markCurrentSeen();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _markCurrentSeen() {
    if (_currentIndex < _items.length) {
      _store.markSeen(_items[_currentIndex].path);
    }
  }

  Future<void> _toggleStar() async {
    final item = _items[_currentIndex];
    final idx = _store.indexOf(item.path);
    if (idx < 0) return;
    final newStar = item.isStarred ? 1 : 5;
    final ok = await _store.setStar(idx, newStar);
    if (ok && mounted) {
      setState(() {
        _items[_currentIndex] = _store.items[idx];
      });
    }
  }

  Future<void> _setStar(int star) async {
    final item = _items[_currentIndex];
    final idx = _store.indexOf(item.path);
    if (idx < 0) return;
    final ok = await _store.setStar(idx, star);
    if (ok && mounted) {
      setState(() {
        _items[_currentIndex] = _store.items[idx];
      });
    }
  }

  Future<void> _delete() async {
    final item = _items[_currentIndex];
    final idx = _store.indexOf(item.path);
    if (idx < 0) return;
    final ok = await _store.delete(idx);
    if (ok && mounted) {
      setState(() {
        _items.removeAt(_currentIndex);
        if (_items.isEmpty) {
          Navigator.of(context).pop();
        } else if (_currentIndex >= _items.length) {
          _currentIndex = _items.length - 1;
        }
      });
    }
  }

  Future<void> _move() async {
    final item = _items[_currentIndex];
    final parentDir = dirnameOf(item.path);
    final target = await showMoveDialog(context, parentDir);
    if (target == null) return;
    final idx = _store.indexOf(item.path);
    if (idx < 0) return;
    final ok = await _store.move(idx, '$parentDir/$target');
    if (ok && mounted) {
      setState(() {
        _items.removeAt(_currentIndex);
        if (_items.isEmpty) {
          Navigator.of(context).pop();
        } else if (_currentIndex >= _items.length) {
          _currentIndex = _items.length - 1;
        }
      });
    }
  }

  Future<void> _rename() async {
    final item = _items[_currentIndex];
    final controller = TextEditingController(text: item.filename);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '新文件名（含扩展名）',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == item.filename) return;
    final idx = _store.indexOf(item.path);
    if (idx < 0) return;
    final ok = await _store.rename(idx, newName);
    if (mounted) {
      if (ok) {
        setState(() => _items[_currentIndex] = _store.items[idx]);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('重命名失败（文件名可能不合法）')),
        );
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
            onPageChanged: (i) {
              setState(() => _currentIndex = i);
              _markCurrentSeen();
            },
            itemBuilder: (context, i) => _FeedItem(
              item: _items[i],
              isActive: i == _currentIndex,
              onDoubleTap: _toggleStar,
            ),
          ),
          // 位置指示
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Text(
              '${_currentIndex + 1} / ${_items.length}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
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
              // 星标切换
              IconButton(
                onPressed: _toggleStar,
                icon: Icon(
                  item.isStarred ? Icons.star : Icons.star_border,
                  color: item.isStarred ? Colors.amber : Colors.white,
                ),
              ),
              // 星级 1~5
              for (var s = 1; s <= 5; s++)
                GestureDetector(
                  onTap: () => _setStar(s),
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
              IconButton(
                onPressed: _rename,
                icon: const Icon(Icons.edit_outlined, color: Colors.white),
                tooltip: '重命名',
              ),
              IconButton(
                onPressed: _move,
                icon: const Icon(Icons.drive_file_move, color: Colors.white),
              ),
              IconButton(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline, color: Colors.white),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单个 feed 项：视频循环播放，图片静态展示；支持单击暂停/缩放。
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
  bool _playing = true;
  bool _zoomContain = true; // true=适应屏幕, false=填满

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
      if (widget.isActive) {
        controller.play();
        _playing = true;
      }
    }
  }

  @override
  void didUpdateWidget(covariant _FeedItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final c = _videoController;
    if (c == null || !_inited) return;
    if (widget.isActive && !oldWidget.isActive) {
      c.play();
      _playing = true;
    } else if (!widget.isActive && oldWidget.isActive) {
      c.pause();
      _playing = false;
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  void _togglePause() {
    final c = _videoController;
    if (widget.item.isImage) {
      setState(() => _zoomContain = !_zoomContain);
      return;
    }
    if (c == null || !_inited) return;
    setState(() {
      if (_playing) {
        c.pause();
        _playing = false;
      } else {
        c.play();
        _playing = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.isImage) {
      return GestureDetector(
        onDoubleTap: widget.onDoubleTap,
        onTap: _togglePause,
        child: Center(
          child: Image.file(
            File(widget.item.path),
            fit: _zoomContain ? BoxFit.contain : BoxFit.cover,
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
      onTap: _togglePause,
      child: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: VideoPlayer(_videoController!),
            ),
          ),
          if (!_playing)
            const Center(child: Icon(Icons.play_circle_outline, color: Colors.white70, size: 64)),
        ],
      ),
    );
  }
}
