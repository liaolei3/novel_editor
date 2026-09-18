# AGENTS.md

本文件是 AI 代理在本仓库工作的强制约定。分为：代理行为规范、代码约定、UI 红线。逐条遵守，无例外。

## 一、代理行为规范

- 思考与回复始终使用中文。
- **执行任何写 SQL（INSERT / UPDATE / DELETE / DDL、修改数据库内容）前，必须先征得用户同意。**
- 代码只需要关键注释：仅在逻辑不自明处解释"为什么"，禁止写复述代码的"是什么"注释，禁止给未改动的代码补注释。
- 禁止擅自 commit / push，仅在用户明确要求时提交。
- 禁止破坏性 git 操作（force push、reset --hard、clean -f 等），除非用户明确要求。
- 新增依赖、资源前先确认必要性，避免过度工程；优先编辑现有文件而非新建文件。

## 二、文件结构

```
lib/
├── main.dart                     # 入口（桌面端初始化 sqflite_ffi、window_manager）
├── core/
│   ├── constants.dart
│   ├── utils/                    # 纯工具层，禁止依赖 UI / DB
│   │   ├── chapter_title_suggest.dart   # 章节标题建议（含中文数字）
│   │   ├── rich_text_codec.dart         # Delta 编解码、Delta 拆分工具
│   │   ├── pair_symbols.dart            # 中文成对符号自动补全
│   │   ├── global_search.dart           # 全局搜索（Delta 偏移映射）
│   │   ├── text_formatter.dart / text_stats.dart / sensitive_words.dart
│   │   └── docx_exporter.dart / txt_importer.dart
│   ├── data/
│   │   ├── db.dart                      # 数据库建表与迁移
│   │   ├── models.dart                  # 数据模型
│   │   └── repositories.dart            # 仓储层（含章节 sortNumber 移位）
│   ├── services/                        # autosave、durability、logger、session_stats、ai_gateway、sync_engine
│   └── state/
│       ├── app_state.dart               # 核心状态与业务方法
│       ├── app_config.dart / settings_controller.dart
└── ui/
    ├── app_theme.dart                   # 三套主题：浅色 / 暗色 / 像素
    ├── app_root.dart / workspace_page.dart / shelf_page.dart / stats_page.dart
    ├── recycle_page.dart / conflict_page.dart / login_page.dart
    ├── settings_dialog.dart / global_search_dialog.dart
    ├── panels/                          # 右侧面板：character、outline、notes、snapshot、stats、ai、sensitive
    ├── widgets/                         # book_tree、editor_area、toast、context_menu、search_replace_bar 等
    └── common/                          # dialogs、file_io、book_cover 等
third_party/flutter_quill/       # flutter_quill 11.5.1 本地补丁
test/                            # 单元测试与 Widget 测试
assets/avatars/                  # 角色默认头像
prd/                             # 产品需求文档
```

## 三、运行与依赖

```bash
flutter pub get          # 同步依赖
flutter run -d windows   # Windows 桌面端启动
flutter test             # 全部测试
flutter analyze          # 静态检查
```

- `flutter_quill` 必须使用 `third_party/flutter_quill` 本地补丁版（dependency_overrides）。**禁止通过升级依赖覆盖该补丁**；如需升级，必须先确认并重新应用 Windows IME 补丁（候选框跟随光标：逐帧上报 composing rect、锚点取光标行底部、含异常保护）。
- `objective_c` 固定 9.6.0，禁止升级（9.6.1 在 Windows 构建失败）。
- 新增资源必须放入 `assets/` 并在 pubspec 注册。

## 四、代码约定

- 通用工具逻辑放 `lib/core/utils/` 并必须配套单元测试。
- 修改模型字段必须同步 `lib/core/data/db.dart` 写迁移（如 gender 列默认 male）。
- 所有 Delta 操作必须保留内联样式与块属性。
- 编辑器右键菜单必须通过 `appEditorContextMenuBuilder` 的 `extraEntries` 扩展业务项，禁止硬编码进通用菜单。

## 五、UI 红线

### 对话框与弹窗
- **所有弹窗（每一个 showDialog 调用）必须 `barrierDismissible: false`：点击外部永不关闭，只能通过显式按钮 / 图标关闭。**
- **所有弹窗必须支持拖动。**
- 提示统一使用 `lib/ui/widgets/toast.dart` 的 `showToast`（顶部滑动通知），禁止使用 SnackBar 等其他形式。
