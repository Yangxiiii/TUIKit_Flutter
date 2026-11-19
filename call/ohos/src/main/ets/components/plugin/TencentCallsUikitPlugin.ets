import { common } from '@kit.AbilityKit';
import { camera } from '@kit.CameraKit';
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
import { CallMediaType, CallParams, CloudRecordPolicy, LoginStore } from '@tencentcloud/atomicxcore';
import { TUICallKit } from '../../TUICallKit';
import { RouterManager } from '../../manager/RouterManager';
import { Logger } from '../../common/utils/Logger';
import { FlutterCallPresentation } from './FlutterCallPresentation';
import { HarmonyVideoViewFactory, HARMONY_VIDEO_VIEW } from './HarmonyVideoView';

/** 在 Flutter 与 HarmonyOS 原生 TUICallKit 之间转发登录和呼叫命令。 */
export default class TencentCallsUikitPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  /** 独立于腾讯通用方法通道，避免 Flutter 侧通话事件监听被覆盖。 */
  private presentationChannel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;
  /** Flutter 可展示通话后才接管，卸载引擎时释放对窗口的引用。 */
  private presentation: FlutterCallPresentation | null = null;

  getUniqueClassName(): string {
    return 'TencentCallsUikitPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'tencent_calls_uikit');
    this.channel.setMethodCallHandler(this);
    this.presentationChannel = new MethodChannel(binding.getBinaryMessenger(), 'tencent_calls_uikit/harmony_presentation');
    this.presentationChannel.setMethodCallHandler(this);
    binding.getPlatformViewRegistry().registerViewFactory(HARMONY_VIDEO_VIEW, new HarmonyVideoViewFactory());
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.detachPresentation();
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
    this.presentationChannel?.setMethodCallHandler(null);
    this.presentationChannel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.detachPresentation();
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const context = this.context;
    if (context === null) {
      result.error('NO_ABILITY', 'HarmonyOS Ability 尚未就绪', null);
      return;
    }

    switch (call.method) {
      case 'getCameraCount': {
        try {
          // 仅统计前后朝向，不能把同侧多枚摄像头当作支持翻转。
          const devices = camera.getCameraManager(context).getSupportedCameras();
          const positions = new Set<camera.CameraPosition>();
          devices.forEach((device: camera.CameraDevice): void => {
            if (device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_FRONT ||
              device.cameraPosition === camera.CameraPosition.CAMERA_POSITION_BACK) {
              positions.add(device.cameraPosition);
            }
          });
          result.success(positions.size);
        } catch (_) {
          result.error('CAMERA_QUERY_FAILED', '无法读取摄像头能力', null);
        }
        return;
      }
      case 'harmonyPresentationReady': {
        const channel = this.presentationChannel;
        if (channel === null) {
          result.error('NO_CHANNEL', 'Flutter 通道尚未就绪', null);
          return;
        }
        if (this.presentation === null) {
          // 缺省值兼容尚未传入显示模式的旧宿主，保留已验证的原生窗口。
          const presentation = new FlutterCallPresentation(channel, context, call.argument('nativeVideo') !== false);
          this.presentation = presentation;
          RouterManager.bindFlutterPresenter((route): boolean => presentation.present(route));
        }
        result.success(this.presentation.snapshot());
        return;
      }
      case 'harmonyPresentationSnapshot':
        result.success(this.presentation?.snapshot() ?? null);
        return;
      case 'harmonyPresentationAction': {
        const presentation = this.presentation;
        const id = call.argument('id') as string;
        const action = call.argument('action') as string;
        if (presentation === null || typeof id !== 'string' || typeof action !== 'string') {
          result.error('CALL_ACTION_UNAVAILABLE', '当前通话操作不可用', null);
          return;
        }
        void presentation.action(id, action)
          .then((): void => result.success(null))
          .catch((error: Error): void => {
            Logger.warn('Flutter call action failed:', action, error);
            result.error('CALL_ACTION_FAILED', error.message, null);
          });
        return;
      }
      case 'harmonyPresentationGroupDevice': {
        const presentation = this.presentation;
        const id = call.argument('id') as string;
        const callId = call.argument('callId') as string;
        const device = call.argument('device') as string;
        const enabled = call.argument('enabled') as boolean | null;
        // 省略目标状态时只申请权限，申请失败或参数异常都不会开启设备。
        if (presentation === null || typeof id !== 'string' || typeof callId !== 'string' ||
          (device !== 'microphone' && device !== 'camera') || (enabled != null && typeof enabled !== 'boolean')) {
          result.error('CALL_ACTION_UNAVAILABLE', '当前通话操作不可用', null);
          return;
        }
        void presentation.groupDevice(id, callId, device, enabled ?? null)
          .then((submitted: boolean): void => result.success(submitted))
          .catch((error: Error): void => result.error('CALL_ACTION_FAILED', error.message, null));
        return;
      }
      case 'harmonyLogin':
        this.login(call, context, result);
        return;
      case 'harmonyLogout':
        LoginStore.shared().logout()
          .then((): void => result.success(null))
          .catch((error: Error): void => result.error('LOGOUT_FAILED', error.message, null));
        return;
      case 'harmonyCalls':
        this.calls(call, context, result);
        return;
      case 'harmonyJoin':
        this.join(call, context, result);
        return;
      default:
        result.notImplemented();
    }
  }

  /** 引擎或 Ability 离开后清除 Flutter 接管，后续由原生窗口处理通话。 */
  private detachPresentation(): void {
    if (this.presentation !== null) {
      RouterManager.bindFlutterPresenter(null);
      this.presentation = null;
    }
  }

  /** 同步原生通话登录态，使 IM 上传和 Flutter 相册共用应用级缓存。 */
  private login(call: MethodCall, context: common.UIAbilityContext, result: MethodResult): void {
    const sdkAppId = call.argument('sdkAppId') as number;
    const userId = call.argument('userId') as string;
    const userSig = call.argument('userSig') as string;
    LoginStore.shared().login(sdkAppId, userId, userSig, context.getApplicationContext())
      .then((): void => result.success(null))
      .catch((error: Error): void => result.error('LOGIN_FAILED', error.message, null));
  }

  /** 把 Flutter 通话参数交给原生 CallKit，群归属必须在第一次呼叫时设置。 */
  private calls(call: MethodCall, context: common.UIAbilityContext, result: MethodResult): void {
    const userIds = call.argument('userIds') as string[];
    const mediaType = call.argument('mediaType') === 'video'
      ? CallMediaType.video
      : CallMediaType.audio;
    const groupId = call.argument('chatGroupId') as string | null;
    const params = new CallParams();
    params.chatGroupId = groupId ?? '';
    params.timeout = 45;
    // 缺省参数使用原生默认值，兼容仍只传群标识的 Flutter 调用。
    params.roomId = (call.argument('roomId') as string | null) ?? '';
    params.userData = (call.argument('userData') as string | null) ?? '';
    params.isEphemeralCall = call.argument('isEphemeralCall') === true;
    params.offlinePushTitle = (call.argument('offlinePushTitle') as string | null) ?? '';
    params.offlinePushDescription = (call.argument('offlinePushDescription') as string | null) ?? '';
    const policy = call.argument('cloudRecordPolicy') as string | null;
    if (policy === 'enable') {
      params.cloudRecordPolicy = CloudRecordPolicy.enable;
    } else if (policy === 'disable') {
      params.cloudRecordPolicy = CloudRecordPolicy.disable;
    }
    TUICallKit.createInstance(context).calls(userIds, mediaType, params)
      .then((): void => result.success(null))
      .catch((error: Error): void => result.error('CALL_FAILED', error.message, null));
  }

  /** 仅转发真实 callId，原生 SDK 决定加入资格；错误必须返回 Flutter 供用户重试。 */
  private join(call: MethodCall, context: common.UIAbilityContext, result: MethodResult): void {
    const callId = call.argument('callId') as string;
    const media = call.argument('mediaType') as string;
    if (typeof callId !== 'string' || (media != null && media !== 'audio' && media !== 'video')) {
      result.error('INVALID_ARGUMENT', '通话场次或媒体类型无效', null);
      return;
    }
    // 兼容只传 callId 的调用。未知媒体时先申请麦克风，摄像头按原生页面读到的实际类型申请。
    const mediaType = media === 'video' ? CallMediaType.video : CallMediaType.audio;
    TUICallKit.createInstance(context).join(callId, mediaType)
      .then((): void => result.success(null))
      .catch((error: Error): void => result.error('JOIN_FAILED', error.message, null));
  }
}
