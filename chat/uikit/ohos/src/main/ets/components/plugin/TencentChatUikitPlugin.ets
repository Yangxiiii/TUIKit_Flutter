import {
  AbilityAware,
  AbilityPluginBinding,
  FlutterPlugin,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
} from '@ohos/flutter_ohos';
import { pasteboard } from '@kit.BasicServicesKit';
import AudioPlayer from '../../audioplayer/AudioPlayer';
import AudioRecorder from '../../audiorecorder/AudioRecorder';
import FilePicker from '../../filepicker/FilePicker';
import VideoRecorder from '../../videorecorder/VideoRecorder';

/** 将 Dart 的一次复制与鸿蒙剪贴板变更计数绑定，不存储消息内容。 */
interface MessageClipboardEntry {
  token: string;
  changeCount: number;
}

/**
 * TencentChatUikitPlugin
 *
 * OpenHarmony 侧的根插件类,对齐 pubspec.yaml 中 `ohos.pluginClass: TencentChatUikitPlugin`。
 * 与 Android 端保持一致的聚合模式:根类只做子模块生命周期编排 + AbilityAware 转发。
 *
 * 子模块清单(P0):
 *   [x] file_picker      -> filepicker/FilePicker.ets           (需要 UIAbilityContext)
 *   [x] audio_player     -> audioplayer/AudioPlayer.ets         (含 EventChannel)
 *   [x] audio_recorder   -> audiorecorder/AudioRecorder.ets     (含 EventChannel + UIAbilityContext)
 *   [x] video_recorder   -> videorecorder/VideoRecorder.ets     (cameraPicker + UIAbilityContext)
 *   [-] video_player     -> 用 Dart 降级方案:ohos 上 VideoPlayer.play 直接调
 *                            FilePicker.openFile 由系统视频播放器打开,不做 PlatformView。
 *                            见 chat/uikit/lib/src/video_player/video_player.dart。
 */
export default class TencentChatUikitPlugin implements FlutterPlugin, MethodCallHandler, AbilityAware {
  private channel: MethodChannel | null = null;
  /** 绑定本次纯文本写入的系统版本；剪贴板发生任何替换后即失效。 */
  private messageClipboard: MessageClipboardEntry | null = null;
  private filePicker: FilePicker | null = null;
  private audioPlayer: AudioPlayer | null = null;
  private audioRecorder: AudioRecorder | null = null;
  private videoRecorder: VideoRecorder | null = null;

  constructor() {
  }

  getUniqueClassName(): string {
    return 'TencentChatUikitPlugin';
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.channel = new MethodChannel(binding.getBinaryMessenger(), 'tencent_chat_uikit');
    this.channel.setMethodCallHandler(this);

    this.filePicker = new FilePicker(binding);
    this.audioPlayer = new AudioPlayer(binding);
    this.audioRecorder = new AudioRecorder(binding);
    this.videoRecorder = new VideoRecorder(binding);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    this.videoRecorder?.dispose();
    this.videoRecorder = null;
    this.audioRecorder?.dispose();
    this.audioRecorder = null;
    this.audioPlayer?.dispose();
    this.audioPlayer = null;
    this.messageClipboard = null;
    this.filePicker?.dispose();
    this.filePicker = null;

    if (this.channel !== null) {
      this.channel.setMethodCallHandler(null);
      this.channel = null;
    }
  }

  // ---- AbilityAware ----
  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.filePicker?.onAttachedToAbility(binding);
    this.audioRecorder?.onAttachedToAbility(binding);
    this.videoRecorder?.onAttachedToAbility(binding);
  }

  onDetachedFromAbility(): void {
    this.filePicker?.onDetachedFromAbility();
    this.audioRecorder?.onDetachedFromAbility();
    this.videoRecorder?.onDetachedFromAbility();
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'getPlatformVersion') {
      result.success('OpenHarmony ^ ^ ');
      return;
    }
    if (call.method === 'writeMessageClipboard' || call.method === 'readMessageClipboardToken') {
      this.handleMessageClipboard(call, result);
      return;
    }
    result.notImplemented();
  }

  /** 鸿蒙用系统变更计数校验纯文本条目，不依赖键盘是否保留附加 MIME。 */
  private async handleMessageClipboard(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const clipboard = pasteboard.getSystemPasteboard();
      if (call.method === 'readMessageClipboardToken') {
        const entry = this.messageClipboard;
        result.success(entry !== null && clipboard.getChangeCount() === entry.changeCount
          ? entry.token : null);
        return;
      }
      const text = call.argument('text') as string | null;
      const token = call.argument('token') as string | null;
      if (typeof text !== 'string' || typeof token !== 'string') {
        result.error('INVALID_ARGUMENT', '剪贴板参数无效', null);
        return;
      }
      // 写入期间只允许发生此次变更，避免并发外部复制与旧消息绑定。
      this.messageClipboard = null;
      const previousCount = clipboard.getChangeCount();
      await clipboard.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      const currentCount = clipboard.getChangeCount();
      if (currentCount === previousCount + 1) {
        this.messageClipboard = { token: token, changeCount: currentCount };
      }
      result.success(null);
    } catch (_) {
      result.error('CLIPBOARD_UNAVAILABLE', '系统剪贴板不可用', null);
    }
  }
}
