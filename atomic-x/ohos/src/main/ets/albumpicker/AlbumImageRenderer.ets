import { LengthMetricsUnit } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';

export interface EditorPoint {
  /// 正向原图中的水平比例。
  x: number;
  /// 正向原图中的垂直比例。
  y: number;
}

export interface EditorStroke {
  /// 按触摸顺序记录的原图坐标。
  points: EditorPoint[];
  /// 笔迹使用的 Canvas 颜色。
  color: string;
  /// 笔迹宽度与原图短边的比例。
  width: number;
}

export interface EditorCrop {
  /// 裁剪左边与原图左边的距离占比。
  x: number;
  /// 裁剪上边与原图上边的距离占比。
  y: number;
  /// 裁剪宽度占原图宽度的比例。
  width: number;
  /// 裁剪高度占原图高度的比例。
  height: number;
}

/// 解码本地授权图片供编辑和压缩使用，并按相册编辑坐标渲染独立副本。
export class AlbumImageRenderer {
  /// 限制长边像素和总像素，避免高分辨率照片的画布和临时位图同时占用过多内存。
  private static readonly MAX_EDGE = 4096;
  private static readonly MAX_PIXELS = 12000000;

  /// 将沙盒路径或已授权 URI 解码为正向位图。指定正整数短边上限时按发送档位缩放，
  /// 其余情况使用画布的内存限制。调用方负责释放返回的位图。
  static async load(path: string, maxShortEdge?: number): Promise<image.PixelMap> {
    let file: fileIo.File | undefined;
    let source: image.ImageSource | undefined;
    let bitmap: image.PixelMap | undefined;
    try {
      // 先用元数据限制解码尺寸。从文件描述符解码可共用图库授权 URI 和沙盒路径。
      file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      source = image.createImageSource(file.fd);
      const info = await source.getImageInfo();
      const width = info.size.width;
      const height = info.size.height;
      if (!(width > 0 && height > 0) ||
        (maxShortEdge !== undefined && (!Number.isInteger(maxShortEdge) || maxShortEdge <= 0))) {
        throw new Error('图片尺寸无效');
      }
      const desiredSize = AlbumImageRenderer.decodingSize(width, height, maxShortEdge);
      const options: image.DecodingOptions = {
        desiredSize,
        editable: true,
        desiredDynamicRange: image.DecodingDynamicRange.SDR,
      };
      // 实际转正像素，使显示、笔迹和裁剪共享坐标，输出不依赖相机 EXIF 方向。
      const orientation = await source.getImageProperty(image.PropertyKey.ORIENTATION).catch(() => '');
      bitmap = await source.createPixelMap(options);
      await AlbumImageRenderer.orient(bitmap, orientation);
      return bitmap;
    } catch (error) {
      await bitmap?.release().catch(() => {});
      throw error as Error;
    } finally {
      // 关闭图库授权的描述符，保留已经解码完成的独立位图。
      await source?.release().catch(() => {});
      if (file !== undefined) {
        await fileIo.close(file).catch(() => {});
      }
    }
  }

  /// 发送按短边等比缩小且不放大，编辑按长边和总像素限制画布的内存占用。
  private static decodingSize(width: number, height: number, maxShortEdge?: number): image.Size {
    if (maxShortEdge !== undefined) {
      const shortEdge = Math.min(width, height);
      const targetShortEdge = Math.min(shortEdge, maxShortEdge);
      return {
        width: Math.floor(width * targetShortEdge / shortEdge),
        height: Math.floor(height * targetShortEdge / shortEdge),
      };
    }
    const scale = Math.min(1, AlbumImageRenderer.MAX_EDGE / Math.max(width, height),
      Math.sqrt(AlbumImageRenderer.MAX_PIXELS / (width * height)));
    return { width: Math.max(1, Math.floor(width * scale)), height: Math.max(1, Math.floor(height * scale)) };
  }

  /// 编辑预览与导出共用同一画法。画布原点和宽高须对应未旋转图像的位置和尺寸。
  static drawStroke(context: CanvasRenderer, stroke: EditorStroke, width: number, height: number): void {
    if (stroke.points.length === 0 || !(stroke.width > 0 && Number.isFinite(stroke.width))) {
      return;
    }
    const first = stroke.points[0];
    const penWidth = Math.max(1, stroke.width * Math.min(width, height));
    context.beginPath();
    if (stroke.points.length === 1) {
      // 单击也生成圆点，无需触摸移动才显示笔迹。
      context.fillStyle = stroke.color;
      context.arc(first.x * width, first.y * height, penWidth / 2, 0, 2 * Math.PI);
      context.fill();
      return;
    }
    context.lineCap = 'round';
    context.lineJoin = 'round';
    context.strokeStyle = stroke.color;
    context.lineWidth = penWidth;
    context.moveTo(first.x * width, first.y * height);
    for (let index = 1; index < stroke.points.length; index++) {
      const point = stroke.points[index];
      context.lineTo(point.x * width, point.y * height);
    }
    context.stroke();
  }

  /// 将原图比例坐标的裁剪和笔迹渲染到沙盒 PNG，按顺时针 90° 的倍数旋转结果。
  static async save(pixelMap: image.PixelMap, crop: EditorCrop, strokes: EditorStroke[],
    cacheDir: string, turns: number = 0): Promise<string> {
    const size = (await pixelMap.getImageInfo()).size;
    const width = size.width;
    const height = size.height;
    const region = AlbumImageRenderer.cropRegion(crop, width, height);
    if (!Number.isInteger(turns) || !cacheDir.startsWith('/')) {
      throw new Error('编辑参数无效');
    }
    // 直接在旋转后的裁剪尺寸上渲染，避免再分配一张全尺寸合成位图。
    const quarterTurns = ((turns % 4) + 4) % 4;
    const outputWidth = quarterTurns % 2 === 0 ? region.size.width : region.size.height;
    const outputHeight = quarterTurns % 2 === 0 ? region.size.height : region.size.width;
    const canvas = new OffscreenCanvas(outputWidth, outputHeight, LengthMetricsUnit.PX);
    const context = canvas.getContext('2d', new RenderingContextSettings(true));
    const translationX = quarterTurns === 1 || quarterTurns === 2 ? outputWidth : 0;
    const translationY = quarterTurns === 2 || quarterTurns === 3 ? outputHeight : 0;
    context.translate(translationX, translationY);
    context.rotate(quarterTurns * Math.PI / 2);
    context.translate(-region.x, -region.y);
    context.drawImage(pixelMap, 0, 0, width, height);
    for (const stroke of strokes) {
      AlbumImageRenderer.drawStroke(context, stroke, width, height);
    }

    // 导出使用独立文件，回写失败时保留原图与在编辑页上的现有操作。
    const result = context.getPixelMap(0, 0, outputWidth, outputHeight);
    try {
      return await AlbumImageRenderer.writePng(result, cacheDir);
    } finally {
      await result.release().catch(() => {});
    }
  }

  /// 裁剪位置按两条边分别取整，消除浮点误差并拒绝没有实际像素的区域。
  private static cropRegion(crop: EditorCrop, width: number, height: number): image.Region {
    if (![crop.x, crop.y, crop.width, crop.height].every((value: number) => Number.isFinite(value))) {
      throw new Error('裁剪范围无效');
    }
    const left = Math.max(0, Math.round(crop.x * width));
    const top = Math.max(0, Math.round(crop.y * height));
    const right = Math.min(width, Math.round((crop.x + crop.width) * width));
    const bottom = Math.min(height, Math.round((crop.y + crop.height) * height));
    if (right <= left || bottom <= top) {
      throw new Error('裁剪范围为空');
    }
    return { x: left, y: top, size: { width: right - left, height: bottom - top } };
  }

  /// EXIF 的镜像操作在旋转之前执行，保证转正结果与平台图库方向一致。
  private static async orient(bitmap: image.PixelMap, orientation: string): Promise<void> {
    const flipHorizontally = orientation === 'Top-right' || orientation === 'Left-top' ||
      orientation === 'Right-bottom';
    const flipVertically = orientation === 'Bottom-left';
    if (flipHorizontally || flipVertically) {
      await bitmap.flip(flipHorizontally, flipVertically);
    }
    switch (orientation) {
      case 'Bottom-right':
        await bitmap.rotate(180);
        break;
      case 'Right-top':
      case 'Right-bottom':
        await bitmap.rotate(90);
        break;
      case 'Left-top':
      case 'Left-bottom':
        await bitmap.rotate(270);
        break;
    }
  }

  /// PNG 保留透明区域。写盘和关闭均成功后才交付路径。
  private static async writePng(bitmap: image.PixelMap, cacheDir: string): Promise<string> {
    const outputPath = `${cacheDir}/album_edit_${util.generateRandomUUID()}.png`;
    const packer = image.createImagePacker();
    try {
      const file = await fileIo.open(outputPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      try {
        await packer.packToFile(bitmap, file.fd, { format: 'image/png', quality: 100 });
      } finally {
        await fileIo.close(file);
      }
      return outputPath;
    } catch (error) {
      // 部分写入的临时文件也不进入相册预览。
      await fileIo.unlink(outputPath).catch(() => {});
      throw error as Error;
    } finally {
      await packer.release().catch(() => {});
    }
  }
}
