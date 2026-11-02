import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../data/models.dart';

/// 单个编辑窗格的运行时会话：独立控制器、焦点节点、章节标签与文档状态。
class PaneSession {
  PaneSession(this.paneId)
      : controller = QuillController.basic(),
        focusNode = FocusNode();

  final String paneId;
  final QuillController controller;
  final FocusNode focusNode;

  /// 窗格内的章节标签顺序。
  List<String> tabIds = <String>[];

  /// 当前显示的章节。
  Chapter? activeChapter;

  /// 程序化加载文档期间为 true，抑制内容变化回调。
  bool loadingDoc = false;

  /// 上次文档序列化结果，用于忽略纯选区变化。
  String? lastDocJson;

  StreamSubscription? docSub;

  VoidCallback? _onChanged;

  /// 监听文档内容变化；替换文档后自动重绑。
  void bindDocumentListener(VoidCallback onChanged) {
    _onChanged = onChanged;
    docSub?.cancel();
    docSub = controller.document.changes.listen((_) => onChanged());
  }

  /// 替换文档并重绑内容监听。
  void replaceDocument(Document document, {bool fireChange = true}) {
    controller.document = document;
    final onChanged = _onChanged;
    if (onChanged != null) bindDocumentListener(onChanged);
    if (fireChange) onChanged?.call();
  }

  void dispose() {
    docSub?.cancel();
    docSub = null;
    controller.dispose();
    focusNode.dispose();
  }
}
