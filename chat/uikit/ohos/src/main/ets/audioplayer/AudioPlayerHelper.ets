import { audio } from '@kit.AudioKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { media } from '@kit.MediaKit';

/**
 * OHOS 端 audio 播放核心工具类。
 * 完整复用 harmony/atomic_x/audioplayer/utils/AudioPlayer.ets 的 MediaAudioPlayer 实现,
 * 差异:
 *   1. 单例(global),chat 会话内同时只允许一个音频在放,方便 Dart 上层做互斥。
 *   2. progress 用 setInterval 而不是递归 setTimeout,避免 stop 后残留一次触发。
 *   3. play 时如果传入的 filePath 与当前正在播放的一致,直接 resume 避免重开 fd。
 *
 * AVPlayer 状态机链路:
 *   setSource(url=fd://) -> initialized -> prepare -> prepared -> play -> playing
 *   pause/resume/stop/completed 都靠 stateChange 回调驱动 listener。
 */

export interface AudioPlayerListener {
  onPlay?(): void;
  onPause?(): void;
  onResume?(): void;
  onProgressUpdate?(currentPositionMs: number, durationMs: number): void;
  onCompletion?(): void;
  onError?(errorMessage: string): void;
}

export default class AudioPlayerHelper {
  private static readonly TAG = 'ChatUiKit.AudioPlayerHelper';
  private static readonly PROGRESS_INTERVAL_MS = 200;

  private static _instance: AudioPlayerHelper | null = null;
  static shared(): AudioPlayerHelper {
    if (AudioPlayerHelper._instance === null) {
      AudioPlayerHelper._instance = new AudioPlayerHelper();
    }
    return AudioPlayerHelper._instance;
  }

  private avPlayer: media.AVPlayer | null = null;
  private srcFile: fs.File | null = null;
  private _isPlaying: boolean = false;
  private _isPaused: boolean = false;
  private currentDuration: number = 0;
  private currentPosition: number = 0;
  private listener: AudioPlayerListener | null = null;
  private progressTimerId: number = -1;

  /** 本条消息恢复起点，单位为毫秒；只在当前播放器准备完成后应用。 */
  private startPositionMs: number = 0;
  /** 等待定位完成后再开始发声，不能先播放文件开头。 */
  private waitingForSeek: boolean = false;

  /** 仅在原生接受配置后更新；停止音源不丢失用户选择的下一次播放方式。 */
  private earpieceMode: boolean = false;
  /** 用户是否主动选择播放方式；未选择时尊重连接的耳机。 */
  private routeConfigured: boolean = false;
  /** 只恢复本播放器修改过且仍由它持有的外放状态，避免覆盖后来接入的通话。 */
  private previousSpeaker: boolean | null = null;
  private appliedSpeaker: boolean | null = null;

  /** 无听筒设备明确失败；活动语音切换时等待原生路由确认，不能只改菜单状态。 */
  async setEarpiece(enabled: boolean): Promise<void> {
    const routing = audio.getAudioManager().getRoutingManager();
    const devices = await routing.getDevices(audio.DeviceFlag.OUTPUT_DEVICES_FLAG);
    if (enabled && !devices.some((device: audio.AudioDeviceDescriptor) => device.deviceType === audio.DeviceType.EARPIECE)) {
      throw new Error('Earpiece is unavailable');
    }
    if (this._isPlaying) await this.applyRoute(!enabled);
    this.earpieceMode = enabled;
    this.routeConfigured = true;
  }

  /** 保存原路由并核实切换；失败回滚硬件，不能只保留旧菜单状态。 */
  private async applyRoute(speaker: boolean): Promise<void> {
    const routing = audio.getAudioManager().getRoutingManager();
    const previous = await routing.isCommunicationDeviceActive(audio.CommunicationDeviceType.SPEAKER);
    try {
      await routing.setCommunicationDevice(audio.CommunicationDeviceType.SPEAKER, speaker);
      if ((await routing.isCommunicationDeviceActive(audio.CommunicationDeviceType.SPEAKER)) !== speaker) {
        throw new Error('Audio route rejected');
      }
      if (this.previousSpeaker === null) this.previousSpeaker = previous;
      this.appliedSpeaker = speaker;
    } catch (error) {
      await routing.setCommunicationDevice(audio.CommunicationDeviceType.SPEAKER, previous);
      throw error;
    }
  }

  /** 停止后归还共享音频资源，外部已接管路由时不覆盖外部选择。 */
  private async restoreRoute(): Promise<void> {
    const previous = this.previousSpeaker;
    const applied = this.appliedSpeaker;
    this.previousSpeaker = null;
    this.appliedSpeaker = null;
    if (previous === null || applied === null) return;
    const routing = audio.getAudioManager().getRoutingManager();
    if ((await routing.isCommunicationDeviceActive(audio.CommunicationDeviceType.SPEAKER)) === applied) {
      await routing.setCommunicationDevice(audio.CommunicationDeviceType.SPEAKER, previous);
    }
  }

  setListener(listener: AudioPlayerListener | null): void {
    this.listener = listener;
  }

  async play(filePath: string, startPositionMs: number = 0): Promise<void> {
    try {
      // 若当前有播放器,先彻底 release 掉,避免 stateChange 事件混淆
      if (this.avPlayer !== null) {
        await this.stop();
      }

      this.startPositionMs = startPositionMs;
      this.waitingForSeek = false;
      this.avPlayer = await media.createAVPlayer();
      this.setupAVPlayerCallbacks();

      // 分两种 source:
      //   1) http(s):// —— TTS 朗读、AI 翻译语音等,后端下发临时签名 URL,
      //      AVPlayer 原生支持,直接赋给 url,由播放器内部走网络加载。
      //   2) 本地绝对路径 —— IMSDK 缓存的语音消息文件,fs.open 拿 fd 后走 fd:// 播放,
      //      fd 的所有权在 stop() 里 close,避免泄漏。
      if (AudioPlayerHelper.isNetworkUrl(filePath)) {
        this.avPlayer.url = filePath;
      } else {
        try {
          this.srcFile = await fs.open(filePath, fs.OpenMode.READ_ONLY);
        } catch (e) {
          this.emitError(`can not open file: ${filePath}, ${(e as BusinessError).message}`);
          // 失败时必须把刚创建的 avPlayer 释放掉,否则下次 play 时残留 state 会崩
          await this.stop();
          return;
        }
        this.avPlayer.url = `fd://${this.srcFile.fd}`;
      }
      // 从这里开始 AVPlayer 会自动流转到 initialized -> prepared -> playing,
      // 见 setupAVPlayerCallbacks.stateChange 里的处理。
    } catch (e) {
      this.emitError(`play error: ${(e as Error).message}`);
      // 兜底:任何异常都要清理已创建的 avPlayer,防止状态残留导致下次 play 崩
      await this.stop().catch((se: Error) => {
        console.warn(`${AudioPlayerHelper.TAG} stop after play error failed`, se.message);
      });
    }
  }

  private static isNetworkUrl(path: string): boolean {
    const lower = path.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  /** 暂停保留消息位置，先归还本播放器修改过的路由，避免与来电抢占。 */
  async pause(): Promise<void> {
    if (this.avPlayer !== null && this._isPlaying) {
      await this.avPlayer.pause();
      await this.restoreRoute();
    }
  }

  /** 恢复前重新应用用户选择，切换失败不伪报继续播放。 */
  async resume(): Promise<void> {
    const player = this.avPlayer;
    if (player !== null && this._isPaused) {
      await this.prepareRoute();
      if (this.avPlayer === player) await player.play();
    }
  }

  /** 未主动选择时尊重耳机；显式选择才允许覆盖系统外部输出。 */
  private async prepareRoute(): Promise<void> {
    const routing = audio.getAudioManager().getRoutingManager();
    const devices = await routing.getDevices(audio.DeviceFlag.OUTPUT_DEVICES_FLAG);
    const external = devices.some((device: audio.AudioDeviceDescriptor) =>
      device.deviceType !== audio.DeviceType.SPEAKER && device.deviceType !== audio.DeviceType.EARPIECE);
    if (this.routeConfigured || !external) await this.applyRoute(!this.earpieceMode);
  }

  async stop(): Promise<void> {
    this.stopProgressTracking();
    const player = this.avPlayer;
    this.avPlayer = null;
    this._isPlaying = false;
    this._isPaused = false;
    this.currentPosition = 0;

    if (player !== null) {
      // ⚠ 关键:先 off 掉 stateChange / error,避免 release 过程中
      // 老 player 触发 'released' 事件,回调里 `this.avPlayer = null`
      // 会把已被下一次 play() 创建的新 player 也置空,导致后续 play 时崩溃。
      try {
        player.off('stateChange');
        player.off('error');
        player.off('seekDone');
      } catch (_) {
        // off 失败无关紧要,继续走 stop/release
      }
      try {
        // 只有非 idle/released 状态才需要 stop
        const state = player.state;
        if (state !== 'idle' && state !== 'released') {
          await player.stop();
        }
        await player.release();
      } catch (e) {
        console.warn(`${AudioPlayerHelper.TAG} stop/release failed`, (e as BusinessError).message);
      }
    }

    // fd 在 player.release 后才安全关掉,不然 AVPlayer 内部还在读
    const f = this.srcFile;
    this.srcFile = null;
    if (f !== null) {
      try {
        fs.closeSync(f);
      } catch (e) {
        console.warn(`${AudioPlayerHelper.TAG} close(fd) failed`, (e as BusinessError).message);
      }
    }
    await this.restoreRoute();
  }

  isPlaying(): boolean {
    return this._isPlaying;
  }

  isPaused(): boolean {
    return this._isPaused;
  }

  getCurrentPosition(): number {
    return this.currentPosition;
  }

  getDuration(): number {
    return this.currentDuration;
  }

  private setupAVPlayerCallbacks(): void {
    const p = this.avPlayer;
    if (p === null) {
      return;
    }
    p.on('error', (err: BusinessError) => {
      if (this.avPlayer !== p) return;
      this.emitError(`playError: ${err.message}`);
      try {
        this.avPlayer?.reset();
      } catch (_) {
        // reset 失败也接受,通常紧接着会走 stop
      }
    });

    // 定位结果只属于当前源，旧播放器的回调不能启动新消息。
    p.on('seekDone', () => {
      if (this.avPlayer === p && this.waitingForSeek) {
        this.waitingForSeek = false;
        p.play().catch((error: Error) => this.emitError(error.message));
      }
    });

    p.on('stateChange', async (state: string, reason: media.StateChangeReason) => {
      // 已释放源的迟到事件不能操作下一条消息的新播放器。
      if (this.avPlayer !== p) return;
      switch (state) {
        case 'initialized':
          if (this.avPlayer !== null) {
            this.avPlayer.audioRendererInfo = {
              usage: audio.StreamUsage.STREAM_USAGE_VOICE_COMMUNICATION,
              rendererFlags: 0,
            };
            try {
              await p.prepare();
            } catch (e) {
              this.emitError(`prepare error: ${(e as BusinessError).message}`);
            }
          }
          break;
        case 'prepared':
          if (this.avPlayer !== null) {
            this.currentDuration = this.avPlayer.duration;
            try {
              await this.prepareRoute();
              if (this.avPlayer !== p) return;
              if (this.startPositionMs > 0) {
                this.waitingForSeek = true;
                p.seek(Math.min(this.startPositionMs, this.currentDuration), media.SeekMode.SEEK_CLOSEST);
              } else {
                await p.play();
              }
            } catch (e) {
              this.emitError(`play error: ${(e as BusinessError).message}`);
            }
          }
          break;
        case 'playing': {
          const wasPlaying = this._isPlaying;
          const wasPaused = this._isPaused;
          this._isPlaying = true;
          this._isPaused = false;
          if (wasPaused) {
            this.listener?.onResume?.();
          } else if (!wasPlaying) {
            this.listener?.onPlay?.();
          }
          this.startProgressTracking();
          break;
        }
        case 'paused':
          this._isPlaying = false;
          this._isPaused = true;
          this.stopProgressTracking();
          this.listener?.onPause?.();
          break;
        case 'completed':
          this._isPlaying = false;
          this._isPaused = false;
          this.currentPosition = 0;
          this.stopProgressTracking();
          this.listener?.onCompletion?.();
          // completed 后主动 stop+release,让下一次 play 从干净状态开始
          try {
            await this.stop();
          } catch (e) {
            console.warn(`${AudioPlayerHelper.TAG} auto stop after completed failed`,
              (e as BusinessError).message);
          }
          break;
        case 'stopped':
          this._isPlaying = false;
          this._isPaused = false;
          this.stopProgressTracking();
          break;
        case 'released':
          this.avPlayer = null;
          break;
        default:
          break;
      }
    });
  }

  private startProgressTracking(): void {
    this.stopProgressTracking();
    this.progressTimerId = setInterval(() => {
      if (this.avPlayer !== null && this._isPlaying) {
        this.currentPosition = this.avPlayer.currentTime;
        this.listener?.onProgressUpdate?.(this.currentPosition, this.currentDuration);
      }
    }, AudioPlayerHelper.PROGRESS_INTERVAL_MS);
  }

  private stopProgressTracking(): void {
    if (this.progressTimerId !== -1) {
      clearInterval(this.progressTimerId);
      this.progressTimerId = -1;
    }
  }

  private emitError(msg: string): void {
    console.error(`${AudioPlayerHelper.TAG} ${msg}`);
    this.listener?.onError?.(msg);
  }
}
