# NovelEditor

跨平台小说编辑器（Windows / Android / iOS），面向中文网文作者，支持专业长篇稿件管理、伏笔管理、防丢稿、多端同步与内置 AI 辅助。

## 技术栈

- **框架**：Flutter (SDK ^3.9.0) / Dart
- **状态管理**：provider
- **富文本编辑器**：flutter_quill 11.5.1（本地补丁版，见 `third_party/flutter_quill`；Delta 格式存储）
- **本地数据库**：sqflite + sqflite_common_ffi（桌面 FFI / 移动原生）
- **统计图表**：fl_chart；**文本差异**：diff_match_patch
- **其他**：path_provider、window_manager（桌面端窗口控制）、intl、archive、xml、http、crypto、file_picker

## 目录结构

```
lib\
├── main.dart                     # 应用入口（桌面端初始化 sqflite_ffi、window_manager）
├── core\
│   ├── constants.dart            # 自动保存/快照/AI 等常量
│   └── utils\                    # 纯工具层（不依赖 UI / DB）
│       ├── chapter_title_suggest.dart   # 章节/卷标题建议（含中文数字）
│       ├── foreshadow_delta.dart        # 正文伏笔标注（fsid 内联属性）
│       ├── global_search.dart           # 全局搜索（Delta 偏移映射）
│       ├── pair_symbols.dart            # 中文成对符号自动补全
│       ├── rich_text_codec.dart         # Delta 编解码与拆分
│       ├── text_formatter.dart          # 一键排版（中文标点/缩进）
│       ├── text_stats.dart              # 字数统计口径
│       ├── sensitive_words.dart         # 敏感词检测
│       ├── docx_exporter.dart           # Word 导出
│       └── txt_importer.dart            # TXT 批量导入
├── data\
│   ├── db.dart                   # SQLite 连接、建表、迁移与数据目录管理
│   ├── models.dart               # Book/Volume/Chapter/Foreshadow 等模型
│   └── repositories.dart         # 各实体 CRUD
├── services\
│   ├── ai\ai_gateway.dart        # AI 网关（续写/润色/灵感/角色卡）
│   ├── sync\sync_engine.dart     # 云同步引擎（本地优先 + 抽象 CloudGateway）
│   ├── autosave_service.dart     # 自动保存（2s 停顿 / 30s 间隔）
│   ├── durability_service.dart   # 快照/备份/崩溃恢复
│   ├── session_stats.dart        # 会话码字统计
│   └── logger.dart               # 运行日志
├── state\
│   ├── app_state.dart            # 全局应用状态与业务方法
│   ├── app_config.dart           # 应用配置（config.json，数据目录切换）
│   └── settings_controller.dart  # 主题/字体/缩放/同步开关等
└── ui\
    ├── app_root.dart             # MaterialApp 根 + 全局渐变背景垫底
    ├── app_theme.dart            # 四主题（有机自然/玻璃拟态/黏土拟态/活力涂鸦）
    ├── shelf_page.dart           # 书架页（首页）
    ├── workspace_page.dart       # 工作区（左树 + 中编辑器 + 右活动列面板）
    ├── stats_page.dart           # 码字统计（周/月/年、时速、码字日历）
    ├── recycle_page.dart         # 回收站（30 天保留）
    ├── conflict_page.dart        # 同步冲突解决
    ├── login_page.dart           # 登录/注册弹窗
    ├── global_search_dialog.dart # 全书全局搜索
    ├── settings_dialog.dart      # 设置（弹窗）
    ├── panels\                   # 右侧面板：AI/角色/伏笔/素材/大纲/敏感词/快照
    ├── widgets\                  # book_tree、editor_area、foreshadow_tip、character_tip、
    │                             # search_replace_bar、toast、window_controls 等
    └── common\                   # dialogs（含拖动弹窗）、context_menu、file_io、book_cover
test\                             # 单元测试与 Widget 测试
third_party\flutter_quill\        # flutter_quill 本地补丁（Windows IME 候选框跟随等）
```

## 环境准备

1. 安装 Flutter SDK ≥ 3.9.0（<https://docs.flutter.dev/get-started/install>）。
2. 确认 `flutter doctor` 无报错（Windows 桌面端需 Windows 10+ 与 Visual Studio 含 C++ 桌面工作负载）。

## 安装与运行

```bash
flutter pub get              # 安装依赖
flutter run -d windows       # Windows 桌面端
flutter run -d <device-id>   # 指定 Android/iOS/Web 设备
```

> 依赖通过 `dependency_overrides` 指向 `third_party/flutter_quill` 本地补丁版；禁止通过升级依赖覆盖该补丁。

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
flutter test                 # 运行全部测试
```

## 关键特性

- **编辑器核心**：三级管理（作品/卷/章）、flutter_quill 富文本、撤销 200 步、内嵌查找替换、全文全局搜索。
- **伏笔管理**：正文划词内联标注（未完成红/已完成绿），悬浮 tip 查看与跳转，面板管理伏笔条目与片段列表。
- **角色卡**：角色面板维护设定，正文角色名悬浮 tip 展示卡片。
- **防丢稿**：自动保存（2s 停顿 / 30s 间隔）、快照保留 50 个、本地多副本备份 7 天、崩溃恢复。
- **云同步**：本地优先，按章节粒度增量同步；冲突绝不静默覆盖，提供冲突解决页。
- **AI 辅助**：续写、润色、灵感、角色卡（30s 超时，3000 字上下文）。
- **导入导出**：TXT 批量导入（按“第X章”切分）、Word(.docx) 导出。
- **排版与检测**：一键排版（中文标点/缩进）、敏感词检测、中文成对符号自动补全。
- **统计**：周/月/年指标、时速、摸鱼统计、码字日历（月历/年历）、目标进度。
- **回收站**：书/卷/章/素材 30 天保留，过期清理前二次确认。
- **界面**：四套主题（有机自然/玻璃拟态/黏土拟态/活力涂鸦）、界面缩放与字体独立可调、Windows 自绘标题栏。

## 配置说明

- **应用配置**：不使用 shared_preferences，配置统一存为数据目录内的 `config.json`（`lib/state/app_config.dart`），随数据目录一起迁移。
- **数据目录可切换**：目录解析优先级为 exe 旁指针文件 `novel_editor.data_dir` > 默认目录 `config.json` 的 `dataDir` > 应用默认目录；切换时通过 `VACUUM INTO` 迁移数据库并拷贝备份，重启后生效。
- **数据库跨平台**：桌面端（Windows/Linux/macOS）使用 `sqflite_common_ffi`，移动端使用 `sqflite`，数据库文件位于数据目录下 `novel_editor.db`。
- **主题**：四套主题（有机自然 / 玻璃拟态 / 黏土拟态 / 活力涂鸦），仅在设置弹窗内切换（主题名 + 预览卡横向滚动选择，顶栏无切换按钮）；渐变主题由 `MaterialApp.builder` 全局垫底，未知的历史主题值读取时回退「有机自然」。主题不携带字体，界面字体独立设置。
- **模型与迁移**：数据模型字段变更必须同步 `lib/core/data/db.dart` 的建表迁移逻辑。
- **中文字体回退**：Microsoft YaHei / PingFang SC / Noto Sans CJK SC，各端显示一致。
- **代码规范**：强制单引号、禁止 `print`（见 `analysis_options.yaml`）；开发约定见 [`AGENTS.md`](AGENTS.md)。
