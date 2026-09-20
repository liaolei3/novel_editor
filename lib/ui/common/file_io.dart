import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

/// 导入导出（FR-23 / FR-24）的文件选择与写入封装。
class FileIO {
  FileIO._();

  static Future<String?> pickReadText({List<String> ext = const ['txt']}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ext,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return null;
    if (file.path != null && File(file.path!).existsSync()) {
      return File(file.path!).readAsString();
    }
    return file.bytes != null ? String.fromCharCodes(file.bytes!) : null;
  }

  /// 选择并读取文本文件，返回 (去扩展名文件名, 内容)，取消返回 null。
  static Future<(String, String)?> pickReadTextNamed({
    List<String> ext = const ['txt'],
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ext,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return null;
    String? content;
    if (file.path != null && File(file.path!).existsSync()) {
      content = await File(file.path!).readAsString();
    } else if (file.bytes != null) {
      content = String.fromCharCodes(file.bytes!);
    }
    if (content == null) return null;
    final name = file.name;
    final dot = name.lastIndexOf('.');
    return (dot > 0 ? name.substring(0, dot) : name, content);
  }

  /// 选择二进制文件，返回其路径，取消返回 null。
  static Future<String?> pickFilePath({List<String> ext = const ['ttf', 'otf']}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ext,
    );
    return result?.files.single.path;
  }

  static Future<String?> pickDirectory() =>
      FilePicker.platform.getDirectoryPath();

  static Future<String?> saveBytes({
    required String fileName,
    required List<int> bytes,
  }) async {
    if (kIsWeb) return null;
    final path = await FilePicker.platform.saveFile(fileName: fileName);
    if (path == null) return null;
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      return path;
    }
    // 移动端：saveFile(Android 19+/iOS) 已写入指定 uri。
    return path;
  }

  static Future<String?> saveText({
    required String fileName,
    required String content,
  }) =>
      saveBytes(fileName: fileName, bytes: content.codeUnits);
}