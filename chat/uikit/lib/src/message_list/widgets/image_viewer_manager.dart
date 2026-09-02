import 'package:atomic_x_core/api/message/message_action_store.dart';
import 'dart:io';

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/image_viewer/image_element.dart';

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

    final result = await dataManager.loadInitialData();
    _initialImageElements = result.mediaElements;
    _initialImageIndex = result.currentIndex;
    _isLoadingImageData = false;
    _isShowingImageViewer = true;
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

    final mediaElements =
        await _loadMediaMessages(option: option, isInitialLoad: true);
    final currentIndex = _findCurrentMessageIndex();
    return (mediaElements: mediaElements, currentIndex: currentIndex);
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

      final allElements =
          await _loadMediaMessages(option: option, isInitialLoad: false);
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
        return originalImagePath == byImagePath ||
            largeImagePath == byImagePath;
      } else if (message.messageType == MessageType.video) {
        final payload = message.messagePayload as VideoMessagePayload?;
        final videoSnapshotPath = payload?.videoSnapshotPath;
        return videoSnapshotPath == byImagePath;
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
    required bool isInitialLoad,
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

  Future<ImageElement> _processImageMessagePayload(MessageInfo msg) async {
    final imagePayload = msg.messagePayload as ImageMessagePayload?;
    String imagePath = '';

    if (imagePayload?.largeImagePath != null &&
        imagePayload!.largeImagePath!.isNotEmpty) {
      final file = File(imagePayload.largeImagePath!);
      if (await file.exists()) {
        imagePath = imagePayload.largeImagePath!;
      }
    }

    if (imagePath.isEmpty &&
        imagePayload?.originalImagePath != null &&
        imagePayload!.originalImagePath!.isNotEmpty) {
      final file = File(imagePayload.originalImagePath!);
      if (await file.exists()) {
        imagePath = imagePayload.originalImagePath!;
      }
    }

    if (imagePath.isEmpty) {
      await MessageActionStore.create(msg)
          .downloadMedia(quality: MediaQuality.standard);

      final updatedMessage =
          messageListStore.state.messageList.value.firstWhere(
        (message) => message.msgID == msg.msgID,
        orElse: () => msg,
      );

      imagePath = (updatedMessage.messagePayload as ImageMessagePayload?)
              ?.largeImagePath ??
          (updatedMessage.messagePayload as ImageMessagePayload?)
              ?.originalImagePath ??
          '';
    }

    return ImageElement(
      type: 0,
      imagePath: imagePath,
    );
  }

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

    if (imagePath.isEmpty) {
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

  void dispose() {}
}
