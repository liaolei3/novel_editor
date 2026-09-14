# NovelEditor

跨平台小说编辑器 MVP（Windows / Android / iOS），面向中文网文作者，支持专业长篇稿件管理、防丢稿、三端同步与内置 AI 辅助。

## 技术栈

- **框架**：Flutter (SDK ^3.9.0) / Dart
- **状态管理**：provider
- **富文本编辑器**：flutter_quill（Delta 格式存储）
- **本地数据库**：sqflite + sqflite_common_ffi（桌面 FFI / 移动原生）
- **其他**：path_provider、window_manager（桌面端窗口控制）、pixelarticons（像素风图标）、intl、archive、xml、http、crypto、file_picker

## 目录结构

```
lib\
├── main.dart                   # 应用入口
├── core\                       # 常量与纯工具
│   ├── constants.dart          # 自动保存/快照/AI 等常量
│   └── utils\                  # docx 导出、富文本编解码、敏感词、排版、字数、TXT 导入
├── data\                       # 数据层
│   ├── db.dart                 # SQLite 连接、建表与数据目录管理
│   ├── models.dart             # Book/Volume/Chapter 等模型
│   └── repositories.dart       # 各实体 CRUD
├── services\                   # 业务服务层
│   ├── ai\ai_gateway.dart      # AI 网关（续写/润色/灵感/角色卡）
│   ├── sync\sync_engine.dart   # 云同步引擎
│   ├── autosave_service.dart   # 自动保存（2s 停顿/30s 间隔）
│   ├── durability_service.dart # 快照/备份/崩溃恢复
│   └── session_stats.dart      # 会话码字统计
├── state\                      # 状态层（ChangeNotifier）
│   ├── app_state.dart          # 全局应用状态
│   ├── app_config.dart         # 应用配置（config.json，数据目录切换）
│   └── settings_controller.dart # 主题/字体/同步开关
└── ui\                         # 表现层
    ├── app_root.dart           # MaterialApp 根 + 主题
    ├── app_theme.dart          # 三主题配置（亮色/暗色/像素风）
    ├── shelf_page.dart         # 书架页（首页）
    ├── workspace_page.dart     # 工作区（左树+中大纲+右编辑器）
    ├── login_page.dart         # 登录/注册
    ├── conflict_page.dart      # 同步冲突解决
    ├── recycle_page.dart       # 回收站（30 天保留）
    ├── settings_page.dart      # 设置
    ├── stats_page.dart         # 码字统计
    ├── panels\                 # AI/素材/大纲/敏感词/快照/统计面板
    ├── widgets\                # book_tree、editor_area、search_replace_bar、window_controls 等
    └── common\                 # dialogs、file_io
test\                           # 单元测试（工具层）
output\prd-novel-editor.md      # PRD 产品需求文档
```

## 环境准备

1. 安装 Flutter SDK ≥ 3.9.0（<https://docs.flutter.dev/get-started/install>）。
2. 确认 `flutter doctor` 无报错（Windows 桌面端需 Windows 10+ 与 Visual Studio 含 C++ 桌面工作负载）。

## 安装与运行

```bash
flutter pub get              # 安装依赖
flutter run                  # 运行（自动选择目标设备）
flutter run -d windows       # Windows 桌面端
flutter run -d <device-id>   # 指定 Android/iOS 设备
```

## 构建生产包

```bash
flutter build windows        # Windows
flutter build apk            # Android APK
flutter build appbundle      # Android AAB（推荐上架）
flutter build ios            # iOS（需 macOS + Xcode）
```

## 代码分析与测试

```bash
flutter analyze              # 静态分析
flutter test                 # 运行全部单元测试
```

## 关键特性

- **编辑器核心**：三级管理（作品/卷/章）、flutter_quill 富文本、撤销 200 步、查找替换。
- **防丢稿**：自动保存（2s 停顿 / 30s 间隔）、快照保留 50 个、本地多副本备份 7 天、崩溃恢复。
- **云同步**：按章节粒度增量同步，冲突解决（保留我的/使用云端/两者都保留）。
- **AI 辅助**：续写、润色、灵感、角色卡（30s 超时，3000 字上下文）。
- **导入导出**：TXT 批量导入（按"第X章"切分）、Word(.docx) 导出。
- **排版与检测**：一键排版（中文标点/缩进）、敏感词检测。
- **统计**：日/周/月字数、时长、速度曲线、目标进度条。
- **回收站**：30 天保留，过期清理前二次确认。

## 配置说明

- **应用配置**：不使用 shared_preferences，配置统一存为数据目录内的 `config.json`（`lib/state/app_config.dart`），首次运行自动从旧版 `shared_preferences.json` 导入。
- **数据目录可切换**：目录解析优先级为 exe 旁指针文件 `novel_editor.data_dir` > 默认目录 `config.json` 的 `dataDir` > 应用默认目录；切换时通过 `VACUUM INTO` 迁移数据库并拷贝备份，重启后生效。
- **数据库跨平台**：桌面端（Windows/Linux/macOS）使用 `sqflite_common_ffi`，移动端使用 `sqflite`，数据库文件位于数据目录下 `novel_editor.db`。
- **主题**：Material 3 + 种子色 `0xFF7C4DFF`，三种主题（亮色/暗色/像素风）；像素风全量使用 Zpix 字体与 Pixelarticons 图标。
- **中文字体回退**：Microsoft YaHei / PingFang SC / Noto Sans CJK SC，三端显示一致。
- **代码规范**：强制单引号、禁止 `print`（见 `analysis_options.yaml`）。

## 文档

详细产品需求见 [`output/prd-novel-editor.md`](output/prd-novel-editor.md)。
