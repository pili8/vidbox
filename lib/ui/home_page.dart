import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/filename_parser.dart';
import '../core/grouper.dart';
import '../models/media_item.dart';
import '../services/file_service.dart';
import '../services/index_service.dart';
import '../services/settings_service.dart';
import 'feed_page.dart';
import 'grid_page.dart';
import 'trash_page.dart';

/// 首页：目录管理、扫描、分组展示、待整理、网格/回收站入口。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _dirController = TextEditingController();
  List<String> _dirs = [];
  List<MediaItem> _items = [];
  GroupingResult? _grouping;
  bool _loading = false;
  String? _error;
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadDirs();
  }

  @override
  void dispose() {
    _dirController.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    if (mounted) setState(() => _permissionGranted = status.isGranted);
  }

  Future<void> _loadDirs() async {
    final dirs = await SettingsService.getScanDirs();
    if (mounted) setState(() => _dirs = dirs);
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
    });

    try {
      // 增量索引：未变化的文件直接读缓存，只重新解析变化的文件
      final items = await IndexService.scanAndIndex(_dirs);
      final grouping = Grouper.group(items);
      if (mounted) {
        setState(() {
          _items = items;
          _grouping = grouping;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '扫描失败: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openGrid() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GridPage(items: _items)),
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

  /// 对待整理文件改名，重命名后自动重新解析归位。
  Future<void> _renameUnparsed(MediaItem item) async {
    final controller = TextEditingController(text: item.filename);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: '输入 dy1_作者_类型_标题_时间戳_序号.扩展名 格式',
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
    final newPath = await FileService.renameFile(item.path, newName);
    if (newPath != null) {
      await IndexService.updatePath(item.path, newPath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已重命名，重新扫描后归位')),
        );
        _scan();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: _items.isEmpty ? null : _openGrid,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_permissionGranted) _buildPermissionBanner(),
          _buildDirSection(),
          Expanded(child: _buildResult()),
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
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: _addDir,
              ),
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

  Widget _buildResult() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final g = _grouping;
    if (g == null) {
      return const Center(child: Text('添加目录后点击"扫描"'));
    }
    if (_items.isEmpty) {
      return const Center(child: Text('目录下没有视频或图片'));
    }

    final authors = g.authors.values.toList()
      ..sort((a, b) => a.author.compareTo(b.author));

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '共 ${_items.length} 个文件 · ${authors.length} 个作者 · ${g.unparsed.length} 个待整理',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        ...authors.map((a) {
          final videos = [...a.videos];
          final albumImages = a.albumSets.values.expand((l) => l).toList();
          final all = [...videos, ...albumImages];
          return ListTile(
            leading: const Icon(Icons.person),
            title: Text(a.author),
            subtitle: Text(
              '视频 ${a.videos.length} · 图集 ${a.albumSets.length} 组 · 共 ${a.totalCount} 项',
            ),
            onTap: () => _openFeed(all, 0),
          );
        }),
        if (g.unparsed.isNotEmpty) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              '待整理（点击可重命名归位）',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          ...g.unparsed.map((u) => ListTile(
                leading: const Icon(Icons.inbox),
                title: Text(u.filename, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.edit, size: 18),
                onTap: () => _renameUnparsed(u),
              )),
        ],
      ],
    );
  }
}
