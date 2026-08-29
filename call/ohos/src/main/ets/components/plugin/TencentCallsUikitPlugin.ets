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

/** 在 Flutter 与 HarmonyOS 原生 TUICallKit 之间转发登录和呼叫命令。 */
export default class TencentCallsUikitPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  private context: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return 'TencentCallsUikitPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'tencent_calls_uikit');
    this.channel.setMethodCallHandler(this);
  }

  onDetachedFromEngine(_binding: FlutterPluginBinding): void {
    this.channel?.setMethodCallHandler(null);
    this.channel = null;
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.context = binding.getAbility().context;
  }

  onDetachedFromAbility(): void {
    this.context = null;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    const context = this.context;
    if (context === null) {
      result.error('NO_ABILITY', 'HarmonyOS Ability 尚未就绪', null);
      return;
    }

    switch (call.method) {
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
