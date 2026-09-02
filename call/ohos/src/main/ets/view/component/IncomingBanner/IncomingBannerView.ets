// Top-anchored incoming-call banner.
//
// Layout primitive: Row + flex Column for name/tip + fixed-size buttons.
// Mirrors iOS IncomingBannerViewController:
//   [avatar 60][gap 12][flex Column(name/tip)][reject 36][gap 22][accept 36][inset 16]
// Tapping the body opens the full call view; child Image taps consume
// their own touches via onClick so Decline/Answer don't bubble.
//
// 顶部固定的来电横幅。
//
// 布局原语：行 + 弹性列显示姓名/提示 + 固定大小按钮。参考 iOS 的 IncomingBannerViewController：[头像 60][间隙 12][弹性列(姓名/提示)][拒接
// 36][间隙 22][接听 36][内边距 16] 点击主体打开完整通话界面；子 Image 点击通过 onClick 消费自身触摸事件，所以拒接/接听不会冒泡。

import {
  CallStore, CallParticipantInfo, CallInfo, CallMediaType,
} from '@tencentcloud/atomicxcore';
import { CallKitBundle } from '../../../common/CallKitBundle';
import { TUICallKitLocalize } from '../../../common/Localized';
import { CallConstants } from '../../../common/CallConstants';
import { UserManager } from '../../../manager/UserManager';
import { RouterManager } from '../../../manager/RouterManager';
import { Logger } from '../../../common/utils/Logger';
import { CallEndedFlag } from '../../../state/CallEndedFlag';
import { ViewStateClass } from '../../../state/ViewState';
import { CallingBellFeature } from '../../../feature/CallingBellFeature';
import { CallingVibratorFeature } from '../../../feature/CallingVibratorFeature';

const BANNER_HEIGHT: number = 92;
const BANNER_CORNER_RADIUS: number = 10;
const BANNER_BG_COLOR: string = '#22262E';

const AVATAR_SIZE: number = 60;
const AVATAR_CORNER_RADIUS: number = 7;    // rounded-square, not circle
const AVATAR_LEADING: number = 16;

const NAME_LEADING_GAP: number = 12;
const NAME_FONT_SIZE: number = 18;

const TIP_FONT_SIZE: number = 12;
const TIP_COLOR: string = '#C5CCDB';

const BTN_SIZE: number = 36;
const BTN_GAP: number = 22;
const BTN_TRAILING_INSET: number = 16;

@Component
export struct IncomingBannerView {
  @ObjectLink viewState: ViewStateClass;
  @ObjectLink activeCall: CallInfo;
  @ObjectLink selfInfo: CallParticipantInfo;
  @ObjectLink allParticipants: CallParticipantInfo[];

  build() {
    Row() {
      // Avatar.
      this.avatarSlot();

      // Name + tip column (takes remaining space).
      //
      // 姓名 + 提示列（占用剩余空间）。
      Column() {
        Text(this.callerName())
          .fontColor(CallConstants.Color_OweWhite)
          .fontSize(NAME_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
          .width('100%');

        Text(this.tipText())
          .fontColor(TIP_COLOR)
          .fontSize(TIP_FONT_SIZE)
          .fontWeight(FontWeight.Bold)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)
          .width('100%')
          .margin({ top: 4 });
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      // iOS spacing: name top = avatar.top + 10, tip bottom = avatar.bottom - 10.
      // The avatar is 60vp tall; name(~22) + 4 + tip(~17) ≈ 43vp leaves
      // ~(60-43)/2 = 8.5 above and below if centered. iOS uses asymmetric
      // 10/10, which we match by padding the column.
      //
      // 头像高 60vp；姓名(~22) + 4 + 提示(~17) ≈ 43vp 剩余
      //
      // 10/10，通过为列加内边距匹配。
      .padding({ left: NAME_LEADING_GAP, top: 10, bottom: 10, right: 8 });

      // Reject button.
      //
      // 拒接按钮。
      Image(CallKitBundle.imageMap('icon_hangup'))
        .width(BTN_SIZE)
        .height(BTN_SIZE)
        .objectFit(ImageFit.Contain)
        .onClick((): void => {
          Logger.info('IncomingBanner: reject tapped');
          // Self-initiated reject → suppress the upcoming end-reason toast.
          //
          // 自发拒接 → 抑制即将显示的结束原因提示。
          CallEndedFlag().markSelfEnded();
          void CallStore.shared().reject()
            .then((): void => {
              Logger.info('IncomingBanner: reject resolved');
            })
            .catch((e: Object): void => {
              Logger.warn('IncomingBanner: reject failed', JSON.stringify(e));
            });
        });

      // Gap between reject and accept.
      //
      // 拒接和接听之间的间隙。
      Column().width(BTN_GAP).height(1);

      // Accept button.
      //
      // 接听按钮。
      Image(this.answerIcon())
        .width(BTN_SIZE)
        .height(BTN_SIZE)
        .objectFit(ImageFit.Contain)
        .onClick((): void => {
          Logger.info('IncomingBanner: accept tapped');
          // Hard-stop ringtone + vibrator immediately on tap.
          //
          // 点击时立即停止铃声 + 震动。
          CallingBellFeature.shared().stopAll();
          CallingVibratorFeature.shared().stop();
          void CallStore.shared().accept()
            .then((): void => {
              Logger.info('IncomingBanner: accept resolved');
            })
            .catch((e: Object): void => {
              Logger.warn('IncomingBanner: accept failed', JSON.stringify(e));
            });
        });
    }
    .width('100%')
    .height(BANNER_HEIGHT)
    .padding({ left: AVATAR_LEADING, right: BTN_TRAILING_INSET })
    .backgroundColor(BANNER_BG_COLOR)
    .borderRadius(BANNER_CORNER_RADIUS)
    .clip(true)
    .alignItems(VerticalAlign.Center)
    .onClick((): void => {
      RouterManager.showCallingView();
    });
  }

  @Builder
  avatarSlot() {
    if (this.findCaller()
        && this.findCaller()!.avatarURL
        && this.findCaller()!.avatarURL!.length > 0) {
      Image(this.findCaller()!.avatarURL!)
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(AVATAR_CORNER_RADIUS)
        .alt($r('app.media.default_user_icon'))
        .objectFit(ImageFit.Cover);
    } else {
      Image($r('app.media.default_user_icon'))
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(AVATAR_CORNER_RADIUS);
    }
  }

  private findCaller(): CallParticipantInfo | undefined {
    const inviterId = this.activeCall.inviterId;
    return this.allParticipants.find((p: CallParticipantInfo): boolean => p.id === inviterId);
  }

  private callerName(): string {
    return UserManager.getUserDisplayName(this.findCaller());
  }

  private tipText(): string {
    if ((this.activeCall.chatGroupId?.length ?? 0) > 0
        || this.allParticipants.length > 2) {
      return TUICallKitLocalize('TUICallKit.Group.inviteToGroupCall');
    }
    return this.activeCall.mediaType === CallMediaType.video
      ? TUICallKitLocalize('TUICallKit.inviteToVideoCall')
      : TUICallKitLocalize('TUICallKit.inviteToAudioCall');
  }

  private answerIcon(): Resource {
    return this.activeCall.mediaType === CallMediaType.video
      ? CallKitBundle.imageMap('icon_video_dialing')
      : CallKitBundle.imageMap('icon_dialing');
  }
}
