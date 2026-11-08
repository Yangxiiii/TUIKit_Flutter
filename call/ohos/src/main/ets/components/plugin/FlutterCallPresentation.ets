import { common } from '@kit.AbilityKit';
import { MethodChannel } from '@ohos/flutter_ohos';
import {
  AudioRoute, CallMediaType, CallParticipantInfo, CallParticipantStatus, CallStore,
  DeviceStatus, DeviceStore, NetworkQuality,
} from '@tencentcloud/atomicxcore';
import { Permission } from '../../common/utils/Permission';
import { Logger } from '../../common/utils/Logger';
import { CallingBellFeature } from '../../feature/CallingBellFeature';
import { CallingVibratorFeature } from '../../feature/CallingVibratorFeature';
import { CallStatusObserver } from '../../feature/CallStatusObserver';
import { RouterManager } from '../../manager/RouterManager';
import { NetworkQualityToastManager } from '../../manager/NetworkQualityToastManager';
import { CallEndedFlag } from '../../state/CallEndedFlag';
import { CallRoute, ViewState } from '../../state/ViewState';

/** 将单聊展示交给宿主 Flutter。原生 CallStore 仍负责状态、设备及信令。 */
export class FlutterCallPresentation {
  /** 页面会话序号只随通话开始和结束变化，SDK 更新信令 ID 时沿用原序号。 */
  private presentationSequence: number = 0;
  private presentationId: string = '';
  /** SDK 当前信令标识只用于记录确认阶段的更新，不参与按钮校验。 */
  private observedSdkCallId: string = '';
  /** 默认设备仅初始化一次，切换横幅和全屏时保留用户已选择的状态。 */
  private initializedId: string = '';
  /** 原生 SDK 时长暂未更新时，使用接通时间补齐展示，单位为毫秒。 */
  private connectedAt: number = 0;

  private readonly channel: MethodChannel;
  private readonly context: common.UIAbilityContext;

  constructor(channel: MethodChannel, context: common.UIAbilityContext) {
    this.channel = channel;
    this.context = context;
  }

  /** 关闭已有 Flutter 浮层或接管单聊路由。群聊继续由原生窗口承载。 */
  present(route: CallRoute): boolean {
    if (route === CallRoute.none) {
      this.presentationId = '';
      this.observedSdkCallId = '';
      this.initializedId = '';
      this.connectedAt = 0;
      this.channel.invokeMethod('harmonyPresentationChanged', false);
      return false;
    }
    const state = CallStore.shared().state;
    const call = state.activeCall;
    // 主叫振铃时信令标识可能未回填，Flutter 页面仍用独立展示序号接管。
    const outgoingVoiceWaiting = route === CallRoute.fullView && call.mediaType === CallMediaType.audio &&
      state.selfInfo.status === CallParticipantStatus.waiting && state.selfInfo.id.length > 0 &&
      call.inviterId === state.selfInfo.id && call.inviteeIds.length === 1;
    if ((call.callId.length === 0 && !outgoingVoiceWaiting) ||
      call.chatGroupId.length > 0 || call.inviteeIds.length > 1) {
      return false;
    }
    if (this.presentationId.length === 0) {
      // 原生路由在结束时清空；同一通话的横幅与全屏沿用同一页面会话。
      this.presentationId = (++this.presentationSequence).toString();
      this.observedSdkCallId = call.callId;
    }
    // 弱网提示由共享 Flutter 操作区展示，停止原生 Toast 防止重复提示。
    NetworkQualityToastManager.stop();
    if (route === CallRoute.fullView && this.initializedId !== this.presentationId && call.mediaType !== undefined) {
      this.initializedId = this.presentationId;
      void this.initializeMedia(this.presentationId, call.mediaType);
    }
    this.channel.invokeMethod('harmonyPresentationChanged', true);
    return true;
  }

  /** 只读投影共享界面需要的资料和设备事实。铃声监听沿用原生接通状态。 */
  snapshot(): Map<string, Object> | null {
    if (this.presentationId.length === 0) return null;
    const state = CallStore.shared().state;
    const call = state.activeCall;
    if (call.callId.length > 0 && call.callId !== this.observedSdkCallId) {
      Logger.info('Flutter call signaling identifier updated within the same presentation');
      this.observedSdkCallId = call.callId;
    }
    const self = state.selfInfo;
    const device = DeviceStore.shared().state;
    // 接通后沿用 SDK 状态停止原生铃声，并为时长缺失的 SDK 版本补齐本地时钟。
    const accepted = self.status === CallParticipantStatus.accept;
    CallStatusObserver().notify(self.status);
    if (accepted && this.connectedAt === 0) {
      this.connectedAt = Date.now() - call.duration * 1000;
      // 从系统通知接听也应进入全屏，并初始化本通话的媒体设备。
      if (ViewState().router === CallRoute.banner) RouterManager.showCallingView();
    }
    const peer = state.allParticipants.find((user: CallParticipantInfo): boolean => user.id !== self.id);
    const peerId = peer?.id ?? (call.inviterId === self.id ? call.inviteeIds[0] ?? '' : call.inviterId);
    // 平台通道只传共享组件所需的只读值，不传登录凭证或 SDK 对象。
    const data = new Map<string, Object>();
    data.set('id', this.presentationId);
    data.set('banner', ViewState().router === CallRoute.banner && !accepted);
    data.set('video', call.mediaType === CallMediaType.video);
    data.set('accepted', accepted);
    data.set('incoming', !accepted && call.inviterId !== self.id);
    data.set('microphone', device.microphoneStatus === DeviceStatus.on);
    data.set('speaker', device.currentAudioRoute === AudioRoute.speakerphone);
    data.set('duration', accepted ? Math.max(call.duration, Math.floor((Date.now() - this.connectedAt) / 1000)) : 0);
    data.set('selfPoor', this.isPoor(state.networkQualities.get(self.id)));
    data.set('peerPoor', this.isPoor(state.networkQualities.get(peerId)));
    data.set('self', this.user(self, self.id, device.cameraStatus === DeviceStatus.on));
    data.set('peer', this.user(peer, peerId, peer?.isCameraOpened === true));
    return data;
  }

  /** 将 Flutter 按钮转为当前通话的 SDK 操作，权限返回后再次校验通话标识。 */
  async action(presentationId: string, action: string): Promise<void> {
    if (!this.isCurrent(presentationId)) {
      Logger.warn('Flutter call action ignored for inactive call:', action);
      return;
    }
    Logger.info('Flutter call action:', action);
    const store = CallStore.shared();
    const devices = DeviceStore.shared();
    switch (action) {
      case 'expand':
        RouterManager.showCallingView();
        break;
      case 'accept': {
        // 权限弹窗结束时，原邀请可能已取消或在其他设备接听。
        if (store.state.selfInfo.status !== CallParticipantStatus.waiting ||
          store.state.activeCall.inviterId === store.state.selfInfo.id) return;
        const mediaType = store.state.activeCall.mediaType ?? CallMediaType.audio;
        if (!await Permission.hasPermission(this.context, mediaType) || !this.isCurrent(presentationId) ||
          store.state.selfInfo.status !== CallParticipantStatus.waiting) return;
        await store.accept();
        if (!this.isCurrent(presentationId)) return;
        CallingBellFeature.shared().stopAll();
        CallingVibratorFeature.shared().stop();
        RouterManager.showCallingView();
        break;
      }
      case 'end':
        CallEndedFlag().markSelfEnded();
        if (store.state.selfInfo.status === CallParticipantStatus.waiting &&
          store.state.activeCall.inviterId !== store.state.selfInfo.id) {
          await store.reject();
        } else {
          await store.hangup();
        }
        break;
      // 设备切换以原生当前状态为准，关闭设备无需重新请求权限。
      case 'microphone':
        if (devices.state.microphoneStatus === DeviceStatus.on) {
          devices.closeLocalMicrophone();
        } else if (await Permission.hasPermission(this.context, CallMediaType.audio) && this.isCurrent(presentationId)) {
          await devices.openLocalMicrophone();
        }
        break;
      case 'speaker':
        devices.setAudioRoute(devices.state.currentAudioRoute === AudioRoute.speakerphone ?
          AudioRoute.earpiece : AudioRoute.speakerphone);
        break;
      case 'camera':
        if (devices.state.cameraStatus === DeviceStatus.on) {
          devices.closeLocalCamera();
        } else if (await Permission.requestCameraInCall(this.context) && this.isCurrent(presentationId)) {
          await devices.openLocalCamera(devices.state.isFrontCamera);
        }
        break;
      case 'flip':
        if (devices.state.cameraStatus === DeviceStatus.on) devices.switchCamera(!devices.state.isFrontCamera);
        break;
    }
  }

  /** 只允许原页面会话操作当前通话，已结束或被替换的页面请求立即失效。 */
  private isCurrent(presentationId: string): boolean {
    return presentationId.length > 0 && presentationId === this.presentationId &&
      ViewState().router !== CallRoute.none;
  }

  /** 与原生通话页一致，权限成功后设置默认路由，再初始化麦克风和视频预览。 */
  private async initializeMedia(presentationId: string, mediaType: CallMediaType): Promise<void> {
    try {
      if (!await Permission.hasPermission(this.context, mediaType) || !this.isCurrent(presentationId)) return;
      const devices = DeviceStore.shared();
      devices.setAudioRoute(mediaType === CallMediaType.video ? AudioRoute.speakerphone : AudioRoute.earpiece);
      await devices.openLocalMicrophone();
      if (mediaType === CallMediaType.video && this.isCurrent(presentationId)) await devices.openLocalCamera(true);
    } catch (error) {
      Logger.warn('Flutter call media setup failed', error);
    }
  }

  private isPoor(quality: NetworkQuality | undefined): boolean {
    return quality === NetworkQuality.bad || quality === NetworkQuality.veryBad || quality === NetworkQuality.down;
  }

  private user(info: CallParticipantInfo | undefined, id: string, camera: boolean): Map<string, Object> {
    const user = new Map<string, Object>();
    user.set('id', id);
    user.set('name', info?.remark || info?.name || id);
    user.set('avatar', info?.avatarURL ?? '');
    user.set('camera', camera);
    return user;
  }
}
