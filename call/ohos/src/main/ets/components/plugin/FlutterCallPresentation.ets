import { common } from '@kit.AbilityKit';
import { MethodChannel } from '@ohos/flutter_ohos';
import {
  AudioRoute, CallMediaType, CallParticipantInfo, CallParticipantStatus, CallState, CallStore,
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

/** 将单聊和多人展示交给 Flutter，设备、成员和信令仍取自鸿蒙 SDK。 */
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
  /** 构建指定原生回退时，视频全屏不经过 Flutter 的纹理合成。 */
  private readonly nativeVideo: boolean;

  constructor(channel: MethodChannel, context: common.UIAbilityContext, nativeVideo: boolean) {
    this.channel = channel;
    this.context = context;
    this.nativeVideo = nativeVideo;
  }

  /** Flutter 承载单聊和多人页面。显式视频回退时继续使用原生窗口。 */
  present(route: CallRoute): boolean {
    if (route === CallRoute.none) {
      this.clearPresentation();
      return false;
    }
    const state = CallStore.shared().state;
    const call = state.activeCall;
    if (this.usesNativeVideoWindow(route, call.mediaType)) {
      // 让 ArkUI 窗口直接合成 SDK 的视频 Surface，避免嵌入 Flutter 纹理后画面不可见。
      if (this.presentationId.length > 0) {
        this.clearPresentation();
        NetworkQualityToastManager.start();
      }
      return false;
    }
    // 主叫振铃时信令标识可能未回填，Flutter 页面仍用独立展示序号接管。
    const outgoingWaiting = route === CallRoute.fullView && call.mediaType !== undefined &&
      state.selfInfo.status === CallParticipantStatus.waiting && state.selfInfo.id.length > 0 &&
      call.inviterId === state.selfInfo.id && call.inviteeIds.length > 0;
    if (call.callId.length === 0 && !outgoingWaiting) {
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
      if (this.isGroupCall(state)) {
        // 多人成员由会控决定开启时机，原生初始化只选择默认音频路由。
        this.setDefaultAudioRoute(call.mediaType);
      } else {
        void this.initializeMedia(this.presentationId, call.mediaType);
      }
    }
    this.channel.invokeMethod('harmonyPresentationChanged', true);
    return true;
  }

  /** 回退模式保留 Flutter 来电横幅，打开全屏后才切到原生窗口。 */
  private usesNativeVideoWindow(route: CallRoute, mediaType: CallMediaType | undefined): boolean {
    return this.nativeVideo && route === CallRoute.fullView && mediaType === CallMediaType.video;
  }

  /** 使旧浮层操作失效并通知 Flutter 移除界面。跨到原生窗口时保持同一通话。 */
  private clearPresentation(): void {
    this.presentationId = '';
    this.observedSdkCallId = '';
    this.initializedId = '';
    this.connectedAt = 0;
    this.channel.invokeMethod('harmonyPresentationChanged', false);
  }

  /** 只读投影共享界面需要的资料和设备事实。铃声监听沿用原生接通状态。 */
  snapshot(): Map<string, Object> | null {
    if (this.presentationId.length === 0) return null;
    const state = CallStore.shared().state;
    const call = state.activeCall;
    // 原生回退模式下，SDK 补齐早期缺失的媒体类型后仍须交还窗口。
    if (this.usesNativeVideoWindow(ViewState().router, call.mediaType)) {
      RouterManager.showCallingView();
      return null;
    }
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
      if (ViewState().router === CallRoute.banner) {
        RouterManager.showCallingView();
        if (this.presentationId.length === 0) return null;
      }
    }
    const group = this.isGroupCall(state);
    const targetId = call.inviterId === self.id ? call.inviteeIds[0] ?? '' : call.inviterId;
    // 多人横幅始终展示邀请人，不能取成员列表中的任意一人。
    const peer = state.allParticipants.find((user: CallParticipantInfo): boolean =>
      group ? user.id === targetId : user.id !== self.id);
    const peerId = peer?.id ?? targetId;
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
    if (group) {
      data.set('callId', call.callId);
      data.set('groupId', call.chatGroupId);
      // 部分鸿蒙 SDK 在接通后返回十位 Unix 秒，桥接值统一为毫秒。
      const start = call.startTime;
      const startMs = start >= 1000000000 && start < 10000000000 ? start * 1000 : start;
      data.set('connectedAtMs', startMs > 0 ? startMs : this.connectedAt);
      data.set('chatGroup', call.chatGroupId.length > 0);
      data.set('inviterId', call.inviterId);
      data.set('members', this.groupMembers(state, accepted));
    }
    return data;
  }

  /** SDK 群来源或独立多人标记决定是否进入共享会控。 */
  private isGroupCall(state: CallState): boolean {
    const call = state.activeCall;
    return call.chatGroupId.length > 0 || call.inviteeIds.length > 1 || ViewState().temporaryMulti;
  }

  /** 只投影当前在场或仍等待的成员，邀请终态以 SDK 状态为准。 */
  private groupMembers(state: CallState, accepted: boolean): Array<Map<string, Object>> {
    const call = state.activeCall;
    const self = state.selfInfo;
    const device = DeviceStore.shared().state;
    const live = new Map<string, CallParticipantInfo>();
    state.allParticipants.forEach((member: CallParticipantInfo): void => {
      if (member.id.length > 0 && member.status !== CallParticipantStatus.none) live.set(member.id, member);
    });
    if (self.id.length > 0 && self.status !== CallParticipantStatus.none) live.set(self.id, self);
    // 振铃期间软件可能先给邀请名单、再给成员对象。接通后以 SDK 实时成员为准。
    const ids = new Set<string>([call.inviterId, ...call.inviteeIds, ...Array.from(live.keys())]);
    const members: Array<Map<string, Object>> = [];
    ids.forEach((id: string): void => {
      if (id.length === 0 || members.length >= 9) return;
      const member = live.get(id);
      if (member === undefined && accepted) return;
      const local = id === self.id;
      const joined = member?.status === CallParticipantStatus.accept;
      const data = this.user(member, id, joined &&
        (local ? device.cameraStatus === DeviceStatus.on : member?.isCameraOpened === true));
      data.set('joined', joined);
      data.set('microphone', joined &&
        (local ? device.microphoneStatus === DeviceStatus.on : member?.isMicrophoneOpened === true));
      data.set('volume', joined ? state.speakerVolumes[id] ?? 0 : 0);
      members.push(data);
    });
    return members;
  }

  /** 将 Flutter 按钮转为当前通话的 SDK 操作，权限返回后再次校验通话标识。 */
  async action(presentationId: string, action: string): Promise<void> {
    if (!this.isCurrent(presentationId)) {
      // 已结束或换场时不能把未执行的到期挂断回报为成功。
      if (action === 'endAtDurationLimit') throw new Error('原通话已结束');
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
      case 'endAtDurationLimit': {
        if (store.state.selfInfo.status !== CallParticipantStatus.accept) {
          throw new Error('原通话未接通');
        }
        // 本端挂断由 Flutter 显示专用提示，避免原生再提示对方挂断。
        CallEndedFlag().markSelfEnded();
        try {
          await store.hangup();
        } catch (error) {
          if (this.isCurrent(presentationId)) CallEndedFlag().clear();
          // ArkTS 要求抛出明确的 Error，保留 SDK 消息供 Flutter 错误回调使用。
          throw new Error((error as Error).message);
        }
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

  /** 仅已接通的原多人场次可以申请权限或操作设备；权限结束后由 Flutter 复核会控版本。 */
  async groupDevice(presentationId: string, callId: string, device: string,
    enabled: boolean | null): Promise<boolean> {
    if (!this.isGroupDeviceCurrent(presentationId, callId, device)) return false;
    const camera = device === 'camera';
    if (enabled === null) {
      return camera ? Permission.requestCameraInCall(this.context) :
        Permission.hasPermission(this.context, CallMediaType.audio);
    }
    // 使用指令的目标状态；重复关闭不能翻转为开启。
    const devices = DeviceStore.shared();
    const on = (camera ? devices.state.cameraStatus : devices.state.microphoneStatus) === DeviceStatus.on;
    if (enabled === on) return true;
    if (camera) {
      if (enabled) {
        await devices.openLocalCamera(devices.state.isFrontCamera);
      } else {
        devices.closeLocalCamera();
      }
    } else if (enabled) {
      await devices.openLocalMicrophone();
    } else {
      devices.closeLocalMicrophone();
    }
    // 这里只报告 SDK 调用已完成，Flutter 还须核对实际设备快照再回执。
    return this.isGroupDeviceCurrent(presentationId, callId, device);
  }

  /** 信令 ID、展示序号及媒体能力必须同时对应本次接通。 */
  private isGroupDeviceCurrent(presentationId: string, callId: string, device: string): boolean {
    const state = CallStore.shared().state;
    return this.isCurrent(presentationId) && callId.length > 0 && state.activeCall.callId === callId &&
      state.selfInfo.status === CallParticipantStatus.accept && this.isGroupCall(state) &&
      (device === 'microphone' || (device === 'camera' && state.activeCall.mediaType === CallMediaType.video));
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
      this.setDefaultAudioRoute(mediaType);
      await devices.openLocalMicrophone();
      if (mediaType === CallMediaType.video && this.isCurrent(presentationId)) await devices.openLocalCamera(true);
    } catch (error) {
      Logger.warn('Flutter call media setup failed', error);
    }
  }

  /** 默认视频用扬声器，语音用听筒，后续由用户自行调整。 */
  private setDefaultAudioRoute(mediaType: CallMediaType): void {
    DeviceStore.shared().setAudioRoute(
      mediaType === CallMediaType.video ? AudioRoute.speakerphone : AudioRoute.earpiece);
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
