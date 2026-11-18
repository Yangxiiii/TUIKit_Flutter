import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { media } from '@kit.MediaKit';
import AlbumPickerHelper, { AlbumPickMode, AlbumPickResult } from './AlbumPickerHelper';

export interface AlbumPickerSelection {
  /// 沙盒文件及其媒体信息，确认后由调用方接管。
  media: AlbumPickResult;
  /// 实际返回原件时为真，包括压缩不适用或压缩文件更大的情况。
  isOriginal: boolean;
  /// 处理前原件的字节数。
  sourceSize: number;
}

/// 在相册读取授权有效期间生成沙盒结果，确保确认只交付完整选集。
export class AlbumPickerOutput {
  /// 单个视频的转码等待上限，超时交付原件，避免确认一直不可用。
  private static readonly VIDEO_TRANSCODE_TIMEOUT_MS = 60000;

  /// 单项导出失败时清理本次结果并拒绝整批，允许用户在当前页面重试。
  static async prepare(uris: string[], original: boolean, context: common.Context): Promise<AlbumPickerSelection[]> {
    // 新页面只依赖已选 URI 的读取权限，视频信息从沙盒副本提取。
    const files = await AlbumPickerHelper.exportSelectedMedia(uris, context.cacheDir, null);
    // 导出工具允许跳过失败项，独立选择器必须保留用户确认的数量和顺序。
    if (files.length !== uris.length || files.some((item: AlbumPickResult) => item.fileSize <= 0)) {
      await AlbumPickerOutput.removeFiles(files);
      throw new Error('相册选中的文件未全部导出');
    }

    const selections: AlbumPickerSelection[] = [];
    // 串行处理可保持选择顺序，也避免同时占用多个视频编解码器。
    for (const item of files) {
      const sourceSize = item.fileSize;
      let compressed = false;
      if (!original) {
        compressed = item.mediaTypeIndex === AlbumPickMode.VIDEO ?
          await AlbumPickerOutput.compressVideo(item) : await AlbumPickerOutput.compressJpeg(item);
      }
      selections.push({ media: item, isOriginal: !compressed, sourceSize });
    }
    return selections;
  }

  /// 放弃异步生成的结果，释放本次创建的媒体和视频缩略图。
  static async discard(selections: AlbumPickerSelection[]): Promise<void> {
    await AlbumPickerOutput.removeFiles(selections.map((selection: AlbumPickerSelection) => selection.media));
  }

  /// 将普通 JPEG 重新编码到独立文件，只有体积下降且写入成功才替换原件副本。
  private static async compressJpeg(item: AlbumPickResult): Promise<boolean> {
    // shortcut: 非 JPEG 图片保留原件，待编码器覆盖动图、透明通道和广色域后扩展。
    if (item.extension !== 'jpg' && item.extension !== 'jpeg') {
      return false;
    }

    const compressedPath = `${item.filePath}.compressed.${item.extension}`;
    let source: image.ImageSource | undefined;
    let packer: image.ImagePacker | undefined;
    let target: fileIo.File | undefined;
    let replacementSize = 0;

    try {
      // 传入图源并保留属性，避免丢失原有方向信息。
      source = image.createImageSource(item.filePath);
      packer = image.createImagePacker();
      target = await fileIo.open(compressedPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY |
        fileIo.OpenMode.TRUNC);
      await packer.packToFile(source, target.fd, { format: 'image/jpeg', quality: 85, needsPackProperties: true });
      const info = await fileIo.stat(compressedPath);
      if (info.size > 0 && info.size < item.fileSize) {
        replacementSize = info.size;
      }
    } catch (_) {
      // 编解码失败时仍可交付完整原件。
    } finally {
      if (target !== undefined) {
        try { await fileIo.close(target); } catch (_) { /* 沙盒文件仍由下方分支统一处理。 */ }
      }
      if (packer !== undefined) {
        try { await packer.release(); } catch (_) { /* 释放失败不影响已经落盘的文件。 */ }
      }
      if (source !== undefined) {
        try { await source.release(); } catch (_) { /* 释放失败不影响原文件。 */ }
      }
    }

    // 压缩结果与原件二选一，先确定结果有效再移除另一份文件。
    return await AlbumPickerOutput.replaceIfSmaller(item, compressedPath, replacementSize);
  }

  /// 使用系统视频转码器写出 MP4，结束事件和文件释放都成功后才采用产物。
  private static async compressVideo(item: AlbumPickResult): Promise<boolean> {
    const compressedPath = `${item.filePath}.compressed.mp4`;
    let source: fileIo.File | undefined;
    let target: fileIo.File | undefined;
    let transcoder: media.AVTranscoder | undefined;
    let timeout = -1;
    let replacementSize = 0;

    try {
      source = await fileIo.open(item.filePath, fileIo.OpenMode.READ_ONLY);
      target = await fileIo.open(compressedPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY |
        fileIo.OpenMode.TRUNC);
      const job = await media.createAVTranscoder();
      transcoder = job;
      job.fdSrc = { fd: source.fd, offset: 0, length: item.fileSize };
      job.fdDst = target.fd;

      // 先监听终态再开始转码，遇到系统错误或无回调时保留原文件。
      await new Promise<void>((resolve, reject) => {
        timeout = setTimeout(() => reject(new Error('视频转码超时')), AlbumPickerOutput.VIDEO_TRANSCODE_TIMEOUT_MS);
        job.on('complete', () => resolve());
        job.on('error', (error) => reject(error));
        const config: media.AVTranscoderConfig = { fileFormat: media.ContainerFormatType.CFT_MPEG_4 };
        job.prepare(config).then(() => job.start()).catch((error: Error) => reject(error));
      });

      // 媒体服务释放转码器后才完成 MP4 封装，不能提前读取或交付。
      await job.release();
      transcoder = undefined;
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

    if (await AlbumPickerOutput.replaceIfSmaller(item, compressedPath, replacementSize)) {
      item.extension = 'mp4';
      item.fileName = `${item.fileName.slice(0, item.fileName.lastIndexOf('.'))}.mp4`;
      return true;
    }
    return false;
  }

  /// 仅在产物有效且体积下降时替换沙盒原件，否则移除临时产物。
  private static async replaceIfSmaller(item: AlbumPickResult, path: string, size: number): Promise<boolean> {
    if (size <= 0 || size >= item.fileSize) {
      await AlbumPickerOutput.unlink(path);
      return false;
    }
    await AlbumPickerOutput.unlink(item.filePath);
    item.filePath = path;
    item.fileSize = size;
    return true;
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
