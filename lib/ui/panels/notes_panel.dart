import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../app_root.dart';
import '../common/dialogs.dart';

/// 素材库（FR-21 / 9.7）：角色卡 / 世界观 / 灵感便签三类，支持新建、编辑、删除、搜索。
class NotesPanel extends StatefulWidget {
  const NotesPanel({super.key, required this.book});

  final Book book;

  @override
  State<NotesPanel> createState() => _NotesPanelState();
}

class _NotesPanelState extends State<NotesPanel> {
  NoteType _tab = NoteType.role;
  String _keyword = '';

  static const _tabs = [(NoteType.role, '角色卡'), (NoteType.world, '世界观'), (NoteType.idea, '灵感便签')];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return FutureBuilder<List<Note>>(
      future: state.notes.listByBook(widget.book.id, type: _tab),
      builder: (ctx, snap) {
        final notes = (snap.data ?? const <Note>[])
            .where((n) =>
                _keyword.isEmpty ||
                n.title.contains(_keyword) ||
                n.content.contains(_keyword))
            .toList();
        return Column(children: [
          Row(children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final (type, label) in _tabs)
                      Padding(
                        padding: const EdgeInsets.all(4),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: _tab == type,
                          onSelected: (_) => setState(() => _tab = type),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: '搜索',
              icon: const Icon(Icons.search),
              onPressed: () async {
                final kw = await inputDialog(context, title: '搜索素材', hint: '标题或正文关键字');
                if (kw != null) setState(() => _keyword = kw.trim());
              },
            ),
            IconButton(
              tooltip: '新建',
              icon: const Icon(Icons.add),
              onPressed: () => _create(context),
            ),
          ]),
          const Divider(height: 1),
          Expanded(
            child: notes.isEmpty
                ? const Center(child: Text('暂无素材，点击右上角 + 新建'))
                : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: notes.length,
                    itemBuilder: (ctx, i) => _noteCard(context, notes[i]),
                  ),
          ),
        ]);
      },
    );
  }

  Widget _noteCard(BuildContext context, Note note) {
    final state = context.read<AppState>();
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(note.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          note.content.isEmpty ? '（空）' : note.content,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (action) async {
            if (action == 'edit') {
              await _edit(context, note);
            } else if (action == 'delete') {
              final ok = await confirmDangerous(context, '删除素材「${note.title}」？将进入回收站保留 30 天。');
              if (ok) {
                await state.recycle.add(RecycleType.note, note.id,
                    {'book_id': note.bookId, 'title': note.title, 'content': note.content, 'type': note.type.name});
                await state.notes.hardDelete(note.id);
                if (context.mounted) setState(() {});
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              height: 44,
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit_outlined, size: 16),
                SizedBox(width: 9),
                Text('编辑'),
              ]),
            ),
            PopupMenuItem(
              height: 44,
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline, size: 16),
                SizedBox(width: 9),
                Text('删除'),
              ]),
            ),
          ],
        ),
        onTap: () => _edit(context, note),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final title = await inputDialog(context, title: '新建${_labelOf(_tab)}', hint: '标题');
    if (title == null || title.trim().isEmpty) return;
    final state = context.read<AppState>();
    await state.notes.create(bookId: widget.book.id, type: _tab, title: title.trim());
    if (context.mounted) setState(() {});
  }

  Future<void> _edit(BuildContext context, Note note) async {
    final titleCtrl = TextEditingController(text: note.title);
    final bodyCtrl = TextEditingController(text: note.content);
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DraggableDialog(
        child: AlertDialog(
          title: Text('编辑${_labelOf(note.type)}'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: '标题')),
              const SizedBox(height: 12),
              TextField(
                controller: bodyCtrl,
                maxLines: 8,
                decoration: InputDecoration(
                  labelText: switch (note.type) {
                    NoteType.role => '外貌 / 性格 / 背景 / 口头禅 / 人物关系',
                    NoteType.world => '世界观设定',
                    NoteType.idea => '灵感内容',
                  },
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (saved == true) {
      note.title = titleCtrl.text.trim();
      note.content = bodyCtrl.text;
      await context.read<AppState>().notes.update(note);
      if (context.mounted) setState(() {});
    }
  }

  String _labelOf(NoteType t) => switch (t) {
        NoteType.role => '角色卡',
        NoteType.world => '世界观',
        NoteType.idea => '灵感便签',
      };
}