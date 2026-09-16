import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/constants.dart';
import '../logger.dart';

/// AI 网关（FR-16 ~ FR-20 / NFR-P4）。
///
/// 统一封装第三方大模型 API（OpenAI 兼容协议），Prompt 模板集中管理，
/// 便于切换供应商。超时 30s，失败可重试；网关不可用时降级提示，
/// 不阻断本地写作（NFR-U4）。
abstract class AiGateway {
  Future<AiResult> complete(AiRequest request);
}

class AiRequest {
  AiRequest({
    required this.kind,
    required this.prompt,
    this.systemPrompt,
    this.count = 1,
  });

  final AiTask kind;
  final String prompt;
  final String? systemPrompt;
  final int count;
}

class AiResult {
  AiResult(this.candidates, {this.error});

  final List<String> candidates;
  final String? error;

  bool get ok => error == null && candidates.isNotEmpty;
}

enum AiTask { continueWriting, polish, inspiration, roleCard }

/// OpenAI 兼容实现。
class OpenAiCompatibleGateway implements AiGateway {
  OpenAiCompatibleGateway({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client _client;

  @override
  Future<AiResult> complete(AiRequest request) async {
    if (baseUrl.isEmpty || apiKey.isEmpty) {
      return AiResult(const [],
          error: '未配置 AI 网关（设置 → AI 配置）。本应用已自动降级为纯写作模式，本地功能不受影响。');
    }
    try {
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': request.systemPrompt ?? _defaultSystem()},
        {'role': 'user', 'content': request.prompt},
      ];
      final resp = await _client
          .post(
            Uri.parse('${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': 0.8,
              'n': request.count.clamp(1, 3),
            }),
          )
          .timeout(AppConstants.aiTimeout);
      if (resp.statusCode != 200) {
        return AiResult(const [], error: 'AI 网关错误（HTTP ${resp.statusCode}），可重试。');
      }
      final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, Object?>;
      final choices = (data['choices'] as List<Object?>?) ?? const [];
      final texts = choices
          .map((c) => (((c as Map)['message'] as Map)['content']) as String? ?? '')
          .where((t) => t.trim().isNotEmpty)
          .toList();
      if (texts.isEmpty) return AiResult(const [], error: 'AI 返回为空，可重试。');
      return AiResult(texts);
    } on TimeoutException {
      Logger.warn('AI 请求超时', tag: 'AI');
      return AiResult(const [], error: 'AI 请求超时（30s），可重试。');
    } catch (e, s) {
      Logger.error('AI 请求失败', error: e, stackTrace: s, tag: 'AI');
      return AiResult(const [], error: 'AI 请求失败：$e');
    }
  }

  String _defaultSystem() =>
      '你是中文网文写作助手。输出为简体中文纯文本，风格贴合正文，禁止输出任何解释性文字。';
}

/// Prompt 模板（FR-16 ~ FR-19）。
class AiPrompts {
  AiPrompts._();

  static String continueWriting(String context) =>
      '以下是小说当前章节的正文片段，请自然地续写一段 200~400 字的内容，'
      '保持人称、时态与文风一致，直接输出续写文本：\n\n$context';

  static String polish(String selected, String mode) {
    const modeDesc = {
      '润色': '在不改变情节的前提下润色文字，使其更具文学性与画面感',
      '精简': '压缩篇幅、删减冗余，保留核心信息与语感',
      '扩写': '扩充细节描写，增强画面感与情绪张力，篇幅约增加一倍',
      '对白优化': '优化对白，使语气更贴合人物性格、更口语化',
    };
    return '请${modeDesc[mode] ?? '润色'}以下小说片段，直接输出结果：\n\n$selected';
  }

  static String inspiration(String type) {
    const typeDesc = {
      '剧情转折': '设计一个出人意料又合乎逻辑的剧情转折',
      '人物冲突': '设计一组尖锐的人物冲突场景',
      '开脑洞': '提出一个大胆的世界观脑洞',
    };
    return '为一部网络小说${typeDesc[type] ?? '提供创作灵感'}。'
        '每条灵感包含一句话概括与两三句展开，共 3 条，按序号列出。';
  }

  static String roleCard(String name, String desc) =>
      '为小说角色生成角色卡。角色名：$name。描述：$desc。\n'
      '请按以下字段输出，每项一行，格式为"字段：内容"：\n外貌、性格、背景、口头禅、人物关系。';
}