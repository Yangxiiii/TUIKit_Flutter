// AiMediaProcessManager — chat-side facade over the AI media experimental APIs.
//
// Architecture note (technical debt): this file depends directly on
// `tencent_cloud_chat_sdk` because AtomicXCore does not yet expose these AI
// capabilities. It deliberately does NOT use the message-bound
// `MessageActionStore` — record-overlay translation happens before any message
// exists.
//
// AiMediaProcessManager — 基于 AI 媒体实验 API 的聊天端外观。
//
// 架构说明（技术债务）：这个文件直接依赖 `tencent_cloud_chat_sdk`，因为 AtomicXCore 还没有暴露这些 AI 功能。它故意不使用绑定消息的
// `MessageActionStore` — 记录覆盖翻译在任何消息之前进行。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_value_callback.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

import 'tts/voice_item.dart';

// MARK: - ASR (Automatic Speech Recognition) result types
//
// MARK: - ASR（自动语音识别）结果类型

/// Result of an ASR (Automatic Speech Recognition) conversion.
///
/// ASR（自动语音识别）转换的结果。
abstract class AiAsrResult {
  const AiAsrResult();
}

/// ASR succeeded with non-empty text.
///
/// ASR 成功，文本非空。
class AiAsrSuccess extends AiAsrResult {
  const AiAsrSuccess(this.text);
  final String text;
}

/// ASR failed (upload error, recognize error, empty result, or timeout).
///
/// ASR 失败（上传错误、识别错误、结果为空或超时）。
class AiAsrFailure extends AiAsrResult {
  const AiAsrFailure({
    required this.code,
    this.message,
    this.isTimeout = false,
  });

  final int code;
  final String? message;
  final bool isTimeout;
}

// MARK: - AI result types
//
// MARK: - AI 结果类型

class AiTtsResult {
  final bool success;
  final String? audioUrl;
  final int code;
  final String? message;
  const AiTtsResult(
      {required this.success, this.audioUrl, this.code = 0, this.message});
}

class AiVoiceCloneResult {
  final bool success;
  final String? voiceId;
  final int code;
  final String? message;
  const AiVoiceCloneResult(
      {required this.success, this.voiceId, this.code = 0, this.message});
}

class AiTranslateResult {
  final bool success;
  final String? text;
  final int code;
  final String? message;
  const AiTranslateResult(
      {required this.success, this.text, this.code = 0, this.message});
}

class AiVoiceListResult {
  final bool success;
  final List<CustomVoiceItem> voices;
  final int code;
  final String? message;
  const AiVoiceListResult(
      {required this.success,
      this.voices = const [],
      this.code = 0,
      this.message});
}

// MARK: - Injectable signatures
//
// MARK: - 可注入的签名

/// Injectable signature for `callExperimentalAPI` (matches the SDK method).
///
/// `callExperimentalAPI` 的可注入签名（与 SDK 方法匹配）。
typedef CallExperimentalApi = Future<V2TimValueCallback<dynamic>> Function({
  required String api,
  required Map<String, dynamic> param,
});

/// Injectable signature for the SDK message-manager `translateText`.
///
/// SDK 消息管理器 `translateText` 的可注入签名。
typedef TranslateApi = Future<V2TimValueCallback<Map<String, String>>>
    Function({
  required List<String> texts,
  required String targetLanguage,
  String? sourceLanguage,
});

// MARK: - API / param / response keys
//
// MARK: - API / 参数 / 响应键

const String _apiUploadFile = 'internal_operation_upload_file';
const String _apiConvertVoiceToText =
    'internal_operation_convert_voice_to_text';
const String _apiConvertTextToVoice =
    'internal_operation_convert_text_to_voice';
const String _apiVoiceClone = 'internal_operation_voice_clone';
const String _apiGetCustomVoiceList =
    'internal_operation_get_custom_voice_list';
const String _apiDeleteCustomVoice = 'internal_operation_delete_custom_voice';

const String _paramUploadFilePath = 'request_upload_file_file_path';
const String _paramUploadFileType = 'request_upload_file_file_type';
const String _respUploadUrl = 'response_upload_file_url';

const String _paramConvertUrl = 'request_convert_voice_to_text_url';
const String _paramConvertLanguage = 'request_convert_voice_to_text_language';
const String _respConvertText = 'response_convert_voice_to_text_result';

/// File type 3 = audio (matches SDK enum index used across the AI managers).
const int _fileTypeAudio = 3;

const Duration _defaultTimeout = Duration(seconds: 30);

class AiMediaProcessManager {
  AiMediaProcessManager({
    CallExperimentalApi? callExperimentalApi,
    TranslateApi? translateApi,
    Duration timeout = _defaultTimeout,
  })  : _call = callExperimentalApi ?? _defaultCall,
        _translate = translateApi ?? _defaultTranslate,
        _timeout = timeout;

  static final AiMediaProcessManager shared = AiMediaProcessManager();

  final CallExperimentalApi _call;
  final TranslateApi _translate;
  final Duration _timeout;

  // MARK: ASR — speech to text (upload + recognize, with overall timeout)
  //
  // MARK: ASR — 语音转文字（上传 + 识别，带整体超时）

  /// Upload [filePath] then recognize the uploaded URL into text (ASR).
  ///
  /// 上传 [filePath] 然后将上传的 URL 识别为文本（ASR）。
  Future<AiAsrResult> convert(String filePath) async {
    try {
      return await _runAsrPipeline(filePath).timeout(
        _timeout,
        onTimeout: () => const AiAsrFailure(
          code: -1,
          message: 'asr timeout',
          isTimeout: true,
        ),
      );
    } catch (e) {
      return AiAsrFailure(code: -1, message: e.toString());
    }
  }

  Future<AiAsrResult> _runAsrPipeline(String filePath) async {
    final url = await uploadFile(filePath: filePath);
    if (url == null || url.isEmpty) {
      return const AiAsrFailure(code: -1, message: 'upload failed');
    }
    final asrResult = await _call(
      api: _apiConvertVoiceToText,
      param: <String, dynamic>{
        _paramConvertUrl: url,
        _paramConvertLanguage: '',
      },
    );
    final text = _readString(asrResult, _respConvertText);
    if (text == null || text.isEmpty) {
      return AiAsrFailure(
        code: asrResult.code,
        message:
            asrResult.desc.isNotEmpty ? asrResult.desc : 'asr empty or failed',
      );
    }
    return AiAsrSuccess(text);
  }

  // MARK: Translation

  Future<AiTranslateResult> translateSingleText({
    required String text,
    required String targetLanguage,
    String sourceLanguage = '',
  }) async {
    try {
      final result = await _translate(
        texts: [text],
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
      );
      if (result.code == 0 && result.data != null) {
        String? translated = result.data![text];
        // Fallback: if exact-key lookup misses but there is exactly one entry,
        // use it — the single input can only map to that single output.
        //
        // 回退：如果精确键查找失败但恰好有一个条目，则使用它 — 单个输入只能映射到那个单一输出。
        if ((translated == null || translated.isEmpty) &&
            result.data!.length == 1) {
          translated = result.data!.values.first;
        }
        if (translated != null && translated.isNotEmpty) {
          return AiTranslateResult(success: true, text: translated);
        }
      }
      return AiTranslateResult(
          success: false, code: result.code, message: result.desc);
    } catch (e) {
      return AiTranslateResult(success: false, code: -1, message: e.toString());
    }
  }

  // MARK: Text to voice
  //
  // MARK: 文字转语音

  Future<AiTtsResult> convertTextToVoice({
    required String text,
    String voiceId = '',
    String audioFormat = 'wav',
    String language = '',
  }) async {
    final param = <String, dynamic>{
      'request_convert_text_to_voice_text': text,
      'request_convert_text_to_voice_audio_format': audioFormat,
      'request_convert_text_to_voice_language': language,
    };
    if (voiceId.isNotEmpty) {
      param['request_convert_text_to_voice_voice_id'] = voiceId;
    }
    try {
      final result = await _call(api: _apiConvertTextToVoice, param: param);
      final url =
          _readString(result, 'response_convert_text_to_voice_audio_url');
      if (result.code == 0 && url != null && url.isNotEmpty) {
        return AiTtsResult(success: true, audioUrl: url);
      }
      return AiTtsResult(
          success: false, code: result.code, message: result.desc);
    } catch (e) {
      return AiTtsResult(success: false, code: -1, message: e.toString());
    }
  }

  // MARK: Upload

  Future<String?> uploadFile({
    required String filePath,
    int fileType = _fileTypeAudio,
  }) async {
    final result = await _call(api: _apiUploadFile, param: <String, dynamic>{
      _paramUploadFilePath: filePath,
      _paramUploadFileType: fileType,
    });
    if (result.code == 0) {
      return _readString(result, _respUploadUrl);
    }
    return null;
  }

  // MARK: Voice clone
  //
  // MARK: 语音克隆

  Future<AiVoiceCloneResult> voiceCloneFromFile({
    required String filePath,
    required String voiceName,
    String promptText = '',
    String language = '',
  }) async {
    try {
      final audioUrl = await uploadFile(filePath: filePath);
      if (audioUrl == null || audioUrl.isEmpty) {
        return const AiVoiceCloneResult(
            success: false, code: -1, message: 'upload failed');
      }
      final result = await _call(api: _apiVoiceClone, param: <String, dynamic>{
        'request_voice_clone_audio_url': audioUrl,
        'request_voice_clone_voice_name': voiceName,
        'request_voice_clone_prompt_text': promptText,
        'request_voice_clone_language': language,
      });
      final voiceId = _readString(result, 'response_voice_clone_voice_id');
      if (result.code == 0 && voiceId != null && voiceId.isNotEmpty) {
        return AiVoiceCloneResult(success: true, voiceId: voiceId);
      }
      return AiVoiceCloneResult(
          success: false, code: result.code, message: result.desc);
    } catch (e) {
      return AiVoiceCloneResult(
          success: false, code: -1, message: e.toString());
    }
  }

  // MARK: Custom voice list
  //
  // MARK: 自定义语音列表

  Future<AiVoiceListResult> getCustomVoiceList() async {
    try {
      final result = await _call(api: _apiGetCustomVoiceList, param: {});
      if (result.code == 0 && result.data is Map) {
        final list =
            (result.data as Map)['response_get_custom_voice_list_voice_list'];
        if (list is List) {
          final voices = <CustomVoiceItem>[];
          for (final item in list) {
            if (item is Map) {
              final id = item['custom_voice_item_voice_id'];
              final name = item['custom_voice_item_name'];
              if (id is String && id.isNotEmpty) {
                voices.add(CustomVoiceItem(
                  voiceId: id,
                  name: name is String ? name : '',
                  isDefault: false,
                ));
              }
            }
          }
          return AiVoiceListResult(success: true, voices: voices);
        }
      }
      return AiVoiceListResult(
          success: false, code: result.code, message: result.desc);
    } catch (e) {
      return AiVoiceListResult(success: false, code: -1, message: e.toString());
    }
  }

  Future<bool> deleteCustomVoice({required String voiceId}) async {
    try {
      final result = await _call(api: _apiDeleteCustomVoice, param: {
        'request_delete_custom_voice_voice_id': voiceId,
      });
      return result.code == 0;
    } catch (_) {
      return false;
    }
  }

  // MARK: Helpers

  String? _readString(V2TimValueCallback<dynamic> result, String key) {
    final data = result.data;
    if (data is Map) {
      final value = data[key];
      return value is String ? value : null;
    }
    return null;
  }
}

Future<V2TimValueCallback<dynamic>> _defaultCall({
  required String api,
  required Map<String, dynamic> param,
}) {
  return TencentImSDKPlugin.v2TIMManager.callExperimentalAPI(
    api: api,
    param: param,
  );
}

Future<V2TimValueCallback<Map<String, String>>> _defaultTranslate({
  required List<String> texts,
  required String targetLanguage,
  String? sourceLanguage,
}) {
  return TencentImSDKPlugin.v2TIMManager.getMessageManager().translateText(
        texts: texts,
        targetLanguage: targetLanguage,
        sourceLanguage: sourceLanguage,
      );
}
