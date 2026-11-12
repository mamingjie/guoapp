import '../../core_bridge.dart';
import '../../local_store.dart';
import '../../models.dart';
import '../../playback_session.dart';
import '../../player/player_factory.dart';

class PlaybackHandle {
  PlaybackHandle({
    required AppRepository repository,
    required LocalStore store,
    required DramaDetail detail,
    required int index,
    double position = 0,
    bool autoplay = true,
    bool preopen = true,
  }) {
    final main = createAppPlayer();
    final standby = preopen ? createAppPlayer() : null;
    session = PlaybackSession(
      repository: repository,
      store: store,
      detail: detail,
      player: main,
      standby: standby,
      index: index,
      position: position,
      autoplay: autoplay,
    );
  }

  late final PlaybackSession session;

  void dispose() => session.dispose();
}
