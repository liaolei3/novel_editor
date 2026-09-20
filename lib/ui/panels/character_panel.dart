import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/settings_controller.dart';
import '../app_root.dart';
import '../common/dialogs.dart' show DraggableDialog;
import '../widgets/tinted_card.dart';
import '../widgets/toast.dart';
import '../widgets/view_toggle.dart';

/// 角色卡面板：收藏卡册风格，角色列表 + 内页详情编辑。
class CharacterPanel extends StatefulWidget {
  const CharacterPanel({super.key, required this.book, this.openCharacterId});

  final Book book;

  /// 外部请求打开的角色 id（编辑器悬浮 tip「编辑」跳转）。
  final String? openCharacterId;

  @override
  State<CharacterPanel> createState() => _CharacterPanelState();
}

class _CharacterPanelState extends State<CharacterPanel> {
  List<Character> _characters = [];
  Character? _selected;
  CharacterType? _filter;
  String _keyword = '';
  bool _searching = false;
  bool _loading = true;
  bool _gridView = false;

  late Character _draft;
  bool _isNew = false;

  /// 自定义属性行：属性名添加后固定，仅值可编辑。
  final List<(String, TextEditingController)> _attrRows = [];

  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  final _aliasesCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _gridView = context.read<SettingsController>().characterGridView;
    _load();
    final openId = widget.openCharacterId;
    if (openId != null) _openById(openId);
  }

  @override
  void didUpdateWidget(CharacterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final openId = widget.openCharacterId;
    if (openId != null && openId != oldWidget.openCharacterId) {
      _openById(openId);
    }
  }

  /// 打开指定角色详情；列表未加载完成时先加载。
  Future<void> _openById(String id) async {
    Character? find(List<Character> l) {
      for (final c in l) {
        if (c.id == id) return c;
      }
      return null;
    }

    var char = find(_characters);
    if (char == null) {
      final state = context.read<AppState>();
      final list = await state.characters.listByBook(widget.book.id);
      if (!mounted) return;
      _characters = list;
      _loading = false;
      char = find(list);
    }
    if (char != null && mounted) _openDetail(char);
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final list = await state.characters.listByBook(widget.book.id);
    if (mounted) setState(() { _characters = list; _loading = false; });
  }

  List<Character> get _filtered {
    var list = _characters;
    if (_filter != null) list = list.where((c) => c.type == _filter).toList();
    if (_keyword.isNotEmpty) {
      final kw = _keyword.toLowerCase();
      list = list.where((c) =>
          c.name.toLowerCase().contains(kw) ||
          c.aliases.toLowerCase().contains(kw) ||
          c.tags.toLowerCase().contains(kw)).toList();
    }
    return list;
  }

  static const _typeLabels = <CharacterType, String>{
    CharacterType.protagonist: '主角',
    CharacterType.supporting: '配角',
    CharacterType.antagonist: '反派',
    CharacterType.minor: '龙套',
  };

  static const _filterTypes = <CharacterType?>[null, CharacterType.protagonist,
      CharacterType.supporting, CharacterType.antagonist, CharacterType.minor];
  static const _filterLabels = <String>['全部', '主角', '配角', '反派', '龙套'];

  static const _colorPresets = [
    Color(0xFF4A90D9),
    Color(0xFF7CB342),
    Color(0xFFE53935),
    Color(0xFFFF8F00),
    Color(0xFF8E24AA),
    Color(0xFF00ACC1),
    Color(0xFFD81B60),
    Color(0xFF9E9E9E),
  ];

  static const _maleAvatar = 'assets/avatars/male.png';
  static const _femaleAvatar = 'assets/avatars/female.png';

  static String _avatarAsset(Gender g) =>
      g == Gender.female ? _femaleAvatar : _maleAvatar;

  String _colorToHex(Color c) => '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _aliasesCtrl.dispose();
    _tagsCtrl.dispose();
    _disposeAttrRows();
    super.dispose();
  }

  void _disposeAttrRows() {
    for (final (_, v) in _attrRows) {
      v.dispose();
    }
    _attrRows.clear();
  }

  void _loadAttrRows(List<CharacterAttribute> attrs) {
    _disposeAttrRows();
    for (final a in attrs) {
      _attrRows.add((a.name, TextEditingController(text: a.value)));
    }
  }

  /// 弹窗同时输入属性名与属性值后新增属性行；属性名添加后不可修改。
  Future<void> _addAttrRow() async {
    final nameCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 18, 24, 20),
          title: const Text('添加属性',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          content: SizedBox(
            width: 260,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                      hintText: '属性名，如：外貌、年龄', isDense: true),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: valueCtrl,
                  minLines: 3,
                  maxLines: 5,
                  decoration:
                      const InputDecoration(hintText: '属性值', isDense: true),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 38),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text('取消'),
            ),
            FilledButton.tonal(
              onPressed: () {
                final n = nameCtrl.text.trim();
                if (n.isEmpty) return; // 属性名必填
                Navigator.pop(ctx, (n, valueCtrl.text));
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size(72, 38),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    valueCtrl.dispose();
    if (result == null || !mounted) return;
    setState(() {
      _attrRows.add((result.$1, TextEditingController(text: result.$2)));
    });
  }

  List<CharacterAttribute> _collectAttrRows() {
    return [
      for (final (n, v) in _attrRows) CharacterAttribute(name: n, value: v.text),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_selected != null) return _buildDetail(scheme);
    return _buildList(scheme);
  }

  Widget _buildList(ColorScheme scheme) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          Text('角色', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface,
          )),
          const Spacer(),
          if (_searching)
            SizedBox(
              width: 180,
              height: 28,
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: TextStyle(fontSize: 12, color: scheme.onSurface),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '姓名 / 别名 / 标签',
                  hintStyle: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                  prefixIcon: Icon(Icons.search, size: 14),
                  prefixIconConstraints: const BoxConstraints(minWidth: 26, minHeight: 28),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                  ),
                ),
                onSubmitted: (v) {
                  setState(() => _keyword = v.trim());
                },
                onChanged: (v) {
                  setState(() => _keyword = v.trim());
                },
              ),
            )
          else
            SizedBox(
              height: 28,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    _searchCtrl.text = _keyword;
                    setState(() => _searching = true);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _keyword.isEmpty ? Icons.search : Icons.filter_alt,
                      size: 18,
                      color: _keyword.isEmpty ? null : scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 4),
          SizedBox(
            height: 28,
            child: Material(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(6),
                onTap: () => _create(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    Icon(Icons.add, size: 14, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text('新建', style: TextStyle(fontSize: 12, color: scheme.primary)),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          ViewToggleGroup(
            gridView: _gridView,
            onChanged: (grid) {
              setState(() => _gridView = grid);
              context.read<SettingsController>().setCharacterGridView(grid);
            },
          ),
        ]),
      ),
      SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            for (var i = 0; i < _filterTypes.length; i++)
              _UnderlineTab(
                label: _filterLabels[i],
                selected: _filter == _filterTypes[i],
                onTap: () => setState(() => _filter = _filterTypes[i]),
              ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.person_outline, size: 48,
                            color: scheme.onSurfaceVariant.withValues(alpha: 0.3)),
                        const SizedBox(height: 8),
                        Text('暂无角色', style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant,
                        )),
                      ],
                    ),
                  )
                : _gridView
                    ? _buildGrid(scheme)
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
                        itemCount: _filtered.length,
        itemBuilder: (ctx, i) => _buildCard(_filtered[i], scheme, i),
                      ),
      ),
    ]);
  }

  /// 角色网格视图：竖向卡片，高度与大纲网格一致（180px）。
  Widget _buildGrid(ColorScheme scheme) {
    return LayoutBuilder(builder: (ctx, constraints) {
      // 每列最小 220px，面板过窄时自动减少列数。
      final columns = (constraints.maxWidth ~/ 220).clamp(1, 4);
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 80),
        itemCount: _filtered.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          mainAxisExtent: 280,
        ),
        itemBuilder: (ctx, i) => _CharacterGridCell(
          char: _filtered[i],
          avatarAsset: _avatarAsset(_filtered[i].gender),
          typeLabel: _typeLabels[_filtered[i].type] ?? '',
          tintIndex: i,
          onTap: () => _openDetail(_filtered[i]),
          onDelete: () => _deleteFromList(_filtered[i]),
        ),
      );
    });
  }

  Widget _buildCard(Character char, ColorScheme scheme, int tintIndex) {
    return _CharacterCard(
      char: char,
      avatarAsset: _avatarAsset(char.gender),
      typeLabel: _typeLabels[char.type] ?? '',
      tintIndex: tintIndex,
      onTap: () => _openDetail(char),
      onDelete: () => _deleteFromList(char),
    );
  }

  Future<void> _deleteFromList(Character char) async {
    final ok = await confirmDangerous(context, '删除角色「${char.name}」？将进入回收站保留 30 天。');
    if (ok != true) return;
    if (!mounted) return;
    final state = context.read<AppState>();
    await state.recycle.add(RecycleType.character, char.id, {
      'book_id': char.bookId,
      'name': char.name,
      'aliases': char.aliases,
      'type': char.type.name,
      'gender': char.gender.name,
      'attributes': char.attributes,
      'avatar': char.avatar,
      'color': char.color,
      'tags': char.tags,
      'sort': char.sort,
    });
    await state.characters.hardDelete(char.id);
    state.characterDictVersion.value++;
    _characters.removeWhere((c) => c.id == char.id);
    if (mounted) setState(() {});
  }

  Widget _buildDetail(ColorScheme scheme) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(children: [
          SizedBox(
            height: 28,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() {
                  _selected = null;
                }),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.arrow_back, size: 18),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(_isNew ? '新建角色' : '角色 · ${_draft.name.isEmpty ? '未命名' : _draft.name}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface)),
          ),
          if (!_isNew)
            SizedBox(
              height: 28,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  mouseCursor: SystemMouseCursors.click,
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _delete(),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline, size: 18),
                  ),
                ),
              ),
            ),
          ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Center(
              child: Column(children: [
                CircleAvatar(
                  radius: 30,
                  backgroundImage: AssetImage(_avatarAsset(_draft.gender)),
                ),
                const SizedBox(height: 6),
                Text(_draft.name.isEmpty ? '未命名' : _draft.name,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: scheme.onSurface)),
                if (_draft.aliases.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(_draft.aliases.split(',').first.trim(),
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ],
              ]),
            ),
            const SizedBox(height: 20),
            _sectionLabel('性别', scheme),
            const SizedBox(height: 6),
            _genderSegmented(scheme),
            const SizedBox(height: 14),
            _sectionLabel('类型', scheme),
            const SizedBox(height: 6),
            _typeSegmented(scheme),
            const SizedBox(height: 14),
            _sectionLabel('标记色', scheme),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final c in _colorPresets)
                  _ColorSwatch(
                    color: c,
                    selected: _draft.color == _colorToHex(c),
                    onTap: () => setState(() => _draft.color = _colorToHex(c)),
                  ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => setState(() => _draft.color = ''),
                    child: Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: scheme.outlineVariant, width: 1.5),
                      ),
                      child: Center(child: Icon(Icons.close, size: 12, color: scheme.onSurfaceVariant)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionLabel('姓名', scheme),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(hintText: '角色姓名', isDense: true),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 14),
            _sectionLabel('别名 / 称号', scheme),
            const SizedBox(height: 6),
            TextField(
              controller: _aliasesCtrl,
              decoration: const InputDecoration(hintText: '多个别名用逗号分隔', isDense: true),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            _sectionLabel('标签', scheme),
            const SizedBox(height: 6),
            TextField(
              controller: _tagsCtrl,
              decoration: const InputDecoration(hintText: '多个标签用逗号分隔', isDense: true),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < _attrRows.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _buildAttrRow(i, scheme),
            ],
            const SizedBox(height: 6),
            Center(
              child: TextButton.icon(
                onPressed: _addAttrRow,
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                icon: Icon(Icons.add, size: 14, color: scheme.primary),
                label: Text('添加属性', style: TextStyle(
                    fontSize: 11, color: scheme.primary)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 34,
              child: FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text('保存修改',
                    style: TextStyle(fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _sectionLabel(String text, ColorScheme scheme) {
    return Text(text, style: TextStyle(
      fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant,
    ));
  }

  Widget _genderSegmented(ColorScheme scheme) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        for (final g in Gender.values) ...[
          if (g != Gender.male)
            Container(width: 1, height: 26, color: scheme.outlineVariant.withValues(alpha: 0.6)),
          Expanded(
            child: Material(
              color: _draft.gender == g ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                onTap: () => setState(() => _draft.gender = g),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  child: Text(g == Gender.female ? '女' : '男', style: TextStyle(
                    fontSize: 12,
                    fontWeight: _draft.gender == g ? FontWeight.w600 : FontWeight.w400,
                    color: _draft.gender == g ? scheme.primary : scheme.onSurfaceVariant,
                  )),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _typeSegmented(ColorScheme scheme) {
    final types = CharacterType.values;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Row(children: [
        for (var i = 0; i < types.length; i++) ...[
          if (i > 0) Container(width: 1, height: 26, color: scheme.outlineVariant.withValues(alpha: 0.6)),
          Expanded(
            child: _typeSegment(types[i], scheme),
          ),
        ],
      ]),
    );
  }

  Widget _typeSegment(CharacterType type, ColorScheme scheme) {
    final selected = _draft.type == type;
    final color = _typeColor(type, scheme);
    return Material(
      color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: () => setState(() {
          _draft.type = type;
          _draft.color = _colorToHex(color);
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          child: Text(_typeLabels[type] ?? type.name, style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? color : scheme.onSurfaceVariant,
          )),
        ),
      ),
    );
  }

  /// 单个属性块：属性名（只读小标签 + 删除按钮）+ 全宽属性值输入框，
  /// 布局与其他字段（标签 + 输入框）一致。
  Widget _buildAttrRow(int index, ColorScheme scheme) {
    final (name, valueCtrl) = _attrRows[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          _sectionLabel(name, scheme),
          const Spacer(),
          SizedBox(
            width: 22,
            height: 22,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 14,
              tooltip: '删除属性',
              onPressed: () => setState(() {
                _attrRows[index].$2.dispose();
                _attrRows.removeAt(index);
              }),
              icon: Icon(Icons.close, size: 14, color: scheme.onSurfaceVariant),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        TextField(
          controller: valueCtrl,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '属性值', isDense: true),
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }

  void _openDetail(Character char, {bool isNew = false}) {
    _draft = Character(
      id: char.id,
      bookId: char.bookId,
      name: char.name,
      aliases: char.aliases,
      type: char.type,
      gender: char.gender,
      attributes: char.attributes,
      avatar: char.avatar,
      color: char.color,
      tags: char.tags,
      sort: char.sort,
      createdAt: char.createdAt,
      updatedAt: char.updatedAt,
    );
    _isNew = isNew;
    _nameCtrl.text = _draft.name;
    _aliasesCtrl.text = _draft.aliases;
    _loadAttrRows(_draft.attrList);
    _tagsCtrl.text = _draft.tags;
    _searching = false;
    _searchCtrl.clear();
    _keyword = '';
    setState(() => _selected = char);
  }

  void _create() {
    final now = DateTime.now();
    _openDetail(
      Character(id: '', bookId: widget.book.id, name: '', createdAt: now, updatedAt: now),
      isNew: true,
    );
    _nameCtrl.clear();
    _aliasesCtrl.clear();
    _disposeAttrRows();
    _tagsCtrl.clear();
    setState(() {});
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showToast(context, '请填写角色姓名');
      return;
    }
    final state = context.read<AppState>();
    if (_isNew) {
      final char = await state.characters.create(bookId: widget.book.id, name: name);
      char.aliases = _aliasesCtrl.text.trim();
      char.type = _draft.type;
      char.gender = _draft.gender;
      char.attrList = _collectAttrRows();
      char.color = _draft.color;
      char.tags = _tagsCtrl.text.trim();
      await state.characters.update(char);
      state.characterDictVersion.value++;
      _characters.insert(0, char);
    } else {
      _draft.name = name;
      _draft.aliases = _aliasesCtrl.text.trim();
      _draft.attrList = _collectAttrRows();
      _draft.tags = _tagsCtrl.text.trim();
      await state.characters.update(_draft);
      state.characterDictVersion.value++;
      final idx = _characters.indexWhere((c) => c.id == _draft.id);
      if (idx >= 0) _characters[idx] = _draft;
      if (mounted) setState(() {});
    }
    if (mounted) {
      setState(() {
        if (_isNew) _selected = null;
      });
      showToast(context, '角色保存成功');
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDangerous(context, '删除角色「${_draft.name}」？将进入回收站保留 30 天。');
    if (ok != true) return;
    if (!mounted) return;
    final state = context.read<AppState>();
    await state.recycle.add(RecycleType.character, _draft.id, {
      'book_id': _draft.bookId,
      'name': _draft.name,
      'aliases': _draft.aliases,
      'type': _draft.type.name,
      'gender': _draft.gender.name,
      'attributes': _draft.attributes,
      'avatar': _draft.avatar,
      'color': _draft.color,
      'tags': _draft.tags,
      'sort': _draft.sort,
    });
    await state.characters.hardDelete(_draft.id);
    state.characterDictVersion.value++;
    _characters.removeWhere((c) => c.id == _draft.id);
    if (mounted) setState(() => _selected = null);
  }

  Color _typeColor(CharacterType type, ColorScheme scheme) => switch (type) {
    CharacterType.protagonist => const Color(0xFF4A90D9),
    CharacterType.supporting => const Color(0xFF7CB342),
    CharacterType.antagonist => const Color(0xFFE53935),
    CharacterType.minor => const Color(0xFF9E9E9E),
  };
}

/// 下划线式文字 Tab。
class _UnderlineTab extends StatelessWidget {
  const _UnderlineTab({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? scheme.primary : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Text(label, style: TextStyle(
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
        )),
      ),
    );
  }
}

/// 标记色色块：选中态为同色环 + 白色间隙 + 轻微放大（业界标准样式）。
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, required this.selected, required this.onTap});

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.12 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 26,
          height: 26,
          padding: EdgeInsets.all(selected ? 2 : 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// 角色网格卡片：内容与正文角色 tip 一致（别名/标签/自定义属性），悬浮显示删除。
class _CharacterGridCell extends StatefulWidget {
  const _CharacterGridCell({
    required this.char,
    required this.avatarAsset,
    required this.typeLabel,
    required this.onTap,
    required this.onDelete,
    this.tintIndex = 0,
  });

  final Character char;
  final String avatarAsset;
  final String typeLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final int tintIndex;

  @override
  State<_CharacterGridCell> createState() => _CharacterGridCellState();
}

class _CharacterGridCellState extends State<_CharacterGridCell> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final char = widget.char;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TintedCard(
        emphasized: false,
        tintIndex: widget.tintIndex,
        padding: const EdgeInsets.all(16),
        onTap: widget.onTap,
        child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: AssetImage(widget.avatarAsset),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(char.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface)),
                          ),
                          const SizedBox(width: 4),
                          _TypeBadge(
                              label: widget.typeLabel, type: char.type),
                          const SizedBox(width: 4),
                          Text(char.gender == Gender.female ? '女' : '男',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: scheme.onSurfaceVariant)),
                        ]),
                        const SizedBox(height: 2),
                        Text('修改于 ${_formatUpdated(char.updatedAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.7))),
                      ],
                    ),
                  ),
                  if (_hover)
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          mouseCursor: SystemMouseCursors.click,
                          borderRadius: BorderRadius.circular(6),
                          onTap: widget.onDelete,
                          child: Center(
                            child: Icon(Icons.delete_outline,
                                size: 15, color: scheme.error),
                          ),
                        ),
                      ),
                    ),
                ]),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (char.aliases.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text.rich(
                            TextSpan(
                              text: '别名：',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant),
                              children: [
                                TextSpan(
                                  text: char.aliases,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w400,
                                      color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (char.tags.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text.rich(
                            TextSpan(
                              text: '标签：',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant),
                              children: [
                                TextSpan(
                                  text: char.tags,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w400,
                                      color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        for (final attr in char.attrList) ...[
                          const SizedBox(height: 3),
                          Text.rich(
                            TextSpan(
                              text: '${attr.name}：',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant),
                              children: [
                                TextSpan(
                                  text: attr.value,
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w400,
                                      color: scheme.onSurfaceVariant),
                                ),
                              ],
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
          ),
      ),
    );
  }

  String _formatUpdated(DateTime t) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    if (t.year == now.year) {
      return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    }
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }
}

/// 角色列表卡片：主题色板彩底（无边框），头像 + 姓名 + 类型 + 修改时间，悬浮显示删除。
class _CharacterCard extends StatefulWidget {
  const _CharacterCard({
    required this.char,
    required this.avatarAsset,
    required this.typeLabel,
    required this.onTap,
    required this.onDelete,
    this.tintIndex = 0,
  });

  final Character char;
  final String avatarAsset;
  final String typeLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final int tintIndex;

  @override
  State<_CharacterCard> createState() => _CharacterCardState();
}

class _CharacterCardState extends State<_CharacterCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final char = widget.char;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: TintedCard(
          emphasized: false,
          tintIndex: widget.tintIndex,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          onTap: widget.onTap,
          child: Row(children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: AssetImage(widget.avatarAsset),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(char.name, maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurface,
                              )),
                        ),
                        const SizedBox(width: 6),
                        _TypeBadge(label: widget.typeLabel, type: char.type),
                      ]),
                      const SizedBox(height: 3),
                      Text(_formatUpdated(char.updatedAt), style: TextStyle(
                        fontSize: 10, color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                      )),
                    ],
                  ),
                ),
                SizedBox(
                  width: 26,
                  height: 26,
                  child: _hover
                      ? Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          child: InkWell(
                            mouseCursor: SystemMouseCursors.click,
                            borderRadius: BorderRadius.circular(6),
                            onTap: widget.onDelete,
                            child: Center(
                              child: Icon(Icons.delete_outline, size: 16,
                                  color: scheme.error),
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ]),
        ),
      ),
    );
  }

  String _formatUpdated(DateTime t) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    if (t.year == now.year) return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }
}

/// 角色类型标签徽章。
class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.type});

  final String label;
  final CharacterType type;

  Color _colorOf(ColorScheme scheme) => switch (type) {
    CharacterType.protagonist => const Color(0xFF4A90D9),
    CharacterType.supporting => const Color(0xFF7CB342),
    CharacterType.antagonist => const Color(0xFFE53935),
    CharacterType.minor => const Color(0xFF9E9E9E),
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _colorOf(scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w500,
        color: color,
      )),
    );
  }
}