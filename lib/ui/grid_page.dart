import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/filename_parser.dart';
import '../models/media_item.dart';
import '../services/file_service.dart';
import 'feed_page.dart';
import 'move_dialog.dart';

/// 网格模式：按作者分组折叠 + 长按多选 + 批量操作。
class GridPage extends StatefulWidget {
  final List<MediaItem> items;

  const GridPage({super.key, required this.items});

  @override
  State<GridPage> createState() => _GridPageState();
}

class _GridPageState extends State<GridPage> {
  late List<MediaItem> _items;
  late Map<String, List<MediaItem>> _groups;
  final Set<String> _selectedPaths = {};
  final Set<String> _collapsed = {};
  bool _selectionMode = false;
  final Map<String, Uint8List?> _thumbCache = {};

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
    _groups = _groupByAuthor(_items);
  }

  Map<String, List<MediaItem>> _groupByAuthor(List<MediaItem> items) {
    final map = <String, List<MediaItem>>{};
    for (final item in items) {
      final key = item.isParsed ? item.author : '待整理';
      map.putIfAbsent(key, () => []).add(item);
    }
    // 组内排序：待整理放最后，其余按时间戳
    map.forEach((key, list) {
      list.sort((a, b) => (a.timestamp ?? '').compareTo(b.timestamp ?? ''));
    });
    return map;
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

  void _toggleSelect(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
      } else {
        _selectedPaths.add(path);
      }
      if (_selectedPaths.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelection(String path) {
    setState(() {
      _selectionMode = true;
      _selectedPaths.add(path);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
    });
  }

  void _toggleCollapse(String key) {
    setState(() {
      if (_collapsed.contains(key)) {
        _collapsed.remove(key);
      } else {
        _collapsed.add(key);
      }
    });
  }

  MediaItem? _findByPath(String path) {
    for (final it in _items) {
      if (it.path == path) return it;
    }
    return null;
  }

  Future<void> _batchStar(int star) async {
    final paths = _selectedPaths.toList();
    for (final p in paths) {
      final item = _findByPath(p);
      if (item == null) continue;
      final newName = FilenameParser.buildStarredFilename(item.filename, star);
      final newPath = await FileService.renameFile(p, newName);
      if (newPath != null) {
        final idx = _items.indexWhere((it) => it.path == p);
        if (idx >= 0) _items[idx] = FilenameParser.parse(newPath);
      }
    }
    if (mounted) {
      setState(() {
        _groups = _groupByAuthor(_items);
        _selectedPaths.clear();
        _selectionMode = false;
      });
    }
  }

  Future<void> _batchDelete() async {
    for (final p in _selectedPaths.toList()) {
      await FileService.deleteToTrash(p);
    }
    if (mounted) {
      setState(() {
        _items.removeWhere((it) => _selectedPaths.contains(it.path));
        _groups = _groupByAuthor(_items);
        _selectedPaths.clear();
        _selectionMode = false;
      });
      if (_items.isEmpty) Navigator.of(context).pop();
    }
  }

  Future<void> _batchMove() async {
    final first = _selectedPaths.first;
    final parentDir = dirnameOf(first);
    final target = await showMoveDialog(context, parentDir);
    if (target == null) return;
    for (final p in _selectedPaths.toList()) {
      await FileService.moveFile(p, '$parentDir/$target');
    }
    if (mounted) {
      setState(() {
        _items.removeWhere((it) => _selectedPaths.contains(it.path));
        _groups = _groupByAuthor(_items);
        _selectedPaths.clear();
        _selectionMode = false;
      });
      if (_items.isEmpty) Navigator.of(context).pop();
    }
  }

  void _openFeed(List<MediaItem> groupItems, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeedPage(items: groupItems, startIndex: index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_selectionMode ? '已选 ${_selectedPaths.length} 项' : '网格'),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelection,
              )
            : null,
      ),
      body: _groups.isEmpty
          ? const Center(child: Text('没有内容'))
          : ListView(
              children: _buildGroupSections(),
            ),
      bottomNavigationBar: _selectionMode ? _buildSelectionBar() : null,
    );
  }

  List<Widget> _buildGroupSections() {
    final widgets = <Widget>[];
    // 作者组按名称排序，待整理放最后
    final keys = _groups.keys.toList()
      ..sort((a, b) {
        if (a == '待整理') return 1;
        if (b == '待整理') return -1;
        return a.compareTo(b);
      });

    for (final key in keys) {
      final list = _groups[key]!;
      final isCollapsed = _collapsed.contains(key);
      widgets.add(_buildHeader(key, list.length, isCollapsed));
      if (!isCollapsed) {
        widgets.add(_buildGrid(list));
      }
    }
    return widgets;
  }

  Widget _buildHeader(String key, int count, bool isCollapsed) {
    return InkWell(
      onTap: () => _toggleCollapse(key),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Icon(
              isCollapsed ? Icons.expand_more : Icons.expand_less,
              size: 20,
              color: Colors.grey,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                key,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(List<MediaItem> list) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) {
        final item = list[i];
        final selected = _selectedPaths.contains(item.path);
        return GestureDetector(
          onTap: () {
            if (_selectionMode) {
              _toggleSelect(item.path);
            } else {
              _openFeed(list, i);
            }
          },
          onLongPress: () {
            if (!_selectionMode) _enterSelection(item.path);
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Thumbnail(item: item, loader: _getThumb),
              if (_selectionMode)
                Container(
                  color: selected
                      ? Colors.blue.withOpacity(0.3)
                      : Colors.black.withOpacity(0.4),
                ),
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
              if (item.isStarred)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Icon(Icons.star, size: 18, color: Colors.amber),
                ),
            ],
          ),
        );
      },
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
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.drive_file_move, color: Colors.white),
              onPressed: _batchMove,
            ),
            const SizedBox(width: 8),
            for (var s = 1; s <= 5; s++)
              IconButton(
                icon: Icon(Icons.star, size: 22, color: Colors.amber.shade600),
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
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, color: Colors.white54),
        ),
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
