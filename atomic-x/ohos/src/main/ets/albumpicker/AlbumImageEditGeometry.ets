import { EditorCrop, EditorPoint, EditorStroke } from './AlbumImageRenderer';

/// 裁剪框最小可操作尺寸，界面通过相同的距离确定拖拽把手范围。
const HANDLE_SIZE = 24;

export interface CropHandle {
  /// 水平方向的边，-1 为左边，1 为右边，0 为不移动该轴。
  x: number;
  /// 垂直方向的边，-1 为上边，1 为下边，0 为不移动该轴。
  y: number;
}

/// 在画布坐标、旋转后的照片坐标和原图坐标之间换算，保证预览和导出使用同一裁剪范围。
export class AlbumImageEditGeometry {
  static clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }

  /// 将当前可见裁剪区域居中显示，返回整张照片在画布上的投影范围，单位为 vp。
  static fit(width: number, height: number, photoWidth: number, photoHeight: number, crop: EditorCrop): EditorCrop {
    const scale = Math.min(width / (photoWidth * crop.width), height / (photoHeight * crop.height));
    const w = photoWidth * scale;
    const h = photoHeight * scale;
    return {
      x: (width - w * crop.width) / 2 - w * crop.x,
      y: (height - h * crop.height) / 2 - h * crop.y,
      width: w,
      height: h,
    };
  }

  /// 将归一化的裁剪框映射到画布，仍使用旋转后的照片方向。
  static project(view: EditorCrop, crop: EditorCrop): EditorCrop {
    return {
      x: view.x + view.width * crop.x,
      y: view.y + view.height * crop.y,
      width: view.width * crop.width,
      height: view.height * crop.height,
    };
  }

  /// 将固定在画布上的裁剪框还原为当前缩放和偏移下的照片范围。
  static unproject(view: EditorCrop, bounds: EditorCrop): EditorCrop {
    return {
      x: (bounds.x - view.x) / view.width,
      y: (bounds.y - view.y) / view.height,
      width: bounds.width / view.width,
      height: bounds.height / view.height,
    };
  }

  /// 顺时针旋转归一化矩形，允许裁剪框与原有笔迹一起跟随照片。
  static rotate(rect: EditorCrop): EditorCrop {
    return { x: 1 - rect.y - rect.height, y: rect.x, width: rect.height, height: rect.width };
  }

  /// 将预览方向的点还原到原图，笔迹在旋转、裁剪和导出时共享该坐标。
  static sourcePoint(x: number, y: number, turns: number): EditorPoint {
    if (turns === 1) {
      return { x: y, y: 1 - x };
    }
    if (turns === 2) {
      return { x: 1 - x, y: 1 - y };
    }
    if (turns === 3) {
      return { x: 1 - y, y: x };
    }
    return { x, y };
  }

  /// 将预览方向的裁剪框还原到原图，交由导出层先裁剪再旋转。
  static sourceCrop(crop: EditorCrop, turns: number): EditorCrop {
    let result = crop;
    for (let i = 0; i < (4 - turns) % 4; i++) {
      result = AlbumImageEditGeometry.rotate(result);
    }
    return result;
  }

  /// 优先命中角点，其次命中边缘；框内其他位置交给图片平移。
  static handle(frame: EditorCrop, point: EditorPoint): CropHandle {
    const right = frame.x + frame.width;
    const bottom = frame.y + frame.height;
    const nearX = point.x >= frame.x - HANDLE_SIZE && point.x <= right + HANDLE_SIZE;
    const nearY = point.y >= frame.y - HANDLE_SIZE && point.y <= bottom + HANDLE_SIZE;
    return {
      x: nearY ? AlbumImageEditGeometry.edge(point.x, frame.x, right) : 0,
      y: nearX ? AlbumImageEditGeometry.edge(point.y, frame.y, bottom) : 0,
    };
  }

  private static edge(point: number, start: number, end: number): number {
    const before = Math.abs(point - start);
    const after = Math.abs(point - end);
    if (Math.min(before, after) > HANDLE_SIZE) {
      return 0;
    }
    return before <= after ? -1 : 1;
  }

  /// 限制把手移动在可见照片范围内，同时允许任意宽高比例。
  static resize(frame: EditorCrop, handle: CropHandle, delta: EditorPoint, view: EditorCrop,
    width: number, height: number): EditorCrop {
    const minWidth = Math.min(HANDLE_SIZE * 1.5, frame.width);
    const minHeight = Math.min(HANDLE_SIZE * 1.5, frame.height);
    const right = frame.x + frame.width;
    const bottom = frame.y + frame.height;
    const x = handle.x < 0 ?
      AlbumImageEditGeometry.clamp(frame.x + delta.x, Math.max(0, view.x), right - minWidth) : frame.x;
    const y = handle.y < 0 ?
      AlbumImageEditGeometry.clamp(frame.y + delta.y, Math.max(0, view.y), bottom - minHeight) : frame.y;
    const endX = handle.x > 0 ?
      AlbumImageEditGeometry.clamp(right + delta.x, x + minWidth, Math.min(width, view.x + view.width)) : right;
    const endY = handle.y > 0 ?
      AlbumImageEditGeometry.clamp(bottom + delta.y, y + minHeight, Math.min(height, view.y + view.height)) : bottom;
    return { x, y, width: endX - x, height: endY - y };
  }

  /// 计算橡皮擦与笔迹各线段的距离，按安卓行为移除命中的整条笔迹。
  static hits(stroke: EditorStroke, point: EditorPoint, width: number, height: number): boolean {
    const radius = 14 + stroke.width * Math.min(width, height) / 2;
    for (let index = 0; index < stroke.points.length; index++) {
      const a = stroke.points[Math.max(0, index - 1)];
      const b = stroke.points[index];
      const dx = (b.x - a.x) * width;
      const dy = (b.y - a.y) * height;
      const px = (point.x - a.x) * width;
      const py = (point.y - a.y) * height;
      const projection = dx === 0 && dy === 0 ? 0 :
        AlbumImageEditGeometry.clamp((px * dx + py * dy) / (dx * dx + dy * dy), 0, 1);
      if (Math.hypot(px - dx * projection, py - dy * projection) <= radius) {
        return true;
      }
    }
    return false;
  }
}
