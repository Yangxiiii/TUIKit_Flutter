import { AlbumImageEditGeometry as Geometry, CropHandle } from './AlbumImageEditGeometry';
import { EditorCrop, EditorPoint, EditorStroke } from './AlbumImageRenderer';

const FULL_FRAME: EditorCrop = { x: 0, y: 0, width: 1, height: 1 };
/// 给裁剪把手预留可点击区域，避开系统屏幕边缘的返回手势。
const CROP_INSET = 24;

interface EditSnapshot {
  crop: EditorCrop;
  turns: number;
  strokes: EditorStroke[];
}

interface CropDrag {
  start: EditorPoint;
  frame: EditorCrop;
  view: EditorCrop;
  handle: CropHandle;
}

interface PinchStart {
  center: EditorPoint;
  distance: number;
  frame: EditorCrop;
  view: EditorCrop;
}

/// 管理单次编辑的裁剪草稿、触摸手势和撤销记录，保存前始终保留源图片。
export class AlbumImageEditSession {
  /// 已应用的编辑，只有一笔完成或裁剪确认才进入历史记录。
  current: EditSnapshot = { crop: FULL_FRAME, turns: 0, strokes: [] };
  /// 编辑中的笔迹，触摸抬起才成为可撤销的一笔。
  draftStroke?: EditorStroke;
  /// 进入裁剪时从已应用值开始，取消不会影响笔迹与撤销历史。
  draftCrop?: EditorCrop;
  /// 当前裁剪草稿的顺时针旋转次数，应用后才写入历史。
  draftTurns: number = 0;

  /// 历史快照只保存已完成的操作，旧笔迹在快照间共享。
  private undo: EditSnapshot[] = [];
  /// 撤销后的操作在新笔迹或新裁剪提交前仍可重做。
  private redo: EditSnapshot[] = [];
  /// 连续擦除使用单独的预览集合，抬起时才记为一次操作。
  private erasing?: EditorStroke[];
  /// 持续拖动保持手势开始时选中的裁剪边角。
  private drag?: CropDrag;
  /// 双指缩放以首次测得的中心和间距为基准。
  private pinch?: PinchStart;
  /// 记录照片在画布中的平移和缩放，仅当前工具使用。
  private zoomedView?: EditorCrop;
  private photoWidth: number = 1;
  private photoHeight: number = 1;
  private bounds: EditorCrop = FULL_FRAME;

  resize(width: number, height: number, photoWidth: number, photoHeight: number): void {
    this.bounds = { x: 0, y: 0, width, height };
    this.photoWidth = photoWidth;
    this.photoHeight = photoHeight;
    this.zoomedView = undefined;
  }

  turns(): number {
    return this.draftCrop === undefined ? this.current.turns : this.draftTurns;
  }

  view(): EditorCrop {
    return this.zoomedView ?? this.fittedView();
  }

  /// 裁剪时显示整张照片，绘图时以已应用的裁剪范围填充画布。
  private fittedView(): EditorCrop {
    const rotated = this.turns() % 2 !== 0;
    const inset = this.draftCrop === undefined ? 0 : CROP_INSET;
    const fitted = Geometry.fit(Math.max(1, this.bounds.width - 2 * inset),
      Math.max(1, this.bounds.height - 2 * inset), rotated ? this.photoHeight : this.photoWidth,
      rotated ? this.photoWidth : this.photoHeight, this.draftCrop === undefined ? this.current.crop : FULL_FRAME);
    return { x: fitted.x + inset, y: fitted.y + inset, width: fitted.width, height: fitted.height };
  }

  visibleFrame(): EditorCrop {
    return this.draftCrop === undefined ? Geometry.project(this.fittedView(), this.current.crop) : this.bounds;
  }

  strokes(): EditorStroke[] {
    return this.erasing ?? this.current.strokes;
  }

  canUndo(): boolean {
    return this.undo.length > 0;
  }

  canRedo(): boolean {
    return this.redo.length > 0;
  }

  undoEdit(): void {
    const snapshot = this.undo.pop();
    if (snapshot !== undefined) {
      this.redo.push(this.current);
      this.current = snapshot;
      this.zoomedView = undefined;
    }
  }

  redoEdit(): void {
    const snapshot = this.redo.pop();
    if (snapshot !== undefined) {
      this.undo.push(this.current);
      this.current = snapshot;
      this.zoomedView = undefined;
    }
  }

  beginCrop(): void {
    this.draftCrop = this.current.crop;
    this.draftTurns = this.current.turns;
    this.zoomedView = undefined;
  }

  rotateCrop(): void {
    if (this.draftCrop !== undefined) {
      this.draftCrop = Geometry.rotate(this.draftCrop);
      this.draftTurns = (this.draftTurns + 1) % 4;
      this.zoomedView = undefined;
    }
  }

  endCrop(apply: boolean): void {
    const crop = this.draftCrop;
    const previous = this.current.crop;
    // 比较实际范围，直接应用未调整的裁剪框不会产生撤销记录。
    if (apply && crop !== undefined && (this.draftTurns !== this.current.turns ||
      Math.hypot(crop.x - previous.x, crop.y - previous.y, crop.width - previous.width,
        crop.height - previous.height) > 0.00001)) {
      this.commit({ crop, turns: this.draftTurns, strokes: this.current.strokes });
    }
    this.draftCrop = undefined;
    this.zoomedView = undefined;
  }

  /// 手势起点决定裁剪边角、图片平移或涂鸦，连续移动沿用该选择。
  touchDown(point: EditorPoint, drawing: boolean, eraser: boolean, color: string): void {
    this.pinch = undefined;
    const view = this.view();
    if (this.draftCrop !== undefined) {
      const frame = Geometry.project(view, this.draftCrop);
      const handle = Geometry.handle(frame, point);
      this.drag = { start: point, frame, view, handle };
      return;
    }

    if (!drawing || !this.contains(this.visibleFrame(), point)) {
      return;
    }
    const source = this.sourcePoint(view, point);
    if (eraser) {
      this.erasing = this.current.strokes;
      this.erase(source, view);
    } else {
      this.draftStroke = { points: [source], color, width: 5 / Math.min(view.width, view.height) };
    }
  }

  /// 在同一次手势内更新裁剪草稿或笔迹，原图坐标在画布缩放后仍保持连续。
  touchMove(point: EditorPoint): void {
    if (this.pinch !== undefined) {
      return;
    }
    const drag = this.drag;
    if (drag !== undefined) {
      const delta: EditorPoint = { x: point.x - drag.start.x, y: point.y - drag.start.y };
      if (drag.handle.x === 0 && drag.handle.y === 0) {
        this.transformView(drag.view, drag.frame, drag.view.x + delta.x, drag.view.y + delta.y, 1);
      } else {
        const resized = Geometry.resize(drag.frame, drag.handle, delta, drag.view,
          this.bounds.width, this.bounds.height);
        this.draftCrop = Geometry.unproject(drag.view, resized);
      }
    } else if (this.draftStroke !== undefined || this.erasing !== undefined) {
      const view = this.view();
      const source = this.sourcePoint(view, point);
      if (this.draftStroke !== undefined) {
        this.draftStroke.points.push(source);
      } else {
        this.erase(source, view);
      }
    }
  }

  /// 抬起时合并一次连续擦除，系统取消手势时丢弃尚未提交的笔迹。
  touchEnd(cancelled: boolean): void {
    if (!cancelled) {
      if (this.draftStroke !== undefined) {
        this.commit({ crop: this.current.crop, turns: this.current.turns,
          strokes: [...this.current.strokes, this.draftStroke] });
      } else if (this.erasing !== undefined && this.erasing.length !== this.current.strokes.length) {
        this.commit({ crop: this.current.crop, turns: this.current.turns, strokes: this.erasing });
      }
    }
    this.draftStroke = undefined;
    this.erasing = undefined;
    this.drag = undefined;
    this.pinch = undefined;
  }

  /// 双指缩放以指尖中心为锚点，裁剪框在屏幕上保持固定。
  zoom(first: EditorPoint, second: EditorPoint): void {
    const center: EditorPoint = { x: (first.x + second.x) / 2, y: (first.y + second.y) / 2 };
    const distance = Math.hypot(first.x - second.x, first.y - second.y);
    if (this.pinch === undefined) {
      // 第二根手指落下可能意味着缩放，撤回第一根手指误画的起笔。
      this.touchEnd(true);
      const view = this.view();
      const clip = this.draftCrop !== undefined ? Geometry.project(view, this.draftCrop) : this.visibleFrame();
      this.pinch = { center, distance: Math.max(1, distance), frame: clip, view };
      return;
    }
    const start = this.pinch;
    const min = Math.max(start.frame.width / start.view.width, start.frame.height / start.view.height);
    const max = Math.max(min, this.fittedView().width * 8 / start.view.width);
    const scale = Geometry.clamp(distance / start.distance, min, max);
    this.transformView(start.view, start.frame, center.x - (start.center.x - start.view.x) * scale,
      center.y - (start.center.y - start.view.y) * scale, scale);
  }

  /// 确保移动和缩放后的照片覆盖裁剪框，裁剪结果不会引入图片外的透明边。
  private transformView(view: EditorCrop, frame: EditorCrop, x: number, y: number, scale: number): void {
    const width = view.width * scale;
    const height = view.height * scale;
    const zoomed: EditorCrop = {
      x: Geometry.clamp(x, frame.x + frame.width - width, frame.x),
      y: Geometry.clamp(y, frame.y + frame.height - height, frame.y),
      width,
      height,
    };
    this.zoomedView = zoomed;
    if (this.draftCrop !== undefined) {
      this.draftCrop = Geometry.unproject(zoomed, frame);
    }
  }

  private contains(bounds: EditorCrop, point: EditorPoint): boolean {
    return point.x >= bounds.x && point.x <= bounds.x + bounds.width &&
      point.y >= bounds.y && point.y <= bounds.y + bounds.height;
  }

  private sourcePoint(view: EditorCrop, point: EditorPoint): EditorPoint {
    const crop = this.current.crop;
    const x = Geometry.clamp((point.x - view.x) / view.width, crop.x, crop.x + crop.width);
    const y = Geometry.clamp((point.y - view.y) / view.height, crop.y, crop.y + crop.height);
    return Geometry.sourcePoint(x, y, this.turns());
  }

  private erase(point: EditorPoint, view: EditorCrop): void {
    const rotated = this.turns() % 2 !== 0;
    const width = rotated ? view.height : view.width;
    const height = rotated ? view.width : view.height;
    this.erasing = this.erasing?.filter((stroke: EditorStroke) => !Geometry.hits(stroke, point, width, height));
  }

  /// 提交新操作后清空重做分支，历史条目共享已完成的笔迹。
  private commit(snapshot: EditSnapshot): void {
    this.undo.push(this.current);
    this.redo = [];
    this.current = snapshot;
  }
}
