import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'app_player.dart';

/// HarmonyOS 后端：走系统 AVPlayer（经 video_player 的 OpenHarmony 实现）。
///
/// 与 media_kit 的差异：
/// - 没有 mpv 选项（`platform` 返回 null，调用方会跳过硬件解码等设置）；
/// - 不支持「预开下一集」的多路解码器，预缓冲由上层按需降级；
/// - 音量口径是 0~1，对外仍然沿用 0~100。
class SystemPlayer implements AppPlayer {
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _buffer = StreamController<Duration>.broadcast();
  final _rate = StreamController<double>.broadcast();
  final _volume = StreamController<double>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _videoParams = StreamController<AppVideoParams>.broadcast();
  final _revision = ValueNotifier<int>(0);

  VideoPlayerController? _controller;
  VoidCallback? _watch;
  AppPlayerState _state = const AppPlayerState();
  bool _disposed = false;

  VideoPlayerController? get _active => _controller;

  @override
  AppPlayerState get state => _state;

  @override
  AppPlayerStream get stream => AppPlayerStream(
    playing: _playing.stream,
    completed: _completed.stream,
    position: _position.stream,
    duration: _duration.stream,
    buffering: _buffering.stream,
    buffer: _buffer.stream,
    rate: _rate.stream,
    volume: _volume.stream,
    error: _error.stream,
    videoParams: _videoParams.stream,
  );

  @override
  Object? get platform => null;

  AppVideoParams _params(VideoPlayerValue value) {
    final size = value.size;
    if (size.width <= 0 || size.height <= 0) return AppVideoParams.none;
    return AppVideoParams(
      w: size.width.round(),
      h: size.height.round(),
      dw: size.width.round(),
      dh: size.height.round(),
      rotate: 0,
    );
  }

  void _publish(VideoPlayerValue value) {
    if (_disposed) return;
    final duration = value.duration;
    final position = value.position;
    final completed =
        duration > Duration.zero &&
        position >= duration &&
        !value.isPlaying &&
        !value.isBuffering;
    final next = AppPlayerState(
      playing: value.isPlaying,
      buffering: value.isBuffering,
      completed: completed,
      position: position,
      duration: duration,
      buffer: value.buffered.isEmpty ? Duration.zero : value.buffered.last.end,
      volume: value.volume * 100,
      rate: value.playbackSpeed,
      width: value.size.width > 0 ? value.size.width.round() : null,
      videoParams: _params(value),
    );
    final previous = _state;
    _state = next;
    if (previous.playing != next.playing) _playing.add(next.playing);
    if (previous.completed != next.completed) _completed.add(next.completed);
    if (previous.position != next.position) _position.add(next.position);
    if (previous.duration != next.duration) _duration.add(next.duration);
    if (previous.buffering != next.buffering) _buffering.add(next.buffering);
    if (previous.rate != next.rate) _rate.add(next.rate);
    if (previous.volume != next.volume) _volume.add(next.volume);
    if (next.buffer != Duration.zero) _buffer.add(next.buffer);
    if (previous.videoParams.dw != next.videoParams.dw ||
        previous.videoParams.dh != next.videoParams.dh) {
      _videoParams.add(next.videoParams);
    }
    if (value.hasError && value.errorDescription != null) {
      _error.add(value.errorDescription!);
    }
  }

  @override
  Future<void> open(
    String url, {
    Map<String, String>? headers,
    Duration? start,
    bool play = true,
  }) async {
    await _closeController();
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      httpHeaders: headers ?? const {},
    );
    _controller = controller;
    _revision.value++;
    try {
      await controller.initialize();
    } catch (error) {
      if (!_disposed) _error.add(error.toString());
      rethrow;
    }
    if (_disposed || !identical(_controller, controller)) return;
    if (start != null && start > Duration.zero) {
      await controller.seekTo(start);
    }
    if (play) await controller.play();
    _watch = () => _publish(controller.value);
    controller.addListener(_watch!);
    _publish(controller.value);
  }

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> playOrPause() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  @override
  Future<void> stop() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.pause();
    await controller.seekTo(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) async => _controller?.seekTo(position);

  @override
  Future<void> setRate(double rate) async =>
      _controller?.setPlaybackSpeed(rate);

  @override
  Future<void> setVolume(double volume) async =>
      _controller?.setVolume((volume / 100).clamp(0, 1).toDouble());

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _closeController();
    await _playing.close();
    await _completed.close();
    await _position.close();
    await _duration.close();
    await _buffering.close();
    await _buffer.close();
    await _rate.close();
    await _volume.close();
    await _error.close();
    await _videoParams.close();
    _revision.dispose();
  }

  Future<void> _closeController() async {
    final watch = _watch;
    final controller = _controller;
    _watch = null;
    _controller = null;
    _state = const AppPlayerState();
    if (controller != null) {
      if (watch != null) controller.removeListener(watch);
      await controller.dispose();
    }
  }

  @override
  bool get supportsOutputSize => false;

  @override
  Future<void> setOutputSize({required int width, required int height}) async {}

  @override
  Widget buildVideo() => ValueListenableBuilder<int>(
    valueListenable: _revision,
    builder: (context, _, _) {
      final controller = _active;
      if (controller == null || !controller.value.isInitialized) {
        return const ColoredBox(color: Colors.black);
      }
      final size = controller.value.size;
      final width = size.width > 0 ? size.width : 16.0;
      final height = size.height > 0 ? size.height : 9.0;
      // 外层的 OverflowBox 已经把画面尺寸算好，这里按 stretch 铺满，
      // 与 media_kit 的 BoxFit.fill 行为保持一致。
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fill,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: width,
            height: height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    },
  );
}
