import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../data/db.dart';

/// 书籍封面存取工具：
/// - 上传图片复制到数据目录 covers/ 子目录，DB 存相对路径
/// - 未上传封面时由 UI 用主题色代码绘制默认封面（保证与页面协调）
class BookCover {
  BookCover._();

  /// 相对路径 → 绝对文件路径。
  static Future<String> resolve(String relativePath) async =>
      p.join(await Db.supportDir(), relativePath);

  /// 相对路径是否指向真实存在的封面文件。
  static Future<bool> exists(String relativePath) async {
    if (relativePath.isEmpty) return false;
    try {
      return File(await resolve(relativePath)).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 弹出选图并把文件复制到 covers/ 目录，返回相对路径；取消返回 null。
  static Future<String?> pickAndStore(String bookId) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: false,
    );
    final source = result?.files.single.path;
    if (source == null) return null;

    final dir = Directory(p.join(await Db.supportDir(), 'covers'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    final ext = p.extension(source).toLowerCase();
    final fileName = '${bookId}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final target = p.join(dir.path, fileName);
    await File(source).copy(target);
    return 'covers/$fileName';
  }

  /// 删除 covers/ 下的封面文件（尽力而为，忽略失败）。
  static Future<void> deleteFile(String relativePath) async {
    if (relativePath.isEmpty) return;
    try {
      final f = File(await resolve(relativePath));
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // 文件被占用或缺失时忽略，不影响 DB 状态。
    }
  }

  /// 自定义封面图 provider；未上传或文件缺失时返回 null（UI 绘制默认封面）。
  static Future<ImageProvider?> providerFor(String coverPath) async {
    if (await exists(coverPath)) {
      return FileImage(File(await resolve(coverPath)));
    }
    return null;
  }
}
