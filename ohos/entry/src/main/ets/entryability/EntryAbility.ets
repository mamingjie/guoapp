
import { FlutterAbility, FlutterEngine } from '@ohos/flutter_ohos';
import { common } from '@kit.AbilityKit';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';
import { DeviceChannel } from './DeviceChannel';

export default class EntryAbility extends FlutterAbility {
  private deviceChannel: DeviceChannel | null = null;

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // Dart 侧 duanju/device 通道（亮度、音量、横竖屏、电量、视频导出）。
    this.deviceChannel = new DeviceChannel(flutterEngine, this.context as common.UIAbilityContext);
  }
}
