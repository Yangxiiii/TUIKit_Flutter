import { CallInfo, CallParticipantInfo, CallParticipantStatus, CallStore, DeviceStore } from '@tencentcloud/atomicxcore';
import { CallConstants } from '../common/CallConstants';

export enum CallRoute {
  none = 0,
  banner = 1,
  fullView = 2,
}

/** 已登录的 Flutter 宿主按对端标识返回组织岗位副标题。 */
export type PeerOrganizationLoader = (accountId: string, userId: string) => Promise<string>;

/** 维护当前通话的窗口路由、镜头选择和展示资料，供 Flutter 与原生窗口共用。 */
@Observed
export class ViewStateClass {
  /** 当前显示横幅、全屏或关闭，原生和 Flutter 通过同一个路由协调。 */
  router: CallRoute = CallRoute.none;
  /** 独立多人只选一人时仍用多人界面，接听和会控权限由 SDK 决定。 */
  temporaryMulti: boolean = false;
  /** 本场从前置开始，重开摄像头或重新绑定纹理沿用本场手动选择。 */
  isFrontCamera: boolean = true;
  /** 当前场次的组织岗位按成员保存，只有查到真实资料时才展示。 */
  peerOrganizations: Map<string, string> = new Map<string, string>();
  /** 宿主查资料，原生窗口只保存当前通话的展示结果。 */
  private organizationLoader: PeerOrganizationLoader | null = null;
  /** 组织资料只绑定当前账号及场次。 */
  private organizationScope: string = '';
  /** 记录本场已经查过的成员，空结果同样不随快照重复查询。 */
  private requestedOrganizations: Set<string> = new Set<string>();
  /** 换场、解绑及销毁窗口后，过期结果不能恢复原资料。 */
  private organizationGeneration: number = 0;
  /** Status-bar height in vp, injected by SubWindowManager via getWindowAvoidArea(TYPE_SYSTEM). */

  /* 状态栏高度（vp），通过 SubWindowManager 的 getWindowAvoidArea(TYPE_SYSTEM) 注入。 */
  statusBarHeight: number = 0;
  /** Navigation-indicator height in vp, injected via TYPE_NAVIGATION_INDICATOR. */

  /* 导航指示器高度（vp），通过 TYPE_NAVIGATION_INDICATOR 注入。 */
  navBarHeight: number = 0;

  /** 切换 Flutter 引擎时清除旧资料及待返回的结果。 */
  setPeerOrganizationLoader(loader: PeerOrganizationLoader | null): void {
    this.organizationLoader = loader;
    this.clearPeerOrganization();
  }

  /** 原生界面只读取自己的对端资料，即使旧快照尚未清空也不会串场。 */
  organizationFor(accountId: string, callId: string, userId: string): string {
    return this.organizationScope === JSON.stringify([accountId, callId])
      ? this.peerOrganizations.get(userId) ?? '' : '';
  }

  /** 单聊查对端，群来电查发起人，共享群呼叫页按邀请名单加载成员组织。 */
  refreshPeerOrganization(call: CallInfo, self: CallParticipantInfo, includeOutgoingGroup: boolean = false): void {
    const loader = this.organizationLoader;
    const accountId = self.id;
    const callId = call.callId;
    const caller = call.inviterId === accountId;
    if (loader === null || self.status === CallParticipantStatus.none ||
      accountId.length === 0 || (callId.length === 0 && !caller)) {
      this.clearPeerOrganization();
      return;
    }
    const group = call.chatGroupId.length > 0 || call.inviteeIds.length > 1 || this.temporaryMulti;
    const ids = !caller ? [call.inviterId] : !group ? call.inviteeIds.slice(0, 1) :
      includeOutgoingGroup && self.status === CallParticipantStatus.waiting ?
        call.inviteeIds.filter((id: string): boolean => id.length > 0 && id !== accountId)
          .slice(0, CallConstants.MAX_PARTICIPANT - 1) : [];
    const scope = JSON.stringify([accountId, callId]);
    if (scope !== this.organizationScope) {
      this.clearPeerOrganization();
      this.organizationScope = scope;
    }
    // SDK 高频刷新，同一场次及成员仅向既有宿主通道查询一次。
    for (const userId of ids) {
      if (userId.length === 0 || userId === accountId || this.requestedOrganizations.has(userId)) continue;
      this.requestedOrganizations.add(userId);
      this.loadPeerOrganization(loader, accountId, callId, userId, this.organizationGeneration);
    }
  }

  /** 仅写入尚在当前场次的资料，换场及登出后不接收迟到结果。 */
  private loadPeerOrganization(loader: PeerOrganizationLoader, accountId: string, callId: string,
    userId: string, generation: number): void {
    void loader(accountId, userId).then((text: string): void => {
      const state = CallStore.shared().state;
      if (generation !== this.organizationGeneration || state.activeCall.callId !== callId ||
        state.selfInfo.id !== accountId || state.selfInfo.status === CallParticipantStatus.none || text.length === 0) {
        return;
      }
      // 替换集合引用，让原生待接听页的观察组件也能收到刷新。
      const next = new Map<string, string>(this.peerOrganizations);
      next.set(userId, text);
      this.peerOrganizations = next;
    }).catch((): void => {});
  }

  /** 清空副标题并撤销当前查询的展示资格。 */
  clearPeerOrganization(): void {
    if (this.organizationScope.length === 0) return;
    this.organizationGeneration++;
    this.organizationScope = '';
    this.requestedOrganizations.clear();
    this.peerOrganizations = new Map<string, string>();
  }

  /** 提交翻转请求后记录本场方向，避免 SDK 共享状态把上一次通话的方向带进来。 */
  flipCamera(): void {
    const isFront = !this.isFrontCamera;
    DeviceStore.shared().switchCamera(isFront);
    this.isFrontCamera = isFront;
  }

  /** 通话关闭时清除与场次绑定的选择，下一通重新从前置开始。 */
  reset(): void {
    this.clearPeerOrganization();
    this.isFrontCamera = true;
    this.router = CallRoute.none;
    this.temporaryMulti = false;
    // Safe-area heights are device hardware properties; preserved across calls.
    //
    // 安全区高度是设备硬件属性；在调用间保持不变。
  }
}

let _instance: ViewStateClass | null = null;

export function ViewState(): ViewStateClass {
  if (!_instance) {
    _instance = new ViewStateClass();
  }
  return _instance;
}
