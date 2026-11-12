import '../platform_target.dart';
import 'app_player.dart';
import 'media_kit_player.dart';
import 'system_player.dart';

/// 按平台挑播放器后端：鸿蒙走系统 AVPlayer，其余走 media_kit。
AppPlayer createAppPlayer() =>
    useSystemPlayer ? SystemPlayer() : MediaKitPlayer();
