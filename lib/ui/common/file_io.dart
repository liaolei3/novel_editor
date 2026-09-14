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