import {
  CallStore, DeviceStore, CallMediaType, CallParticipantStatus,
  CallParticipantInfo, CallInfo, DeviceState, DeviceStatus, NetworkQuality,
} from '@tencentcloud/atomicxcore';
import { CallCoreView, CallCoreController, CallLayoutTemplate, VolumeLevel } from '@tencentcloud/atomicxcore';
import { CallConstants } from '../../../common/CallConstants';
import { CallKitBundle } from '../../../common/CallKitBundle';
import { Constants } from '../../../common/Constants';
import { TimerView } from './hint/TimerView';
import { HintView } from './hint/HintView';
import { WaitingParticipantsView } from './waiting/WaitingParticipantsView';
import { SingleCallControlsView } from './controls/SingleCallControlsView';
import { MultiCallControlsView } from './controls/MultiCallControlsView';
import { SmartCellularSwitchRecommendationView } from './smartCellularSwitchRecommendation/SmartCellularSwitchRecommendationView';
import { Logger } from '../../../common/utils/Logger';
import { ViewStateClass } from '../../../state/ViewState';
import { UserManager } from '../../../manager/UserManager';
import { HarmonyParticipantSurface } from '../../../components/plugin/HarmonyVideoView';

/** 组合 SDK 媒体、通话资料和原生接听控制，资料加载独立于通话。 */
@Component
export struct CallView {
  @State controller: CallCoreController = new CallCoreController();
  @State controlsHeight: number = CallConstants.groupFunctionViewHeight;
  @State smartCellularVisible: boolean = false;
  @State screenHeightVp: number = 800;

  @ObjectLink viewState: ViewStateClass;
  @ObjectLink callState_activeCall: CallInfo;
  @ObjectLink callState_selfInfo: CallParticipantInfo;
  @ObjectLink callState_allParticipants: CallParticipantInfo[];
  @ObjectLink deviceState: DeviceState;

  aboutToAppear(): void {
    this.applyControllerResources();
    this.applyControllerLayout();
  }

  aboutToDisappear(): void {
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.backgroundAvatar();

      // 单聊资料区替换 SDK 内置头像姓名；等待视频仍绑定本机真实镜头。
      if (this.shouldShowSingleIdentity()) {
        if (this.callState_activeCall.mediaType === CallMediaType.video &&
          this.deviceState.cameraStatus === DeviceStatus.on) {
          HarmonyParticipantSurface({
            userId: this.callState_selfInfo.id,
            viewName: 'oa_native_waiting_local_video',
          }).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
        }
        this.singleIdentity();
      } else {
        CallCoreView({ controller: this.controller })
          .width('100%')
          .height('100%')
          .padding({ top: this.isGroupCall() ? this.viewState.statusBarHeight + 50 : 0 })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .visibility(this.shouldHideCoreView() ? Visibility.Hidden : Visibility.Visible);
      }

      if (this.shouldShowWaitingRoster()) {
        WaitingParticipantsView({
          activeCall: this.callState_activeCall,
          allParticipants: this.callState_allParticipants,
          selfId: this.callState_selfInfo.id,
          peerOrganization: this.viewState.organizationFor(
            this.callState_selfInfo.id, this.callState_activeCall.callId, this.callState_activeCall.inviterId),
        })
          .margin({ top: this.viewState.statusBarHeight + 80 });
      }

      // 时长和状态提示叠在媒体上方，底部设备控制独立处理手势。
      Column() {
        TimerView({
          selfInfo: this.callState_selfInfo,
          activeCall: this.callState_activeCall,
        });
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .margin({ top: this.viewState.statusBarHeight + 20 });

      if (!this.isGroupCall()) {
        Column() {
          HintView({
            selfInfo: this.callState_selfInfo,
            activeCall: this.callState_activeCall,
            isCaller: this.isCaller(),
          });
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .padding({ top: this.screenHeightVp * 2 / 3 })
        .hitTestBehavior(HitTestMode.None);
      }

      Column() {
        if (this.isGroupCall()) {
          MultiCallControlsView({
            selfInfo: this.callState_selfInfo,
            deviceState: this.deviceState,
            controlsHeight: this.controlsHeight,
            mediaType: this.callState_activeCall.mediaType ?? CallMediaType.audio,
            enableVirtualBackground: true,
            bottomExtension: this.viewState.navBarHeight,
          });
        } else {
          SingleCallControlsView({
            selfInfo: this.callState_selfInfo,
            deviceState: this.deviceState,
            mediaType: this.callState_activeCall.mediaType ?? CallMediaType.audio,
            isCaller: this.isCaller(),
            enableVirtualBackground: true,
            // Single has no card background; it just adds the safe-area
            // inset to its own bottom padding.
            //
            // 单人没有卡片背景；它只是在自身底部填充中添加安全区域插入。
            bottomSafeInset: this.viewState.navBarHeight,
          });
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .hitTestBehavior(HitTestMode.Transparent);

      SmartCellularSwitchRecommendationView({
        visible: this.smartCellularVisible,
        onImprove: (): void => {
          Logger.info('SmartCellular: user chose Improve');
        },
        onKeepWifi: (): void => {
          Logger.info('SmartCellular: user chose KeepWifi');
        },
      });
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CallConstants.Color_Black)
    .onAreaChange((_old: Area, area: Area): void => {
      const h = Number(area.height);
      if (!Number.isNaN(h) && h > 0 && h !== this.screenHeightVp) {
        this.screenHeightVp = h;
      }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }

  /** 单聊头像、姓名与组织在同一栏，视频接通后把空间留给双路画面。 */
  @Builder
  singleIdentity() {
    Column() {
      if (this.findPeerForAvatar()?.avatarURL) {
        Image(this.findPeerForAvatar()!.avatarURL!)
          .width(this.singleAvatarSize())
          .height(this.singleAvatarSize())
          .borderRadius(this.singleAvatarSize() / 2)
          .objectFit(ImageFit.Cover);
      } else {
        Image($r('app.media.default_user_icon'))
          .width(this.singleAvatarSize())
          .height(this.singleAvatarSize())
          .borderRadius(this.singleAvatarSize() / 2);
      }
      Text(this.singlePeerName())
        .fontColor(CallConstants.Color_White)
        .fontSize(20)
        .lineHeight(28)
        .fontWeight(FontWeight.Medium)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 20 });
      if (this.singlePeerOrganization().length > 0) {
        Text(this.singlePeerOrganization())
          .fontColor(CallConstants.Color_CallSecondaryText)
          .fontSize(16)
          .lineHeight(22)
          .fontWeight(FontWeight.Medium)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 16 });
      }
    }
    .width('100%')
    .padding({ left: 24, right: 24 })
    .margin({ top: this.callState_activeCall.mediaType === CallMediaType.video
      ? this.viewState.statusBarHeight + 80 : this.screenHeightVp * 250 / 844 })
    .hitTestBehavior(HitTestMode.None);
  }

  /** 单聊资料区根据媒体形态保留现有的头像层级。 */
  private singleAvatarSize(): number {
    return this.callState_activeCall.mediaType === CallMediaType.video ? 72 : 96;
  }

  /** 成员对象还没补齐时，以当前场次标识暂时代替姓名。 */
  private singlePeerName(): string {
    const peer = this.findPeerForAvatar();
    if (peer !== undefined) return UserManager.getUserDisplayName(peer);
    return this.singlePeerId();
  }

  /** 单聊邀请两端使用同一 SDK 标识选择资料，等待阶段也能独立解析对端。 */
  private singlePeerId(): string {
    return this.isCaller()
      ? this.callState_activeCall.inviteeIds[0] ?? '' : this.callState_activeCall.inviterId;
  }

  /** 对端资料按当前账号和场次读取，避免换场时误用上一位来电人的组织。 */
  private singlePeerOrganization(): string {
    return this.viewState.organizationFor(
      this.callState_selfInfo.id, this.callState_activeCall.callId, this.singlePeerId());
  }

  /** 单聊语音和等待中的视频显示完整资料，接通的视频仍由 SDK 布局。 */
  private shouldShowSingleIdentity(): boolean {
    return !this.isGroupCall() &&
      this.callState_selfInfo.status !== CallParticipantStatus.none &&
      (this.callState_activeCall.mediaType === CallMediaType.audio ||
        this.callState_activeCall.mediaType === CallMediaType.video && this.isInWaitingState());
  }

  @Builder
  backgroundAvatar() {
    Stack() {
      if (this.backgroundAvatarUrl().length > 0) {
        Image(this.backgroundAvatarUrl())
          .width('100%')
          .height('100%')
          .alt($r('app.media.default_participant_icon'))
          .blur(80)
          .objectFit(ImageFit.Cover);
      } else {
        Image($r('app.media.default_participant_icon'))
          .width('100%')
          .height('100%')
          .blur(80)
          .objectFit(ImageFit.Cover);
      }
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(CallConstants.Color_BlurMask);
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]);
  }

  private backgroundAvatarUrl(): string {
    if (this.isGroupCall()) {
      return this.callState_selfInfo.avatarURL ?? '';
    }
    const peer = this.findPeerForAvatar();
    return (peer?.avatarURL ?? this.callState_selfInfo.avatarURL) ?? '';
  }

  /** Foreground peer avatar shown during 1:1 waiting (rounded square, not a circle). */

  /* 一对一等待时显示前景对方头像（圆角方形，不是圆形）。 */

  private isCaller(): boolean {
    return this.callState_activeCall.inviterId === this.callState_selfInfo.id;
  }

  private isGroupCall(): boolean {
    // Aligned with iOS CallView.swift:73 — chatGroupId non-empty OR more
    // than one invitee (covers a 2-participant group call where
    // allParticipants.length === 2 would otherwise be misclassified as 1:1).
    //
    // 与 iOS 的 CallView.swift:73 对齐 —— chatGroupId 非空或受邀者多于一个（覆盖 2 人参与群组通话的情况，否则 allParticipants.length ===
    // 2 会被错误分类为一对一）。
    return (this.callState_activeCall.chatGroupId?.length ?? 0) > 0
      || (this.callState_activeCall.inviteeIds?.length ?? 0) > 1 || this.viewState.temporaryMulti;
  }

  private isInWaitingState(): boolean {
    return this.callState_selfInfo.status === CallParticipantStatus.waiting;
  }

  private isCalledWaiting(): boolean {
    return this.callState_selfInfo.id !== this.callState_activeCall.inviterId
      && this.isInWaitingState();
  }

  private shouldHideCoreView(): boolean {
    return this.isGroupCall() && this.isCalledWaiting();
  }

  private shouldShowWaitingRoster(): boolean {
    return this.isGroupCall() && this.isCalledWaiting();
  }

  private findPeerForAvatar(): CallParticipantInfo | undefined {
    if (this.callState_allParticipants.length === 0) {
      return undefined;
    }
    if (!this.isGroupCall()) {
      return this.callState_allParticipants
        .find((p: CallParticipantInfo): boolean => p.id === this.singlePeerId());
    }
    return this.callState_allParticipants
      .find((p: CallParticipantInfo): boolean => p.id === this.callState_activeCall.inviterId);
  }

  private applyControllerResources(): void {
    const muteIcon: ResourceStr = $r('app.media.icon_mic_off');
    const audioInputIcon: ResourceStr = $r('app.media.icon_volume');
    const networkBadIcon: ResourceStr = $r('app.media.group_network_low_quality');

    const volumes = new Map<VolumeLevel, ResourceStr>();
    volumes.set(VolumeLevel.mute, muteIcon);
    volumes.set(VolumeLevel.low, audioInputIcon);
    volumes.set(VolumeLevel.medium, audioInputIcon);
    volumes.set(VolumeLevel.high, audioInputIcon);
    volumes.set(VolumeLevel.peak, audioInputIcon);
    this.controller.setVolumeLevelIcons(volumes);

    const networks = new Map<NetworkQuality, ResourceStr>();
    networks.set(NetworkQuality.bad, networkBadIcon);
    networks.set(NetworkQuality.veryBad, networkBadIcon);
    this.controller.setNetworkQualityIcons(networks);

    this.controller.setWaitingAnimation($r('app.media.callview_ic_loading'));
    this.controller.setDefaultAvatar($r('app.media.default_participant_icon'));
  }

  private applyControllerLayout(): void {
    const layout = this.isGroupCall() ? CallLayoutTemplate.grid : CallLayoutTemplate.float;
    this.controller.setLayoutTemplate(layout);
  }
}
