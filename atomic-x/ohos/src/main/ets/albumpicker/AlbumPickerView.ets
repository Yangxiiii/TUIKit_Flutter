import { AlbumInfo, AlbumPickerComponent } from '@ohos.file.AlbumPickerComponent';
import {
  BaseItemInfo,
  ClickType,
  DataType,
  ItemInfo,
  PhotoBrowserRange,
  PhotoBrowserUIElement,
  PhotoPickerComponent,
  PickerColorMode,
  PickerController,
  PickerOptions,
  ReminderMode,
  SelectMode,
} from '@ohos.file.PhotoPickerComponent';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { AlbumImageEditor } from './AlbumImageEditor';
import { NativeToast, NativeToastState } from '../components/feedback/NativeToast';
import { AlbumPickerOutput, AlbumPickerSelection } from './AlbumPickerOutput';

/// 对齐安卓相册的 album_picker_dark_background，供网格、工具栏和系统栏共用。
export const ALBUM_PICKER_BACKGROUND = '#393939';

/// 下拉面板和遮罩沿用安卓相册的过渡时长，单位为毫秒。
const ALBUM_MENU_TRANSITION_MS = 300;

/// 网格和预览共用固定的顶部工具栏高度，单位为 vp。
const ALBUM_HEADER_HEIGHT = 52;

/// 安卓预览和系统授权圆圈的共同直径，单位为 vp。
const PREVIEW_CHECKBOX_SIZE = 20;

/// 系统授权圆圈的横向位置是容器百分比，圈心比配置位置向左偏 2 vp。
const PREVIEW_CHECKBOX_X = 85;
const PREVIEW_CHECKBOX_INSET = 2;
const PREVIEW_CHECKBOX_TOP = (ALBUM_HEADER_HEIGHT - PREVIEW_CHECKBOX_SIZE) / 2;

/// 在圆的上、下半区按 1 vp 填充四角，最靠近圆心的一行没有需要补色的空间。
const PREVIEW_CORNER_ROWS = [0, 1, 2, 3, 4, 5, 6, 7, 8];

/// 协调系统授权图库、图片编辑和发送确认，并回收会话内的编辑副本。
@Component
export struct AlbumPickerView {
  /// 支持仅图片、仅视频或混合选择，挂载时传给相册和网格。
  @Prop mediaType: photoAccessHelper.PhotoViewMIMETypes = photoAccessHelper.PhotoViewMIMETypes.IMAGE_VIDEO_TYPE;
  /// 单次确认最多返回的媒体数量，默认与聊天相册一致。
  @Prop maxCount: number = 9;
  /// 控制嵌入式网格的拍摄入口，拍摄和权限交互由系统处理。
  @Prop showsCameraItem: boolean = true;
  /// 发送按钮与选中编号使用的十六进制主题色。
  @Prop primaryColor: string = '#0370ED';
  /// 外层相册容器已为系统保留的底部空间，Toast 只补足整屏距离。
  @Prop toastBottomInset: number = 0;
  /// 所选媒体全部落盘后回调，调用方接管文件并决定关闭时机。
  onConfirm: (selection: AlbumPickerSelection[]) => void = () => {};
  /// 从相册网格取消时回调，由调用方关闭页面。
  onCancel: () => void = () => {};

  /// 发送选集按用户勾选顺序排列，跨相册保留，编辑授权不计入。
  @State private selectedUris: string[] = [];
  /// 当前系统相册的标题，空字符串时显示宿主媒体范围对应的默认名称。
  @State private albumName: string = '';
  /// 浮层打开时由系统相册列表处理点击，网格保留当前滚动位置和选集。
  @State private showingAlbums: boolean = false;
  /// 由系统预览回调更新，决定顶部返回按钮和底部编辑入口。
  @State private showingPreview: boolean = false;
  /// 系统当前预览的媒体，用于同步勾选状态和控制图片编辑入口。
  @State private previewItem: BaseItemInfo = {};
  /// 底栏打开已选预览时的顺序，取消勾选后仍留在这次预览中以便恢复选择。
  @State private previewSelection: string[] = [];
  /// 未授权的图片需要用户点系统勾选框，回调只对发起编辑的那张图片打开编辑器。
  @State private awaitingEditPermissionUri: string = '';
  /// 非空时显示编辑器，可能指向授权的图库 URI 或已编辑的沙盒副本。
  @State private editorSource: string = '';
  /// 编辑开始时固定图库 URI，避免系统迟到的预览切换回调写到另一张图片。
  private editingUri: string = '';
  /// 以图库 URI 索引最新编辑稿，选集继续按图库 URI 判断顺序和权限。
  private editedImages: Map<string, string> = new Map();
  /// 系统预览可能仍引用上一版编辑稿，发送或退出会话后一起回收。
  private previousEdits: string[] = [];
  /// 控制确认时是否保留原件，对所有选择项生效。
  @State private original: boolean = false;
  /// 系统就绪回调完成前无法调用预览和切换相册。
  @State private pickerReady: boolean = false;
  /// 从确认开始到调用方接管文件期间冻结操作，避免重复导出。
  @State private exporting: boolean = false;
  /// 页面销毁后终止结果交付并回收已生成的缓存文件。
  private active: boolean = false;
  @State private pickerController: PickerController = new PickerController();
  /// 图库、系统数量回调和图片编辑页共享一条提示。
  @State private toast: NativeToastState = new NativeToastState();
  private pickerOptions: PickerOptions = new PickerOptions();

  aboutToAppear(): void {
    this.active = true;
    this.pickerOptions.MIMEType = this.mediaType;
    this.pickerOptions.maxSelectNumber = this.selectionLimit();
    this.pickerOptions.selectMode = SelectMode.MULTI_SELECT;
    this.pickerOptions.isPhotoTakingSupported = this.showsCameraItem;
    this.pickerOptions.isSearchSupported = false;
    this.pickerOptions.isSlidingSelectionSupported = true;
    // 手机标准网格是四列，宽松档位减少一列以对齐聊天相册的默认布局。
    this.pickerOptions.gridPinchMode = {
      gridPinchModeType: photoAccessHelper.GridPinchModeType.FULL_FUNCTION_GRID,
      defaultGridLevel: photoAccessHelper.GridLevel.SPACIOUS,
    };
    this.pickerOptions.checkBoxColor = this.primaryColor;
    this.pickerOptions.checkboxTextColor = '#FFFFFF';
    this.pickerOptions.uiComponentColorMode = PickerColorMode.DARK;
    this.pickerOptions.photoBrowserBackgroundColorMode = PickerColorMode.DARK;
    // 网格和大图共用同一图库矩形，入场动画不会因宿主移除标题栏而重新布局。
    this.pickerOptions.gridMargin = { top: ALBUM_HEADER_HEIGHT };
    // 系统勾选框高 20 vp，从大图顶部开始放置时与工具栏中心对齐。
    this.pickerOptions.photoBrowserMargin = { top: PREVIEW_CHECKBOX_TOP };
    // 勾选坐标相对大图区域，与宿主标题栏同一行，同时保留系统授权热区。
    this.pickerOptions.photoBrowserCheckboxPosition = [PREVIEW_CHECKBOX_X / 100, 0.006];
    this.pickerOptions.backgroundColor = ALBUM_PICKER_BACKGROUND;
    // 系统仍限制选择数量，提示由相册统一布局。
    this.pickerOptions.maxSelectedReminderMode = ReminderMode.NONE;
  }

  aboutToDisappear(): void {
    this.active = false;
    this.toast.clear();
    if (!this.exporting) {
      void this.discardEdits();
    }
  }

  private selectionLimit(): number {
    // 系统选图 API 接受正整数，非法配置沿用聊天默认值。
    return Number.isFinite(this.maxCount) && this.maxCount >= 1 ? Math.floor(this.maxCount) : 9;
  }

  /// 安卓相册的关闭按钮始终取消选图，只有图片预览使用返回按钮。
  private handleLeadingButton(): void {
    if (this.showingPreview) {
      this.pickerController.exitPhotoBrowser();
    } else {
      this.showingAlbums = false;
      this.onCancel();
    }
  }

  /// 初次进入或默认相册恢复时，标题应与图库的媒体范围一致。
  private currentAlbumTitle(): string {
    if (this.albumName.length > 0) {
      return this.albumName;
    }
    switch (this.mediaType) {
      case photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE:
        return '图片';
      case photoAccessHelper.PhotoViewMIMETypes.VIDEO_TYPE:
        return '视频';
      case photoAccessHelper.PhotoViewMIMETypes.MOVING_PHOTO_IMAGE_TYPE:
        return '实况照片';
      default:
        return '图片和视频';
    }
  }

  /// 系统列表同时提供分类和具体相册。用返回的 URI 刷新网格并保留已勾选的媒体。
  private switchAlbum(album: AlbumInfo): boolean {
    const uri = album.uri;
    if (uri === undefined || !this.pickerReady || !this.showingAlbums || this.exporting) {
      return false;
    }
    try {
      // 空 URI 表示默认图库。同步已选 URI 后，已选项在切换回原相册时仍可见。
      this.pickerController.setData(DataType.SET_ALBUM_URI, uri);
      this.pickerController.setData(DataType.SET_SELECTED_URIS, this.selectedUris);
      this.albumName = uri.length === 0 ? '' : (album.albumName ?? '相册');
      this.showingAlbums = false;
      return true;
    } catch (_) {
      this.notify('暂时无法切换相册，请重试');
      return false;
    }
  }

  /// 按系统授权回调追加 URI，忽略重复通知和越过上限的异常回调。
  private select(uri: string): void {
    if (uri.length === 0 || this.selectedUris.includes(uri)) {
      return;
    }
    if (this.isAwaitingEdit(uri)) {
      // 这次勾选是编辑授权，恢复系统勾选状态后再读取图片，保持发送选集。
      this.awaitingEditPermissionUri = '';
      this.pickerController.setData(DataType.SET_SELECTED_URIS, this.selectedUris);
      this.openEditor(uri);
      return;
    }
    if (this.selectedUris.length >= this.selectionLimit()) {
      this.pickerController.setData(DataType.SET_SELECTED_URIS, this.selectedUris);
      return;
    }
    this.selectedUris = [...this.selectedUris, uri];
    this.updatePreviewCheckbox();
    // 编辑过的图片重新勾选后，系统预览和将要发送的文件应使用同一编辑稿。
    const editedPath = this.editedImages.get(uri);
    if (editedPath !== undefined) {
      this.refreshEditedPreview(uri, editedPath);
    }
  }

  /// 系统图库未授权时保留本次编辑意图，用户在当前页确认后直接进入编辑器。
  private async editPreview(): Promise<void> {
    const uri = this.previewItem.uri ?? '';
    if (!this.canEditPreview() || uri.length === 0 || !this.allowGalleryAction()) {
      return;
    }
    if (this.editedImages.has(uri) || this.selectedUris.includes(uri)) {
      this.openEditor(uri);
      return;
    }

    // 已经被用户授权但当前未勾选的图片也能编辑，检查权限不改变发给聊天的选集。
    this.awaitingEditPermissionUri = uri;
    try {
      const file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      await fileIo.close(file);
      if (this.isAwaitingEdit(uri)) {
        this.awaitingEditPermissionUri = '';
        this.openEditor(uri);
      }
    } catch (_) {
      // 读权限由系统的勾选动作发放。用户切换预览对象后不再提示旧图片的授权。
      if (this.isAwaitingEdit(uri)) {
        if (this.selectedUris.length >= this.selectionLimit()) {
          this.awaitingEditPermissionUri = '';
          this.notify('已达到选择上限，请先取消选择一项');
          return;
        }
        this.notify('点右上角圆圈授权并进入编辑');
      }
    }
  }

  private canEditPreview(): boolean {
    return this.previewItem.mimeType?.startsWith('image/') === true;
  }

  /// 自动进入编辑前重新核对当前页，避免文件打开或勾选回调迟到后覆盖其他操作。
  private isAwaitingEdit(uri: string): boolean {
    return this.active && this.showingPreview && this.allowGalleryAction() &&
      this.awaitingEditPermissionUri === uri && this.previewItem.uri === uri;
  }

  /// 固定本次编辑的图库 URI，已有编辑稿时从最新副本继续修改。
  private openEditor(uri: string): void {
    this.editingUri = uri;
    this.editorSource = this.editedImages.get(uri) ?? uri;
  }

  private currentPreviewUri(): string {
    return this.previewItem.uri ?? this.previewSelection[0] ?? '';
  }

  private isCurrentPreviewSelected(): boolean {
    return this.selectedUris.includes(this.currentPreviewUri());
  }

  /// 已选预览中的项目已经授权，可在同一位置使用应用自己的选择按钮。
  private usesPreviewSelectionButton(): boolean {
    return this.previewSelection.includes(this.currentPreviewUri()) || this.isCurrentPreviewSelected();
  }

  /// 隐藏与应用按钮重叠的系统控件，首次勾选仍通过系统授权入口。
  private updatePreviewCheckbox(): void {
    if (this.showingPreview) {
      this.pickerController.setPhotoBrowserUIElementVisibility(
        [PhotoBrowserUIElement.CHECKBOX], !this.usesPreviewSelectionButton());
    }
  }

  /// 已选预览内只修改发送状态，返回网格后再同步系统列表，避免当前浏览页被移除。
  private togglePreviewSelection(): void {
    const uri = this.currentPreviewUri();
    if (uri.length === 0 || !this.usesPreviewSelectionButton() || !this.allowGalleryAction()) {
      return;
    }
    const selected = this.isCurrentPreviewSelected();
    if (this.previewSelection.includes(uri)) {
      // 恢复勾选时沿用进入预览前的顺序。
      this.selectedUris = this.previewSelection.filter((item: string) =>
        item === uri ? !selected : this.selectedUris.includes(item));
      return;
    }

    // 从网格直开的预览仍浏览整个相册，取消勾选无需保留系统选集。
    const selection = this.selectedUris.filter((item: string) => item !== uri);
    try {
      this.pickerController.setData(DataType.SET_SELECTED_URIS, selection);
      this.selectedUris = selection;
      this.updatePreviewCheckbox();
    } catch (_) {
      this.notify('暂时无法取消选择，请重试');
    }
  }

  /// 保存编辑稿供预览和确认使用，图库文件仍由系统管理。
  private saveEdit(path: string): void {
    const uri = this.editingUri;
    this.editorSource = '';
    this.editingUri = '';
    if (!this.active || uri.length === 0) {
      void this.removeEdit(path);
      return;
    }

    // 发送读取沙盒稿，系统预览仍用原始图库 URI 定位相册中的条目。
    const previous = this.editedImages.get(uri);
    if (previous !== undefined) {
      this.previousEdits.push(previous);
    }
    this.editedImages.set(uri, path);
    this.refreshEditedPreview(uri, path);
  }

  /// 更新系统预览。系统替换接口只接受勾选项，回显期间的临时勾选与发送选集独立。
  private refreshEditedPreview(uri: string, path: string): void {
    // 在已选预览取消勾选的图片仍留在系统浏览列表，可直接刷新编辑稿。
    const needsTemporarySelection = !this.selectedUris.includes(uri) && !this.previewSelection.includes(uri);
    const restoreSelection = () => {
      if (needsTemporarySelection && this.active) {
        try {
          this.pickerController.setData(DataType.SET_SELECTED_URIS, this.selectedUris);
        } catch (_) {
          // 图库窗口可能正在关闭，发送仍以应用保存的选集为准。
          console.warn('相册无法恢复系统勾选');
        }
      }
    };
    try {
      if (needsTemporarySelection) {
        // 此时图片已经授权，只临时同步给图库用于替换缩略图和大图。
        this.pickerController.setData(DataType.SET_SELECTED_URIS, [uri]);
      }
      this.pickerController.replacePhotoPickerPreview(uri, fileUri.getUriFromPath(path), (error) => {
        // 还原回调到达时的发送选集，期间其他媒体的勾选仍然有效。
        restoreSelection();
        if (error && error.code !== 0 && this.active) {
          this.notify('编辑稿已保留，暂时无法刷新预览');
        }
      });
    } catch (_) {
      restoreSelection();
      this.notify('编辑稿已保留，暂时无法刷新预览');
    }
  }

  /// 平台窗口关闭时可能无法展示提示，提示失败不影响保留编辑稿。
  private notify(message: string): void {
    try {
      this.toast.show(this.getUIContext(), message);
    } catch (_) {
      console.warn('相册窗口无法显示提示');
    }
  }

  /// 释放当前会话的所有编辑稿，已确认的媒体由导出工具另行复制交付。
  private async discardEdits(): Promise<void> {
    const paths = this.previousEdits.concat(Array.from(this.editedImages.values()));
    this.editedImages.clear();
    this.previousEdits = [];
    await Promise.all(paths.map((path: string) => this.removeEdit(path)));
  }

  /// 回收编辑器创建的临时文件，沙盒缓存可能已经被系统清理。
  private async removeEdit(path: string): Promise<void> {
    try {
      await fileIo.unlink(path);
    } catch (_) {
      // 缓存文件已经回收时无需重试。
    }
  }

  /// 确认先在授权仍有效时导出快照，失败时留在相册供用户重试。
  private async confirm(): Promise<void> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined || this.exporting || this.showingAlbums || this.selectedUris.length === 0) {
      return;
    }
    this.exporting = true;
    // 用编辑文件替换来源，沿用导出工具对选择顺序和完整数量的保证。
    const uris = this.selectedUris.slice();
    const paths = uris.map((uri: string) => this.editedImages.get(uri) ?? uri);
    let selection: AlbumPickerSelection[];
    try {
      selection = await AlbumPickerOutput.prepare(paths, this.original, context);
    } catch (_) {
      if (this.active) {
        this.exporting = false;
        this.notify('无法读取所选文件，请重试');
      } else {
        await this.discardEdits();
      }
      return;
    }

    // 原图开关保留未修改的原件，用户编辑过的图片始终发送编辑稿。
    selection.forEach((item: AlbumPickerSelection, index: number) => {
      if (paths[index] !== uris[index]) {
        item.isOriginal = false;
        // 编辑稿的文件名和大小不作为原件信息回传给聊天发送层。
        item.sourceName = undefined;
      }
    });
    await this.discardEdits();
    // 宿主可以在导出期间外部退出页面，此时由组件回收未交付的文件。
    if (!this.active) {
      await AlbumPickerOutput.discard(selection);
      return;
    }
    this.onConfirm(selection);
  }

  @Builder
  private header() {
    Row() {
      // 下拉只改变中间的箭头，左侧关闭图标保持原样。
      Button() {
        Image($r('app.media.album_picker_ic_close'))
          .width(24)
          .height(24)
          .accessibilityLevel('no')
      }
        .id('album_picker.header.back')
        .accessibilityText('取消')
        .type(ButtonType.Normal)
        .width(64)
        .height(48)
        .backgroundColor(Color.Transparent)
        .enabled(!this.exporting)
        .onClick(() => this.handleLeadingButton())
      // 网格和相册列表间切换时显示当前相册。
      Button() {
        Row({ space: 4 }) {
          Text(this.currentAlbumTitle())
            .fontColor(Color.White)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '80%' })
          Image($r('app.media.album_picker_ic_arrow_down'))
            .width(24)
            .height(24)
            .rotate({ angle: this.showingAlbums ? 180 : 0 })
            .accessibilityLevel('no')
        }.justifyContent(FlexAlign.Center)
      }
        .id('album_picker.header.albums')
        .accessibilityText(`${this.currentAlbumTitle()}，${this.showingAlbums ? '收起相册列表' : '展开相册列表'}`)
        .type(ButtonType.Normal)
        .backgroundColor(Color.Transparent)
        .height(48)
        .layoutWeight(1)
        .enabled(this.pickerReady && !this.exporting)
        .onClick(() => { this.showingAlbums = !this.showingAlbums; })
      // 与左侧按钮等宽，保证标题相对整个页面居中。
      Blank().width(64)
    }
    .height(ALBUM_HEADER_HEIGHT)
    .width('100%')
    .backgroundColor(ALBUM_PICKER_BACKGROUND)
  }

  @Builder
  private previewHeader() {
    // 固定颜色遮住左侧导航区，右侧给系统勾选保留独立的绘制和点击空间。
    Column()
      .width(this.usesPreviewSelectionButton() ? '80%' :
        `calc(${PREVIEW_CHECKBOX_X}% - ${PREVIEW_CHECKBOX_SIZE / 2 + PREVIEW_CHECKBOX_INSET}vp)`)
      .height(ALBUM_HEADER_HEIGHT)
      .position({ x: 0, y: 0 })
      .backgroundColor(ALBUM_PICKER_BACKGROUND)
      .hitTestBehavior(HitTestMode.None)
    Button() {
      Image($r('app.media.album_picker_ic_back'))
        .width(24)
        .height(24)
        .accessibilityLevel('no')
    }
      .id('album_picker.preview.back')
      .accessibilityText('返回')
      .type(ButtonType.Normal)
      .width(56)
      .height(ALBUM_HEADER_HEIGHT)
      .padding(0)
      .position({ x: 0, y: 0 })
      .backgroundColor(Color.Transparent)
      .enabled(!this.exporting)
      .onClick(() => this.handleLeadingButton())
    if (this.usesPreviewSelectionButton()) {
      this.previewSelectionButton()
    } else {
      this.nativePreviewSelection()
    }
  }

  @Builder
  private nativePreviewSelection() {
    // 只给圆形控件的外围补底色，圆内留给系统呈现和授权。
    Column()
      .width(PREVIEW_CHECKBOX_SIZE)
      .height(PREVIEW_CHECKBOX_TOP)
      .position({ x: `${PREVIEW_CHECKBOX_X}%`, y: PREVIEW_CHECKBOX_TOP + PREVIEW_CHECKBOX_SIZE })
      .translate({ x: -PREVIEW_CHECKBOX_SIZE / 2 - PREVIEW_CHECKBOX_INSET })
      .backgroundColor(ALBUM_PICKER_BACKGROUND)
      .hitTestBehavior(HitTestMode.None)
    ForEach(PREVIEW_CORNER_ROWS, (row: number) => {
      this.authorizationCorner(row, false, false)
      this.authorizationCorner(row, true, false)
      this.authorizationCorner(row, true, true)
      this.authorizationCorner(row, false, true)
    })
    Text(this.awaitingEditPermissionUri.length > 0 ? '授权' : '选择')
      .fontColor(Color.White)
      .fontSize(15)
      .textAlign(TextAlign.Center)
      .width(`calc(${100 - PREVIEW_CHECKBOX_X}% - ${PREVIEW_CHECKBOX_SIZE / 2 - PREVIEW_CHECKBOX_INSET}vp)`)
      .height(ALBUM_HEADER_HEIGHT)
      .position({ right: 0, top: 0 })
      .backgroundColor(ALBUM_PICKER_BACKGROUND)
      .hitTestBehavior(HitTestMode.None)
  }

  /// 按距圆心最近的行边界算宽度，每条补色都在圆外，避免透明图形的边界拦截点击。
  private authorizationCornerWidth(row: number): number {
    const radius = PREVIEW_CHECKBOX_SIZE / 2;
    const distance = radius - row - 1;
    return radius - Math.sqrt(radius * radius - distance * distance);
  }

  @Builder
  private authorizationCorner(row: number, right: boolean, bottom: boolean) {
    Column()
      .width(this.authorizationCornerWidth(row))
      .height(1)
      .position({
        x: `${PREVIEW_CHECKBOX_X}%`,
        y: PREVIEW_CHECKBOX_TOP + (bottom ? PREVIEW_CHECKBOX_SIZE - row - 1 : row),
      })
      .translate({ x: -PREVIEW_CHECKBOX_INSET + (right ?
        PREVIEW_CHECKBOX_SIZE / 2 - this.authorizationCornerWidth(row) : -PREVIEW_CHECKBOX_SIZE / 2) })
      .backgroundColor(ALBUM_PICKER_BACKGROUND)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private previewSelectionButton() {
    // 沿用安卓的白色空心圆和实心对勾，状态切换时保持图标位置不变。
    Button() {
      Row() {
        Row() {
          Stack() {
            if (this.isCurrentPreviewSelected()) {
              Image($r('app.media.album_picker_ic_done'))
                .width(16)
                .height(16)
                .accessibilityLevel('no')
            }
          }
          .width(PREVIEW_CHECKBOX_SIZE)
          .height(PREVIEW_CHECKBOX_SIZE)
          .borderRadius(PREVIEW_CHECKBOX_SIZE / 2)
          .border({ width: this.isCurrentPreviewSelected() ? 0 : 2, color: Color.White })
          .backgroundColor(this.isCurrentPreviewSelected() ? this.primaryColor : Color.Transparent)
        }.width('44%').justifyContent(FlexAlign.Center)
        Text('选择')
          .fontColor(Color.White)
          .fontSize(15)
          .textAlign(TextAlign.Center)
          .width('56%')
      }.width('100%')
    }
    .id('album_picker.preview.selection')
    .accessibilityText('选择')
    .accessibilityChecked(this.isCurrentPreviewSelected())
    .type(ButtonType.Normal)
    .width('20%')
    .height(ALBUM_HEADER_HEIGHT)
    .padding(0)
    .position({ right: 0, top: 0 })
    .backgroundColor(ALBUM_PICKER_BACKGROUND)
    .enabled(!this.exporting)
    .onClick(() => this.togglePreviewSelection())
  }

  @Builder
  private gallery() {
    PhotoPickerComponent({
      pickerOptions: this.pickerOptions,
      pickerController: this.pickerController,
      onPickerControllerReady: () => {
        // 控制器就绪后隐藏系统返回按钮，预览和网格共用应用的导航栏。
        this.pickerController.setPhotoBrowserUIElementVisibility([PhotoBrowserUIElement.BACK_BUTTON], false);
        this.pickerReady = true;
      },
      onSelect: (uri: string) => this.select(uri),
      onExceedMaxSelected: () => this.notify(`最多选择${this.selectionLimit()}项`),
      onDeselect: (uri: string) => {
        this.selectedUris = this.selectedUris.filter((selected: string) => selected !== uri);
        this.updatePreviewCheckbox();
      },
      onItemClicked: (_item: ItemInfo, _click: ClickType) => this.allowGalleryAction(),
      onSelectedItemsDeleted: (items: BaseItemInfo[]) => {
        this.selectedUris = this.selectedUris.filter((uri: string) =>
          !items.some((item: BaseItemInfo) => item.uri === uri));
        this.previewSelection = this.previewSelection.filter((uri: string) =>
          !items.some((item: BaseItemInfo) => item.uri === uri));
        this.updatePreviewCheckbox();
      },
      onCurrentAlbumDeleted: () => {
        this.pickerController.setData(DataType.SET_ALBUM_URI, '');
        this.albumName = '';
      },
      onEnterPhotoBrowser: () => {
        if (!this.allowGalleryAction()) {
          // 进入预览的回调返回值不会阻止系统打开预览，因此主动退回网格。
          this.previewSelection = [];
          this.pickerController.exitPhotoBrowser();
          return false;
        }
        this.showingPreview = true;
        this.updatePreviewCheckbox();
        return true;
      },
      onExitPhotoBrowser: () => {
        this.showingPreview = false;
        this.previewItem = {};
        if (this.previewSelection.length > 0) {
          // 回到网格后应用预览期间的取消勾选，网格和发送数量以同一份选集为准。
          this.pickerController.setData(DataType.SET_SELECTED_URIS, this.selectedUris);
        }
        this.previewSelection = [];
        this.awaitingEditPermissionUri = '';
        this.pickerController.setPhotoBrowserUIElementVisibility([PhotoBrowserUIElement.CHECKBOX], true);
        return true;
      },
      onPhotoBrowserChanged: (item: BaseItemInfo) => {
        // 离开待授权图片后，后续勾选不再打开先前图片的编辑器。
        if (item.uri !== this.previewItem.uri) {
          this.awaitingEditPermissionUri = '';
        }
        this.previewItem = item;
        this.updatePreviewCheckbox();
        return true;
      },
    })
      .layoutWeight(1)
      .width('100%')
  }

  /// 浮层显示或导出期间拦截系统图库回调，避免底层状态随手势变化。
  private allowGalleryAction(): boolean {
    return !this.exporting && !this.showingAlbums;
  }

  @Builder
  private footer() {
    Row({ space: 10 }) {
      // 左右操作区等宽，预览、编辑和发送的文案变化不会挪动原图选项。
      Row() {
        if (!this.showingPreview) {
          Button(this.selectedUris.length === 0 ? '预览' : `预览(${this.selectedUris.length})`)
            .id('album_picker.footer.preview')
            .type(ButtonType.Normal)
            .fontColor(Color.White)
            .fontSize(16)
            .backgroundColor(Color.Transparent)
            .enabled(!this.showingAlbums && this.pickerReady && this.selectedUris.length > 0 &&
              !this.exporting)
            .onClick(() => {
              // 系统只允许指定已授权的媒体，预览范围按入场的已选集合限制。
              this.previewSelection = this.selectedUris.slice();
              this.pickerController.setPhotoBrowserItem(this.selectedUris[0], PhotoBrowserRange.SELECTED_ONLY);
            })
        } else if (this.canEditPreview()) {
          Button('编辑')
            .id('album_picker.preview.edit')
            .type(ButtonType.Normal)
            .fontColor(Color.White)
            .fontSize(16)
            .backgroundColor(Color.Transparent)
            .enabled(!this.exporting)
            .onClick(() => { void this.editPreview(); })
        }
      }.layoutWeight(1)
      // 去掉复选框的默认外边距，使居中基于复选框和文字的实际宽度。
      Row({ space: 10 }) {
        Checkbox({ name: 'original' })
          .id('album_picker.footer.original')
          .select(this.original)
          .selectedColor(this.primaryColor)
          .enabled(!this.showingAlbums && !this.exporting)
          .accessibilityText('原图')
          .onChange((value: boolean) => this.original = value)
          .width(24)
          .height(24)
          .margin(0)
        Text('原图')
          .id('album_picker.footer.original_label')
          .fontSize(15)
          .fontColor(Color.White)
          .enabled(!this.showingAlbums && !this.exporting)
          .onClick(() => this.original = !this.original)
      }
      // 发送按钮靠右，处理中沿用同一位置并禁止重复确认。
      Row() {
        Button(this.exporting ? '处理中…' :
          (this.selectedUris.length === 0 ? '发送' : `发送(${this.selectedUris.length})`))
          .id('album_picker.footer.send')
          .type(ButtonType.Normal)
          .fontColor(Color.White)
          .backgroundColor(this.selectedUris.length === 0 ? '#414141' : this.primaryColor)
          .borderRadius(6)
          .height(36)
          .enabled(!this.showingAlbums && this.selectedUris.length > 0 && !this.exporting)
          .onClick(() => {
            void this.confirm();
          })
      }.layoutWeight(1).justifyContent(FlexAlign.End)
    }
    .height(56)
    .width('100%')
    .padding({ left: 12, right: 12 })
  }

  @Builder
  private floatingAlbumMenu() {
    // 遮罩拦截面板外的点击，只执行收起，避免触发下方图库或发送按钮。
    Button()
      .id('album_picker.filter.dismiss')
      .accessibilityText('收起相册列表')
      .type(ButtonType.Normal)
      .width('100%')
      .height('100%')
      .borderRadius(0)
      .backgroundColor('#66000000')
      .stateEffect(false)
      .onClick(() => { this.showingAlbums = false; })
      .transition(TransitionEffect.OPACITY.animation({ duration: ALBUM_MENU_TRANSITION_MS }))

    // 直接显示系统列表的分类、相册、封面和数量，面板独立于网格测量。
    AlbumPickerComponent({
      albumPickerOptions: { themeColorMode: PickerColorMode.DARK, filterType: this.mediaType, fontSize: 14 },
      onAlbumClick: (album: AlbumInfo) => this.switchAlbum(album),
      onEmptyAreaClick: () => { this.showingAlbums = false; },
    })
      .id('album_picker.album.list')
      .width('100%')
      .height('60%')
      .borderRadius(12)
      .clip(true)
      .transition(TransitionEffect.translate({ y: -16 }).combine(TransitionEffect.OPACITY)
        .animation({ duration: ALBUM_MENU_TRANSITION_MS, curve: Curve.EaseInOut }))
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 图库保留挂载和预览位置，编辑器只替换当前可见内容。
      Column() {
        this.gallery()
        this.footer()
      }
      .width('100%')
      .height('100%')
      .visibility(this.editorSource.length > 0 ? Visibility.Hidden : Visibility.Visible)
      if (this.editorSource.length > 0) {
        AlbumImageEditor({
          sourcePath: this.editorSource,
          onCancel: () => {
            this.editorSource = '';
            this.editingUri = '';
          },
          onSave: (path: string) => this.saveEdit(path),
          onToast: (message: string) => this.notify(message),
        })
      }
      // 下拉层从固定工具栏下方开始，不参与图库的测量。
      if (this.showingAlbums) {
        Column() {
          Blank().height(ALBUM_HEADER_HEIGHT)
          Stack({ alignContent: Alignment.Top }) {
            this.floatingAlbumMenu()
          }.layoutWeight(1).width('100%').clip(true)
        }.width('100%').height('100%')
      }
      if (this.editorSource.length === 0) {
        if (this.showingPreview) {
          this.previewHeader()
        } else {
          this.header()
        }
      }
      // 提示绘制在图库和编辑页上方，触摸仍交给当前操作区域。
      NativeToast({ state: this.toast, bottomInset: this.toastBottomInset })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(ALBUM_PICKER_BACKGROUND)
  }
}
