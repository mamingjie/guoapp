import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../playback_preferences.dart';
import '../../playback_session.dart';
import '../../player/app_player.dart';

class PlayerVideo extends StatelessWidget {
  const PlayerVideo({
    super.key,
    required this.player,
    this.fit = VideoFit.auto,
  });
  final AppPlayer player;
  final VideoFit fit;

  @override
  Widget build(BuildContext context) {
    final video = player.buildVideo();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return ColoredBox(
      color: Colors.black,
      child: StreamBuilder(
        stream: player.stream.videoParams,
        initialData: player.state.videoParams,
        builder: (context, snapshot) => LayoutBuilder(
          builder: (context, constraints) {
            final box = constraints.biggest;
            final source = videoDisplaySize(
              snapshot.data ?? AppVideoParams.none,
            );
            final size = source == null || !box.isFinite || box.isEmpty
                ? box
                : fit.size(box, source, ratio);
            final sized = ClipRect(
              child: OverflowBox(
                minWidth: size.width,
                maxWidth: size.width,
                minHeight: size.height,
                maxHeight: size.height,
                child: video,
              ),
            );
            final output = size * ratio;
            if (!player.supportsOutputSize ||
                !output.isFinite ||
                output.isEmpty) {
              return sized;
            }
            return _OutputSize(player: player, box: output, child: sized);
          },
        ),
      ),
    );
  }
}

class _OutputSize extends StatefulWidget {
  const _OutputSize({
    required this.player,
    required this.box,
    required this.child,
  });
  final AppPlayer player;
  final Size box;
  final Widget child;

  @override
  State<_OutputSize> createState() => _OutputSizeState();
}

class _OutputSizeState extends State<_OutputSize> {
  @override
  void initState() {
    super.initState();
    _VideoOutput.request(widget.player, this, widget.box);
  }

  @override
  void didUpdateWidget(_OutputSize oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      _VideoOutput.release(oldWidget.player, this);
    }
    if (oldWidget.player != widget.player || oldWidget.box != widget.box) {
      _VideoOutput.request(widget.player, this, widget.box);
    }
  }

  @override
  void dispose() {
    _VideoOutput.release(widget.player, this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _VideoOutput {
  _VideoOutput(this.player) {
    _subscription = player.stream.videoParams.listen((_) => _schedule());
  }

  static final _outputs = <AppPlayer, _VideoOutput>{};

  static void request(AppPlayer player, Object owner, Size box) {
    final output = _outputs[player] ??= _VideoOutput(player);
    output._boxes[owner] = box;
    output._schedule();
  }

  static void release(AppPlayer player, Object owner) {
    final output = _outputs[player];
    if (output == null) return;
    output._boxes.remove(owner);
    if (output._boxes.isNotEmpty) return;
    output._timer?.cancel();
    unawaited(output._subscription.cancel());
    _outputs.remove(player);
  }

  final AppPlayer player;
  final _boxes = <Object, Size>{};
  late final StreamSubscription<AppVideoParams> _subscription;
  Timer? _timer;

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), _apply);
  }

  void _apply() {
    final params = player.state.videoParams;
    final width = params.dw ?? params.w ?? 0;
    final height = params.dh ?? params.h ?? 0;
    if (width <= 0 || height <= 0 || _boxes.isEmpty) return;
    final scale = math.min(
      1.0,
      _boxes.values
          .map((box) => math.max(box.width / width, box.height / height))
          .reduce(math.max),
    );
    unawaited(
      player
          .setOutputSize(
            width: math.max(1, (width * scale).round()),
            height: math.max(1, (height * scale).round()),
          )
          .catchError((Object _) {}),
    );
  }
}
