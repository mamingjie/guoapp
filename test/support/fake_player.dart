import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:duanju_app/player/app_player.dart';

class OpenedMedia {
  const OpenedMedia(this.uri, {this.start, this.headers});

  final String uri;
  final Duration? start;
  final Map<String, String>? headers;
}

class FakePlayer implements AppPlayer {
  @override
  AppPlayerState state = const AppPlayerState();
  final opened = <OpenedMedia>[];
  final rates = <double>[];
  final seeks = <Duration>[];
  var stops = 0;
  var disposed = false;
  final _playing = StreamController<bool>.broadcast(sync: true);
  final _completed = StreamController<bool>.broadcast(sync: true);
  final _position = StreamController<Duration>.broadcast(sync: true);
  final _duration = StreamController<Duration>.broadcast(sync: true);
  final _buffer = StreamController<Duration>.broadcast(sync: true);
  final _rate = StreamController<double>.broadcast(sync: true);
  final _volume = StreamController<double>.broadcast(sync: true);
  final _videoParams = StreamController<AppVideoParams>.broadcast(sync: true);
  final _error = StreamController<String>.broadcast(sync: true);
  final _buffering = StreamController<bool>.broadcast(sync: true);

  @override
  Object? get platform => null;

  @override
  late final AppPlayerStream stream = AppPlayerStream(
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

  void progress(Duration position, {Duration? duration}) {
    state = state.copyWith(
      position: position,
      duration: duration ?? state.duration,
    );
    if (duration != null) _duration.add(duration);
    _position.add(position);
  }

  void finish() {
    state = state.copyWith(
      position: state.duration,
      completed: true,
      playing: false,
    );
    _completed.add(true);
  }

  void fail(String message) => _error.add(message);

  void buffer(bool buffering) {
    state = state.copyWith(buffering: buffering);
    _buffering.add(buffering);
  }

  void resize(int width, int height) {
    state = state.copyWith(width: width);
    _videoParams.add(AppVideoParams(w: width, h: height));
  }

  @override
  Future<void> open(
    String url, {
    Map<String, String>? headers,
    Duration? start,
    bool play = true,
  }) async {
    opened.add(OpenedMedia(url, start: start, headers: headers));
    state = state.copyWith(
      playing: play,
      completed: false,
      position: start ?? Duration.zero,
    );
    _playing.add(play);
  }

  @override
  Future<void> stop() async {
    stops++;
    state = state.copyWith(playing: false, position: Duration.zero);
  }

  @override
  Future<void> play() async {
    state = state.copyWith(playing: true);
    _playing.add(true);
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(playing: false);
    _playing.add(false);
  }

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();

  @override
  Future<void> seek(Duration duration) async {
    seeks.add(duration);
    state = state.copyWith(position: duration);
  }

  @override
  Future<void> setRate(double rate) async {
    rates.add(rate);
    state = state.copyWith(rate: rate);
    _rate.add(rate);
  }

  @override
  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
    _volume.add(volume);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Widget buildVideo() => const SizedBox.shrink();

  @override
  bool get supportsOutputSize => false;

  @override
  Future<void> setOutputSize({required int width, required int height}) async {}
}
