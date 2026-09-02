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
   * One-shot bootstrap on entering the call page:
   *   1) Permission check + auto-reject (callee path) on denial.
   *   2) Default audio route (video → speakerphone, audio → earpiece).
   *   3) Open mic + (if video) front camera.
   *
   * Fire-and-forget: any failure is logged but the page still renders so the
   * user can retry / open Settings via the in-call buttons.
   *
   * 进入通话页面的一次性初始化：1) 权限检查 + 拒绝时自动拒接（被叫路径）。2) 默认音频路由（视频 → 扬声器，音频 → 听筒）。3) 打开麦克风 + （如果有视频）前置摄像头。
   *
   * 即发即忘：任何失败都会被记录，但页面仍会渲染，所以用户可以重试或通过通话中的按钮打开设置。
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
          DeviceStore.shared().openLocalCamera(true).catch((err: Object): void => {
            Logger.warn('CallMainPage: openLocalCamera failed', err);
          });
        }
      })
      .catch((e: Object): void => {
        Logger.error('CallMainPage.bootstrapMediaForCall: hasPermission threw', e);
      });
  }
}
