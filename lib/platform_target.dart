import 'dart:io';

import 'package:flutter/foundation.dart';

/// 平台判定收口。
///
/// 鸿蒙版 Flutter 有独立的 `TargetPlatform.ohos`，`dart:io` 的
/// `Platform.operatingSystem` 同样返回 `ohos`。两个信号任一命中即认为在鸿蒙上，
/// 避免 SDK 版本差异导致判定失效。
bool get isOhos {
  if (Platform.operatingSystem == 'ohos') return true;
  return defaultTargetPlatform.name == 'ohos';
}

/// 鸿蒙上使用系统播放器（AVPlayer），其他平台沿用 media_kit（libmpv）。
bool get useSystemPlayer => isOhos;

/// 移动端语义（手机 / 平板）：有触摸、按屏幕宽度分栏。
/// 鸿蒙手机、平板都归到这里，电视模式由用户在界面里单独指定。
bool get isMobileTarget => switch (defaultTargetPlatform) {
  TargetPlatform.android || TargetPlatform.iOS => true,
  _ => isOhos,
};
