import {
  PlatformView, PlatformViewFactory, StandardMessageCodec,
} from '@ohos/flutter_ohos';
import { Params } from '@ohos/flutter_ohos/src/main/ets/plugin/platform/PlatformView';
import {
  CallCoreController, CallCoreView, CallLayoutTemplate, CallParticipantInfo,
  CallState, CallStore, DeviceState, DeviceStore,
} from '@tencentcloud/atomicxcore';
// 当前鸿蒙 SDK 没有公开单路视频槽，从同一 SDK 复用组合视图所用的组件。
import { CallParticipantView } from '@tencentcloud/atomicxcore/src/main/ets/impl/view/call/CallParticipantView';

export const HARMONY_VIDEO_VIEW: string = 'oa.harmony.call.video';

/** 等待接听时用腾讯视图显示本机预览，资料和操作由 Flutter 绘制。 */
@Component
struct HarmonyVideoSurface {
  private controller: CallCoreController = new CallCoreController();

  aboutToAppear(): void {
    this.controller.setDefaultAvatar($r('app.media.default_participant_icon'));
    // 接通时 Flutter 改用两个独立视频槽，预览无需再切换原生布局。
    this.controller.setLayoutTemplate(CallLayoutTemplate.pip);
  }

  build() {
    Stack() {
      CallCoreView({ controller: this.controller }).width('100%').height('100%');
    }
    .width('100%')
    .height('100%');
  }
}

@Builder
function buildVideo(params: Params) {
  if ((params.platformView as HarmonyVideoView).userId.length > 0) {
    HarmonyParticipantSurface({ userId: (params.platformView as HarmonyVideoView).userId });
  } else {
    HarmonyVideoSurface();
  }
}

/** 通话接通后为指定用户保留腾讯视频槽，头像与画面位置由 Flutter 管理。 */
@Component
struct HarmonyParticipantSurface {
  /** 创建参数指定对应的参与者，关闭摄像头时保持同一个槽位。 */
  userId: string = '';

  @State private callState: CallState = CallStore.shared().state;
  @State private selfInfo: CallParticipantInfo = CallStore.shared().state.selfInfo;
  @State private deviceState: DeviceState = DeviceStore.shared().state;

  /** 原生订阅绑定 SDK 当前会话中的真实参与者对象。 */
  private findParticipant(): CallParticipantInfo | undefined {
    if (this.userId === this.selfInfo.id) return this.selfInfo;
    return this.callState.allParticipants.find((participant: CallParticipantInfo) => participant.id === this.userId);
  }

  build() {
    Stack() {
      // 由腾讯视频槽管理原生表面的绑定与释放，避免旧视图释放时取消新订阅。
      if (this.findParticipant() !== undefined) {
        CallParticipantView({
          participant: this.findParticipant()!,
          callState: this.callState,
          selfInfo: this.selfInfo,
          deviceState: this.deviceState,
          isLocal: this.userId === this.selfInfo.id,
          isShowAvatar: false,
          showName: false,
          showStatusIcons: false,
        }).width('100%').height('100%');
      }
    }.width('100%').height('100%');
  }
}

/** 将腾讯组合视图或指定参与者的视频嵌入 Flutter。 */
class HarmonyVideoView extends PlatformView {
  /** 空标识代表组合视图，单路模式仅绑定指定参与者。 */
  readonly userId: string;

  constructor(userId: string) {
    super();
    this.userId = userId;
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

  /** Flutter 以字符串指定单路参与者，组合视图沿用原来的空参数。 */
  create(_context: Context, _viewId: number, args: ESObject): PlatformView {
    return new HarmonyVideoView(typeof args === 'string' ? args as string : '');
  }
}
