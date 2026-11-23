import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import AlbumPicker from '../../albumpicker/AlbumPicker';
import Device from '../../device_info/Device';
import Permission from '../../permission/Permission';

/// 注册设备、权限和相册通道，并将 Flutter 引擎与宿主窗口的生命周期转交给子模块。
export default class AtomicXPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private device: Device | null = null;
  private permission: Permission | null = null;
  private albumPicker: AlbumPicker | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return 'AtomicXPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'tuikit_atomic_x');
    this.channel.setMethodCallHandler(this);

    this.device = new Device(binding);
    this.permission = new Permission(binding);
    this.albumPicker = new AlbumPicker(binding);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.device?.dispose();
    this.device = null;
    this.permission?.dispose();
    this.permission = null;
    this.albumPicker?.dispose();
    this.albumPicker = null;

    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  // 权限和相册只使用所属 Ability，相册借此在正确的主窗口挂载界面。
  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.permission?.onAttachedToAbility(binding);
    this.albumPicker?.onAttachedToAbility(binding);
  }

  onDetachedFromAbility(): void {
    this.albumPicker?.onDetachedFromAbility();
    this.permission?.onDetachedFromAbility();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    result.notImplemented();
  }
}
