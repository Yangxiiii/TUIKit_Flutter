import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:atomic_x_core/atomicxcore.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/message_input/utils/image_size_reader.dart';
import 'package:tuikit_atomic_x/album_picker/album_picker.dart';
import 'chat_media_sender.dart';

/// 将相册预览占位、导出失败和可发送文件交给当前会话。
abstract class AlbumPickerMediaSendListener {
  void onSendMessage(MessageInfo messageInfo,
      {MessageInfo? albumUploadPlaceholder});

  void onSendPlaceholderMessage(MessageInfo placeholder);

  void onRemovePlaceholderMessage(MessageInfo placeholder);

  /// 原件读取失败时由当前聊天页提示，其他选中文件继续发送。
  void onMediaPreparationFailed();
}

/// 协调每次相册选择的回调与本地占位，实际上传交给聊天发送入口。
class AlbumPickerMediaSendManager {
  static final AlbumPickerMediaSendManager shared =
      AlbumPickerMediaSendManager._();

  AlbumPickerMediaSendManager._();

  final Map<String, _PickerSession> _pickerSessions = {};

  Future<void> pickAlbumMedia({
    required String conversationID,
    required AlbumPickerMediaSendListener listener,
    AlbumPickerConfig? config,
    AlbumPickerTheme? theme,
  }) async {
    final sessionKey =
        '${DateTime.now().millisecondsSinceEpoch}_${conversationID.hashCode}';
    final session = _PickerSession(
      sessionKey: sessionKey,
      conversationID: conversationID,
      listener: listener,
      routeLargeFiles: config?.includeSourceMetadata ?? false,
    );
    _pickerSessions[sessionKey] = session;

    debugPrint(
        "[MediaSendManager] pickAlbumMedia: session=$sessionKey, conversationID=$conversationID");

    await AlbumPicker.pickMedia(
      config: config,
      theme: theme,
      onPickConfirm: (pickedAlbumMedias, textMessage) {
        debugPrint(
            "[MediaSendManager] onPickConfirm: ${pickedAlbumMedias.length} items, session=$sessionKey");
        _handlePickConfirm(
            pickedAlbumMedias: pickedAlbumMedias, session: session);
      },
      onMediaProcessing: (albumMedia, progress, error) {
        _handleMediaProcessing(
            media: albumMedia,
            progress: progress,
            error: error,
            session: session);
      },
      onMediaProcessed: () {
        debugPrint("[MediaSendManager] onMediaProcessed: session=$sessionKey");
        _finishSession(session);
      },
      onCancel: () {
        debugPrint("[MediaSendManager] onCancel: session=$sessionKey");
        _finishSession(session);
      },
    ).catchError((Object error, StackTrace stackTrace) {
      // 原生选择启动失败也应释放会话，避免恢复页面时继续挂载旧占位。
      _finishSession(session);
      Error.throwWithStackTrace(error, stackTrace);
    });
    await session.readyToSend;
  }

  /// 先为每项记录分流，缩略图异步完成时不会改变其他媒体的判定。
  void _handlePickConfirm({
    required List<AlbumMedia> pickedAlbumMedias,
    required _PickerSession session,
  }) {
    for (final media in pickedAlbumMedias) {
      if (session.processedMediaIds.contains(media.id) ||
          session.mediaStates.containsKey(media.id)) {
        continue;
      }

      final kind = _mediaKind(media);
      // 压缩后的大小可能跨过原生阈值，只有明确发送原件才能提前分流。
      final sourceSize = media.isOriginal
          ? media.sourceFileSize ?? (media.fileSize > 0 ? media.fileSize : null)
          : null;
      final direct = session.routeLargeFiles &&
          sourceSize != null &&
          sourceSize > kind.nativeLimitBytes;
      final needsFilePlaceholder =
          session.routeLargeFiles && (direct || (sourceSize ?? 0) <= 0);
      final state = _MediaState(directUpload: direct);
      session.mediaStates[media.id] = state;

      final placeholder = _newPlaceholder(
        'album_${session.sessionKey}_${media.id}',
        needsFilePlaceholder ? MessageType.file : _messageType(media),
      );
      if (needsFilePlaceholder) {
        // 压缩期间也保留文件卡片，但只展示已经确定的大小。
        final name = media.sourceFileName ??
            (media.mediaPath.isEmpty
                ? null
                : File(media.mediaPath).uri.pathSegments.last);
        placeholder.messagePayload = FileMessagePayload(
          fileName: name != null && name.isNotEmpty
              ? name
              : kind == ChatMediaKind.video
                  ? '视频.mp4'
                  : '图片.jpg',
          fileSize: sourceSize ?? 0,
        );
        state.placeholder = placeholder;
        session.listener.onSendPlaceholderMessage(placeholder);
      } else {
        unawaited(_preparePreview(media, session, state, placeholder));
      }
    }
  }

  /// 保留原有普通媒体封面，终态先到时不再发布过期占位。
  Future<void> _preparePreview(AlbumMedia media, _PickerSession session,
      _MediaState state, MessageInfo placeholder) async {
    final supplied = media.videoThumbnailPath;
    final thumbnail = supplied != null && supplied.isNotEmpty
        ? supplied
        : await _generateBlackSnapshot();
    if (thumbnail.isEmpty) return;
    if (media.mediaType == AlbumMediaType.video) {
      placeholder.messagePayload =
          VideoMessagePayload(videoSnapshotPath: thumbnail);
    } else {
      final size = await ImageSizeReader.read(thumbnail);
      placeholder.messagePayload = ImageMessagePayload(
        originalImagePath: thumbnail,
        originalImageWidth: size?.width ?? 0,
        originalImageHeight: size?.height ?? 0,
      );
    }
    if (!identical(session.mediaStates[media.id], state)) return;
    placeholder.uploadMediaProgress = (state.progress * 100).toInt();
    state.placeholder = placeholder;
    session.listener.onSendPlaceholderMessage(placeholder);
  }

  /// 回到聊天时继续显示同一批导出占位，上传接管后由宿主恢复进度。
  void restorePlaceholders({
    required String conversationID,
    required AlbumPickerMediaSendListener listener,
  }) {
    for (final session in _pickerSessions.values) {
      if (session.conversationID != conversationID) continue;
      session.listener = listener;
      for (final state in session.mediaStates.values) {
        final placeholder = state.placeholder;
        if (placeholder != null) listener.onSendPlaceholderMessage(placeholder);
      }
    }
  }

  /// 回收没有收到单项终态的占位，避免失败文件永久停留在导出中。
  void _finishSession(_PickerSession session) {
    _pickerSessions.remove(session.sessionKey);
    for (final state in session.mediaStates.values) {
      final placeholder = state.placeholder;
      if (placeholder != null) {
        session.listener.onRemovePlaceholderMessage(placeholder);
      }
    }
    session.mediaStates.clear();
  }

  /// 每项只发送一次，导出完成后用实际大小为待定文件分流。
  void _handleMediaProcessing({
    required AlbumMedia media,
    required double progress,
    required bool error,
    required _PickerSession session,
  }) {
    final state = session.mediaStates[media.id];
    if (!error && progress < 1) {
      if (state != null) {
        state.progress = progress;
        state.placeholder?.uploadMediaProgress = (progress * 100).toInt();
      }
      return;
    }

    // 先关闭单项导出状态，异步封面和重复终态都不能再发布旧气泡。
    if (!session.processedMediaIds.add(media.id)) return;
    session.mediaStates.remove(media.id);
    final placeholder = state?.placeholder;
    if (error || media.mediaPath.isEmpty) {
      if (placeholder != null) {
        session.listener.onRemovePlaceholderMessage(placeholder);
      }
      session.listener.onMediaPreparationFailed();
      return;
    }
    final direct = state?.directUpload == true ||
        (session.routeLargeFiles &&
            media.fileSize > _mediaKind(media).nativeLimitBytes);
    // 读取封面尺寸需要异步 IO，顺序准备发送以免后选的大文件越过前一条普通视频。
    session.readyToSend = session.readyToSend.then((_) async {
      try {
        await _sendExportedMedia(media, session, direct, placeholder);
      } on Object {
        if (placeholder != null) {
          session.listener.onRemovePlaceholderMessage(placeholder);
        }
        session.listener.onMediaPreparationFailed();
      }
    });
  }

  /// 普通媒体保留原生消息所需元数据，直传只消费已导出的本地文件。
  Future<void> _sendExportedMedia(AlbumMedia media, _PickerSession session,
      bool direct, MessageInfo? placeholder) async {
    final MessagePayload payload;
    if (media.mediaType == AlbumMediaType.image) {
      final size = direct ? null : await ImageSizeReader.read(media.mediaPath);
      payload = ImageMessagePayload(
        originalImagePath: media.mediaPath,
        originalImageWidth: size?.width ?? 0,
        originalImageHeight: size?.height ?? 0,
      );
    } else {
      var thumbnail = media.videoThumbnailPath ?? '';
      if (!direct && thumbnail.isEmpty) {
        thumbnail = await _generateBlackSnapshot();
      }
      // SDK 创建发送中的气泡前就带上封面尺寸，避免先按默认横屏宽度绘制。
      final size = direct ? null : await ImageSizeReader.read(thumbnail);
      final extension = File(media.mediaPath).uri.pathSegments.last.split('.');
      // 沙盒文件有时没有扩展名，原生视频消息用 mp4 作为兜底。
      final type = extension.length > 1 ? extension.last : '';
      payload = VideoMessagePayload(
        videoPath: media.mediaPath,
        videoSnapshotPath: thumbnail,
        videoSnapshotWidth: size?.width ?? 0,
        videoSnapshotHeight: size?.height ?? 0,
        videoDuration: (media.duration / 1000).round(),
        videoType: type.isEmpty || type.length > 5 ? 'mp4' : type,
      );
    }
    // 确认需要直传时才移交文件卡片，普通媒体准备好后再撤掉导出占位。
    final directPlaceholder =
        direct && placeholder?.messageType == MessageType.file
            ? placeholder
            : null;
    if (placeholder != null && directPlaceholder == null) {
      session.listener.onRemovePlaceholderMessage(placeholder);
    }
    session.listener.onSendMessage(
      MessageInfo(messageType: _messageType(media), messagePayload: payload),
      albumUploadPlaceholder: directPlaceholder,
    );
  }

  ChatMediaKind _mediaKind(AlbumMedia media) =>
      media.mediaType == AlbumMediaType.video
          ? ChatMediaKind.video
          : ChatMediaKind.image;

  MessageType _messageType(AlbumMedia media) =>
      media.mediaType == AlbumMediaType.video
          ? MessageType.video
          : MessageType.image;

  /// 用同一个本地标识贯穿导出和上传，保留当前发送者资料。
  MessageInfo _newPlaceholder(String id, MessageType type) {
    final user = LoginStore.shared.loginState.loginUserInfo;
    return MessageInfo(
      msgID: id,
      messageType: type,
      status: MessageStatus.sending,
      isSentBySelf: true,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      from: MessageSenderInfo(
        userID: user?.userID ?? '',
        avatarURL: user?.avatarURL,
        nickname: user?.nickname,
      ),
    );
  }

  String? _cachedBlackSnapshotPath;

  Future<String> _generateBlackSnapshot() async {
    if (_cachedBlackSnapshotPath != null &&
        File(_cachedBlackSnapshotPath!).existsSync()) {
      return _cachedBlackSnapshotPath!;
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 320, 240),
      Paint()..color = Colors.black,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(320, 240);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return '';
    final bytes = byteData.buffer.asUint8List();
    final dir = Directory.systemTemp;
    final file = File('${dir.path}/album_picker_black_snapshot.png');
    await file.writeAsBytes(bytes);
    _cachedBlackSnapshotPath = file.path;
    return file.path;
  }
}

/// 隔离每次相册选择的处理进度和占位，恢复页面时重绑同一会话。
class _PickerSession {
  final String sessionKey;
  final String conversationID;
  AlbumPickerMediaSendListener listener;

  /// 宿主提供大文件上传时，允许根据确认资料提前分流。
  final bool routeLargeFiles;
  final Map<int, _MediaState> mediaStates = {};
  final Set<int> processedMediaIds = {};

  /// 按原生导出完成顺序准备发送负载，无需等待上一条上传完成。
  Future<void> readyToSend = Future<void>.value();

  _PickerSession({
    required this.sessionKey,
    required this.conversationID,
    required this.listener,
    required this.routeLargeFiles,
  });
}

/// 单项导出中的通道、占位和进度，终态到达后由上传层或消息 SDK 接管。
class _MediaState {
  _MediaState({required this.directUpload});

  /// 确认时原件已超限，后续即使导出变小也继续直传。
  final bool directUpload;

  /// 初始占位等待封面时为空；大文件占位在确认后立即可用。
  MessageInfo? placeholder;

  /// 原生本地导出进度，范围为 0 到 1。
  double progress = 0;
}
