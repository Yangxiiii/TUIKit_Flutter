import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import { AlbumImageRenderer } from './AlbumImageRenderer';
import AlbumPickerHelper, { AlbumPickMode, AlbumPickResult } from './AlbumPickerHelper';

export interface AlbumPickerSelection {
  /// 沙盒文件及其媒体信息，确认后由调用方接管。
  media: AlbumPickResult;
  /// 交付未经转码的来源文件时为真，来源可能是编辑后的沙盒副本。
  isOriginal: boolean;
  /// 处理前的文件名，使用编辑稿时不作为原件信息返回。
  sourceName?: string;
  /// 处理前来源文件的字节数。
  sourceSize: number;
}

/// 在相册读取授权有效期间生成沙盒结果，确保确认只交付完整选集。
export class AlbumPickerOutput {
  /// 安卓相册标准档的短边上限，单位为像素。
  private static readonly IMAGE_SHORT_EDGE_LIMIT = 1080;
  /// 安卓相册标准档的 JPEG 编码质量，取值范围为 0 至 100。
  private static readonly IMAGE_JPEG_QUALITY = 90;
  /// 安卓视频标准档的短边上限，单位为像素。
  private static readonly VIDEO_SHORT_EDGE_LIMIT = 720;
  /// 安卓视频标准档的画面目标码率，单位为比特每秒。
  private static readonly VIDEO_BITRATE = 1200000;
  /// 安卓视频标准档的音频目标码率，单位为比特每秒。
  private static readonly VIDEO_AUDIO_BITRATE = 64000;
  /// MP4 的总平均码率超过目标总码率的 1.2 倍才转码。
  private static readonly VIDEO_BITRATE_TOLERANCE = 1.2;
  /// 单个视频的转码等待上限，超时交付原件，避免确认一直不可用。
  private static readonly VIDEO_TRANSCODE_TIMEOUT_MS = 60000;

  /// 单项导出失败时清理本次结果并拒绝整批，允许用户在当前页面重试。
  static async prepare(uris: string[], original: boolean, context: common.Context): Promise<AlbumPickerSelection[]> {
    // IM 与原生 CallKit 使用应用级缓存，媒体和封面都须落在同一个目录下供 RequestKit 上传。
    const cacheDir = context.getApplicationContext().cacheDir;
    const files = await AlbumPickerHelper.exportSelectedMedia(uris, cacheDir, null);
    // 导出工具允许跳过失败项，独立选择器必须保留用户确认的数量和顺序。
    if (files.length !== uris.length || files.some((item: AlbumPickResult) => item.fileSize <= 0)) {
      await AlbumPickerOutput.removeFiles(files);
      throw new Error('相册选中的文件未全部导出');
    }

    const selections: AlbumPickerSelection[] = [];
    // 串行处理可保持选择顺序，也避免同时占用多个视频编解码器。
    for (const item of files) {
      const sourceName = item.fileName;
      const sourceSize = item.fileSize;
      let compressed = false;
      if (!original) {
        compressed = item.mediaTypeIndex === AlbumPickMode.VIDEO ?
          await AlbumPickerOutput.compressVideo(item) : await AlbumPickerOutput.compressImage(item);
      }
      selections.push({ media: item, isOriginal: !compressed, sourceName, sourceSize });
    }
    return selections;
  }

  /// 放弃异步生成的结果，释放本次创建的媒体和视频缩略图。
  static async discard(selections: AlbumPickerSelection[]): Promise<void> {
    await AlbumPickerOutput.removeFiles(selections.map((selection: AlbumPickerSelection) => selection.media));
  }

  /// 将可解码图片输出为标准档 JPEG，解码或落盘失败时交付来源文件。
  private static async compressImage(item: AlbumPickResult): Promise<boolean> {
    const compressedPath = `${item.filePath}.compressed.jpg`;
    let bitmap: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;
    let replacementSize = 0;

    try {
      // 解码时限制短边并转正像素，保证导出的 JPEG 无需依赖原有 EXIF 方向。
      bitmap = await AlbumImageRenderer.load(item.filePath, AlbumPickerOutput.IMAGE_SHORT_EDGE_LIMIT);
      packer = image.createImagePacker();
      const target = await fileIo.open(compressedPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY |
        fileIo.OpenMode.TRUNC);
      try {
        await packer.packToFile(bitmap, target.fd, { format: 'image/jpeg', quality: AlbumPickerOutput.IMAGE_JPEG_QUALITY });
      } finally {
        await fileIo.close(target);
      }
      replacementSize = (await fileIo.stat(compressedPath)).size;
    } catch (_) {
      // 编解码失败时仍可交付完整原件。
    } finally {
      await packer?.release().catch(() => {});
      await bitmap?.release().catch(() => {});
    }

    if (replacementSize <= 0) {
      await AlbumPickerOutput.unlink(compressedPath);
      return false;
    }
    // 安卓标准档以 JPEG 写入成功为准，文件比来源大时也采用，并同步 JPEG 后缀。
    await AlbumPickerOutput.replaceFile(item, compressedPath, replacementSize);
    const dot = item.fileName.lastIndexOf('.');
    item.fileName = `${dot > 0 ? item.fileName.slice(0, dot) : item.fileName}.jpg`;
    item.extension = 'jpg';
    return true;
  }

  /// 按安卓标准档判断并转码为 MP4，失败或无需转码时交付来源文件。
  private static async compressVideo(item: AlbumPickResult): Promise<boolean> {
    const compressedPath = `${item.filePath}.compressed.mp4`;
    let source: fileIo.File | undefined;
    let target: fileIo.File | undefined;
    let transcoder: media.AVTranscoder | undefined;
    let timeout = -1;
    let replacementSize = 0;

    try {
      source = await fileIo.open(item.filePath, fileIo.OpenMode.READ_ONLY);
      const input: media.AVFileDescriptor = { fd: source.fd, offset: 0, length: item.fileSize };
      const metadata = await AlbumPickerHelper.readVideoMetadata(input);
      const config = AlbumPickerOutput.videoConfig(item, metadata);
      if (config === undefined) {
        return false;
      }
      // 只有需要转码时才创建输出文件，避免为达标的 MP4 生成临时文件。
      target = await fileIo.open(compressedPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY |
        fileIo.OpenMode.TRUNC);
      const job = await media.createAVTranscoder();
      transcoder = job;
      job.fdSrc = input;
      job.fdDst = target.fd;

      // 先监听终态再开始转码，遇到系统错误或无回调时保留原文件。
      await new Promise<void>((resolve, reject) => {
        timeout = setTimeout(() => reject(new Error('视频转码超时')), AlbumPickerOutput.VIDEO_TRANSCODE_TIMEOUT_MS);
        job.on('complete', () => resolve());
        job.on('error', (error) => reject(error));
        job.prepare(config).then(() => job.start()).catch((error: Error) => reject(error));
      });

      // 媒体服务释放转码器后才完成 MP4 封装，不能提前读取或交付。
      await job.release();
      transcoder = undefined;
      await fileIo.close(target);
      target = undefined;
      replacementSize = (await fileIo.stat(compressedPath)).size;
    } catch (_) {
      // 设备缺少编解码能力或转码失败时仍可交付原件。
    } finally {
      clearTimeout(timeout);
      if (transcoder !== undefined) {
        try { await transcoder.release(); } catch (_) { /* 回收后续文件仍需继续。 */ }
      }
      if (target !== undefined) {
        try { await fileIo.close(target); } catch (_) { /* 下方统一处理转码文件。 */ }
      }
      if (source !== undefined) {
        try { await fileIo.close(source); } catch (_) { /* 关闭失败不删除原件。 */ }
      }
    }

    // 安卓在转码成功时采用新文件，即使小码率的其他格式转为 MP4 后体积增大。
    if (replacementSize <= 0) {
      await AlbumPickerOutput.unlink(compressedPath);
      return false;
    }
    await AlbumPickerOutput.replaceFile(item, compressedPath, replacementSize);
    item.extension = 'mp4';
    item.fileName = `${item.fileName.slice(0, item.fileName.lastIndexOf('.'))}.mp4`;
    return true;
  }

  /// 通过存储尺寸和平均码率复用安卓标准档的保留或转码判定。
  private static videoConfig(item: AlbumPickResult, metadata: media.AVMetadata): media.AVTranscoderConfig | undefined {
    const width = Number(metadata.videoWidth ?? 0);
    const height = Number(metadata.videoHeight ?? 0);
    const shortEdge = Math.min(width, height);
    if (!Number.isFinite(shortEdge) || shortEdge <= 0) {
      return undefined;
    }
    // 安卓用完整文件大小估算音视频总码率。非 MP4 优先转码以统一容器。
    const duration = Number(metadata.duration ?? item.durationMs);
    const bitrate = duration > 0 ? Math.floor(item.fileSize * 8000 / duration) : 0;
    const threshold = (AlbumPickerOutput.VIDEO_BITRATE + AlbumPickerOutput.VIDEO_AUDIO_BITRATE) *
      AlbumPickerOutput.VIDEO_BITRATE_TOLERANCE;
    if (item.extension === 'mp4' && (metadata.mimeType ?? 'video/mp4') === 'video/mp4' && bitrate <= threshold) {
      return undefined;
    }

    const config: media.AVTranscoderConfig = {
      fileFormat: media.ContainerFormatType.CFT_MPEG_4,
      videoCodec: media.CodecMimeType.VIDEO_AVC,
      audioCodec: media.CodecMimeType.AUDIO_AAC,
      videoBitrate: AlbumPickerOutput.VIDEO_BITRATE,
      audioBitrate: AlbumPickerOutput.VIDEO_AUDIO_BITRATE,
    };
    // 使用视频轨的存储宽高计算偶数尺寸，避免将旋转后的显示宽高传给编码器。
    const targetShortEdge = Math.min(shortEdge, AlbumPickerOutput.VIDEO_SHORT_EDGE_LIMIT);
    const targetWidth = Math.floor(width * targetShortEdge / (2 * shortEdge)) * 2;
    const targetHeight = Math.floor(height * targetShortEdge / (2 * shortEdge)) * 2;
    if (targetWidth !== width || targetHeight !== height) {
      config.videoFrameWidth = targetWidth;
      config.videoFrameHeight = targetHeight;
    }
    return config;
  }

  /// 调用方确认写入完成后，移除来源副本并更新交付文件的位置和大小。
  private static async replaceFile(item: AlbumPickResult, path: string, size: number): Promise<void> {
    await AlbumPickerOutput.unlink(item.filePath);
    item.filePath = path;
    item.fileSize = size;
  }

  /// 只清理本次生成的沙盒文件，原相册内容始终由图库管理。
  private static async removeFiles(media: AlbumPickResult[]): Promise<void> {
    for (const item of media) {
      await AlbumPickerOutput.unlink(item.filePath);
      if (item.videoThumbnailPath.length > 0) {
        await AlbumPickerOutput.unlink(item.videoThumbnailPath);
      }
    }
  }

  private static async unlink(path: string): Promise<void> {
    try {
      await fileIo.unlink(path);
    } catch (_) {
      // 临时文件可能尚未创建，也可能已被系统回收。
    }
  }
}
