/// 手机预览机型：逻辑分辨率（单位 px）。
class PreviewDevice {
  const PreviewDevice(this.id, this.label, this.width, this.height);

  final String id;
  final String label;
  final double width;
  final double height;
}

class AppConstants {
  AppConstants._();

  static const autosaveDebounce = Duration(seconds: 2);
  static const autosaveInterval = Duration(seconds: 30);
  static const snapshotKeepCount = 30;
  static const backupKeepDays = 7;
  static const recycleKeepDays = 30;
  static const undoHistoryLength = 200;
  static const aiTimeout = Duration(seconds: 30);
  static const aiContextLimit = 3000;
  static const defaultDailyGoal = 2000;
  static const outlineMaxLength = 200;
  static const longChapterThreshold = 50000;
  static const longListThreshold = 1000;

  /// 手机预览：默认机型与自定义尺寸档位。
  static const String previewDefaultDeviceId = 'iphone15pro';
  static const String previewCustomDeviceId = 'custom';

  /// 自定义尺寸的合法范围（逻辑像素）。
  static const double previewMinWidth = 240;
  static const double previewMaxWidth = 600;
  static const double previewMinHeight = 480;
  static const double previewMaxHeight = 1200;

  /// 常见机型预设（小/中/大 + 双平台）；自定义尺寸由用户输入。
  static const List<PreviewDevice> previewDevices = [
    PreviewDevice('iphonese', 'iPhone SE', 375, 667),
    PreviewDevice('iphone15pro', 'iPhone 15 Pro', 393, 852),
    PreviewDevice('iphone15promax', 'iPhone 15 Pro Max', 430, 932),
    PreviewDevice('androidSmall', 'Android 小屏', 360, 800),
    PreviewDevice('androidStd', 'Android 标准', 393, 873),
    PreviewDevice('androidLarge', 'Android 大屏', 412, 915),
  ];

  static PreviewDevice get defaultPreviewDevice => previewDevices.firstWhere(
        (d) => d.id == previewDefaultDeviceId,
      );
}