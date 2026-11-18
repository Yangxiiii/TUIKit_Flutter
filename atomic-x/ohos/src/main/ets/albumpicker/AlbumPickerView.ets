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
import { AlbumPickerOutput, AlbumPickerSelection } from './AlbumPickerOutput';

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
  /// 所选媒体全部落盘后回调，调用方接管文件并决定关闭时机。
  onConfirm: (selection: AlbumPickerSelection[]) => void = () => {};
  /// 从相册网格取消时回调，由调用方关闭页面。
  onCancel: () => void = () => {};

  /// 系统选中回调授权的 URI 按操作顺序排列，跨相册切换保留。
  @State private selectedUris: string[] = [];
  @State private albumName: string = '相册';
  @State private showingAlbums: boolean = false;
  @State private showingPreview: boolean = false;
  /// 系统当前预览的图片 URI，预览视频时为空。
  @State private previewImageUri: string = '';
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
    this.pickerOptions.backgroundColor = '#161616';
    this.pickerOptions.maxSelectedReminderMode = ReminderMode.TOAST;
  }

  aboutToDisappear(): void {
    this.active = false;
    if (!this.exporting) {
      void this.discardEdits();
    }
  }

  private selectionLimit(): number {
    // 系统选图 API 接受正整数，非法配置沿用聊天默认值。
    return Number.isFinite(this.maxCount) && this.maxCount >= 1 ? Math.floor(this.maxCount) : 9;
  }

  /// 先退出预览或相册列表，网格层的返回才结束选图会话。
  private goBack(): void {
    if (this.showingPreview) {
      this.pickerController.exitPhotoBrowser();
    } else if (this.showingAlbums) {
      this.showingAlbums = false;
    } else {
      this.onCancel();
    }
  }

  /// 切换安全网格的数据范围，保留当前待发送的完整选集。
  private switchAlbum(album: AlbumInfo): boolean {
    const uri = album.uri;
    if (uri === undefined) {
      return false;
    }
    this.pickerController.setData(DataType.SET_ALBUM_URI, uri);
    this.albumName = album.albumName ?? '相册';
    this.showingAlbums = false;
    return true;
  }

  /// 按系统授权回调追加 URI，忽略重复通知和越过上限的异常回调。
  private select(uri: string): void {
    if (uri.length === 0 || this.selectedUris.includes(uri)) {
      return;
    }
    if (this.selectedUris.length >= this.selectionLimit()) {
      this.pickerController.setData(DataType.SET_SELECTED_URIS, this.selectedUris);
      return;
    }
    this.selectedUris = [...this.selectedUris, uri];
  }

  /// 读取当前预览的图片，已编辑时以最新副本作为下一次编辑的来源。
  private editPreview(): void {
    const uri = this.previewImageUri;
    if (uri.length === 0 || this.exporting) {
      return;
    }
    // shortcut: 先勾选以取得图片读取授权，待安全图库支持从预览直接授权时移除限制。
    if (!this.selectedUris.includes(uri)) {
      this.notify('请先勾选当前图片，再编辑');
      return;
    }
    this.editingUri = uri;
    this.editorSource = this.editedImages.get(uri) ?? uri;
  }

  /// 保存编辑稿供预览和确认使用，图库文件仍由系统管理。
  private saveEdit(path: string): void {
    const uri = this.editingUri;
    this.editorSource = '';
    this.editingUri = '';
    if (!this.active || !this.selectedUris.includes(uri)) {
      void this.removeEdit(path);
      return;
    }

    // 发送读取沙盒稿，系统预览仍用原始图库 URI 定位相册中的条目。
    const previous = this.editedImages.get(uri);
    if (previous !== undefined) {
      this.previousEdits.push(previous);
    }
    this.editedImages.set(uri, path);
    try {
      this.pickerController.replacePhotoPickerPreview(uri, fileUri.getUriFromPath(path), (error) => {
        if (error && error.code !== 0 && this.active) {
          this.notify('编辑稿已保留，暂时无法刷新预览');
        }
      });
    } catch (_) {
      this.notify('编辑稿已保留，暂时无法刷新预览');
    }
  }

  /// 平台窗口关闭时可能无法展示提示，提示失败不影响保留编辑稿。
  private notify(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message });
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
    if (context === undefined || this.exporting || this.selectedUris.length === 0) {
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
      Button(this.showingPreview || this.showingAlbums ? '返回' : '取消')
        .type(ButtonType.Normal)
        .fontColor(Color.White)
        .fontSize(16)
        .backgroundColor(Color.Transparent)
        .enabled(!this.exporting)
        .onClick(() => this.goBack())
      if (this.showingPreview) {
        Text('预览')
          .fontColor(Color.White)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
      } else {
        Button(`${this.albumName} ▾`)
          .type(ButtonType.Normal)
          .fontColor(Color.White)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .backgroundColor(Color.Transparent)
          .layoutWeight(1)
          .enabled(this.pickerReady && !this.exporting)
          .onClick(() => this.showingAlbums = !this.showingAlbums)
      }
      Blank().width(64)
    }
    .height(52)
    .width('100%')
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
      onDeselect: (uri: string) => {
        this.selectedUris = this.selectedUris.filter((selected: string) => selected !== uri);
      },
      // 系统在用户点击相机磁贴和选框前询问是否继续；确认时拒绝修改选集。
      onItemClicked: (_item: ItemInfo, _click: ClickType) => !this.exporting,
      onSelectedItemsDeleted: (items: BaseItemInfo[]) => {
        this.selectedUris = this.selectedUris.filter((uri: string) =>
          !items.some((item: BaseItemInfo) => item.uri === uri));
      },
      onCurrentAlbumDeleted: () => {
        this.pickerController.setData(DataType.SET_ALBUM_URI, '');
        this.albumName = '相册';
      },
      onEnterPhotoBrowser: () => {
        if (this.exporting) {
          return false;
        }
        this.showingPreview = true;
        return true;
      },
      onExitPhotoBrowser: () => {
        this.showingPreview = false;
        this.previewImageUri = '';
        return true;
      },
      onPhotoBrowserChanged: (item: BaseItemInfo) => {
        // 视频可以发送，但图片编辑入口仅对当前显示的图片开放。
        this.previewImageUri = item.mimeType?.startsWith('image/') ? item.uri ?? '' : '';
        return true;
      },
    })
      .visibility(this.showingAlbums || this.editorSource.length > 0 ? Visibility.None : Visibility.Visible)
      .layoutWeight(1)
      .width('100%')

    if (this.showingAlbums) {
      AlbumPickerComponent({
        albumPickerOptions: { themeColorMode: PickerColorMode.DARK, filterType: this.mediaType },
        onAlbumClick: (album: AlbumInfo) => this.switchAlbum(album),
      })
        .layoutWeight(1)
        .width('100%')
    }
  }

  @Builder
  private footer() {
    Row({ space: 10 }) {
      if (!this.showingPreview) {
        Button(this.selectedUris.length === 0 ? '预览' : `预览(${this.selectedUris.length})`)
          .type(ButtonType.Normal)
          .fontColor(Color.White)
          .fontSize(16)
          .backgroundColor(Color.Transparent)
          .enabled(this.pickerReady && this.selectedUris.length > 0 && !this.exporting)
          .onClick(() => {
            // 系统只允许指定已授权的媒体，预览范围按已选集合限制。
            this.pickerController.setPhotoBrowserItem(this.selectedUris[0], PhotoBrowserRange.SELECTED_ONLY);
          })
      } else {
        Button('编辑')
          .id('album_picker.preview.edit')
          .type(ButtonType.Normal)
          .fontColor(Color.White)
          .fontSize(16)
          .backgroundColor(Color.Transparent)
          .enabled(this.previewImageUri.length > 0 && !this.exporting)
          .onClick(() => this.editPreview())
      }
      Checkbox({ name: 'original' })
        .select(this.original)
        .selectedColor(this.primaryColor)
        .enabled(!this.exporting)
        .accessibilityText('原图')
        .onChange((value: boolean) => this.original = value)
        .width(24)
        .height(24)
      Text('原图')
        .fontSize(15)
        .fontColor(Color.White)
        .enabled(!this.exporting)
        .onClick(() => this.original = !this.original)
      Blank()
      Button(this.exporting ? '处理中…' :
        (this.selectedUris.length === 0 ? '发送' : `发送(${this.selectedUris.length})`))
        .type(ButtonType.Normal)
        .fontColor(Color.White)
        .backgroundColor(this.selectedUris.length === 0 ? '#414141' : this.primaryColor)
        .borderRadius(6)
        .height(36)
        .enabled(this.selectedUris.length > 0 && !this.exporting)
        .onClick(() => {
          void this.confirm();
        })
    }
    .height(56)
    .width('100%')
    .padding({ left: 12, right: 12 })
  }

  build() {
    Column() {
      // 页面栏保留取消和相册切换，预览时同一位置返回网格。
      if (this.editorSource.length === 0) {
        this.header()
      }
      // 安全图库不能被浮层遮挡，网格与相册列表在同一区域切换。
      this.gallery()
      if (this.editorSource.length > 0) {
        // 编辑器作为独立内容出现，图库组件保持挂载以保留选集和预览位置。
        AlbumImageEditor({
          sourcePath: this.editorSource,
          onCancel: () => {
            this.editorSource = '';
            this.editingUri = '';
          },
          onSave: (path: string) => this.saveEdit(path),
        })
      } else if (!this.showingAlbums) {
        this.footer()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#161616')
  }
}
