import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/index_service.dart';
import '../services/media_store.dart';
import 'feed_page.dart';
import 'move_dialog.dart';

enum _SortMode { newest, oldest, starHigh }

/// 网格模式：按作者分组折叠 + 筛选/搜索/排序 + 长按多选 + 批量操作。
class GridPage extends StatefulWidget {
  final List<MediaItem> items;

  const GridPage({super.key, required this.items});

  @override
  State<GridPage> createState() => _GridPageState();
}

class _GridPageState extends State<GridPage> {
  late List<MediaItem> _baseItems;
  List<MediaItem> _filtered = [];
  late Map<String, List<MediaItem>> _groups;

  final Set<String> _selectedPaths = {};
  final Set<String> _collapsed = {};
  bool _selectionMode = false;
  final Map<String, Uint8List?> _thumbCache = {};

  // 筛选与排序
  String _query = '';
  String _filter = '全部'; // 全部 / 已收藏 / 待整理 / 图集
  _SortMode _sort = _SortMode.newest;

  MediaStore get _store => MediaStore.instance;

  @override
  void initState() {
    super.initState();
    _baseItems = List.of(widget.items);
    _store.addListener(_onStoreChange);
    _recompute();
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChange);
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() => _recompute());
  }

  void _recompute() {
    var list = List.of(_baseItems);
    // 筛选
    switch (_filter) {
      case '已收藏':
        list = list.where((it) => it.isStarred).toList();
        break;
      case '待整理':
        list = list.where((it) => !it.isParsed).toList();
        break;
      case '图集':
        list = list.where((it) => it.type == MediaType.album).toList();
        break;
    }
    // 搜索（匹配作者或标题）
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((it) =>
              it.author.toLowerCase().contains(q) ||
              it.title.toLowerCase().contains(q))
          .toList();
    }
    // 排序
    switch (_sort) {
      case _SortMode.newest:
        list.sort((a, b) => (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
        break;
      case _SortMode.oldest:
        list.sort((a, b) => (a.timestamp ?? '').compareTo(b.timestamp ?? ''));
        break;
      case _SortMode.starHigh:
        list.sort((a, b) => b.star.compareTo(a.star));
        break;
    }
    _filtered = list;
    _groups = _groupByAuthor(list);
  }

  Map<String, List<MediaItem>> _groupByAuthor(List<MediaItem> items) {
    final map = <String, List<MediaItem>>{};
    for (final item in items) {
      final key = item.isParsed ? item.author : '待整理';
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  Future<Uint8List?> _getThumb(String path) {
    if (_thumbCache.containsKey(path)) {
      return Future.value(_thumbCache[path]);
    }
    return IndexService.getThumbnail(path).then((b) {
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

  void _selectGroup(String key) {
    final group = _groups[key] ?? [];
    setState(() {
      _selectionMode = true;
      for (final it in group) {
        _selectedPaths.add(it.path);
      }
    });
  }

  Future<void> _batchStar(int star) async {
    final (ok, fail) = await _store.batchStar(_selectedPaths.toList(), star);
    _finishBatch('已标 $star 星', ok, fail);
  }

  Future<void> _batchDelete() async {
    final (ok, fail) = await _store.batchDelete(_selectedPaths.toList());
    if (_store.items.isEmpty && mounted) {
      Navigator.of(context).pop();
      return;
    }
    _finishBatch('已删除', ok, fail);
  }

  Future<void> _batchMove() async {
    final paths = _selectedPaths.toList();
    final first = paths.first;
    final parentDir = dirnameOf(first);
    final target = await showMoveDialog(context, parentDir);
    if (target == null) return;
    final (ok, fail) = await _store.batchMove(paths, '$parentDir/$target');
    _finishBatch('已移动', ok, fail);
  }

  void _finishBatch(String action, int ok, int fail) {
    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedPaths.clear();
      _recompute();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(fail == 0 ? '$action $ok 个' : '$action 成功 $ok 个，失败 $fail 个')),
    );
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
        actions: [
          if (!_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.sort),
              onPressed: _showSortMenu,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _filtered.isEmpty
                ? const Center(child: Text('没有匹配的内容'))
                : ListView(children: _buildGroupSections()),
          ),
        ],
      ),
      bottomNavigationBar: _selectionMode ? _buildSelectionBar() : null,
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              onChanged: (v) => setState(() {
                _query = v;
                _recompute();
              }),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: '搜索作者或标题',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
                isDense: true,
                prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                filled: true,
                fillColor: Colors.grey.shade900,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: _filter,
            dropdownColor: Colors.grey.shade900,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            underline: const SizedBox.shrink(),
            items: const ['全部', '已收藏', '待整理', '图集']
                .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                .toList(),
            onChanged: (v) => setState(() {
              _filter = v!;
              _recompute();
            }),
          ),
        ],
      ),
    );
  }

  void _showSortMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.new_releases, color: Colors.white),
              title: const Text('最新在前', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _sort = _SortMode.newest;
                  _recompute();
                });
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.history, color: Colors.white),
              title: const Text('最旧在前', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _sort = _SortMode.oldest;
                  _recompute();
                });
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.star, color: Colors.amber),
              title: const Text('星级最高', style: TextStyle(color: Colors.white)),
              onTap: () {
                setState(() {
                  _sort = _SortMode.starHigh;
                  _recompute();
                });
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGroupSections() {
    final widgets = <Widget>[];
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
      if (!isCollapsed) widgets.add(_buildGrid(list));
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
            Text('$count', style: const TextStyle(color: Colors.grey)),
            IconButton(
              icon: const Icon(Icons.select_all, size: 18, color: Colors.grey),
              onPressed: () => _selectGroup(key),
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
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: selected ? Colors.blue : Colors.white70,
                  ),
                ),
              if (item.isStarred)
                const Positioned(
                  top: 4,
                  left: 4,
                  child: Icon(Icons.star, size: 18, color: Colors.amber),
                ),
              if (item.isImage)
                const Positioned(
                  bottom: 4,
                  right: 4,
                  child: Icon(Icons.photo, size: 14, color: Colors.white70),
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

/// 缩略图：视频取首帧并显示时长角标，图片直接用原图。
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
        return bytes == null
            ? Container(
                color: Colors.grey.shade900,
                child: const Center(
                  child: Icon(Icons.videocam, color: Colors.white54),
                ),
              )
            : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}
