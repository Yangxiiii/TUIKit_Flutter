import { common } from '@kit.AbilityKit';
import {
  DeviceStore, CallParticipantInfo, CallInfo, DeviceState,
  CallMediaType, AudioRoute,
} from '@tencentcloud/atomicxcore';
import { CallView } from './component/CallView/CallView';
import { CallKitBundle } from '../common/CallKitBundle';
import { ViewStateClass } from '../state/ViewState';
import { PipManager, PipState } from '../manager/PipManager';
import { Logger } from '../common/utils/Logger';
import { Permission } from '../common/utils/Permission';

/** 原生回退页面负责权限和首次媒体准备，镜头方向由当前通话共享。 */
@Component
export struct CallMainPage {
  @ObjectLink viewState: ViewStateClass;
  @ObjectLink callState_activeCall: CallInfo;
  @ObjectLink callState_selfInfo: CallParticipantInfo;
  @ObjectLink callState_allParticipants: CallParticipantInfo[];
  @ObjectLink deviceState: DeviceState;

  /** True while the host ability is in system PiP. Hides the top action bar. */

  /* 当主能力在系统 PiP 时为 true。隐藏顶部操作栏。 */
  @State private isInPipMode: boolean = false;

  private pipUnsubscribe: (() => void) | null = null;

  aboutToAppear(): void {
    this.pipUnsubscribe = PipManager().onStateChange((state: PipState): void => {
      this.isInPipMode = state === PipState.started || state === PipState.starting;
    });
    this.bootstrapMediaForCall();
  }

  aboutToDisappear(): void {
    if (this.pipUnsubscribe !== null) {
      this.pipUnsubscribe();
      this.pipUnsubscribe = null;
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      CallView({
        viewState: this.viewState,
        callState_activeCall: this.callState_activeCall,
        callState_selfInfo: this.callState_selfInfo,
        callState_allParticipants: this.callState_allParticipants,
        deviceState: this.deviceState,
      });

      if (!this.isInPipMode && this.isChatGroupCall()) {
        Image(CallKitBundle.imageMap('icon_add_user'))
          .width(24)
          .height(24)
          .position({ x: 'calc(100% - 44vp)', y: this.viewState.statusBarHeight + 20 })
          .onClick((): void => {
          });
      }
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }

  private isGroupCall(): boolean {
    // Aligned with iOS CallView.swift:73.
    //
    // 与 iOS 的 CallView.swift:73 对齐。
    return (this.callState_activeCall.chatGroupId?.length ?? 0) > 0
      || (this.callState_activeCall.inviteeIds?.length ?? 0) > 1;
  }

  /**
   * Stricter than isGroupCall(): only true when this call is bound to an IM
   * group (has chatGroupId). iOS CallMainView.swift:36 hides the invite
   * button for ad-hoc multi-party calls without a group.
   *
   * 比 isGroupCall() 更严格：只有当该通话绑定到 IM 群组（有 chatGroupId）时才为 true。iOS CallMainView.swift:36
   * 会隐藏临时多方通话的邀请按钮，如果没有群组的话。
   */
  private isChatGroupCall(): boolean {
    return (this.callState_activeCall.chatGroupId?.length ?? 0) > 0;
  }

  /**
   * 进入通话页面时检查权限并设置音频路由，视频按本场镜头方向启动预览。
   * 媒体启动失败时继续显示页面，用户仍可通过通话控件重试。
   */
  private bootstrapMediaForCall(): void {
    const mediaType = this.callState_activeCall.mediaType;
    if (mediaType !== CallMediaType.audio && mediaType !== CallMediaType.video) {
      Logger.warn('CallMainPage.bootstrapMediaForCall: no media type, skipping');
      return;
    }

    let context: common.UIAbilityContext;
    try {
      context = getContext(this) as common.UIAbilityContext;
    } catch (e) {
      Logger.error('CallMainPage.bootstrapMediaForCall: getContext failed', e);
      return;
    }

    Permission.hasPermission(context, mediaType)
      .then((granted: boolean): void => {
        if (!granted) {
          Logger.warn('CallMainPage: call permission denied, aborting media bootstrap');
          return;
        }

        DeviceStore.shared().setAudioRoute(
          mediaType === CallMediaType.video ? AudioRoute.speakerphone : AudioRoute.earpiece,
        );

        DeviceStore.shared().openLocalMicrophone().catch((err: Object): void => {
          Logger.warn('CallMainPage: openLocalMicrophone failed', err);
        });

        if (mediaType === CallMediaType.video) {
          DeviceStore.shared().openLocalCamera(this.viewState.isFrontCamera).catch((err: Object): void => {
            Logger.warn('CallMainPage: openLocalCamera failed', err);
          });
        }
      })
      .catch((e: Object): void => {
        Logger.error('CallMainPage.bootstrapMediaForCall: hasPermission threw', e);
      });
  }
}
