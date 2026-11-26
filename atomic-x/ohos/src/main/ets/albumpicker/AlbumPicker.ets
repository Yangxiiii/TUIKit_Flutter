import {
  AbilityPluginBinding,
  EventChannel,
  EventSink,
  FlutterManager,
  FlutterPluginBinding,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult,
  StreamHandler,
} from '@ohos/flutter_ohos';
import { UIAbility } from '@kit.AbilityKit';
import { ComponentContent, PromptAction, window } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AlbumPickMode } from './AlbumPickerHelper';
import { AlbumPickerOutput, AlbumPickerSelection } from './AlbumPickerOutput';
import { ALBUM_PICKER_BACKGROUND, AlbumPickerView } from './AlbumPickerView';

/// 主窗口实测的系统栏空间，统一使用 vp 数字，供相册布局和提示偏移复用。
interface AlbumPickerInsets {
  top: number;
  bottom: number;
}

interface AlbumPickerDialogOptions {
  /// 媒体范围同时限制网格和相册列表。
  mediaType: photoAccessHelper.PhotoViewMIMETypes;
  /// 宿主允许的单次选择上限。
  maxCount: number;
  /// 是否展示拍摄入口，具体权限由系统组件处理。
  showsCameraItem: boolean;
  /// 宿主传入的选中色，缺省时由相册采用默认值。
  primaryColor: string | undefined;
  /// 主窗口沉浸布局的系统栏避让尺寸，单位为 vp。
  systemInsets: AlbumPickerInsets;
  /// 导出完成后关闭相册并移交沙盒文件。
  onConfirm: (selection: AlbumPickerSelection[]) => void;
  /// 关闭相册并释放 Dart 选择会话。
  onCancel: () => void;
}

@Builder
function buildAlbumPicker(options: AlbumPickerDialogOptions) {
  // Flutter 主窗口铺到系统栏下方，相册标题和底栏在可点击区域内布局。
  Column() {
    AlbumPickerView({
      mediaType: options.mediaType,
      maxCount: options.maxCount,
      showsCameraItem: options.showsCameraItem,
      primaryColor: options.primaryColor ?? '#0370ED',
      toastBottomInset: options.systemInsets.bottom,
      onConfirm: options.onConfirm,
      onCancel: options.onCancel,
    })
  }
  .width('100%')
  .height('100%')
  .padding(options.systemInsets)
  .backgroundColor(ALBUM_PICKER_BACKGROUND)
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
}

interface AlbumPickerSession {
  /// 与 Dart 回调关联，在弹层关闭前独占当前窗口的相册入口。
  id: string;
  prompt: PromptAction;
  content: ComponentContent<AlbumPickerDialogOptions>;
  /// 等待相册系统栏样式生效，再在会话结束时恢复宿主原来的样式。
  restoreSystemBars: () => Promise<void>;
  /// Dart 请求原件资料时才在媒体事件中附带文件名和大小。
  includeSourceMetadata: boolean;
  /// 关闭过程中拒绝同一窗口重复打开或重复确认。
  closing: boolean;
  /// 弹层消失和关闭失败都可能通知退出，系统栏恢复期间只处理一次。
  finishing?: boolean;
  /// 仅在确认后暂存导出结果，弹层退出后才交给调用方。
  selection?: AlbumPickerSelection[];
}

/// 同一媒体在选择确认和处理完成事件中使用相同的标识。
interface MediaWithId {
  id: number;
  selection: AlbumPickerSelection;
}

/// 在 Flutter 主窗口展示鸿蒙相册，把确认、导出完成或取消交还给发起选择的 Dart 会话。
export default class AlbumPicker implements MethodCallHandler, StreamHandler {
  private static readonly TAG = 'AtomicX.AlbumPicker';
  private static readonly METHOD_CHANNEL_NAME = 'atomic_x/album_picker';
  private static readonly EVENT_CHANNEL_NAME = 'atomic_x/album_picker_events';

  private methodChannel: MethodChannel | null = null;
  private eventChannel: EventChannel | null = null;
  private eventSink: EventSink | null = null;
  /// 当前 Flutter 宿主的 Ability，绑定期间用于定位自己的主窗口。
  private ability: UIAbility | null = null;
  /// 当前占用主窗口的选择会话，系统关闭弹层后释放。
  private activePicker: AlbumPickerSession | null = null;
  /// 按确认顺序递增的事件标识，供 Dart 将进度关联到确认时的媒体。
  private mediaIdCounter: number = 0;

  constructor(binding: FlutterPluginBinding) {
    this.methodChannel = new MethodChannel(binding.getBinaryMessenger(), AlbumPicker.METHOD_CHANNEL_NAME);
    this.methodChannel.setMethodCallHandler(this);
    this.eventChannel = new EventChannel(binding.getBinaryMessenger(), AlbumPicker.EVENT_CHANNEL_NAME);
    this.eventChannel.setStreamHandler(this);
  }

  /// 记录所属 Flutter 窗口，避免使用通知或通话浮窗的 UIContext。
  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.ability = binding.getAbility();
  }

  /// 宿主窗口退出时收起相册并放弃尚未交付的文件。
  onDetachedFromAbility(): void {
    this.ability = null;
    const session = this.activePicker;
    if (session !== null) {
      if (session.selection !== undefined) {
        void AlbumPickerOutput.discard(session.selection);
        session.selection = undefined;
      }
      this.closePicker(session.id);
    }
  }

  // ----- StreamHandler -----
  onListen(args: ESObject, events: EventSink): void {
    this.eventSink = events;
  }

  onCancel(args: ESObject): void {
    this.eventSink = null;
  }

  // ----- MethodCallHandler -----
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'pickMedia') {
      this.handlePickMedia(call, result);
      return;
    }
    result.notImplemented();
  }

  /// 方法调用只回执启动请求，确认或取消均经事件通道交付。
  private handlePickMedia(call: MethodCall, result: MethodResult): void {
    const sessionId = call.argument('sessionId') as string | null;
    if (typeof sessionId !== 'string' || sessionId.length === 0) {
      result.error('INVALID_ARGUMENT', 'sessionId is required', null);
      return;
    }
    result.success(null);
    void this.openPicker(call, sessionId);
  }

  /// 在主窗口的安全区内挂载原生图库，保持当前 Flutter 路由和聊天草稿。
  private async openPicker(call: MethodCall, sessionId: string): Promise<void> {
    const ability = this.ability;
    if (ability === null || this.activePicker !== null) {
      // 并发请求或宿主尚未绑定时结束本次会话，避免 Dart 等待一个没有界面的选择。
      this.emitCancel(sessionId);
      return;
    }

    let session: AlbumPickerSession | undefined;
    try {
      const hostWindow = FlutterManager.getInstance().getWindowStage(ability).getMainWindowSync();
      const context = hostWindow.getUIContext();
      const prompt = context.getPromptAction();
      const pickMode = call.argument('pickMode') as number | null;
      const primaryColor = call.argument('primaryColor') as string | null;
      const bars = hostWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const indicator = hostWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const options: AlbumPickerDialogOptions = {
        mediaType: pickMode === AlbumPickMode.IMAGE ? photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE :
          (pickMode === AlbumPickMode.VIDEO ? photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE :
            photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE),
        maxCount: (call.argument('maxCount') as number | null) ?? 1,
        showsCameraItem: call.argument('showsCameraItem') === true,
        // Dart 传入 0xAARRGGBB，ArkUI 使用带井号的颜色字符串。
        primaryColor: typeof primaryColor === 'string' && /^0x[\da-f]{8}$/i.test(primaryColor) ?
          `#${primaryColor.slice(2)}` : undefined,
        systemInsets: {
          top: context.px2vp(bars.topRect.height),
          bottom: context.px2vp(Math.max(bars.bottomRect.height, indicator.bottomRect.height)),
        },
        onConfirm: (selection: AlbumPickerSelection[]) => this.closePicker(sessionId, selection),
        onCancel: () => this.closePicker(sessionId),
      };
      const content = new ComponentContent(context, wrapBuilder(buildAlbumPicker), options);
      const picker: AlbumPickerSession = {
        id: sessionId,
        prompt,
        content,
        restoreSystemBars: this.applyPickerSystemBars(hostWindow),
        includeSourceMetadata: call.argument('includeSourceMetadata') === true,
        closing: false,
      };
      session = picker;
      this.activePicker = picker;
      // 系统返回和主动关闭走同一个退出回调，确认结果在退出后再触发发送流程。
      await prompt.openCustomDialog(content, {
        alignment: DialogAlignment.Center,
        autoCancel: false,
        maskColor: Color.Transparent,
        onDidDisappear: () => { void this.finishPicker(picker); },
      });
    } catch (_) {
      console.error(`${AlbumPicker.TAG} 无法打开相册`);
      if (session !== undefined) {
        void this.finishPicker(session, false);
      } else {
        this.emitCancel(sessionId);
      }
    }
  }

  /// 相册覆在 Flutter 路由上，保存宿主系统栏配置，退出后交还给该路由。
  private applyPickerSystemBars(hostWindow: window.Window): () => Promise<void> {
    try {
      // 状态栏和三键导航使用同一底色，手势区由相册根节点的安全区背景覆盖。
      const previous = hostWindow.getWindowSystemBarProperties();
      const applied = hostWindow.setWindowSystemBarProperties({
        statusBarColor: ALBUM_PICKER_BACKGROUND,
        statusBarContentColor: '#FFFFFF',
        navigationBarColor: ALBUM_PICKER_BACKGROUND,
        navigationBarContentColor: '#FFFFFF',
      }).catch(() => {
        console.warn(`${AlbumPicker.TAG} 无法设置相册系统栏`);
      });
      // 用户可能在设置调用完成前关掉相册，按设置、恢复的顺序写回。
      return async () => {
        try {
          await applied;
          await hostWindow.setWindowSystemBarProperties(previous);
        } catch (_) {
          // 宿主窗口已退出时系统栏由下一窗口接管。
          console.warn(`${AlbumPicker.TAG} 无法恢复宿主系统栏`);
        }
      };
    } catch (_) {
      console.warn(`${AlbumPicker.TAG} 无法读取宿主系统栏`);
      return async () => {};
    }
  }

  /// 仅由当前弹层接受确认；已失去归属的结果立即回收。
  private closePicker(sessionId: string, selection?: AlbumPickerSelection[]): void {
    const session = this.activePicker;
    if (session === null || session.id !== sessionId || session.closing) {
      if (selection !== undefined) {
        void AlbumPickerOutput.discard(selection);
      }
      return;
    }
    session.closing = true;
    session.selection = selection;
    void session.prompt.closeCustomDialog(session.content).catch(() => {
      console.error(`${AlbumPicker.TAG} 无法关闭相册`);
      void this.finishPicker(session, false);
    });
  }

  /// 释放原生组件后结束会话，确认和处理事件按 Dart 创建与替换占位的顺序送达。
  private async finishPicker(session: AlbumPickerSession, deliver: boolean = true): Promise<void> {
    if (this.activePicker !== session || session.finishing) {
      return;
    }
    session.finishing = true;
    session.closing = true;
    session.content.dispose();
    // 保留会话所有权直到系统栏恢复，下一次打开才能快照到宿主的原始配置。
    await session.restoreSystemBars();
    this.activePicker = null;
    const selection = session.selection;
    if (selection === undefined || selection.length === 0 || this.eventSink === null || !deliver) {
      if (selection !== undefined) {
        void AlbumPickerOutput.discard(selection);
      }
      this.emitCancel(session.id);
      return;
    }

    // 此时文件已在沙盒内可读，同一快照用于确认和每个媒体的完成事件。
    const medias = selection.map((item: AlbumPickerSelection): MediaWithId =>
      ({ id: ++this.mediaIdCounter, selection: item }));
    this.emitPickConfirm(session.id, medias, session.includeSourceMetadata);
    for (const m of medias) {
      this.emitMediaProcessing(session.id, m, session.includeSourceMetadata);
    }
    this.emitProcessed(session.id);
  }

  /// 确认和逐项完成共用媒体映射，确保路径、原图状态、大小和标识一致。
  private buildMediaPayload(m: MediaWithId, includeSourceMetadata: boolean): Record<string, ESObject> {
    const item = m.selection.media;
    const thumb = item.videoThumbnailPath;
    const payload: Record<string, ESObject> = {
      'id': m.id,
      'uri': item.filePath,
      'mediaType': item.mediaTypeIndex,
      'mediaPath': item.filePath,
      'fileExtension': item.extension,
      'fileSize': item.fileSize,
      'isOriginal': m.selection.isOriginal,
      'videoThumbnailPath': thumb.length > 0 ? thumb : null,
      'duration': item.durationMs,
    };
    if (includeSourceMetadata && m.selection.sourceName !== undefined) {
      payload['sourceFileName'] = m.selection.sourceName;
      payload['sourceFileSize'] = m.selection.sourceSize;
    }
    return payload;
  }

  private emitPickConfirm(sessionId: string, medias: MediaWithId[], includeSourceMetadata: boolean): void {
    const sink = this.eventSink;
    if (sink === null) {
      console.warn(`${AlbumPicker.TAG} emitPickConfirm dropped: no listener`);
      return;
    }
    const list = medias.map((m: MediaWithId) => this.buildMediaPayload(m, includeSourceMetadata));
    const payload: Record<string, ESObject> = {
      'type': 'onPickConfirm',
      'sessionId': sessionId,
      'pickedAlbumMedias': list,
      'textMessage': null,
    };
    sink.success(payload);
  }

  /// 导出已在图库授权有效时完成，发送层收到完成事件才会替换占位并上传。
  private emitMediaProcessing(
    sessionId: string,
    m: MediaWithId,
    includeSourceMetadata: boolean,
  ): void {
    const sink = this.eventSink;
    if (sink === null) {
      console.warn(`${AlbumPicker.TAG} emitMediaProcessing dropped: no listener`);
      return;
    }
    const payload: Record<string, ESObject> = {
      'type': 'onMediaProcessing',
      'sessionId': sessionId,
      'data': this.buildMediaPayload(m, includeSourceMetadata),
      'progress': 1.0,
      'error': false,
    };
    sink.success(payload);
  }

  private emitProcessed(sessionId: string): void {
    const sink = this.eventSink;
    if (sink === null) {
      return;
    }
    const payload: Record<string, ESObject> = {
      'type': 'onMediaProcessed',
      'sessionId': sessionId,
    };
    sink.success(payload);
  }

  private emitCancel(sessionId: string): void {
    const sink = this.eventSink;
    if (sink === null) {
      return;
    }
    const payload: Record<string, ESObject> = {
      'type': 'onCancel',
      'sessionId': sessionId,
    };
    sink.success(payload);
  }

  /// 引擎断开时释放未交付的选图结果和通道引用。
  dispose(): void {
    this.onDetachedFromAbility();
    if (this.methodChannel !== null) {
      this.methodChannel.setMethodCallHandler(null);
      this.methodChannel = null;
    }
    // EventChannel.setStreamHandler 类型上不接受 null,而 engine 断开时
    // messenger 已回收,这里只需要清本地引用即可。
    this.eventChannel = null;
    this.eventSink = null;
  }
}
