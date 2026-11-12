import 'package:flutter/widgets.dart';

/// 视频参数：画面尺寸与旋转信息，用来推算显示比例。
///
/// 各平台播放器给出的字段不完全一致，这里统一收口成同一份结构。
class AppVideoParams {
  const AppVideoParams({this.w, this.h, this.dw, this.dh, this.rotate});

  /// 编码宽高。
  final int? w;
  final int? h;

  /// 显示宽高（存在时优先使用）。
  final int? dw;
  final int? dh;

  /// 旋转角度，90 / 270 表示需要交换宽高。
  final int? rotate;

  static const none = AppVideoParams();
}

/// 播放器当前状态的一次快照。
class AppPlayerState {
  const AppPlayerState({
    this.playing = false,
    this.buffering = false,
    this.completed = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffer = Duration.zero,
    this.volume = 100,
    this.rate = 1,
    this.width,
    this.videoParams = AppVideoParams.none,
  });

  final bool playing;
  final bool buffering;
  final bool completed;
  final Duration position;
  final Duration duration;

  /// 已缓冲到的位置。
  final Duration buffer;
  final double volume;
  final double rate;

  /// 解码出的画面宽度，0 表示还没有画面。
  final int? width;
  final AppVideoParams videoParams;

  AppPlayerState copyWith({
    bool? playing,
    bool? buffering,
    bool? completed,
    Duration? position,
    Duration? duration,
    Duration? buffer,
    double? volume,
    double? rate,
    int? width,
    AppVideoParams? videoParams,
  }) => AppPlayerState(
    playing: playing ?? this.playing,
    buffering: buffering ?? this.buffering,
    completed: completed ?? this.completed,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    buffer: buffer ?? this.buffer,
    volume: volume ?? this.volume,
    rate: rate ?? this.rate,
    width: width ?? this.width,
    videoParams: videoParams ?? this.videoParams,
  );
}

/// 播放器事件流集合。
class AppPlayerStream {
  const AppPlayerStream({
    required this.playing,
    required this.completed,
    required this.position,
    required this.duration,
    required this.buffering,
    required this.buffer,
    required this.rate,
    required this.volume,
    required this.error,
    required this.videoParams,
  });

  final Stream<bool> playing;
  final Stream<bool> completed;
  final Stream<Duration> position;
  final Stream<Duration> duration;
  final Stream<bool> buffering;
  final Stream<Duration> buffer;
  final Stream<double> rate;
  final Stream<double> volume;
  final Stream<String> error;
  final Stream<AppVideoParams> videoParams;
}

/// 播放器统一接口。
///
/// Android / iOS / Windows / macOS 走 media_kit（libmpv）；HarmonyOS 走系统
/// AVPlayer（video_player）。界面层只认这一层，不直接依赖某个后端。
abstract class AppPlayer {
  AppPlayerState get state;

  AppPlayerStream get stream;

  /// 后端原生对象。media_kit 下是 `NativePlayer`，可用来设置 mpv 选项；
  /// 鸿蒙后端返回 null，调用方据此跳过 mpv 专属配置。
  Object? get platform;

  Future<void> open(
    String url, {
    Map<String, String>? headers,
    Duration? start,
    bool play = true,
  });

  Future<void> play();

  Future<void> pause();

  Future<void> playOrPause();

  Future<void> stop();

  Future<void> seek(Duration position);

  Future<void> setRate(double rate);

  Future<void> setVolume(double volume);

  Future<void> dispose();

  /// 画面组件。外层已经算好要占的尺寸，这里只需要铺满。
  Widget buildVideo();

  /// 是否支持根据容器尺寸反推渲染分辨率（media_kit 在 Windows 上需要）。
  bool get supportsOutputSize => false;

  Future<void> setOutputSize({required int width, required int height}) async {}
}
