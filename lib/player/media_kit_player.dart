import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'app_player.dart';

/// media_kit（libmpv）后端：Android / iOS / Windows / macOS 沿用原有行为。
class MediaKitPlayer implements AppPlayer {
  MediaKitPlayer()
    : _player = Player(
        configuration: const PlayerConfiguration(
          bufferSize: 32 * 1024 * 1024,
          logLevel: MPVLogLevel.error,
        ),
      ) {
    _controller = VideoController(_player);
  }

  final Player _player;
  late final VideoController _controller;

  AppVideoParams _params(VideoParams params) => AppVideoParams(
    w: params.w,
    h: params.h,
    dw: params.dw,
    dh: params.dh,
    rotate: params.rotate,
  );

  @override
  AppPlayerState get state {
    final current = _player.state;
    return AppPlayerState(
      playing: current.playing,
      buffering: current.buffering,
      completed: current.completed,
      position: current.position,
      duration: current.duration,
      buffer: current.buffer,
      volume: current.volume,
      rate: current.rate,
      width: current.width,
      videoParams: _params(current.videoParams),
    );
  }

  @override
  AppPlayerStream get stream {
    final events = _player.stream;
    return AppPlayerStream(
      playing: events.playing,
      completed: events.completed,
      position: events.position,
      duration: events.duration,
      buffering: events.buffering,
      buffer: events.buffer,
      rate: events.rate,
      volume: events.volume,
      error: events.error,
      videoParams: events.videoParams.map(_params),
    );
  }

  @override
  Object? get platform => _player.platform;

  @override
  Future<void> open(
    String url, {
    Map<String, String>? headers,
    Duration? start,
    bool play = true,
  }) => _player.open(
    Media(url, httpHeaders: headers, start: start),
    play: play,
  );

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setRate(double rate) => _player.setRate(rate);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();

  @override
  Widget buildVideo() => Video(
    controller: _controller,
    controls: NoVideoControls,
    fill: Colors.black,
    fit: BoxFit.fill,
    pauseUponEnteringBackgroundMode: false,
  );

  @override
  bool get supportsOutputSize => true;

  @override
  Future<void> setOutputSize({required int width, required int height}) =>
      _controller.setSize(width: width, height: height);
}
