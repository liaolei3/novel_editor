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
}