import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// TextAlign.justify 下引擎会裁掉行首空白（段首全角空格缩进会消失），
/// 渲染层把行首 \u3000 替换为等宽 WidgetSpan 占位：每个占位符对应
/// 恰好一个字符位，文档文本与光标/选区映射均不受影响。
/// [buildRest] 负责去掉缩进后剩余文本的实际渲染。
InlineSpan leadingIndentSpan(
  BuildContext context,
  Node node,
  int nodeOffset,
  String text,
  TextStyle? style,
  InlineSpan Function(String text) buildRest,
) {
  var leading = 0;
  if (nodeOffset == 0 && node.isFirst) {
    while (leading < text.length && text.codeUnitAt(leading) == 0x3000) {
      leading++;
    }
  }
  if (leading == 0) return buildRest(text);
  final fs =
      style?.fontSize ?? DefaultTextStyle.of(context).style.fontSize ?? 16;
  return TextSpan(
    style: style,
    children: [
      for (var i = 0; i < leading; i++)
        WidgetSpan(
          alignment: PlaceholderAlignment.bottom,
          child: SizedBox(width: fs),
        ),
      buildRest(text.substring(leading)),
    ],
  );
}

/// 正文块默认样式：把字号/行距/段间距映射到 flutter_quill 的各正文块。
/// 编辑器与手机预览共用同一份映射，避免两处口径漂移（预览只是参数不同）。
DefaultStyles buildReadingStyles(
  BuildContext context, {
  required double fontSize,
  required double lineHeight,
  required double paragraphSpacing,
  required String fontFamily,
}) {
  final defaults = DefaultStyles.getInstance(context);
  // family 为空时保持主题字体（copyWith 传 null 不覆盖）。
  final base = DefaultTextStyle.of(context).style.copyWith(
        fontSize: fontSize,
        height: lineHeight,
        fontFamily: fontFamily.isEmpty ? null : fontFamily,
        decoration: TextDecoration.none,
      );
  final vs = VerticalSpacing(0, (fontSize * paragraphSpacing).toDouble());

  DefaultTextBlockStyle? bodyBlock(DefaultTextBlockStyle? d) =>
      d?.copyWith(style: base, verticalSpacing: vs);

  DefaultTextBlockStyle? scaledHeading(DefaultTextBlockStyle? d) {
    if (d == null) return null;
    final size = d.style.fontSize;
    return size == null
        ? d
        : d.copyWith(style: d.style.copyWith(fontSize: size * fontSize / 17));
  }

  return DefaultStyles(
    paragraph: bodyBlock(defaults.paragraph),
    indent: bodyBlock(defaults.indent),
    align: bodyBlock(defaults.align),
    // 列表序号/圆点样式与正文一致，否则序号字号偏小且垂直位置偏上。
    leading: defaults.leading?.copyWith(style: base),
    lists: defaults.lists?.copyWith(style: base, verticalSpacing: vs),
    quote: defaults.quote?.copyWith(
      style: base.copyWith(color: base.color?.withValues(alpha: 0.6)),
    ),
    h1: scaledHeading(defaults.h1),
    h2: scaledHeading(defaults.h2),
    h3: scaledHeading(defaults.h3),
    h4: scaledHeading(defaults.h4),
    h5: scaledHeading(defaults.h5),
    h6: scaledHeading(defaults.h6),
  );
}