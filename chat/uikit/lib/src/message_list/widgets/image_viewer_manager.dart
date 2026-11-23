import 'dart:io';

import 'package:atomic_x_core/api/message/message_action_store.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

import '../../image_viewer/image_element.dart';
import '../../image_viewer/image_viewer.dart';
import '../../message_input/chat_media_sender.dart';
import '../message_history_config.dart';
import '../utils/rich_content_media_viewer.dart';
import '../utils/rich_content_message.dart';

/// 将消息媒体转换为预览数据，静态转发集合不拉取原会话历史。
class ImageViewerManager {
  bool _isShowingImageViewer = false;
  List<ImageElement> _initialImageElements = [];
  int _initialImageIndex = 0;
  bool _isLoadingImageData = false;
  final String _conversationID;

  /// 预览窗口必须排除当前账号已删除的消息，即使 SDK 仍能查询到。
  final Set<String> _hiddenMessageIDs;

  /// 富文本视频使用宿主下载，SDK 视频继续下载原消息附件。
  final ChatFileDownloader? _downloadRichVideo;

  /// 宿主负责旧消息归档的账号、会话和网络校验。
  final ChatOlderMessagesLoader? _loadOlderMedia;

  ImageViewerDataManager? _imageViewerDataManager;
  final MessageInfo _currentMessage;

  /// 合并记录、离线窗口或本机补齐的现有媒体。只有提供归档查询时才继续向旧侧翻页。
  final List<MessageInfo>? _presetMediaMessages;

  ImageViewerManager({
    required String conversationID,
    required MessageInfo currentMessage,
    required BuildContext context,
    List<MessageInfo>? presetMediaMessages,
    Set<String> hiddenMessageIDs = const {},
    ChatFileDownloader? downloadRichVideo,
    ChatOlderMessagesLoader? loadOlderMedia,
  })  : _loadOlderMedia = loadOlderMedia,
        _hiddenMessageIDs = hiddenMessageIDs,
        _downloadRichVideo = downloadRichVideo,
        _conversationID = conversationID,
        _currentMessage = currentMessage,
        _presetMediaMessages = presetMediaMessages;

  // Getters
  bool get isShowingImageViewer => _isShowingImageViewer;

  List<ImageElement> get initialImageElements => _initialImageElements;

  int get initialImageIndex => _initialImageIndex;

  bool get isLoadingImageData => _isLoadingImageData;

  /// 在线会话可在两侧续页，预设窗口仅在宿主提供归档查询时向前续页。
  bool get canPageAtEdge =>
      _presetMediaMessages == null || _loadOlderMedia != null;

  /// 初次预览与后续分页复用同一份会话媒体窗口。
  ImageViewerDataManager get _dataManager =>
      _imageViewerDataManager ??= ImageViewerDataManager(
        conversationID: _conversationID,
        currentMessage: _currentMessage,
        presetMediaMessages: _presetMediaMessages,
        hiddenMessageIDs: _hiddenMessageIDs,
        loadOlderMedia: _loadOlderMedia,
      );

  /// 先展示点中的图片，较清晰的资源和相邻媒体随后更新，不阻塞预览页打开。
  Stream<List<ImageElement>> loadImageWindow() =>
      _dataManager.loadImageWindow();

  /// 先定位被点的块，再合并同一会话的历史，避免等待历史请求才打开预览。
  Future<void> showRichContent(
      BuildContext context, RichContentMessage content, int blockIndex) async {
    final media =
        richContentMediaEntries(content, messageId: _currentMessage.msgID);
    final index = media.indexWhere((entry) => entry.index == blockIndex);
    if (index < 0) return;
    final selected = media[index].element;
    await ImageViewer.view(
      context,
      imageElements: media.map((entry) => entry.element).toList(),
      initialIndex: index,
      imageUpdates: _dataManager
          .loadInitialData(currentImage: selected)
          .asStream()
          .map((window) => window.mediaElements),
      onEventTriggered: handleImageViewerEvent,
      loadMoreOnOverscroll: canPageAtEdge,
    );
  }

  Future<void> showImageViewerIfAvailable() async {
    if (_isLoadingImageData) return;

    _isLoadingImageData = true;
    _initialImageElements = [];
    _initialImageIndex = 0;

    try {
      final result = await _dataManager.loadInitialData();
      _initialImageElements = result.mediaElements;
      _initialImageIndex = result.currentIndex;
      _isShowingImageViewer = _initialImageElements.isNotEmpty;
    } finally {
      _isLoadingImageData = false;
    }
  }

  void hideImageViewer() {
    _isShowingImageViewer = false;
  }

  void handleImageViewerEvent(
      Map<String, dynamic> eventData, Function(dynamic) callback) {
    final event = eventData['event'] as String;

    switch (event) {
      case 'onImageTap':
        hideImageViewer();
        callback(null);
        break;

      case 'onLoadMore':
        final param = eventData['param'] as Map<String, dynamic>;
        final isOlder = param['isOlder'] as bool;
        _handleLoadMore(isOlder, callback);
        break;

      case 'onDownloadVideo':
        final param = eventData['param'] as Map<String, dynamic>;
        _handleDownloadVideo(
            param['mediaId'] as String?, param['path'] as String, callback);
        break;

      default:
        callback(null);
    }
  }

  Future<void> _handleLoadMore(bool isOlder, Function(dynamic) callback) async {
    try {
      final result =
          await _imageViewerDataManager?.loadMoreData(isOlder: isOlder) ??
              (elements: <ImageElement>[], hasMoreData: false);
      callback({
        'elements': result.elements,
        'hasMoreData': result.hasMoreData,
      });
    } catch (e) {
      callback({
        'elements': <ImageElement>[],
        'hasMoreData': false,
      });
    }
  }

  /// 按稳定块标识找到视频；普通视频仍允许用已有封面路径定位。
  Future<void> _handleDownloadVideo(
      String? mediaId, String imagePath, Function(dynamic) callback) async {
    if (_dataManager.findRichVideo(mediaId) case final video?) {
      try {
        callback(await downloadRichContentVideo(video, _downloadRichVideo));
      } on Object {
        callback(<String>[]);
      }
      return;
    }
    final targetMessage =
        _dataManager.findVideo(mediaId: mediaId, imagePath: imagePath);
    if (targetMessage == null) {
      callback([]);
      return;
    }

    final videoPayload = targetMessage.messagePayload as VideoMessagePayload?;
    if (videoPayload?.videoPath != null &&
        videoPayload!.videoPath!.isNotEmpty) {
      final file = File(videoPayload.videoPath!);
      if (await file.exists()) {
        callback([videoPayload.videoPath!]);
        return;
      }
    }

    await MessageActionStore.create(targetMessage).downloadMedia();

    final updatedMessage = _dataManager.messageListStore.state.messageList.value.firstWhere(
      (message) => message.msgID == targetMessage.msgID,
      orElse: () => targetMessage,
    );

    final newVideoPath =
        (updatedMessage.messagePayload as VideoMessagePayload?)?.videoPath;
    if (newVideoPath != null && newVideoPath.isNotEmpty) {
      final newFile = File(newVideoPath);
      if (await newFile.exists()) {
        callback([newVideoPath]);
      } else {
        callback([]);
      }
    } else {
      callback([]);
    }
  }

  void dispose() {
    _imageViewerDataManager?.dispose();
  }
}

/// 读取媒体本地文件及远端展示地址，按来源集合提供分页和SDK下载回退。
class ImageViewerDataManager {
  /// 在线预览仅查询此会话范围内的媒体。
  final String conversationID;

  /// 用作历史查询锚点，历史不可用时保留这条消息的媒体。
  final MessageInfo currentMessage;

  /// 需要分页或解析原生视频时才建立 SDK 窗口，静态图片预览可离线打开。
  late final MessageListStore messageListStore =
      _providedStore ?? MessageListStore.create(conversationID: conversationID);

  /// 调用方注入的分页窗口，缺省时由预览器建立独立窗口。
  final MessageListStore? _providedStore;

  /// 预设媒体窗口无需创建 SDK 历史查询；宿主可提供同一会话的旧页归档。
  final List<MessageInfo>? presetMediaMessages;

  /// 当前账号从会话中隐藏的消息不进入预览。
  final Set<String> hiddenMessageIDs;

  /// SDK 历史只能覆盖保留期，旧页通过宿主的会话归档续查。
  final ChatOlderMessagesLoader? loadOlderMedia;

  /// 已取到的归档按时间正序放在 SDK 窗口之前。
  final _archivedMessages = <MessageInfo>[];

  /// 第一页按 SDK 或预设窗口的最早时间查，之后只推进归档游标。
  String? _archiveCursor;

  /// 归档没有更早游标时终止，不重复请求最后一页。
  bool _archiveExhausted = false;

  /// SDK 异常重复同一端游标时，该方向不再请求 SDK。
  final _stalledSdkDirections = <bool>{};

  /// 媒体历史使用独立 SDK 窗口，串行读取以保护双向游标。
  bool _loadingHistory = false;

  /// 首次读取失败时保留当前媒体，下一次边缘滑动仍能重试。
  bool _historyReady = false;

  /// 关闭预览后停止继续翻找历史。
  bool _disposed = false;

  /// SDK 地址和下载回执超过此时长后，继续尝试其他图片规格。
  static const _imageRequestTimeout = Duration(seconds: 10);

  ImageViewerDataManager({
    required this.conversationID,
    required this.currentMessage,
    MessageListStore? messageListStore,
    this.presetMediaMessages,
    this.hiddenMessageIDs = const {},
    this.loadOlderMedia,
  }) : _providedStore = messageListStore;

  bool get _isPresetMode => presetMediaMessages != null;

  List<MessageInfo> get _sdkOrPresetMessages =>
      presetMediaMessages ?? messageListStore.state.messageList.value;

  List<MessageInfo> get _sourceMessages => _archivedMessages.isEmpty
      ? _sdkOrPresetMessages
      : [..._archivedMessages, ..._sdkOrPresetMessages];

  /// 会话按消息时间排列，重复的历史游标只保留一次。
  List<MessageInfo> get _mediaMessages {
    final seen = <String>{};
    return [
      for (final msg in _sourceMessages)
        if (!hiddenMessageIDs.contains(msg.msgID) &&
            msg.status != MessageStatus.revoked &&
            msg.status != MessageStatus.deleted &&
            msg.status != MessageStatus.violation &&
            (msg.messageType == MessageType.image ||
                msg.messageType == MessageType.video ||
                _richContent(msg)?.mediaBlocks.isNotEmpty == true) &&
            (msg.msgID.isEmpty || seen.add(msg.msgID)))
          msg,
    ];
  }

  RichContentMessage? _richContent(MessageInfo msg) {
    final payload = msg.messagePayload;
    return payload is CustomMessagePayload
        ? RichContentMessage.tryParse(payload.customData)
        : null;
  }

  /// 先发布现成图片，再查询大图和周边消息。窗口重查不能替换点中消息已解析的资源。
  Stream<List<ImageElement>> loadImageWindow() async* {
    // 气泡已有的图片先交给预览，弱网时无需等待 SDK。
    final cached = await _processImageMessagePayload(
      currentMessage,
      resolveFromSdk: false,
    );
    if (cached.imagePath.isNotEmpty) yield [cached];
    final current = await _processImageMessagePayload(currentMessage);
    if (cached.imagePath.isEmpty || cached != current) yield [current];

    // 历史消息可能缺少已取到的网址，重建窗口时沿用当前预览资源。
    final window = await loadInitialData(currentImage: current);
    if (window.mediaElements.length > 1) yield window.mediaElements;
  }

  /// 从当前来源建立浏览窗口，优先复用点中的图片资源。
  Future<({List<ImageElement> mediaElements, int currentIndex})>
      loadInitialData({ImageElement? currentImage}) async {
    if (_isPresetMode) {
      // 合并转发和已展示的本机窗口可直接定位点中的图片。
      final mediaElements = await _buildMediaElements(
        _mediaMessages,
        currentImage: currentImage,
      );
      final currentIndex = _findCurrentIndex(mediaElements, currentImage);
      if (currentIndex >= 0) {
        return (mediaElements: mediaElements, currentIndex: currentIndex);
      }
      return _currentMedia(currentImage);
    }

    if (_loadingHistory) return _currentMedia(currentImage);
    // SDK 加类型过滤只查本机；先按会话读取云端消息，再筛选普通及富文本媒体。
    final option = MessageLoadOption()
      ..direction = MessageLoadDirection.both
      ..pageCount = 20
      ..cursor = currentMessage;

    _loadingHistory = true;
    try {
      final mediaElements = await _loadMediaMessages(
        option: option,
        currentImage: currentImage,
      );
      final currentIndex = _findCurrentIndex(mediaElements, currentImage);
      if (currentIndex >= 0) {
        return (mediaElements: mediaElements, currentIndex: currentIndex);
      }
    } on Object {
      // 历史窗口查询失败时仍保留用户点开的资源。
    } finally {
      _loadingHistory = false;
    }
    return _currentMedia(currentImage);
  }

  /// 滑到会话媒体边缘时跳过纯文本页，以原始历史游标推进。
  Future<({List<ImageElement> elements, bool hasMoreData})> loadMoreData(
      {required bool isOlder}) async {
    if (_disposed) return (elements: const <ImageElement>[], hasMoreData: false);
    if (_loadingHistory) {
      return (elements: const <ImageElement>[], hasMoreData: true);
    }
    // 首次历史查询失败时先重建窗口，避免用空游标直接进入旧页。
    if (!_isPresetMode && !_historyReady) {
      final window = await loadInitialData();
      return (
        elements: window.mediaElements,
        hasMoreData: !_historyReady || _hasMoreMedia(isOlder),
      );
    }
    final known = _mediaMessages.map((message) => message.msgID).toSet();
    _loadingHistory = true;
    try {
      while (!_disposed && _hasMoreMedia(isOlder)) {
        // 先取完 SDK 历史，再由宿主归档续查更早一侧。
        if (_hasMoreSdkMedia(isOlder)) {
          await _loadSdkPage(isOlder);
        } else {
          await _loadArchivePage();
        }
        if (_disposed) break;
        final messages = _mediaMessages;
        if (messages.any((message) => !known.contains(message.msgID))) {
          return (
            elements: await _buildMediaElements(messages),
            hasMoreData: _hasMoreMedia(isOlder),
          );
        }
      }
      return (elements: const <ImageElement>[], hasMoreData: false);
    } on Object {
      return (elements: const <ImageElement>[], hasMoreData: !_disposed);
    } finally {
      _loadingHistory = false;
    }
  }

  bool _hasMoreSdkMedia(bool isOlder) =>
      !_isPresetMode &&
      !_stalledSdkDirections.contains(isOlder) &&
      (isOlder
          ? messageListStore.state.hasOlderMessages.value
          : messageListStore.state.hasNewerMessages.value);

  bool _hasMoreMedia(bool isOlder) =>
      _hasMoreSdkMedia(isOlder) ||
      (isOlder && loadOlderMedia != null && !_archiveExhausted);

  /// SDK 以未筛选的原始历史边缘为游标，空媒体页也能推进。
  Future<void> _loadSdkPage(bool isOlder) async {
    String? edgeId() =>
        (isOlder ? _sdkOrPresetMessages.firstOrNull : _sdkOrPresetMessages.lastOrNull)
            ?.msgID;
    final before = edgeId();
    final result = isOlder
        ? await messageListStore.loadOlderMessages()
        : await messageListStore.loadNewerMessages();
    if (!result.isSuccess) throw StateError('会话媒体历史加载失败');
    if (before == edgeId()) _stalledSdkDirections.add(isOlder);
  }

  /// SDK 更早一侧耗尽后，用最早消息时间接上宿主归档。
  Future<void> _loadArchivePage() async {
    int? earliest;
    final existing = <String>{};
    for (final message in _sourceMessages) {
      if (message.msgID.isNotEmpty) existing.add(message.msgID);
      final time = message.timestamp;
      if (time != null && time > 0 && (earliest == null || time < earliest)) {
        earliest = time;
      }
    }
    final page =
        await loadOlderMedia!(beforeTimestamp: earliest, cursor: _archiveCursor);
    if (_disposed) return;
    // SDK 和预设中已有的消息可能带撤回或编辑状态，归档不能覆盖它们。
    final messages = page.messages
        .where((message) => message.msgID.isEmpty || existing.add(message.msgID))
        .toList()
      ..sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
    _archivedMessages.insertAll(0, messages);
    _archiveExhausted =
        page.nextCursor == null || page.nextCursor == _archiveCursor;
    _archiveCursor = page.nextCursor;
  }

  int _findCurrentIndex(List<ImageElement> elements, ImageElement? selected) {
    final rich = _richContent(currentMessage);
    final firstRichId = rich == null
        ? null
        : richContentMediaEntries(rich, messageId: currentMessage.msgID)
            .firstOrNull
            ?.element
            .mediaId;
    final id = selected?.mediaId ?? firstRichId ?? currentMessage.msgID;
    if (id.isEmpty) return elements.isEmpty ? -1 : 0;
    return elements.indexWhere((element) => element.mediaId == id);
  }

  /// 当前会话历史暂不可用时保留被点消息里的完整附件顺序。
  Future<({List<ImageElement> mediaElements, int currentIndex})> _currentMedia(
      ImageElement? currentImage) async {
    final elements =
        await _buildMediaElements([currentMessage], currentImage: currentImage);
    final index = _findCurrentIndex(elements, currentImage);
    return (mediaElements: elements, currentIndex: index < 0 ? 0 : index);
  }

  /// 从当前消息及分页窗口定位富文本视频，多个块共用封面时仍能精确下载。
  RichFileBlock? findRichVideo(String? mediaId) {
    if (mediaId == null || !mediaId.startsWith('rich:')) return null;
    for (final message in [currentMessage, ..._mediaMessages]) {
      final content = _richContent(message);
      if (content == null) continue;
      for (final entry
          in richContentMediaEntries(content, messageId: message.msgID)) {
        if (entry.element.mediaId == mediaId && entry.block is RichFileBlock) {
          return entry.block as RichFileBlock;
        }
      }
    }
    return null;
  }

  /// SDK 视频优先按消息标识定位，兼容旧调用方仅提供封面路径。
  MessageInfo? findVideo({String? mediaId, required String imagePath}) =>
      [currentMessage, ..._mediaMessages].where((message) {
        final payload = message.messagePayload;
        if (payload is! VideoMessagePayload) return false;
        return mediaId != null
            ? message.msgID == mediaId
            : payload.videoSnapshotPath == imagePath ||
                payload.videoSnapshotURL == imagePath;
      }).firstOrNull;

  /// 转换时保留消息顺序；单个资源异常仍在原位置保留占位，避免滑到错误消息。
  Future<List<ImageElement>> _buildMediaElements(
    List<MessageInfo> messages, {
    ImageElement? currentImage,
  }) async {
    final List<ImageElement> resultElements = [];
    for (final msg in messages) {
      if (_disposed) break;
      if (_richContent(msg) case final rich?) {
        resultElements.addAll(richContentMediaEntries(rich, messageId: msg.msgID)
            .map((entry) => entry.element));
        continue;
      }
      try {
        final element =
            currentImage != null && msg.msgID == currentMessage.msgID
                ? currentImage
                : await _processMediaMessage(msg);
        resultElements.add(element);
      } catch (e) {
        // 单条解析失败仍占原位置，保持页码和消息顺序对应。
        final isVideo = msg.messageType == MessageType.video;
        resultElements.add(ImageElement(
          type: isVideo ? 1 : 0,
          imagePath: '',
          videoPath: '',
          mediaId: msg.msgID.isEmpty ? null : msg.msgID,
        ));
      }
    }
    return resultElements;
  }

  /// 载入会话媒体窗口，刷新列表时复用已解析的当前图片。
  Future<List<ImageElement>> _loadMediaMessages({
    required MessageLoadOption option,
    ImageElement? currentImage,
  }) async {
    final result = await messageListStore.loadMessages(option: option);
    if (!result.isSuccess) {
      throw Exception('fetchMessages failed');
    }

    _historyReady = true;
    return _buildMediaElements(_mediaMessages, currentImage: currentImage);
  }

  Future<ImageElement> _processMediaMessage(MessageInfo msg) async {
    if (msg.messageType == MessageType.image) {
      return await _processImageMessagePayload(msg);
    } else if (msg.messageType == MessageType.video) {
      return await _processVideoMessagePayload(msg);
    } else {
      throw Exception('not support message type');
    }
  }

  /// 先收集本机和现成网址，缺少大图时按需查询 SDK，并保留缩略图作为回退。
  Future<ImageElement> _processImageMessagePayload(
    MessageInfo msg, {
    bool resolveFromSdk = true,
  }) async {
    final imagePayload = msg.messagePayload as ImageMessagePayload?;
    final rawMessage = msg.rawMessage;
    final paths = <String>{};
    Future<void> addLocal(String? path) async {
      if (path == null || path.isEmpty) return;
      try {
        final stat = await File(path).stat();
        if (stat.type == FileSystemEntityType.file && stat.size > 0) {
          paths.add(path);
        }
      } on FileSystemException {
        // 沙盒清理期间本地候选可能消失，继续尝试剩余资源。
      }
    }

    void addRemote(String? value) {
      final path = _remotePreviewUrl([value]);
      if (path.isNotEmpty) paths.add(path);
    }

    await addLocal(imagePayload?.largeImagePath);
    await addLocal(imagePayload?.originalImagePath);
    addRemote(imagePayload?.largeImageURL);
    addRemote(imagePayload?.originalImageURL);

    // 跨端消息可能缺少直接网址，先取可预览地址，避免等待完整文件下载。
    if (resolveFromSdk && paths.isEmpty && rawMessage != null) {
      try {
        final result = await TencentImSDKPlugin.v2TIMManager
            .getMessageManager()
            .getMessageOnlineUrl(message: rawMessage, msgID: msg.msgID)
            .timeout(_imageRequestTimeout);
        if (result.code == 0) {
          for (final image in result.data?.imageElem?.imageList ?? const []) {
            addRemote(image?.url);
          }
        }
      } on Object {
        // 无在线地址时仍尝试本机缩略图，打开失败保留原会话可再次点开。
      }
    }
    await addLocal(imagePayload?.thumbImagePath);
    addRemote(imagePayload?.thumbImageURL);
    // 没有可读文件或地址时才下载，单个规格失败不影响剩余候选。
    if (resolveFromSdk && paths.isEmpty && rawMessage != null) {
      for (final quality in [
        MediaQuality.standard,
        MediaQuality.original,
        MediaQuality.thumbnail,
      ]) {
        try {
          final result = await MessageActionStore.create(msg)
              .downloadMedia(quality: quality)
              .timeout(_imageRequestTimeout);
          if (!result.isSuccess) continue;
          final updated = msg.messagePayload as ImageMessagePayload?;
          await addLocal(switch (quality) {
            MediaQuality.standard => updated?.largeImagePath,
            MediaQuality.original => updated?.originalImagePath,
            MediaQuality.thumbnail => updated?.thumbImagePath,
          });
          if (paths.isNotEmpty) break;
        } on Object {
          // 全部规格无法读取时保留错误占位，用户仍可关闭预览。
        }
      }
    }

    return ImageElement(
      type: 0,
      imagePath: paths.firstOrNull ?? '',
      mediaId: msg.msgID.isNotEmpty ? msg.msgID : null,
      fallbackImagePaths: paths.skip(1).toList(growable: false),
    );
  }

  /// 预览本地或远端视频封面，保留原消息与本地视频路径供播放器按需下载。
  Future<ImageElement> _processVideoMessagePayload(MessageInfo msg) async {
    final videoPayload2 = msg.messagePayload as VideoMessagePayload?;
    String imagePath = '';

    if (videoPayload2?.videoSnapshotPath != null &&
        videoPayload2!.videoSnapshotPath!.isNotEmpty) {
      final file = File(videoPayload2.videoSnapshotPath!);
      if (await file.exists()) {
        imagePath = videoPayload2.videoSnapshotPath!;
      }
    }

    // 无原生对象时直接展示封面地址，原生视频继续使用既有SDK下载和播放流程。
    if (imagePath.isEmpty && msg.rawMessage == null) {
      imagePath = _remotePreviewUrl([videoPayload2?.videoSnapshotURL]);
    }
    if (imagePath.isEmpty && msg.rawMessage != null) {
      await MessageActionStore.create(msg)
          .downloadMedia(quality: MediaQuality.thumbnail);

      final updatedMessage =
          messageListStore.state.messageList.value.firstWhere(
        (message) => message.msgID == msg.msgID,
        orElse: () => msg,
      );

      imagePath = (updatedMessage.messagePayload as VideoMessagePayload?)
              ?.videoSnapshotPath ??
          (updatedMessage.messagePayload as ImageMessagePayload?)
              ?.thumbImagePath ??
          '';
    }

    return ImageElement(
      type: 1,
      imagePath: imagePath,
      videoPath: videoPayload2?.videoPath,
      mediaId: msg.msgID.isEmpty ? null : msg.msgID,
    );
  }

  /// 远端展示地址仅接受带Host的HTTP(S)，不把其他协议作为本地文件传入查看器。
  String _remotePreviewUrl(Iterable<String?> urls) {
    for (final value in urls) {
      if (value == null || value.isEmpty) continue;
      final uri = Uri.tryParse(value);
      if (uri != null &&
          uri.host.isNotEmpty &&
          uri.userInfo.isEmpty &&
          (uri.scheme == 'http' || uri.scheme == 'https')) {
        return value;
      }
    }
    return '';
  }

  void dispose() {
    _disposed = true;
  }
}
