import 'dart:io';

import 'package:atomic_x_core/api/message/message_action_store.dart';
import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/image_viewer/image_element.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

/// 将消息媒体转换为预览数据，静态转发集合不拉取原会话历史。
class ImageViewerManager {
  bool _isShowingImageViewer = false;
  List<ImageElement> _initialImageElements = [];
  int _initialImageIndex = 0;
  bool _isLoadingImageData = false;
  String _conversationID = '';

  ImageViewerDataManager? _imageViewerDataManager;
  final MessageListStore _messageListStore;
  final MessageInfo _currentMessage;

  /// Optional pre-populated media list. When supplied (e.g. by the
  /// merged-message detail page, where there is no live MessageListStore
  /// to back-fill from), the viewer skips `loadMessages` entirely and
  /// renders this exact list. `loadMore` becomes a no-op in that mode
  /// because merged forwards are immutable bundles — there is nothing
  /// older or newer to fetch.
  ///
  /// 可选的预填充媒体列表。当提供时（例如通过合并消息详情页，这里没有 live MessageListStore 来补充数据），查看器会完全跳过 `loadMessages`
  /// 并渲染这个精确列表。`loadMore` 在这种模式下无效，因为合并转发是不可变的包——没有更多旧的或新的内容可以获取。
  final List<MessageInfo>? _presetMediaMessages;

  ImageViewerManager({
    required String conversationID,
    required MessageInfo currentMessage,
    required BuildContext context,
    List<MessageInfo>? presetMediaMessages,
  })  : _messageListStore =
            MessageListStore.create(conversationID: conversationID),
        _conversationID = conversationID,
        _currentMessage = currentMessage,
        _presetMediaMessages = presetMediaMessages;

  // Getters
  bool get isShowingImageViewer => _isShowingImageViewer;

  List<ImageElement> get initialImageElements => _initialImageElements;

  int get initialImageIndex => _initialImageIndex;

  bool get isLoadingImageData => _isLoadingImageData;

  Future<void> showImageViewerIfAvailable() async {
    if (_isLoadingImageData) return;

    _isLoadingImageData = true;
    _initialImageElements = [];
    _initialImageIndex = 0;

    final dataManager = ImageViewerDataManager(
      conversationID: _conversationID,
      currentMessage: _currentMessage,
      messageListStore: _messageListStore,
      presetMediaMessages: _presetMediaMessages,
    );
    _imageViewerDataManager = dataManager;

    try {
      final result = await dataManager.loadInitialData();
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
        final imagePath = param['path'] as String;
        _handleDownloadVideo(imagePath, callback);
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

  Future<void> _handleDownloadVideo(
      String imagePath, Function(dynamic) callback) async {
    final targetMessage =
        _imageViewerDataManager?.findMessage(byImagePath: imagePath);
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

    final updatedMessage = _messageListStore.state.messageList.value.firstWhere(
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
  final String conversationID;
  final MessageInfo currentMessage;
  final MessageListStore messageListStore;

  /// Static media list provided by the caller. When non-null, this manager
  /// operates in "preset" mode: it does not call `messageListStore.
  /// loadMessages` and `loadMoreData` returns empty. Used by the merged
  /// message detail page where the bundle is immutable and the underlying
  /// store is empty (there is no real conversation to page against).
  ///
  /// 由调用方提供的静态媒体列表。当非空时，该管理器运行在“预设”模式：不会调用 `messageListStore.loadMessages`，`loadMoreData`
  /// 会返回空。用于合并消息详情页，其中包是不可变的，底层存储为空（没有真正的会话可以分页）。
  final List<MessageInfo>? presetMediaMessages;

  bool _isLoadingOlder = false;
  bool _isLoadingNewer = false;

  ImageViewerDataManager({
    required this.conversationID,
    required this.currentMessage,
    required this.messageListStore,
    this.presetMediaMessages,
  });

  bool get _isPresetMode => presetMediaMessages != null;

  List<MessageInfo> get _mediaMessages {
    if (_isPresetMode) {
      return presetMediaMessages!
          .where((msg) =>
              msg.messageType == MessageType.image ||
              msg.messageType == MessageType.video)
          .toList();
    }
    return messageListStore.state.messageList.value
        .where((msg) =>
            msg.messageType == MessageType.image ||
            msg.messageType == MessageType.video)
        .toList();
  }

  Future<({List<ImageElement> mediaElements, int currentIndex})>
      loadInitialData() async {
    if (_isPresetMode) {
      // Skip the live store fetch — the merged bundle is the entire
      // dataset. Build elements directly from the preset list.
      //
      // 跳过实时商店获取——合并后的包就是完整数据集。直接从预设列表构建元素。
      final mediaElements = await _buildElementsFromPreset();
      final currentIndex = _findCurrentMessageIndex();
      return (mediaElements: mediaElements, currentIndex: currentIndex);
    }

    var option = MessageLoadOption();
    option.direction = MessageLoadDirection.both;
    option.pageCount = 5;
    option.cursor = currentMessage;
    option.messageTypeList = [MessageType.image, MessageType.video];

    try {
      final mediaElements = await _loadMediaMessages(option: option);
      final currentIndex = _mediaMessages
          .indexWhere((message) => message.msgID == currentMessage.msgID);
      if (currentIndex >= 0) {
        return (mediaElements: mediaElements, currentIndex: currentIndex);
      }
    } on Object {
      // 历史窗口查询失败时仍保留用户点开的资源，便于弱网和归档场景重试。
    }
    return (
      mediaElements: [await _processMediaMessage(currentMessage)],
      currentIndex: 0
    );
  }

  Future<({List<ImageElement> elements, bool hasMoreData})> loadMoreData(
      {required bool isOlder}) async {
    // Merged bundles are bounded in-memory lists; nothing to page.
    //
    // 合并的包是有界的内存列表；没有需要分页的内容。
    if (_isPresetMode) {
      return (elements: <ImageElement>[], hasMoreData: false);
    }

    bool hasMoreData = isOlder
        ? messageListStore.state.hasOlderMessages.value
        : messageListStore.state.hasNewerMessages.value;
    if (!hasMoreData) {
      return (elements: <ImageElement>[], hasMoreData: false);
    }

    final isCurrentlyLoading = isOlder ? _isLoadingOlder : _isLoadingNewer;
    if (isCurrentlyLoading) {
      return (elements: <ImageElement>[], hasMoreData: hasMoreData);
    }

    if (_mediaMessages.isEmpty) {
      return (elements: <ImageElement>[], hasMoreData: hasMoreData);
    }

    if (isOlder) {
      _isLoadingOlder = true;
    } else {
      _isLoadingNewer = true;
    }

    try {
      final anchorMessage =
          isOlder ? _mediaMessages.first : _mediaMessages.last;

      var option = MessageLoadOption();
      option.direction =
          isOlder ? MessageLoadDirection.older : MessageLoadDirection.newer;
      option.pageCount = 5;
      option.cursor = anchorMessage;
      option.messageTypeList = [MessageType.image, MessageType.video];

      final allElements = await _loadMediaMessages(option: option);
      hasMoreData = isOlder
          ? messageListStore.state.hasOlderMessages.value
          : messageListStore.state.hasNewerMessages.value;

      return (elements: allElements, hasMoreData: hasMoreData);
    } catch (e) {
      return (elements: <ImageElement>[], hasMoreData: hasMoreData);
    } finally {
      if (isOlder) {
        _isLoadingOlder = false;
      } else {
        _isLoadingNewer = false;
      }
    }
  }

  int _findCurrentMessageIndex() {
    int index =
        _mediaMessages.indexWhere((msg) => msg.msgID == currentMessage.msgID);
    if (index >= 0) {
      return index;
    }

    if (currentMessage.msgID.isNotEmpty) {
      index =
          _mediaMessages.indexWhere((msg) => msg.msgID == currentMessage.msgID);
      if (index >= 0) {
        return index;
      }
    }

    return 0;
  }

  MessageInfo? findMessage({required String byImagePath}) {
    return _mediaMessages.firstWhere((message) {
      if (message.messageType == MessageType.image) {
        final originalImagePath =
            (message.messagePayload as ImageMessagePayload?)?.originalImagePath;
        final largeImagePath =
            (message.messagePayload as ImageMessagePayload?)?.largeImagePath;
        final payload = message.messagePayload as ImageMessagePayload?;
        return originalImagePath == byImagePath ||
            largeImagePath == byImagePath ||
            payload?.originalImageURL == byImagePath ||
            payload?.largeImageURL == byImagePath ||
            payload?.thumbImageURL == byImagePath;
      } else if (message.messageType == MessageType.video) {
        final payload = message.messagePayload as VideoMessagePayload?;
        final videoSnapshotPath = payload?.videoSnapshotPath;
        return videoSnapshotPath == byImagePath ||
            (message.messagePayload as VideoMessagePayload?)
                    ?.videoSnapshotURL ==
                byImagePath;
      }
      return false;
    });
  }

  Future<List<ImageElement>> _buildElementsFromPreset() async {
    final messages = _mediaMessages;
    final List<ImageElement> resultElements = [];
    for (int i = 0; i < messages.length; i++) {
      final msg = messages[i];
      try {
        final element = await _processMediaMessage(msg);
        resultElements.add(element);
      } catch (e) {
        final isVideo = msg.messageType == MessageType.video;
        resultElements.add(ImageElement(
          type: isVideo ? 1 : 0,
          imagePath: '',
          videoPath: '',
        ));
      }
    }
    return resultElements;
  }

  Future<List<ImageElement>> _loadMediaMessages({
    required MessageLoadOption option,
  }) async {
    final result = await messageListStore.loadMessages(option: option);
    if (!result.isSuccess) {
      throw Exception('fetchMessages failed');
    }

    final fetchedMediaMessages = _mediaMessages;

    final List<ImageElement> resultElements = [];

    for (int i = 0; i < fetchedMediaMessages.length; i++) {
      final msg = fetchedMediaMessages[i];

      try {
        final element = await _processMediaMessage(msg);
        resultElements.add(element);
      } catch (e) {
        final isVideo = msg.messageType == MessageType.video;
        resultElements.add(ImageElement(
          type: isVideo ? 1 : 0,
          imagePath: '',
          videoPath: '',
        ));
      }
    }

    return resultElements;
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

  /// 依次收集本机大图、SDK下载和预览降级资源，解码时由查看器按顺序尝试。
  Future<ImageElement> _processImageMessagePayload(MessageInfo msg) async {
    final imagePayload = msg.messagePayload as ImageMessagePayload?;
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

    await addLocal(imagePayload?.largeImagePath);
    await addLocal(imagePayload?.originalImagePath);
    // 收到的消息可能只有部分规格，SDK失败后继续尝试其他尺寸和在线地址。
    if (paths.isEmpty && msg.rawMessage != null && imagePayload != null) {
      final action = MessageActionStore.create(msg);
      for (final quality in [MediaQuality.standard, MediaQuality.original]) {
        try {
          final result = await action.downloadMedia(quality: quality);
          if (result.isSuccess) {
            await addLocal(quality == MediaQuality.standard
                ? imagePayload.largeImagePath
                : imagePayload.originalImagePath);
          }
          if (paths.isNotEmpty) break;
        } on Object {
          // 单个规格下载异常不能阻止打开其他可用图片。
        }
      }
    }

    final remote = [
      imagePayload?.largeImageURL,
      imagePayload?.originalImageURL
    ];
    if (paths.isEmpty &&
        _remotePreviewUrl(remote).isEmpty &&
        msg.rawMessage != null) {
      try {
        final result = await TencentImSDKPlugin.v2TIMManager
            .getMessageManager()
            .getMessageOnlineUrl(message: msg.rawMessage, msgID: msg.msgID);
        if (result.code == 0) {
          remote.addAll(
              result.data?.imageElem?.imageList?.map((image) => image?.url) ??
                  const []);
        }
      } on Object {
        // 无在线地址时仍尝试本机缩略图，打开失败保留原会话可再次点开。
      }
    }
    for (final url in remote) {
      final path = _remotePreviewUrl([url]);
      if (path.isNotEmpty) paths.add(path);
    }
    await addLocal(imagePayload?.thumbImagePath);
    final thumbnail = _remotePreviewUrl([imagePayload?.thumbImageURL]);
    if (thumbnail.isNotEmpty) paths.add(thumbnail);
    if (paths.isEmpty && msg.rawMessage != null && imagePayload != null) {
      try {
        final result = await MessageActionStore.create(msg)
            .downloadMedia(quality: MediaQuality.thumbnail);
        if (result.isSuccess) await addLocal(imagePayload.thumbImagePath);
      } on Object {
        // 全部规格暂不可用时保留占位，用户可关闭后再次尝试。
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

  void dispose() {}
}
