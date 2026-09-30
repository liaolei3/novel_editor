import 'dart:convert';
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

  /// 选择可导入的书稿文件（txt / docx），返回 (去扩展名文件名, 小写扩展名,
  /// 字节内容)，取消返回 null。
  ///
  /// 与 [pickReadTextNamed] 不同，这里不做文本解码——docx 需按二进制解析，
  /// txt 由调用方自行解码，避免二进制被当成字符读取。
  static Future<(String, String, Uint8List)?> pickImportNamed({
    List<String> ext = const ['txt', 'docx'],
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ext,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return null;
    final name = file.name;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final suffix = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
    final Uint8List? bytes = file.path != null && File(file.path!).existsSync()
        ? await File(file.path!).readAsBytes()
        : file.bytes;
    if (bytes == null) return null;
    return (base, suffix, bytes);
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

  /// 保存二进制文件，返回实际写入的路径，取消返回 null。
  ///
  /// [fileName] 需带扩展名。保存对话框不保证扩展名：Windows 的 GetSaveFileName
  /// 只在声明了默认扩展名时才补，file_picker 未设该项，用户在对话框里改成不带
  /// 后缀的名字就会原样落盘（表现为「无后缀的文件」）。故这里显式声明文件类型，
  /// 并在写盘前补回缺失的扩展名。
  static Future<String?> saveBytes({
    required String fileName,
    required List<int> bytes,
  }) async {
    if (kIsWeb) return null;
    final ext = _extensionOf(fileName);
    final path = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: ext.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: ext.isEmpty ? null : <String>[ext],
    );
    if (path == null) return null;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final target = _withExtension(path, ext);
      await File(target).writeAsBytes(bytes, flush: true);
      return target;
    }
    // 移动端：saveFile(Android 19+/iOS) 已写入指定 uri。
    return path;
  }

  /// 取文件名的扩展名（不含点），没有扩展名返回空串。
  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(dot + 1) : '';
  }

  /// 路径的文件名部分没有扩展名时补上 [ext]；已有扩展名则尊重用户输入。
  static String _withExtension(String path, String ext) {
    if (ext.isEmpty) return path;
    final lastSlash = path.lastIndexOf('/');
    final lastBackslash = path.lastIndexOf(r'\');
    final sep = lastSlash > lastBackslash ? lastSlash : lastBackslash;
    return path.lastIndexOf('.') > sep ? path : '$path.$ext';
  }

  /// 写文本文件：按 UTF-8 编码。不能用 [String.codeUnits]——那是 UTF-16
  /// 码元，汉字会被截成单字节而乱码。
  static Future<String?> saveText({
    required String fileName,
    required String content,
  }) =>
      saveBytes(fileName: fileName, bytes: utf8.encode(content));
}