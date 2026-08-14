import 'package:flutter/material.dart';

import '../services/file_service.dart';

/// 获取路径的父目录（不含末尾文件名）。
String dirnameOf(String path) {
  final normalized = path.replaceAll('\\', '/');
  final idx = normalized.lastIndexOf('/');
  return idx <= 0 ? '/' : normalized.substring(0, idx);
}

/// 弹出选择移动目标子目录的对话框，返回选中的子目录名（或新建名称）。
///
/// `rootDir` 为当前文件所在目录，展示其下已有子目录作为分类目标，
/// 也允许输入新名称新建分类文件夹。
Future<String?> showMoveDialog(BuildContext context, String rootDir) async {
  final subDirs = await FileService.listSubDirs(rootDir);
  if (!context.mounted) return null;

  final controller = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('移动到分类文件夹'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subDirs.isNotEmpty) ...[
              ...subDirs.map(
                (d) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder),
                  title: Text(d),
                  onTap: () => Navigator.pop(ctx, d),
                ),
              ),
              const Divider(),
            ] else
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('暂无分类文件夹，可新建'),
              ),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '新建分类文件夹名',
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty) Navigator.pop(ctx, name);
          },
          child: const Text('新建并移动'),
        ),
      ],
    ),
  );
}
