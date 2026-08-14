# VidBox

本地抖音视频管理器（Android）。全屏刷着顺手整理手机本地下载的抖音视频与图片。

## 核心设计

- **文件系统即数据库**：分类/分组状态随文件走，换机重装零丢失。另有 SQLite 索引缓存（可随时重建）提速千级文件扫描。
- **分类 = 文件夹**：移动文件到对应文件夹即分类。
- **星标 = `dy` 后的数字**：`dy1`=基线，`dy2`~`dy5`=收藏星级。双击在 dy1↔dy5 间切换。文件名保持原风格，无额外前缀。
- **分组 = 确定性解析**：解析 `dy<N>_<作者>_<类型>_<标题>_<时间戳>_<序号>` 结构化命名，按作者分组。作者名含下划线也能正确解析（靠类型词定位边界）。

## 技术栈

- Flutter（UI + 分组引擎，纯 Dart）
- Kotlin 原生通道（文件扫描/移动/重命名/删除）
- 播放：video_player

## 目录结构

```
lib/
  main.dart                    # 入口
  models/media_item.dart       # 数据模型
  core/filename_parser.dart    # 文件名解析（dy1_ 结构 + 星标）
  core/grouper.dart            # 分组引擎
  services/file_service.dart   # 文件操作（MethodChannel 封装）
  ui/home_page.dart            # 首页：扫描 + 分组展示
  ui/feed_page.dart            # 全屏流浏览
android/
  app/src/main/kotlin/.../MainActivity.kt   # 原生文件操作通道
  app/src/main/AndroidManifest.xml          # 权限声明
.github/workflows/build.yml                 # 云端构建 APK
```

## 如何构建与测试

本仓库**不需要在本地装 Flutter/Android 环境**，构建在 GitHub Actions 云端完成：

1. 把代码推送到 GitHub（`main` 或 `master` 分支，或打 `v*` 标签）。
2. Actions 会自动运行 `.github/workflows/build.yml`，生成 release APK。
3. 在 GitHub 仓库的 **Actions** 页面 → 对应运行记录 → 底部 **Artifacts** 下载 `vidbox-release-apk`。
4. 把 APK 装到手机（首次安装需允许"未知来源"），在系统设置中授予「所有文件访问」权限。

## 版本管理

- 版本号从 `0.0.1` 起步，每次打包最后一位 +1（`0.0.1` → `0.0.2` → …）。
- 修改 `pubspec.yaml` 的 `version` 后，打 tag `vX.Y.Z` 并推送，触发构建并**自动创建 Release**（附 APK）。
- 直接推送到 main 分支只构建 APK（存为 Artifact），打 tag 才创建 Release。
- 下载：仓库 **Releases** 页拿对应版本的 APK，或用 Actions 页的 Artifact。

## 里程碑

| 里程碑 | 内容 | 版本 |
|--------|------|------|
| M0~M3 | 基础链路：扫描/全屏/网格/回收站/分组/待整理 | v0.0.1~v0.0.4 |
| v0.1.0 | 完成品：单一数据源同步、图集、搜索/筛选/排序、已收藏视图、批量改名、自动回收、Kotlin 异步化、单元测试 | v0.1.0 |

## v0.1.0 功能清单

- 单一数据源（MediaStore），全屏/网格/首页修改即时同步
- 全屏流：图集左右滑、单击暂停、图片缩放、重命名、位置指示、已看标记
- 网格：作者分组折叠、搜索、筛选（已收藏/待整理/图集）、排序（时间/星级）、选整组
- 首页：自动增量扫描、已收藏/图集入口、作者缩略图
- 待整理：批量改名归位
- 回收站：删除时间、30 天自动清理
- 性能：Kotlin 后台线程、SQLite 增量索引、缩略图磁盘缓存
- 测试：解析器 + 分组引擎单元测试，接入 CI
