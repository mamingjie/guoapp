import {
  FlutterEngine,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import window from '@ohos.window';
import { audio } from '@kit.AudioKit';
import { batteryInfo, deviceInfo } from '@kit.BasicServicesKit';
import { bundleManager, common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import fs from '@ohos.file.fs';
import util from '@ohos.util';

/** 与 Dart 侧 lib/ui/settings/backup_actions.dart 的上限保持一致。 */
const MAX_BACKUP_BYTES = 8 * 1024 * 1024;

/**
 * Dart 侧 lib/app_device.dart 的 duanju/device 通道在鸿蒙上的实现。
 *
 * 语义与 Android 的 MainActivity 保持一致：亮度、音量用 0..1 的比例值，
 * 播放器横竖屏用 PlayerOrientation 的字符串。
 */
export class DeviceChannel implements MethodCallHandler {
  private channel: MethodChannel;
  private context: common.UIAbilityContext;
  private televisionMode = false;

  constructor(engine: FlutterEngine, context: common.UIAbilityContext) {
    this.context = context;
    this.channel = new MethodChannel(
      engine.getDartExecutor().getBinaryMessenger(),
      'duanju/device',
    );
    this.channel.setMethodCallHandler(this);
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'deviceInfo':
        this.deviceInfo(result);
        break;
      case 'compatibleRendering':
        // 鸿蒙没有 Android 那套兼容渲染开关，统一当作未启用。
        result.success(false);
        break;
      case 'setCompatibleRendering':
        result.success(null);
        break;
      case 'setTelevisionMode':
        this.setTelevisionMode(call.argument('enabled') as boolean | undefined, result);
        break;
      case 'setPlayerOrientation':
        this.setPlayerOrientation(call.argument('mode') as string, result);
        break;
      case 'getBrightness':
        this.getBrightness(result);
        break;
      case 'setBrightness':
        this.setBrightness(call.argument('brightness') as number, result);
        break;
      case 'resetBrightness':
        this.setWindowBrightness(-1, result);
        break;
      case 'volume':
        this.getVolume(result);
        break;
      case 'setVolume':
        this.setVolume(call.argument('volume') as number, result);
        break;
      case 'battery':
        this.battery(result);
        break;
      case 'requestVideoExport':
        // 导出走系统保存界面，不需要申请存储权限。
        result.success(true);
        break;
      case 'exportVideo':
        this.exportVideo(
          call.argument('source') as string,
          call.argument('name') as string,
          result,
        );
        break;
      case 'createDocument':
        this.createDocument(call.argument('name') as string, result);
        break;
      case 'deleteDocument':
        this.deleteDocument(call.argument('uri') as string, result);
        break;
      case 'saveTextFile':
        this.saveTextFile(
          call.argument('name') as string,
          call.argument('content') as string,
          result,
        );
        break;
      case 'pickTextFile':
        this.pickTextFile(call.argument('extensions') as string, result);
        break;
      default:
        result.notImplemented();
        break;
    }
  }

  private deviceInfo(result: MethodResult): void {
    let version = '';
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT,
      );
      version = info.versionName;
    } catch (error) {
      version = '';
    }
    const payload = new Map<string, Object>();
    payload.set('television', deviceInfo.deviceType === 'tv');
    payload.set('version', version);
    result.success(payload);
  }

  private async mainWindow(): Promise<window.Window | null> {
    try {
      return await window.getLastWindow(this.context);
    } catch (error) {
      return null;
    }
  }

  /** 与 Android 的 MainActivity 一致：开启电视模式锁横屏，关闭恢复自动；状态没变则不动。 */
  private async setTelevisionMode(enabled: boolean | undefined, result: MethodResult): Promise<void> {
    if (enabled === undefined || enabled === null) {
      result.error('invalid_display_mode', '缺少电视模式状态', null);
      return;
    }
    const changed = this.televisionMode !== enabled;
    this.televisionMode = enabled;
    if (!enabled && !changed) {
      result.success(null);
      return;
    }
    await this.setPlayerOrientation(enabled ? 'landscape' : 'auto', result);
  }

  private async setPlayerOrientation(mode: string, result: MethodResult): Promise<void> {
    let orientation: window.Orientation = window.Orientation.AUTO_ROTATION_UNSPECIFIED;
    switch (mode) {
      case 'landscape':
      case 'lockedLandscape':
        orientation = window.Orientation.AUTO_ROTATION_LANDSCAPE;
        break;
      case 'portrait':
        orientation = window.Orientation.AUTO_ROTATION_PORTRAIT;
        break;
      case 'lockedPortrait':
        orientation = window.Orientation.PORTRAIT;
        break;
      default:
        orientation = window.Orientation.AUTO_ROTATION_UNSPECIFIED;
        break;
    }
    try {
      const win = await this.mainWindow();
      if (win !== null) {
        await win.setPreferredOrientation(orientation);
      }
      result.success(null);
    } catch (error) {
      result.error('orientation_failed', `${error}`, null);
    }
  }

  private async getBrightness(result: MethodResult): Promise<void> {
    try {
      const win = await this.mainWindow();
      if (win === null) {
        result.success(0.5);
        return;
      }
      const properties = win.getWindowProperties();
      // -1 表示跟随系统亮度，此时回一个中性值给 UI。
      const value = properties.brightness;
      result.success(value >= 0 ? value : 0.5);
    } catch (error) {
      result.success(0.5);
    }
  }

  private async setBrightness(value: number, result: MethodResult): Promise<void> {
    if (typeof value !== 'number' || Number.isNaN(value)) {
      result.error('invalid_arg', '缺少亮度数值', null);
      return;
    }
    const clamped = Math.min(1, Math.max(0.01, value));
    await this.setWindowBrightness(clamped, result);
  }

  private async setWindowBrightness(value: number, result: MethodResult): Promise<void> {
    try {
      const win = await this.mainWindow();
      if (win !== null) {
        await win.setWindowBrightness(value);
      }
      result.success(true);
    } catch (error) {
      result.error('brightness_failed', `${error}`, null);
    }
  }

  /**
   * 音量读写走 AudioVolumeGroupManager；写操作在鸿蒙上属于受限能力，
   * 失败时静默降级（Dart 侧本身也不关心返回值）。
   */
  private async volumeGroup(): Promise<audio.AudioVolumeGroupManager> {
    const manager = audio.getAudioManager().getVolumeManager();
    return await manager.getVolumeGroupManager(audio.DEFAULT_VOLUME_GROUP_ID);
  }

  private async getVolume(result: MethodResult): Promise<void> {
    try {
      const group = await this.volumeGroup();
      const max = await group.getMaxVolume(audio.AudioVolumeType.MEDIA);
      const current = await group.getVolume(audio.AudioVolumeType.MEDIA);
      result.success(max > 0 ? current / max : null);
    } catch (error) {
      result.success(null);
    }
  }

  private async setVolume(value: number, result: MethodResult): Promise<void> {
    if (typeof value !== 'number' || Number.isNaN(value)) {
      result.error('invalid_arg', '缺少音量数值', null);
      return;
    }
    try {
      const group = await this.volumeGroup();
      const max = await group.getMaxVolume(audio.AudioVolumeType.MEDIA);
      const index = Math.round(Math.min(1, Math.max(0, value)) * max);
      await audio.getAudioManager().setVolume(audio.AudioVolumeType.MEDIA, index);
      result.success(null);
    } catch (error) {
      result.error('volume_failed', `${error}`, null);
    }
  }

  private battery(result: MethodResult): void {
    const payload = new Map<string, Object>();
    payload.set('level', Math.round(batteryInfo.batterySOC));
    payload.set(
      'charging',
      batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.ENABLE ||
        batteryInfo.chargingStatus === batteryInfo.BatteryChargeState.FULL,
    );
    result.success(payload);
  }

  /**
   * 用系统保存界面让用户选目标位置，然后把本地文件复制过去。
   * 鸿蒙保存媒体文件要么申请受限权限，要么用 picker，这里选后者。
   */
  private async exportVideo(source: string, name: string, result: MethodResult): Promise<void> {
    if (!source || !name) {
      result.error('invalid_export', '导出参数无效', null);
      return;
    }
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [name];
      const uris = await new picker.DocumentViewPicker(this.context).save(options);
      if (uris.length === 0) {
        result.error('export_cancelled', '已取消导出', null);
        return;
      }
      const target = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      try {
        const input = fs.openSync(source, fs.OpenMode.READ_ONLY);
        try {
          fs.copyFileSync(input.fd, target.fd);
        } finally {
          fs.closeSync(input);
        }
      } finally {
        fs.closeSync(target);
      }
      result.success(null);
    } catch (error) {
      result.error('export_failed', `导出失败：${error}`, null);
    }
  }

  private async createDocument(name: string, result: MethodResult): Promise<void> {
    if (!name) {
      result.error('invalid_document', '无法创建文件', null);
      return;
    }
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [name];
      const uris = await new picker.DocumentViewPicker(this.context).save(options);
      result.success(uris.length > 0 ? uris[0] : null);
    } catch (error) {
      result.error('no_document_picker', `系统没有可用的文件保存界面：${error}`, null);
    }
  }

  private deleteDocument(uri: string, result: MethodResult): void {
    if (!uri) {
      result.success(false);
      return;
    }
    try {
      fs.unlinkSync(uri);
      result.success(true);
    } catch (error) {
      result.success(false);
    }
  }

  /**
   * 用系统保存界面挑目标位置并写入文本，供「导出备份 / 导出原始配置」使用。
   * 返回 true 表示已保存，false 表示用户取消。
   */
  private async saveTextFile(name: string, content: string, result: MethodResult): Promise<void> {
    if (!name) {
      result.error('invalid_document', '无法创建备份文件', null);
      return;
    }
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [name];
      const uris = await new picker.DocumentViewPicker(this.context).save(options);
      if (uris.length === 0) {
        result.success(false);
        return;
      }
      const file = fs.openSync(
        uris[0],
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC,
      );
      try {
        fs.writeSync(file.fd, content);
      } finally {
        fs.closeSync(file);
      }
      result.success(true);
    } catch (error) {
      result.error('save_failed', `保存备份失败：${error}`, null);
    }
  }

  /**
   * 用系统文件选择器读一个文本文件，供「从备份恢复」使用。
   * extensions 是从 Dart 侧传来的逗号分隔后缀名（如 "json"）。
   */
  private async pickTextFile(extensions: string, result: MethodResult): Promise<void> {
    try {
      const options = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      if (extensions.length > 0) {
        options.fileSuffixFilters = extensions
          .split(',')
          .filter((item: string) => item.length > 0)
          .map((item: string) => `.${item}`);
      }
      const uris = await new picker.DocumentViewPicker(this.context).select(options);
      if (uris.length === 0) {
        result.success(null);
        return;
      }
      const file = fs.openSync(uris[0], fs.OpenMode.READ_ONLY);
      try {
        const size = fs.statSync(file.fd).size;
        if (size > MAX_BACKUP_BYTES) {
          result.error('too_large', '备份文件过大', null);
          return;
        }
        const buffer = new ArrayBuffer(size);
        fs.readSync(file.fd, buffer);
        const decoder = util.TextDecoder.create('utf-8');
        result.success(decoder.decodeToString(new Uint8Array(buffer)));
      } finally {
        fs.closeSync(file);
      }
    } catch (error) {
      result.error('pick_failed', `无法读取备份文件：${error}`, null);
    }
  }
}
