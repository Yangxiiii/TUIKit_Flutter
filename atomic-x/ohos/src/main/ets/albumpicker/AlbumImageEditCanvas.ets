import { image } from '@kit.ImageKit';
import { AlbumImageEditGeometry as Geometry } from './AlbumImageEditGeometry';
import { AlbumImageEditSession } from './AlbumImageEditSession';
import { AlbumImageRenderer, EditorCrop } from './AlbumImageRenderer';

/// 将编辑草稿绘制到界面画布，裁剪辅助线只用于交互预览。
export class AlbumImageEditCanvas {
  /// 先按当前裁剪和旋转显示照片及笔迹，再在裁剪模式绘制框线。
  static paint(context: CanvasRenderingContext2D, bitmap: image.PixelMap, session: AlbumImageEditSession,
    stageWidth: number, stageHeight: number): void {
    const turns = session.turns();
    const view = session.view();
    const rotated = turns % 2 !== 0;
    const width = rotated ? view.height : view.width;
    const height = rotated ? view.width : view.height;

    // 裁剪时看得到边框外内容，绘制时只显示应用后的裁剪范围。
    const clip = session.visibleFrame();
    context.clearRect(0, 0, stageWidth, stageHeight);
    context.save();
    context.beginPath();
    context.rect(clip.x, clip.y, clip.width, clip.height);
    context.clip();
    context.translate(view.x + view.width / 2, view.y + view.height / 2);
    context.rotate(turns * Math.PI / 2);
    context.translate(-width / 2, -height / 2);
    context.drawImage(bitmap, 0, 0, width, height);
    for (const stroke of session.strokes()) {
      AlbumImageRenderer.drawStroke(context, stroke, width, height);
    }
    const draft = session.draftStroke;
    if (draft !== undefined) {
      AlbumImageRenderer.drawStroke(context, draft, width, height);
    }
    context.restore();

    const crop = session.draftCrop;
    if (crop !== undefined) {
      AlbumImageEditCanvas.drawCropFrame(context, Geometry.project(view, crop), stageWidth, stageHeight);
    }
  }

  /// 暗化框外区域，用三分线和高对比角点帮助定位可拖动位置。
  private static drawCropFrame(context: CanvasRenderingContext2D, frame: EditorCrop,
    stageWidth: number, stageHeight: number): void {
    const right = frame.x + frame.width;
    const bottom = frame.y + frame.height;
    context.fillStyle = 'rgba(0,0,0,0.60)';
    context.fillRect(0, 0, stageWidth, frame.y);
    context.fillRect(0, bottom, stageWidth, stageHeight - bottom);
    context.fillRect(0, frame.y, frame.x, frame.height);
    context.fillRect(right, frame.y, stageWidth - right, frame.height);

    // 网格仅辅助取景，角点和框线在窄裁剪范围也保持可见。
    context.strokeStyle = 'rgba(255,255,255,0.54)';
    context.lineWidth = 0.5;
    context.beginPath();
    for (let i = 1; i <= 2; i++) {
      const x = frame.x + frame.width * i / 3;
      const y = frame.y + frame.height * i / 3;
      context.moveTo(x, frame.y);
      context.lineTo(x, bottom);
      context.moveTo(frame.x, y);
      context.lineTo(right, y);
    }
    context.stroke();
    context.strokeStyle = '#FFFFFF';
    context.lineWidth = 1;
    context.strokeRect(frame.x, frame.y, frame.width, frame.height);
    context.lineWidth = 3;
    const length = Math.min(13, frame.width / 3, frame.height / 3);
    context.beginPath();
    AlbumImageEditCanvas.drawCorner(context, frame.x, frame.y, length, length);
    AlbumImageEditCanvas.drawCorner(context, right, frame.y, -length, length);
    AlbumImageEditCanvas.drawCorner(context, frame.x, bottom, length, -length);
    AlbumImageEditCanvas.drawCorner(context, right, bottom, -length, -length);
    context.stroke();
  }

  private static drawCorner(context: CanvasRenderingContext2D, x: number, y: number, dx: number, dy: number): void {
    context.moveTo(x, y + dy);
    context.lineTo(x, y);
    context.lineTo(x + dx, y);
  }
}
