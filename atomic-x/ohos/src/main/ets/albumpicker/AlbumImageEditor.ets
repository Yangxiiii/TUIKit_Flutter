import { fileIo } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { AlbumImageEditCanvas } from './AlbumImageEditCanvas';
import { AlbumImageEditGeometry as Geometry } from './AlbumImageEditGeometry';
import { AlbumImageEditSession } from './AlbumImageEditSession';
import { AlbumImageRenderer, EditorPoint } from './AlbumImageRenderer';

interface Swatch {
  label: string;
  value: string;
}

const PEN_COLORS: Swatch[] = [
  { label: '白色', value: '#FFFFFF' }, { label: '黑色', value: '#171717' },
  { label: '红色', value: '#F44336' }, { label: '橙色', value: '#FF9800' },
  { label: '黄色', value: '#FDD835' }, { label: '绿色', value: '#29BA68' },
  { label: '青色', value: '#2DD4CF' }, { label: '蓝色', value: '#287AF1' },
  { label: '紫色', value: '#864DE3' }, { label: '洋红', value: '#EA5DA8' },
  { label: '灰色', value: '#969696' },
];

@Extend(Button)
function albumEditorButton() {
  .type(ButtonType.Normal)
  .fontSize(15)
  .fontColor(Color.White)
  .backgroundColor(Color.Transparent)
}

/// 承载相册里的裁剪与涂鸦交互，确认只生成图片副本，由相册接管文件。
@Component
export struct AlbumImageEditor {
  /// 本次编辑的沙盒路径或已勾选的图库 URI，挂载期间保持不变。
  @Prop sourcePath: string = '';
  /// 关闭编辑页并返回相册预览。
  onCancel: () => void = () => {};
  /// 接收保存成功的沙盒 PNG 绝对路径。
  onSave: (path: string) => void = () => {};

  @State private drawing: boolean = false;
  @State private cropping: boolean = false;
  @State private eraser: boolean = false;
  @State private penColor: string = PEN_COLORS[0].value;
  @State private canUndo: boolean = false;
  @State private canRedo: boolean = false;
  /// 解码完成前禁止触摸以及保存，加载失败仍可返回相册。
  @State private ready: boolean = false;
  @State private loadFailed: boolean = false;
  /// 导出期间保持位图可用，并屏蔽会改变当前快照的操作。
  @State private saving: boolean = false;

  private session: AlbumImageEditSession = new AlbumImageEditSession();
  private context: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));
  private bitmap?: image.PixelMap;
  private canvasReady: boolean = false;
  private stageWidth: number = 0;
  private stageHeight: number = 0;
  private imageWidth: number = 1;
  private imageHeight: number = 1;
  /// 退出后等待异步操作结束再回收位图和未交付副本。
  private active: boolean = false;

  aboutToAppear(): void {
    this.active = true;
    void this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    if (!this.saving) {
      this.releaseBitmap();
    }
  }

  /// 优先读取选中项授权的文件，有效位图只在当前编辑页存活时使用。
  private async load(): Promise<void> {
    let bitmap: image.PixelMap | undefined;
    try {
      bitmap = await AlbumImageRenderer.load(this.sourcePath);
      const info = await bitmap.getImageInfo();
      if (!this.active) {
        await bitmap.release();
        return;
      }
      this.bitmap = bitmap;
      this.imageWidth = info.size.width;
      this.imageHeight = info.size.height;
      this.ready = true;
      this.updateCanvas();
    } catch (_) {
      await bitmap?.release().catch(() => {});
      if (this.active) {
        this.loadFailed = true;
      }
    }
  }

  private releaseBitmap(): void {
    void this.bitmap?.release().catch(() => {});
    this.bitmap = undefined;
  }

  /// 区域变化时重算居中缩放，保留使用原图比例坐标的裁剪及笔迹。
  private updateCanvas(): void {
    if (this.stageWidth > 0 && this.stageHeight > 0) {
      this.session.resize(this.stageWidth, this.stageHeight, this.imageWidth, this.imageHeight);
      this.paint();
    }
  }

  private refreshHistory(): void {
    this.canUndo = this.session.canUndo();
    this.canRedo = this.session.canRedo();
    this.paint();
  }

  /// 一指编辑或平移，两指缩放时取消当前未提交笔迹。
  private touch(event: TouchEvent): void {
    if (!this.ready || this.saving) {
      return;
    }
    if (event.touches.length > 1 && event.type !== TouchType.Up && event.type !== TouchType.Cancel) {
      const first = event.touches[0];
      const second = event.touches[1];
      this.session.zoom({ x: first.x, y: first.y }, { x: second.x, y: second.y });
      this.paint();
      return;
    }

    const finger = event.changedTouches[0];
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.session.touchEnd(event.type === TouchType.Cancel);
      this.refreshHistory();
    } else if (finger !== undefined) {
      const point: EditorPoint = { x: finger.x, y: finger.y };
      if (event.type === TouchType.Down) {
        this.session.touchDown(point, this.drawing, this.eraser, this.penColor);
      } else if (event.type === TouchType.Move) {
        this.session.touchMove(point);
      }
      this.paint();
    }
  }

  private paint(): void {
    const bitmap = this.bitmap;
    if (this.canvasReady && bitmap !== undefined && this.stageWidth > 0 && this.stageHeight > 0) {
      AlbumImageEditCanvas.paint(this.context, bitmap, this.session, this.stageWidth, this.stageHeight);
    }
  }

  /// 截取导出快照，只有写入成功才退出，失败时保留用户的操作。
  private async save(): Promise<void> {
    const bitmap = this.bitmap;
    const cacheDir = this.getUIContext().getHostContext()?.cacheDir;
    if (bitmap === undefined || cacheDir === undefined || this.saving) {
      return;
    }
    if (!this.session.canUndo()) {
      this.onCancel();
      return;
    }

    this.saving = true;
    const edit = this.session.current;
    let path: string;
    try {
      path = await AlbumImageRenderer.save(bitmap, Geometry.sourceCrop(edit.crop, edit.turns),
        edit.strokes, cacheDir, edit.turns);
    } catch (_) {
      if (this.active) {
        this.getUIContext().getPromptAction().showToast({ message: '保存失败，请重试' });
      }
      return;
    } finally {
      this.saving = false;
      if (!this.active) {
        this.releaseBitmap();
      }
    }
    // 页面可能被宿主提前关闭，此时编辑页仍负责未交付的副本。
    if (this.active) {
      this.onSave(path);
    } else {
      await fileIo.unlink(path).catch(() => {});
    }
  }

  @Builder
  private header() {
    Row() {
      Button('取消').albumEditorButton().id('atomic.album.editor.cancel')
        .enabled(!this.saving).onClick(() => this.onCancel())
      Blank()
      Button('撤销').albumEditorButton().id('atomic.album.editor.undo')
        .enabled(this.canUndo && !this.saving)
        .onClick(() => {
          this.session.undoEdit();
          this.refreshHistory();
        })
      Button('重做').albumEditorButton().id('atomic.album.editor.redo')
        .enabled(this.canRedo && !this.saving)
        .onClick(() => {
          this.session.redoEdit();
          this.refreshHistory();
        })
    }.width('100%').height(52)
  }

  @Builder
  private canvas() {
    Stack() {
      Canvas(this.context)
        .id('atomic.album.editor.canvas')
        .width('100%')
        .height('100%')
        .onReady(() => {
          this.canvasReady = true;
          this.paint();
        })
        .onAreaChange((_: Area, area: Area) => {
          this.stageWidth = Number(area.width);
          this.stageHeight = Number(area.height);
          this.updateCanvas();
        })
        .onTouch((event: TouchEvent) => this.touch(event))
      if (!this.ready) {
        Text(this.loadFailed ? '无法读取图片' : '正在读取图片…').fontColor(Color.White)
      }
    }.width('100%').layoutWeight(1)
  }

  @Builder
  private palette() {
    Row() {
      Button('橡皮擦').albumEditorButton().id('atomic.album.editor.eraser')
        .fontColor(this.eraser ? '#79AEFF' : Color.White)
        .enabled(!this.saving).onClick(() => { this.eraser = !this.eraser; })
      Scroll() {
        Row({ space: 12 }) {
          ForEach(PEN_COLORS, (swatch: Swatch) => {
            Button()
              .id(`atomic.album.editor.color.${swatch.value.slice(1).toLowerCase()}`)
              .type(ButtonType.Circle)
              .width(30)
              .height(30)
              .backgroundColor(swatch.value)
              .border({ width: this.penColor === swatch.value && !this.eraser ? 3 : 1, color: '#FFFFFFBB' })
              .accessibilityText(swatch.label)
              .enabled(!this.saving)
              .onClick(() => {
                this.penColor = swatch.value;
                this.eraser = false;
              })
          }, (swatch: Swatch) => swatch.value)
        }.padding({ left: 6, right: 12 })
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).layoutWeight(1)
    }.width('100%').height(48)
  }

  @Builder
  private editorActions() {
    Row() {
      Button('涂鸦').albumEditorButton().id('atomic.album.editor.draw')
        .fontColor(this.drawing ? '#79AEFF' : Color.White)
        .enabled(this.ready && !this.saving).onClick(() => { this.drawing = !this.drawing; })
      Button('裁剪').albumEditorButton().id('atomic.album.editor.crop')
        .enabled(this.ready && !this.saving).onClick(() => {
          this.cropping = true;
          this.session.beginCrop();
          this.paint();
        })
      Blank()
      Button(this.saving ? '保存中…' : '完成')
        .id('atomic.album.editor.save')
        .type(ButtonType.Normal)
        .fontSize(15)
        .fontColor(Color.White)
        .backgroundColor('#0370ED')
        .borderRadius(6)
        .enabled(this.ready && !this.saving)
        .onClick(() => { void this.save(); })
    }.width('100%').height(56).padding({ left: 8, right: 12 })
  }

  @Builder
  private cropActions() {
    Row() {
      Button('取消').albumEditorButton().id('atomic.album.editor.crop.cancel')
        .onClick(() => {
          this.session.endCrop(false);
          this.cropping = false;
          this.paint();
        })
      Blank()
      Button('旋转').albumEditorButton().id('atomic.album.editor.crop.rotate')
        .onClick(() => {
          this.session.rotateCrop();
          this.paint();
        })
      Button('重置').albumEditorButton().id('atomic.album.editor.crop.reset')
        .onClick(() => {
          this.session.beginCrop();
          this.paint();
        })
      Blank()
      Button('应用').albumEditorButton().id('atomic.album.editor.crop.apply')
        .onClick(() => {
          this.session.endCrop(true);
          this.cropping = false;
          this.refreshHistory();
        })
    }.width('100%').height(56).padding({ left: 8, right: 8 })
  }

  build() {
    Column() {
      // 裁剪模式扩大取景空间，退出后恢复通用的撤销和重做栏。
      if (!this.cropping) {
        this.header()
      }
      // 编辑画布始终独立于图库授权组件，并随上下工具栏调整空间。
      this.canvas()
      // 涂鸦调色板随工具展开，裁剪使用单独的底部操作栏。
      if (this.cropping) {
        this.cropActions()
      } else {
        if (this.drawing) {
          this.palette()
        }
        this.editorActions()
      }
    }.width('100%').height('100%').backgroundColor('#161616')
  }
}
