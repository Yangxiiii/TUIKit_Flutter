import { common } from '@kit.AbilityKit';
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
import { CallMediaType, LoginStore } from '@tencentcloud/atomicxcore';
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
  /** Flutter 可展示单聊后才接管，卸载引擎时释放对窗口的引用。 */
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
      case 'harmonyPresentationReady': {
        const channel = this.presentationChannel;
        if (channel === null) {
          result.error('NO_CHANNEL', 'Flutter 通道尚未就绪', null);
          return;
        }
        if (this.presentation === null) {
          const presentation = new FlutterCallPresentation(channel, context);
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
      default:
        result.notImplemented();
    }
  }

  /** 引擎或 Ability 离开后清除单聊接管，原生窗口仍可处理后续通话。 */
  private detachPresentation(): void {
    if (this.presentation !== null) {
      RouterManager.bindFlutterPresenter(null);
      this.presentation = null;
    }
  }

  private login(call: MethodCall, context: common.UIAbilityContext, result: MethodResult): void {
    const sdkAppId = call.argument('sdkAppId') as number;
    const userId = call.argument('userId') as string;
    const userSig = call.argument('userSig') as string;
    LoginStore.shared().login(sdkAppId, userId, userSig, context)
      .then((): void => result.success(null))
      .catch((error: Error): void => result.error('LOGIN_FAILED', error.message, null));
  }

  private calls(call: MethodCall, context: common.UIAbilityContext, result: MethodResult): void {
    const userIds = call.argument('userIds') as string[];
    const mediaType = call.argument('mediaType') === 'video'
      ? CallMediaType.video
      : CallMediaType.audio;
    TUICallKit.createInstance(context).calls(userIds, mediaType)
      .then((): void => result.success(null))
      .catch((error: Error): void => result.error('CALL_FAILED', error.message, null));
  }
}
