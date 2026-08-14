import 'dart:io';

import 'package:flutter/material.dart';

import '../services/file_service.dart';

/// 回收站：查看 .trash 内容（含删除时间）、恢复、清空、自动清理过期。
class TrashPage extends StatefulWidget {
  final String dir;

  const TrashPage({super.key, required this.dir});

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final paths = await FileService.listTrash(widget.dir);
    final raw = <Map<String, dynamic>>[];
    for (final p in paths) {
      final f = File(p);
      raw.add({
        'path': p,
        'mtime': f.existsSync() ? f.lastModifiedSync().millisecondsSinceEpoch : 0,
      });
    }
    if (mounted) {
      setState(() {
        _files = raw;
        _loading = false;
      });
    }
  }

  String _fmtTime(int mtime) {
    final dt = DateTime.fromMillisecondsSinceEpoch(mtime);
    final now = DateTime.now();
    final d = now.difference(dt);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }

  Future<void> _restore(String path) async {
    final ok = await FileService.restoreFromTrash(path);
    if (mounted) {
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('恢复失败（原目录可能有同名文件）')),
        );
      }
      _load();
    }
  }

  Future<void> _empty() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空回收站'),
        content: Text('将永久删除 ${_files.length} 个文件，不可恢复。确定？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FileService.emptyTrash(widget.dir);
      if (mounted) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('回收站'),
        actions: [
          if (_files.isNotEmpty)
            TextButton(
              onPressed: _empty,
              child: const Text('清空', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(child: Text('回收站为空'))
              : ListView.builder(
                  itemCount: _files.length,
                  itemBuilder: (context, i) {
                    final f = _files[i];
                    final path = f['path'] as String;
                    final mtime = (f['mtime'] as int?) ?? 0;
                    final name = path.split('/').last;
                    return ListTile(
                      leading: const Icon(Icons.restore),
                      title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: mtime > 0 ? Text('删除于 ${_fmtTime(mtime)}') : null,
                      onTap: () => _restore(path),
                    );
                  },
                ),
    );
  }
}
