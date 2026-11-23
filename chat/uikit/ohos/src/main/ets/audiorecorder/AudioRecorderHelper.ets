import { abilityAccessCtrl, bundleManager, common, Permissions } from '@kit.AbilityKit';
import { BusinessError, systemDateTime } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';
import { mergeRecordings } from 'libchat_voice.so';

/**
 * OHOS 端 audio 录音核心工具类。
 * 从 harmony/atomic_x/audiorecorder/components/AudioRecorder.ets 复用并扩展:
 *   1. 加了 min/max duration 参数(原实现硬编码 1s / 60s)
 *   2. 加了 filepath 参数,允许 Dart 侧传入指定路径,否则内部生成
 *   3. 录音结果通过 CompletionListener.onCompleted(resultCode, path, durationMs) 返回,
 *      对齐 Android AudioRecorderHandler 的 result payload。
 *   4. powerLevel 随录音进度采样，转换为 Dart 使用的 dBFS 数值。
 *
 * ResultCode 定义与 Dart AudioRecordResultCode 一一对齐:
 *   success                      =  0
 *   successExceedMaxDuration     =  1
 *   errorCancel                  = -1
 *   errorRecording               = -2  (通用录音失败)
 *   errorStorageUnavailable      = -3
 *   errorLessThanMinDuration     = -4
 *   errorRecordInnerFail         = -5
 *   errorRecordPermissionDenied  = -6
 */

export enum RecordResultCode {
  SUCCESS = 0,
  SUCCESS_EXCEED_MAX_DURATION = 1,
  ERROR_CANCEL = -1,
  ERROR_RECORDING = -2,
  ERROR_STORAGE_UNAVAILABLE = -3,
  ERROR_LESS_THAN_MIN_DURATION = -4,
  ERROR_RECORD_INNER_FAIL = -5,
  ERROR_RECORD_PERMISSION_DENIED = -6,
}

export interface RecordProgressListener {
  /** 录音时长回调,timeMs 累计毫秒。 */
  onRecordTime?(timeMs: number): void;
  /** 峰值音量回调，单位为 dBFS。 */
  onPowerLevel?(powerLevel: number): void;
}

export interface RecordCompletionListener {
  onCompleted(resultCode: RecordResultCode, filePath: string | null, durationMs: number): void;
}

interface RecordConfig {
  filepath: string | null;
  enableAIDeNoise: boolean;
  minDurationMs: number;
  maxDurationMs: number;
  cacheDir: string;                        // 生成 filepath 时用
  uiAbilityContext: common.UIAbilityContext | null;   // 用来查权限
  progress: RecordProgressListener | null;
  completion: RecordCompletionListener;
}

/** 管理鸿蒙采音和录音文件，在有效音频落盘后向平台桥接交付一次结果。 */
export default class AudioRecorderHelper {
  private static readonly TAG = 'ChatUiKit.AudioRecorderHelper';
  /** 进度和音量的刷新间隔，不负责判断录音上限。 */
  private static readonly PROGRESS_INTERVAL_MS = 200;
  private static readonly MIC_PERM: Permissions = 'ohos.permission.MICROPHONE';

  private static _instance: AudioRecorderHelper | null = null;
  static shared(): AudioRecorderHelper {
    if (AudioRecorderHelper._instance === null) {
      AudioRecorderHelper._instance = new AudioRecorderHelper();
    }
    return AudioRecorderHelper._instance;
  }

  private avRecorder: media.AVRecorder | null = null;
  private audioFile: fs.File | null = null;
  private recordingFilePath: string = '';
  /** 仅采音期间为真，停止和裁剪前同步复位以拒绝重复收尾。 */
  private isRecording: boolean = false;
  /** 当前片段的启动时间，使用单调时钟，避免系统时间调整改变录音时长。 */
  private recordingStartTs: number = 0;
  /** 停止或取消时一并清理，避免上次进度回调影响下一段录音。 */
  private progressTimerId: number = -1;
  /** 采音成功启动后按剩余额度计时，先到期限会请求自动停止。 */
  private limitTimerId: number = -1;
  private progress: RecordProgressListener | null = null;
  private completion: RecordCompletionListener | null = null;
  /** 持有采音会话直到结果交付，启动和裁剪期间仍独占文件与回调。 */
  private currentConfig: RecordConfig | null = null;
  /** 保证 completion 只被 fire 一次,stop 和 timeout 竞争 */
  private completionFired: boolean = false;

  /** 权限与路径检查通过后启动采音；上限从实际开始采音时计算。 */
  async startRecord(config: RecordConfig): Promise<void> {
    if (this.currentConfig !== null) {
      console.warn(`${AudioRecorderHelper.TAG} already recording, reject start`);
      config.completion.onCompleted(RecordResultCode.ERROR_RECORDING, null, 0);
      return;
    }

    this.currentConfig = config;
    this.progress = config.progress;
    this.completion = config.completion;
    this.completionFired = false;

    // 1) 权限:Dart 上层调用前已经 Permission.checkAndRequest(microphone),
    //    这里只 check,授权被撤销时才走 -6 分支。
    const hasPerm = await this.checkMicPermission();
    if (!hasPerm) {
      this.fireCompletion(RecordResultCode.ERROR_RECORD_PERMISSION_DENIED, null, 0);
      return;
    }

    // 2) 目标文件路径
    try {
      this.recordingFilePath = this.resolveTargetPath(config.filepath, config.cacheDir);
      await this.ensureParentDir(this.recordingFilePath);
      this.audioFile = fs.openSync(
        this.recordingFilePath,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE,
      );
    } catch (e) {
      console.error(`${AudioRecorderHelper.TAG} prepare file failed`, (e as BusinessError).message);
      this.fireCompletion(RecordResultCode.ERROR_STORAGE_UNAVAILABLE, null, 0);
      return;
    }

    // 3) 创建 AVRecorder,准备参数
    try {
      this.avRecorder = await media.createAVRecorder();
      this.setupRecorderCallbacks();
      const avConfig: media.AVRecorderConfig = {
        audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
        profile: {
          audioBitrate: 100000,
          audioChannels: 1,
          audioCodec: media.CodecMimeType.AUDIO_AAC,
          audioSampleRate: 16000,
          fileFormat: media.ContainerFormatType.CFT_MPEG_4A,
        },
        url: `fd://${this.audioFile.fd}`,
      };
      await this.avRecorder.prepare(avConfig);
      await this.avRecorder.start();
    } catch (e) {
      console.error(`${AudioRecorderHelper.TAG} start failed`, (e as BusinessError).message);
      await this.cleanupRecorder();
      this.fireCompletion(RecordResultCode.ERROR_RECORD_INNER_FAIL, null, 0);
      return;
    }

    // 4) 状态置位 + 计时
    this.isRecording = true;
    this.recordingStartTs = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP);
    this.startProgressTracking(config.maxDurationMs);
  }

  /** 用户主动停止(松开语音键)。产生成功结果或时长过短结果。 */
  async stopRecord(): Promise<void> {
    if (!this.isRecording) {
      console.warn(`${AudioRecorderHelper.TAG} stopRecord called but not recording`);
      return;
    }
    await this.finishAndEmit(false);
  }

  /** 用户取消(上滑取消)。产生 -1 cancel 结果并删除录音文件。 */
  async cancelRecord(): Promise<void> {
    if (!this.isRecording) {
      return;
    }
    this.isRecording = false;
    this.stopProgressTracking();
    await this.cleanupRecorder();
    await this.deleteRecordingFile();
    this.fireCompletion(RecordResultCode.ERROR_CANCEL, null, 0);
  }

  // ---- private ----
  //
  // ---- 私有 ----

  /** 停止录音、校验时长并交付文件；限时结束时裁掉录音器停止延迟带来的尾帧。 */
  private async finishAndEmit(timedOut: boolean): Promise<void> {
    // 先结束采音状态，计时到期与松手竞争时只允许一方收尾。
    this.isRecording = false;
    this.stopProgressTracking();

    const maxMs = this.currentConfig?.maxDurationMs ?? 60000;
    const elapsed = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP) - this.recordingStartTs;
    const reachedLimit = timedOut || elapsed >= maxMs;
    const finalDurationMs = reachedLimit ? maxMs : elapsed;

    // 先落盘 stop + release,再判定 min duration,否则 avRecorder 内部资源没释放
    let stopOk = true;
    try {
      const r = this.avRecorder;
      if (r !== null && (r.state === 'started' || r.state === 'paused')) {
        await r.stop();
      }
    } catch (e) {
      stopOk = false;
      console.warn(`${AudioRecorderHelper.TAG} stop() failed`, (e as BusinessError).message);
    }
    await this.cleanupRecorder();

    const minMs = this.currentConfig?.minDurationMs ?? 1000;
    if (finalDurationMs < minMs) {
      await this.deleteRecordingFile();
      this.fireCompletion(RecordResultCode.ERROR_LESS_THAN_MIN_DURATION, null, finalDurationMs);
      return;
    }
    if (!stopOk) {
      // stop 失败:结果文件可能已经写了大部分,但为了保守起见按 inner fail 处理
      this.fireCompletion(RecordResultCode.ERROR_RECORD_INNER_FAIL, null, finalDurationMs);
      return;
    }
    if (reachedLimit) {
      // AVRecorder 异步落盘后才可裁剪；重封装只保留额度内的完整 AAC 帧。
      const trimmedPath = `${this.recordingFilePath}.trimmed.m4a`;
      try {
        await mergeRecordings([this.recordingFilePath], trimmedPath, maxMs);
      } catch (e) {
        console.warn(`${AudioRecorderHelper.TAG} trim failed`, (e as BusinessError).message);
        await this.deleteRecordingFile();
        this.fireCompletion(RecordResultCode.ERROR_RECORD_INNER_FAIL, null, finalDurationMs);
        return;
      }
      await this.deleteRecordingFile();
      this.fireCompletion(RecordResultCode.SUCCESS_EXCEED_MAX_DURATION, trimmedPath, finalDurationMs);
      return;
    }
    this.fireCompletion(RecordResultCode.SUCCESS, this.recordingFilePath, finalDurationMs);
  }

  /** 采音中的异步故障由错误回调处理；启动与收尾失败由对应的方法处理。 */
  private setupRecorderCallbacks(): void {
    const r = this.avRecorder;
    if (r === null) {
      return;
    }
    r.on('error', (err: BusinessError) => {
      if (!this.isRecording || r !== this.avRecorder) {
        return;
      }
      console.error(`${AudioRecorderHelper.TAG} avRecorder error`, err.message);
      // 走 cancel 语义,清理资源并回调 inner fail
      this.isRecording = false;
      this.stopProgressTracking();
      this.cleanupRecorder().finally(() => {
        this.deleteRecordingFile().finally(() => {
          this.fireCompletion(RecordResultCode.ERROR_RECORD_INNER_FAIL, null, 0);
        });
      });
    });
  }

  /** 限时停止与界面采样分别计时，避免200毫秒的进度采样推迟截断。 */
  private startProgressTracking(maxDurationMs: number): void {
    this.stopProgressTracking();
    this.limitTimerId = setTimeout(() => {
      if (this.isRecording) {
        this.finishAndEmit(true).catch((e: Error) => {
          console.warn(`${AudioRecorderHelper.TAG} auto stop on max duration failed`, e.message);
        });
      }
    }, maxDurationMs);
    this.progressTimerId = setInterval(() => {
      if (!this.isRecording) {
        return;
      }
      const elapsed = systemDateTime.getUptime(systemDateTime.TimeType.STARTUP) - this.recordingStartTs;
      this.progress?.onRecordTime?.(Math.min(elapsed, maxDurationMs));
      void this.samplePowerLevel();
    }, AudioRecorderHelper.PROGRESS_INTERVAL_MS);
  }

  /** 音量采样失败不应中断录音；停止或切换会话后丢弃迟到结果。 */
  private async samplePowerLevel(): Promise<void> {
    const recorder = this.avRecorder;
    if (recorder === null || !this.progress?.onPowerLevel) return;
    try {
      const amplitude = await recorder.getAudioCapturerMaxAmplitude();
      if (this.isRecording && this.avRecorder === recorder) {
        // 采集峰值按 16 位满幅换算，与 Android 和 iOS 使用同一音量契约。
        const ratio = Math.min(1, Math.max(1, amplitude) / 32768);
        this.progress?.onPowerLevel?.(Math.round(20 * Math.log10(ratio)));
      }
    } catch (_err) {
      // 设备中断或停止时统计可能暂不可用，下一次进度采样可以恢复。
    }
  }

  /** 结束采音时同时废止进度监听和限时停止回调。 */
  private stopProgressTracking(): void {
    if (this.limitTimerId !== -1) {
      clearTimeout(this.limitTimerId);
      this.limitTimerId = -1;
    }
    if (this.progressTimerId !== -1) {
      clearInterval(this.progressTimerId);
      this.progressTimerId = -1;
    }
  }

  private async cleanupRecorder(): Promise<void> {
    const r = this.avRecorder;
    this.avRecorder = null;
    if (r !== null) {
      try {
        const state = r.state;
        if (state !== 'idle' && state !== 'released') {
          try {
            await r.reset();
          } catch (e) {
            console.warn(`${AudioRecorderHelper.TAG} reset failed`, (e as BusinessError).message);
          }
        }
        await r.release();
      } catch (e) {
        console.warn(`${AudioRecorderHelper.TAG} release failed`, (e as BusinessError).message);
      }
    }
    const f = this.audioFile;
    this.audioFile = null;
    if (f !== null) {
      try {
        fs.closeSync(f);
      } catch (e) {
        console.warn(`${AudioRecorderHelper.TAG} close fd failed`, (e as BusinessError).message);
      }
    }
  }

  private async deleteRecordingFile(): Promise<void> {
    if (this.recordingFilePath.length === 0) {
      return;
    }
    try {
      if (fs.accessSync(this.recordingFilePath)) {
        fs.unlinkSync(this.recordingFilePath);
      }
    } catch (e) {
      console.warn(`${AudioRecorderHelper.TAG} unlink recording failed`,
        (e as BusinessError).message);
    }
    this.recordingFilePath = '';
  }

  private fireCompletion(
    code: RecordResultCode,
    filePath: string | null,
    durationMs: number,
  ): void {
    if (this.completionFired) {
      return;
    }
    this.completionFired = true;
    const cb = this.completion;
    this.completion = null;
    this.progress = null;
    this.currentConfig = null;
    cb?.onCompleted(code, filePath, durationMs);
  }

  private resolveTargetPath(preferred: string | null, cacheDir: string): string {
    if (preferred !== null && preferred.length > 0) {
      return preferred;
    }
    const timestamp = Date.now();
    const rand = Math.floor(Math.random() * 1e6);
    return `${cacheDir}/audio_recorder/voice_${timestamp}_${rand}.m4a`;
  }

  private async ensureParentDir(filePath: string): Promise<void> {
    const idx = filePath.lastIndexOf('/');
    if (idx <= 0) {
      return;
    }
    const dir = filePath.substring(0, idx);
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (e) {
      console.warn(`${AudioRecorderHelper.TAG} mkdir failed ${dir}`,
        (e as BusinessError).message);
    }
  }

  /**
   * 只 check 不 request。Dart 上层在打开录音面板前已经 checkAndRequest 过一次,
   * 此处 fail 说明用户在设置里撤销了权限,给一个明确的 -6 结果。
   */
  private async checkMicPermission(): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const info = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION,
      );
      const status = await atManager.checkAccessToken(info.appInfo.accessTokenId, AudioRecorderHelper.MIC_PERM);
      return status === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (e) {
      console.warn(`${AudioRecorderHelper.TAG} checkMicPermission failed`,
        (e as BusinessError).message);
      return false;
    }
  }
}
