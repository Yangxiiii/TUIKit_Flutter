// Bottom controls panel for 1-on-1 calls. Layout mirrors Flutter
// SingleCallControlsWidget exactly:
//
//   Flutter Positioned wrapping:    bottom: 40 + safeArea.bottom
//   Flutter inner layout:           Row(spaceEvenly) [+ Column for video]
//
// This view ports the same flow-based layout to ArkUI: a single Column
// with `padding.bottom = 40` plus inner Row(s) using
// `justifyContent(SpaceEvenly)`. The system nav-bar inset is added by
// the PARENT (CallView's controls Column), so this view only handles
// the Flutter literal `40` baseline.
//
// Five layouts (matching Flutter `_viewStrategies`):
//   - audio_waiting_caller: mic / hangup(cancel) / speaker
//   - audio_waiting_called: reject / accept
//   - audio_accept:         mic / hangup / speaker
//   - video_waiting_caller: switchCamera / hangup(cancel) / camera
//   - video_waiting_called: reject / accept
//   - video_accept:         row1 [mic / speaker / camera] + row2 [_, hangup, switchCamera-small]
//
// 1 对 1 通话的底部控制面板。布局完全镜像 Flutter 的 SingleCallControlsWidget：
//
// Flutter Positioned 包裹：bottom: 40 + safeArea.bottom  Flutter 内部布局：Row(spaceEvenly) [+ Column 用于视频]
//
// 这个视图将相同的基于流的布局移植到 ArkUI：一个单独的 Column
//
// `justifyContent(SpaceEvenly)`。系统导航栏的 inset 由 PARENT（CallView 的 controls Column）添加，所以此视图只处理 Flutter
// 字面上的 `40` 基线。
//
// 五种布局（对应 Flutter 的 `_viewStrategies`）：- audio_waiting_caller：麦克风 / 挂断（取消） / 扬声器-
// audio_waiting_called：拒接 / 接听- audio_accept：麦克风 / 挂断 / 扬声器- video_waiting_caller：切换摄像头 / 挂断（取消） /
// 摄像头- video_waiting_called：拒接 / 接听- video_accept：第一行 [麦克风 / 扬声器 / 摄像头] + 第二行 [_, 挂断, 小切换摄像头]

import {
  CallStore, DeviceStore, CallParticipantInfo, DeviceState, CallMediaType,
  CallParticipantStatus, DeviceStatus,
} from '@tencentcloud/atomicxcore';
import { ControlsButton } from '../../../../common/widgets/ControlsButton';
import { CallViewAudioRoutePicker } from './audioRoutePicker/CallViewAudioRoutePicker';
import { CallKitBundle } from '../../../../common/CallKitBundle';
import { TUICallKitLocalize } from '../../../../common/Localized';
import { CallConstants } from '../../../../common/CallConstants';
import { Constants } from '../../../../common/Constants';
import { Logger } from '../../../../common/utils/Logger';
import { CallEndedFlag } from '../../../../state/CallEndedFlag';
import { CallingBellFeature } from '../../../../feature/CallingBellFeature';
import { CallingVibratorFeature } from '../../../../feature/CallingVibratorFeature';

enum Layout {
  calleeWaiting = 0,        // accept + reject
  audio = 1,                // mic + hangup + speaker
  videoWaitingCaller = 2,   // switchCamera + hangup(cancel) + camera
  videoAccept = 3,          // mic/speaker/camera + hangup + switchCameraSmall
}

/** Big button image (60vp) — matches Flutter `imgHeight: 60`. */

/* 大按钮图片（60vp）— 对应 Flutter 的 `imgHeight: 60`。 */
const BTN_LARGE: number = 60;
/** Small button image (28vp) — matches Flutter switchCameraSmall `imgHeight: 28`. */

/* 小按钮图片（28vp）— 对应 Flutter 的 switchCameraSmall `imgHeight: 28`。 */
const BTN_SMALL: number = 28;

/**
 * Bottom inset before the system nav indicator. Matches
 * `Flutter Positioned(bottom: 40 + MediaQuery.padding.bottom)`.
 *
 * 系统导航栏指示器前的底部间距。对应 `Flutter Positioned(bottom: 40 + MediaQuery.padding.bottom)`。
 */
const BOTTOM_INSET: number = 40;

/** Vertical gap between the primary row and the hangup row in video_accept. */

/* video_accept 中主行和挂断行之间的垂直间距。 */
const ROW_GAP: number = 20;

@Component
export struct SingleCallControlsView {
  @ObjectLink selfInfo: CallParticipantInfo;
  @ObjectLink deviceState: DeviceState;
  @State mediaType: CallMediaType = CallMediaType.audio;
  isCaller: boolean = false;
  enableVirtualBackground: boolean = true;

  /**
   * Bottom safe-area inset (≈ navBarHeight). Added to BOTTOM_INSET so the
   * total bottom padding is `40 + safe`, exactly matching Flutter
   * `Positioned(bottom: 40 + MediaQuery.padding.bottom)`.
   *
   * 底部安全区域插入（≈导航栏高度）。添加到 BOTTOM_INSET，因此底部总内边距为 `40 + safe`，完全匹配 Flutter 的 `Positioned(bottom: 40 +
   * MediaQuery.padding.bottom)`。
   */
  bottomSafeInset: number = 0;

  build() {
    Column() {
      this.layoutContent();
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: BOTTOM_INSET + this.bottomSafeInset })
    .constraintSize({ maxWidth: Constants.CONTROLS_CONTAINER_MAX_WIDTH });
  }

  @Builder
  layoutContent() {
    if (this.currentLayout() === Layout.calleeWaiting) {
      this.layoutCalleeWaiting();
    } else if (this.currentLayout() === Layout.audio) {
      this.layoutAudio();
    } else if (this.currentLayout() === Layout.videoWaitingCaller) {
      this.layoutVideoWaitingCaller();
    } else {
      this.layoutVideoAccept();
    }
  }

  /** Flutter `_buildAudioAndVideoCalleeWaitingView`: Row(spaceEvenly){ reject, accept }. */

  /* Flutter `_buildAudioAndVideoCalleeWaitingView`：Row(spaceEvenly){ 拒绝, 接受 }。 */
  @Builder
  layoutCalleeWaiting() {
    Row() {
      this.declineBtn();
      this.answerBtn();
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly);
  }

  /**
   * Flutter `_buildAudioAcceptedView` and `_buildAudioCallerWaitingView`:
   * Row(spaceEvenly){ mic, hangup, speaker }. Hangup tip differs (cancel vs
   * hangup) which is handled by `hangupBtn(titleOverride)`.
   *
   * Flutter `_buildAudioAcceptedView` 和 `_buildAudioCallerWaitingView`：Row(spaceEvenly){ 麦克风, 挂断, 扬声器
   * }。挂断提示不同（取消 vs 挂断），由 `hangupBtn(titleOverride)` 处理。
   */
  @Builder
  layoutAudio() {
    Row() {
      this.muteBtn();
      this.hangupBtn(this.isWaitingCaller() ? 'cancel' : undefined);
      this.audioRoutePicker();
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly);
  }

  /** Flutter `_buildVideoCallerWaitingView`: Row(spaceEvenly){ switchCamera, hangup(cancel), camera }. */

  /* Flutter `_buildVideoCallerWaitingView`：Row(spaceEvenly){ 切换摄像头, 挂断(取消), 摄像头 }。 */
  @Builder
  layoutVideoWaitingCaller() {
    Row() {
      this.switchCameraLargeBtn();
      this.hangupBtn('cancel');
      this.cameraBtn();
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly);
  }

  /**
   * Flutter `_buildVideoCallerAndCalleeAcceptedView`:
   *   Column(start){
   *     Row(spaceEvenly){ mic, speaker, camera },
   *     SizedBox(height: 20),
   *     Row(spaceEvenly){ SizedBox(100), hangup, cameraStatus.on ? switchCameraSmall : SizedBox(100) }
   *   }
   *
   * Row(spaceEvenly){ 麦克风, 扬声器, 摄像头 }, SizedBox(height: 20), Row(spaceEvenly){ SizedBox(100), 挂断,
   * cameraStatus.on ? 小切换摄像头 : SizedBox(100) }
   */
  @Builder
  layoutVideoAccept() {
    Column() {
      Row() {
        this.muteBtn();
        this.audioRoutePicker();
        this.cameraBtn();
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly);

      // Flutter SizedBox(height: 20) between primary row and hangup row.
      //
      // Flutter 在主行和挂断行之间使用 SizedBox(height: 20)。
      Blank().height(ROW_GAP);

      Row() {
        // Left placeholder — matches Flutter `SizedBox(width: 100)`.
        //
        // 左侧占位符 — 对应 Flutter 的 `SizedBox(width: 100)`。
        Column().width(100).height(BTN_LARGE);

        this.hangupBtn('');

        // Right slot: small switch-camera when camera is on, else placeholder.
        //
        // 右侧插槽：摄像头开启时显示小型切换摄像头按钮，否则显示占位符。
        if (this.deviceState.cameraStatus === DeviceStatus.on) {
          this.switchCameraSmallBtn();
        } else {
          Column().width(100).height(BTN_LARGE);
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceEvenly);
    }
    .width('100%');
  }

  private currentLayout(): Layout {
    // Callee in waiting state — same UI for audio + video.
    //
    // 被叫处于等待状态 — 音频和视频界面一致。
    if (this.selfInfo.status === CallParticipantStatus.waiting && !this.isCaller) {
      return Layout.calleeWaiting;
    }
    if (this.mediaType === CallMediaType.audio) {
      // audio_waiting_caller and audio_accept share the same Row layout
      // (only the hangup tip changes — handled by hangupBtn).
      //
      // audio_waiting_caller 和 audio_accept 使用相同的 Row 布局（只有挂断提示不同 — 由 hangupBtn 处理）。
      return Layout.audio;
    }
    // Video, caller side.
    //
    // 视频，主叫端。
    if (this.selfInfo.status !== CallParticipantStatus.accept) {
      return Layout.videoWaitingCaller;
    }
    return Layout.videoAccept;
  }

  private isWaitingCaller(): boolean {
    return this.isCaller && this.selfInfo.status === CallParticipantStatus.waiting;
  }

  // ---- Buttons ----
  //
  // ---- 按钮 ----

  @Builder
  declineBtn() {
    ControlsButton({
      image: CallKitBundle.imageMap('icon_hangup'),
      title: TUICallKitLocalize('TUICallKit.decline'),
      bgColor: CallConstants.Color_HangupRed,
      imageSize: BTN_LARGE,
      onTap: (): void => {
        // See markSelfEnded rationale in CallEndedFlag.
        //
        // 查看 CallEndedFlag 中 markSelfEnded 的理由。
        CallEndedFlag().markSelfEnded();
        CallingBellFeature.shared().stopAll();
        CallingVibratorFeature.shared().stop();
        void CallStore.shared().reject().catch((e: Object): void => {
          Logger.warn('reject failed', e);
        });
      },
    });
  }

  @Builder
  answerBtn() {
    ControlsButton({
      image: this.mediaType === CallMediaType.video
        ? CallKitBundle.imageMap('icon_video_dialing')
        : CallKitBundle.imageMap('icon_dialing'),
      title: TUICallKitLocalize('TUICallKit.answer'),
      bgColor: CallConstants.Color_AnswerGreen,
      imageSize: BTN_LARGE,
      onTap: (): void => {
        CallingBellFeature.shared().stopAll();
        CallingVibratorFeature.shared().stop();
        void CallStore.shared().accept().catch((e: Object): void => {
          Logger.warn('accept failed', e);
        });
      },
    });
  }

  /**
   * `titleOverride`:
   *   undefined → `TUICallKit.hangup`     (audio default)
   *   'cancel'  → `TUICallKit.cancel`     (caller waiting / outgoing)
   *   ''        → icon-only               (video accepted in-call)
   *
   * `titleOverride`：undefined → `TUICallKit.hangup`（音频默认）'cancel' → `TUICallKit.cancel`（主叫等待 / 外呼）'' →
   * 仅图标（视频接通中）
   */
  @Builder
  hangupBtn(titleOverride?: string) {
    ControlsButton({
      image: CallKitBundle.imageMap('icon_hangup'),
      title: titleOverride === undefined
        ? TUICallKitLocalize('TUICallKit.hangup')
        : (titleOverride.length > 0 ? TUICallKitLocalize(`TUICallKit.${titleOverride}`) : ''),
      bgColor: CallConstants.Color_HangupRed,
      imageSize: BTN_LARGE,
      onTap: (): void => {
        CallEndedFlag().markSelfEnded();
        void CallStore.shared().hangup().catch((e: Object): void => {
          Logger.warn('hangup failed', e);
        });
      },
    });
  }

  @Builder
  muteBtn() {
    ControlsButton({
      image: this.deviceState.microphoneStatus === DeviceStatus.on
        ? CallKitBundle.imageMap('icon_mute')
        : CallKitBundle.imageMap('icon_mute_on'),
      title: this.deviceState.microphoneStatus === DeviceStatus.on
        ? TUICallKitLocalize('TUICallKit.unmuted')
        : TUICallKitLocalize('TUICallKit.muted'),
      isSelected: this.deviceState.microphoneStatus !== DeviceStatus.on,
      bgColor: CallConstants.Color_BgMask,
      imageSize: BTN_LARGE,
      onTap: (): void => {
        if (this.deviceState.microphoneStatus === DeviceStatus.on) {
          DeviceStore.shared().closeLocalMicrophone();
        } else {
          void DeviceStore.shared().openLocalMicrophone();
        }
      },
    });
  }

  @Builder
  cameraBtn() {
    ControlsButton({
      image: this.deviceState.cameraStatus === DeviceStatus.on
        ? CallKitBundle.imageMap('icon_camera_on')
        : CallKitBundle.imageMap('icon_camera_off'),
      title: this.deviceState.cameraStatus === DeviceStatus.on
        ? TUICallKitLocalize('TUICallKit.cameraOn')
        : TUICallKitLocalize('TUICallKit.cameraOff'),
      isSelected: this.deviceState.cameraStatus === DeviceStatus.on,
      bgColor: CallConstants.Color_BgMask,
      imageSize: BTN_LARGE,
      onTap: (): void => {
        if (this.deviceState.cameraStatus === DeviceStatus.on) {
          DeviceStore.shared().closeLocalCamera();
        } else {
          void DeviceStore.shared().openLocalCamera(this.deviceState.isFrontCamera);
        }
      },
    });
  }

  @Builder
  audioRoutePicker() {
    CallViewAudioRoutePicker({ deviceState: this.deviceState });
  }

  /** Flutter `_getSwitchCameraButton` — large 60vp icon, used in videoWaitingCaller. */

  /* Flutter `_getSwitchCameraButton` — 大号 60vp 图标，用于 videoWaitingCaller。 */
  @Builder
  switchCameraLargeBtn() {
    ControlsButton({
      image: CallKitBundle.imageMap('icon_big_switch_camera'),
      title: TUICallKitLocalize('TUICallKit.switchCamera'),
      bgColor: CallConstants.Color_BgMask,
      imageSize: BTN_LARGE,
      onTap: (): void => {
        DeviceStore.shared().switchCamera(!this.deviceState.isFrontCamera);
      },
    });
  }

  /** Flutter `_getSwitchCameraSmallButton` — 28vp icon, no title. Used in videoAccept. */

  /* Flutter `_getSwitchCameraSmallButton` — 28vp 图标，无标题。在 videoAccept 中使用。 */
  @Builder
  switchCameraSmallBtn() {
    ControlsButton({
      image: CallKitBundle.imageMap('switch_camera'),
      title: '',
      bgColor: CallConstants.Color_BgMask,
      imageSize: BTN_SMALL,
      onTap: (): void => {
        DeviceStore.shared().switchCamera(!this.deviceState.isFrontCamera);
      },
    });
  }
}
