import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/grouper.dart';
import '../models/media_item.dart';
import '../services/file_service.dart';
import '../services/media_store.dart';
import '../services/settings_service.dart';
import 'feed_page.dart';
import 'grid_page.dart';
import 'trash_page.dart';

/// 首页：目录管理、自动增量扫描、作者分组总览、已收藏/图集入口、待整理。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _dirController = TextEditingController();
  List<String> _dirs = [];
  bool _loading = false;
  String? _error;
  bool _permissionGranted = false;
  bool _didInitialScan = false;

  MediaStore get _store => MediaStore.instance;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadDirs();
    _store.addListener(_onStoreChange);
  }

  Future<void> _loadDirs() async {
    final dirs = await SettingsService.getScanDirs();
    if (mounted) setState(() => _dirs = dirs);
    // 目录加载后清理回收站中超过 30 天的文件
    for (final dir in dirs) {
      await FileService.cleanupTrash(dir, days: 30);
    }
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChange);
    _dirController.dispose();
    super.dispose();
  }

  void _onStoreChange() {
    if (mounted) setState(() {});
  }

  Future<void> _checkPermission() async {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    if (mounted) {
      setState(() => _permissionGranted = status.isGranted);
      // 权限就绪且还没扫过，自动扫描一次
      if (status.isGranted && !_didInitialScan) _scan();
    }
  }



  Future<void> _addDir() async {
    final dir = _dirController.text.trim();
    if (dir.isEmpty) return;
    if (!_dirs.contains(dir)) {
      final newDirs = [..._dirs, dir];
      await SettingsService.saveScanDirs(newDirs);
      if (mounted) setState(() => _dirs = newDirs);
    }
    _dirController.clear();
    _scan();
  }

  Future<void> _removeDir(String dir) async {
    final newDirs = _dirs.where((d) => d != dir).toList();
    await SettingsService.saveScanDirs(newDirs);
    if (mounted) setState(() => _dirs = newDirs);
  }

  Future<void> _scan() async {
    if (_dirs.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
      _didInitialScan = true;
    });
    try {
      await _store.rescan(_dirs);
    } catch (e) {
      if (mounted) setState(() => _error = '扫描失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openGrid([List<MediaItem>? items]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GridPage(items: items ?? _store.items),
      ),
    );
  }

  void _openFeed(List<MediaItem> items, int startIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FeedPage(items: items, startIndex: startIndex),
      ),
    );
  }

  void _openTrash() {
    if (_dirs.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TrashPage(dir: _dirs.first)),
    );
  }

  /// 待整理批量改名：选中多个 → 统一设作者名 → 批量重命名归位。
  Future<void> _batchRenameUnparsed(List<MediaItem> unparsed) async {
    final selected = <String>{}; // 选中文件的 path
    final authorController = TextEditingController();

    final result = await showDialog<(String, Set<String>)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('待整理批量改名'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: authorController,
                  decoration: const InputDecoration(
                    labelText: '作者名（必填，会写入 dy<N>_作者_视频_...）',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text('已选 ${selected.length} 个',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: 4),
                Flexible(
                  child: SizedBox(
                    height: 260,
                    child: ListView(
                      shrinkWrap: true,
                      children: unparsed.map((u) {
                        final checked = selected.contains(u.path);
                        return CheckboxListTile(
                          dense: true,
                          value: checked,
                          title: Text(u.filename,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onChanged: (v) => setDialogState(() {
                            if (v == true) {
                              selected.add(u.path);
                            } else {
                              selected.remove(u.path);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final author = authorController.text.trim();
                if (author.isEmpty || selected.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('请填写作者名并至少选一个文件')),
                  );
                  return;
                }
                Navigator.pop(ctx, (author: author, paths: selected.toSet()));
              },
              child: const Text('批量改名'),
            ),
          ],
        ),
      ),
    );

    if (result == null) return;
    var ok = 0, fail = 0;
    final now = DateTime.now();
    for (final (i, path) in result.$2.indexed) {
      final idx = _store.indexOf(path);
      if (idx < 0) {
        fail++;
        continue;
      }
      final f = File(path);
      final ext = f.existsSync() && f.uri.pathSegments.isNotEmpty
          ? f.path.split('.').last
          : 'mp4';
      // 14 位时间戳 YYYYMMDDHHMMSS + 序号（从当前秒递增）
      String two(int n) => n.toString().padLeft(2, '0');
      final ts =
          '${now.year}${two(now.month)}${two(now.day)}${two(now.hour)}${two(now.minute)}${two(now.second + i)}';
      final newName = 'dy1_${result.$1}_视频_重命名${i + 1}_${ts}_${i + 1}.$ext';
      if (await _store.rename(idx, newName)) {
        ok++;
      } else {
        fail++;
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fail == 0 ? '批量改名成功 $ok 个' : '成功 $ok 个，失败 $fail 个')),
      );
    }
  }

  Future<void> _renameUnparsed(MediaItem item) async {
    final controller = TextEditingController(text: item.filename);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入 dy<N>_作者_类型_标题_时间戳_序号.扩展名 格式',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == item.filename) return;
    final i = _store.indexOf(item.path);
    if (i < 0) return;
    final ok = await _store.rename(i, newName);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? '已重命名，已归位' : '重命名失败（检查文件名是否合法）')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouping = _store.grouping;
    final items = _store.items;
    return Scaffold(
      appBar: AppBar(
        title: const Text('VidBox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _dirs.isEmpty ? null : _openTrash,
          ),
          IconButton(
            icon: const Icon(Icons.grid_view),
            onPressed: items.isEmpty ? null : () => _openGrid(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_permissionGranted) _buildPermissionBanner(),
          _buildDirSection(),
          Expanded(child: _buildResult(grouping, items)),
        ],
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return MaterialBanner(
      content: const Text('需要"所有文件访问"权限才能扫描本地视频'),
      leading: const Icon(Icons.warning),
      actions: [
        TextButton(onPressed: _checkPermission, child: const Text('授权')),
      ],
    );
  }

  Widget _buildDirSection() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dirController,
                  decoration: const InputDecoration(
                    hintText: '添加扫描目录路径',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _addDir(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.add), onPressed: _addDir),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: _loading ? null : _scan,
                child: _loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('扫描'),
              ),
            ],
          ),
          if (_dirs.isNotEmpty)
            Wrap(
              spacing: 4,
              children: _dirs
                  .map((d) => Chip(
                        label: Text(d.split('/').last),
                        onDeleted: () => _removeDir(d),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildResult(GroupingResult? grouping, List<MediaItem> items) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (grouping == null) {
      return const Center(child: Text('授权后自动扫描，或添加目录后点击"扫描"'));
    }
    if (items.isEmpty) {
      return const Center(child: Text('目录下没有视频或图片'));
    }

    final authors = grouping.authors.values.toList()
      ..sort((a, b) => a.author.compareTo(b.author));

    final starredCount = items.where((it) => it.isStarred).length;
    final albumCount = items.where((it) => it.type == MediaType.album).length;

    return RefreshIndicator(
      onRefresh: _scan,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          // 快捷入口
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.star, color: Colors.amber, size: 18),
                  label: Text('已收藏 $starredCount'),
                  onPressed:
                      starredCount == 0 ? null : () => _openFeed(_store.starredItems(), 0),
                ),
                ActionChip(
                  avatar: const Icon(Icons.photo_library, size: 18),
                  label: Text('图集 $albumCount'),
                  onPressed:
                      albumCount == 0 ? null : () => _openFeed(_store.albumItems(), 0),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '共 ${items.length} 个文件 · ${authors.length} 个作者 · ${grouping.unparsed.length} 个待整理',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          ...authors.map((a) {
            final videos = [...a.videos];
            final albumImages = a.albumSets.values.expand((l) => l).toList();
            final all = [...videos, ...albumImages];
            final starred = all.where((it) => it.isStarred).length;
            final thumb = all.isNotEmpty ? all.last : null;
            return ListTile(
              leading: thumb != null
                  ? SizedBox(
                      width: 40,
                      height: 40,
                      child: _AuthorThumb(item: thumb),
                    )
                  : const Icon(Icons.person),
              title: Text(a.author),
              subtitle: Text(
                '${a.videos.length} 视频 · ${a.albumSets.length} 图集 · 收藏 $starred',
              ),
              onTap: () => _openFeed(all, 0),
            );
          }),
          if (grouping.unparsed.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '待整理（点击单个重命名归位）',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _batchRenameUnparsed(grouping.unparsed),
                    child: const Text('批量改名'),
                  ),
                ],
              ),
            ),
            ...grouping.unparsed.map((u) => ListTile(
                  leading: const Icon(Icons.inbox),
                  title: Text(u.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.edit, size: 18),
                  onTap: () => _renameUnparsed(u),
                )),
          ],
        ],
      ),
    );
  }
}

/// 作者缩略图（复用 IndexService 磁盘缓存）
class _AuthorThumb extends StatefulWidget {
  final MediaItem item;
  const _AuthorThumb({required this.item});

  @override
  State<_AuthorThumb> createState() => _AuthorThumbState();
}

class _AuthorThumbState extends State<_AuthorThumb> {
  @override
  Widget build(BuildContext context) {
    if (widget.item.isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(widget.item.path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.person, color: Colors.white54),
        ),
      );
    }
    return FutureBuilder(
      future: MediaStore.instance.thumbFor(widget.item.path),
      builder: (context, snap) {
        final bytes = snap.data;
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: bytes == null
              ? const Icon(Icons.person, color: Colors.white54)
              : Image.memory(bytes, fit: BoxFit.cover),
        );
      },
    );
  }
}
