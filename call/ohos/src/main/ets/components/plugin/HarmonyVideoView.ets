import {
  PlatformView, PlatformViewFactory, StandardMessageCodec,
} from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import {
  CallMediaType, CallParticipantInfo, CallParticipantStatus, CallState, CallStore,
  DeviceState, DeviceStatus, DeviceStore,
} from '@tencentcloud/atomicxcore';
import { CallVideoManager } from '@tencentcloud/atomicxcore/src/main/ets/impl/view/call/CallVideoManager';
import { EngineBridge } from '@tencentcloud/atomicxcore/src/main/ets/engine/EngineBridge';
import { Logger } from '../../common/utils/Logger';
import { ViewState } from '../../state/ViewState';

export const HARMONY_VIDEO_VIEW: string = 'oa.harmony.call.video';

@Builder
function buildVideo(params: Params) {
  HarmonyParticipantSurface({
    userId: (params.platformView as HarmonyVideoView).userId,
    viewName: (params.platformView as HarmonyVideoView).viewName,
  });
}

/** 从当前通话查找真实成员，Flutter 视频槽和原生等待预览共用渲染绑定。 */
@Component
export struct HarmonyParticipantSurface {
  /** 创建参数指定绑定的真实参与者。 */
  userId: string = '';
  /** 每个视图独享一个腾讯渲染目标。 */
  viewName: string = '';

  /** 从 SDK 的当前通话读取成员，避免绑定上一通残留的用户。 */
  @State private callState: CallState = CallStore.shared().state;
  /** 本机镜头开关由 SDK 提供，以实际采集状态决定是否绑定。 */
  @State private deviceState: DeviceState = DeviceStore.shared().state;

  /** 原生订阅绑定 SDK 当前会话中的真实参与者对象。 */
  private findParticipant(): CallParticipantInfo | undefined {
    if (this.userId.length === 0) return undefined;
    const self = this.callState.selfInfo;
    if (this.userId === self.id) return self;
    return this.callState.allParticipants.find((participant: CallParticipantInfo) => participant.id === this.userId);
  }

  build() {
    Stack() {
      if (this.findParticipant() !== undefined) {
        HarmonyCallTexture({
          participant: this.findParticipant()!,
          deviceState: this.deviceState,
          isLocal: this.userId === this.callState.selfInfo.id,
          viewName: this.viewName,
        });
      }
    }.width('100%').height('100%');
  }
}

/** 将单路 SDK 视频绘到能随 ArkUI 节点导出至 Flutter 的纹理。 */
@Component
struct HarmonyCallTexture {
  /** 对端的摄像头状态随 SDK 成员变化更新。 */
  @ObjectLink participant: CallParticipantInfo;
  /** 本端镜头关闭时不能由视图重新启动。 */
  @ObjectLink deviceState: DeviceState;
  /** 本端使用预览，对端使用订阅。 */
  isLocal: boolean = false;
  /** SDK 以 XComponent 的标识查找渲染输出。 */
  viewName: string = '';
  /** 只释放此纹理成功接管的对端订阅。 */
  private boundRemoteId: string = '';

  build() {
    // SDK 内置视频节点使用独立的 SURFACE，Flutter 平台视图需要可合成的 TEXTURE。
    if (this.isLocal ? this.deviceState.cameraStatus === DeviceStatus.on : this.participant.isCameraOpened) {
      XComponent({ id: this.viewName, type: XComponentType.TEXTURE, libraryname: 'liteavsdk' })
        .width('100%')
        .height('100%')
        .onLoad((): void => this.bindVideo())
        .onDestroy((): void => this.unbindRemote());
    }
  }

  /** 原生节点就绪后才绑定 SDK 视频，保留用户当前选择的镜头方向。 */
  private bindVideo(): void {
    const state = CallStore.shared().state;
    if (state.activeCall.mediaType !== CallMediaType.video ||
      state.selfInfo.status === CallParticipantStatus.none) return;
    if (this.isLocal) {
      if (state.selfInfo.id !== this.participant.id || this.deviceState.cameraStatus !== DeviceStatus.on) return;
      // SDK 绑定纹理时会重新传入朝向，使用本场选择避免切换布局时翻回另一侧。
      void EngineBridge.call('DeviceModule.openLocalCamera', JSON.stringify({
        isFront: ViewState().isFrontCamera,
        view: this.viewName,
      })).catch((error: Object): void => {
        Logger.warn('Flutter video texture local bind failed', error);
      });
    } else {
      this.boundRemoteId = this.participant.id;
      CallVideoManager.shared.startRemoteView(this.boundRemoteId, this.viewName);
    }
    Logger.info('Flutter video texture attached', this.isLocal ? 'local' : 'remote');
  }

  /** 带旧目标标识退订，避免主小画面切换时取消新视图的订阅。 */
  private unbindRemote(): void {
    if (this.boundRemoteId.length === 0) return;
    CallVideoManager.shared.stopRemoteView(this.boundRemoteId, this.viewName);
    this.boundRemoteId = '';
  }
}

/** 在 Flutter 视图的生命周期内承载一个参与者的原生纹理。 */
class HarmonyVideoView extends PlatformView {
  /** 当前画面归属的 SDK 用户标识。 */
  readonly userId: string;
  /** 稳定且与 SDK 原生窗口使用的标识不重叠。 */
  readonly viewName: string;

  constructor(userId: string, viewId: number) {
    super();
    this.userId = userId;
    this.viewName = `oa_flutter_call_${viewId}`;
  }

  getView(): WrappedBuilder<[Params]> {
    return wrapBuilder(buildVideo);
  }

  dispose(): void {}
}

/** 注册 Flutter 传入的视频视图类型。 */
export class HarmonyVideoViewFactory extends PlatformViewFactory {
  constructor() {
    super(StandardMessageCodec.INSTANCE);
  }

  /** Flutter 以字符串指定单路参与者，缺少标识时不绑定媒体。 */
  create(_context: Context, viewId: number, args: ESObject): PlatformView {
    return new HarmonyVideoView(typeof args === 'string' ? args as string : '', viewId);
  }
}
