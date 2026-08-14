import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/filename_parser.dart';
import '../models/media_item.dart';
import '../services/file_service.dart';
import 'feed_page.dart';

/// 网格模式：平铺浏览 + 长按多选 + 批量操作。
class GridPage extends StatefulWidget {
  final List<MediaItem> items;
  final int startIndex;

  const GridPage({super.key, required this.items, required this.startIndex});

  @override
  State<GridPage> createState() => _GridPageState();
}

class _GridPageState extends State<GridPage> {
  late List<MediaItem> _items;
  final Set<int> _selected = {};
  bool _selectionMode = false;
  final Map<String, Uint8List?> _thumbCache = {};

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
  }

  Future<Uint8List?> _getThumb(String path) {
    if (_thumbCache.containsKey(path)) {
      return Future.value(_thumbCache[path]);
    }
    return FileService.getThumbnail(path).then((b) {
      _thumbCache[path] = b;
      return b;
    });
  }

  void _toggleSelect(int i) {
    setState(() {
      if (_selected.contains(i)) {
        _selected.remove(i);
      } else {
        _selected.add(i);
      }
      if (_selected.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelection(int i) {
    setState(() {
      _selectionMode = true;
      _selected.add(i);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  Future<void> _batchStar(int star) async {
    final indices = _selected.toList()..sort();
    for (final i in indices) {
      final item = _items[i];
      final newName = FilenameParser.buildStarredFilename(item.filename, star);
      final newPath = await FileService.renameFile(item.path, newName);
      if (newPath != null) {
        _items[i] = FilenameParser.parse(newPath);
      }
    }
    if (mounted) setState(() => _exitSelection());
  }

  Future<void> _batchDelete() async {
    final indices = _selected.toList()..sort((a, b) => b.compareTo(a));
    for (final i in indices) {
      await FileService.deleteToTrash(_items[i].path);
    }
    // 从后往前移除
    for (final i in indices) {
      _items.removeAt(i);
    }
    if (mounted) {
      setState(() => _exitSelection());
      if (_items.isEmpty) Navigator.of(context).pop();
    }
  }

  void _openFeed(int i) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeedPage(items: _items, startIndex: i),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_selectionMode ? '已选 ${_selected.length} 项' : '网格'),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelection,
              )
            : null,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: _items.length,
        itemBuilder: (context, i) {
          final item = _items[i];
          final selected = _selected.contains(i);
          return GestureDetector(
            onTap: () {
              if (_selectionMode) {
                _toggleSelect(i);
              } else {
                _openFeed(i);
              }
            },
            onLongPress: () {
              if (!_selectionMode) _enterSelection(i);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Thumbnail(item: item, loader: _getThumb),
                // 选中遮罩
                if (_selectionMode)
                  Container(
                    color: selected
                        ? Colors.blue.withOpacity(0.3)
                        : Colors.black.withOpacity(0.4),
                  ),
                // 选中勾选
                if (_selectionMode)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(
                      selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: selected ? Colors.blue : Colors.white70,
                    ),
                  ),
                // 星标角标
                if (item.isStarred)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Icon(
                      Icons.star,
                      size: 18,
                      color: Colors.amber,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: _selectionMode ? _buildSelectionBar() : null,
    );
  }

  Widget _buildSelectionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Colors.grey.shade900,
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _batchDelete,
            ),
            const SizedBox(width: 8),
            // 批量加星
            for (var s = 1; s <= 5; s++)
              IconButton(
                icon: Icon(
                  Icons.star,
                  size: 22,
                  color: Colors.amber.shade600,
                ),
                onPressed: () => _batchStar(s),
              ),
          ],
        ),
      ),
    );
  }
}

/// 缩略图：视频取首帧，图片直接用原图。
class _Thumbnail extends StatelessWidget {
  final MediaItem item;
  final Future<Uint8List?> Function(String) loader;

  const _Thumbnail({required this.item, required this.loader});

  @override
  Widget build(BuildContext context) {
    if (item.isImage) {
      return Image.file(
        File(item.path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Center(child: Icon(Icons.broken_image, color: Colors.white54)),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: loader(item.path),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            color: Colors.grey.shade900,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return Container(
            color: Colors.grey.shade900,
            child: const Center(
              child: Icon(Icons.videocam, color: Colors.white54),
            ),
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}
