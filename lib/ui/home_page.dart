import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/filename_parser.dart';
import '../core/grouper.dart';
import '../models/media_item.dart';
import '../services/file_service.dart';
import 'feed_page.dart';
import 'grid_page.dart';

/// 首页：申请权限、选择扫描目录、展示分组结果。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _dirController = TextEditingController(
    text: '/storage/emulated/0/Download',
  );

  List<MediaItem> _items = [];
  GroupingResult? _grouping;
  bool _loading = false;
  String? _error;
  bool _permissionGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
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
    if (mounted) {
      setState(() => _permissionGranted = status.isGranted);
    }
  }

  Future<void> _scan() async {
    final dir = _dirController.text.trim();
    if (dir.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final paths = await FileService.listMediaFiles(dir);
      final items = paths.map(FilenameParser.parse).toList();
      final grouping = Grouper.group(items);
      setState(() {
        _items = items;
        _grouping = grouping;
      });
    } catch (e) {
      setState(() => _error = '扫描失败: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _openGrid() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GridPage(items: _items, startIndex: 0),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VidBox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.grid_view),
            onPressed: _items.isEmpty ? null : _openGrid,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildScanBar(),
          if (!_permissionGranted)
            _buildPermissionBanner(),
          Expanded(child: _buildResult()),
        ],
      ),
    );
  }

  Widget _buildScanBar() {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _dirController,
              decoration: const InputDecoration(
                hintText: '扫描目录路径',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
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
    );
  }

  Widget _buildPermissionBanner() {
    return MaterialBanner(
      content: const Text('需要"所有文件访问"权限才能扫描本地视频'),
      leading: const Icon(Icons.warning),
      actions: [
        TextButton(
          onPressed: _checkPermission,
          child: const Text('授权'),
        ),
      ],
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
      return const Center(child: Text('输入目录后点击"扫描"'));
    }
    if (_items.isEmpty) {
      return const Center(child: Text('该目录下没有视频或图片'));
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
          // 该作者的所有视频 + 图集图片，用于进入全屏流
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
          ListTile(
            leading: const Icon(Icons.inbox),
            title: const Text('待整理'),
            subtitle: Text('${g.unparsed.length} 个未识别文件'),
            onTap: () => _openFeed(g.unparsed, 0),
          ),
        ],
      ],
    );
  }
}
