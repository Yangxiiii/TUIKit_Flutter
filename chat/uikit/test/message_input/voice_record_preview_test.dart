import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';
import 'package:tencent_chat_uikit/src/third_party/extended_text_field/extended_text_field.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../fixtures/emoji_fixture.dart';
import 'package:tencent_chat_uikit/src/ai/ai_media_process_manager.dart';
import 'package:tencent_chat_uikit/src/audio_recoder/audio_recorder.dart';
import 'package:tencent_chat_uikit/src/message_input/widget/voice_record_preview.dart';

/// 记录实际绘制的波形线段高度，验证声音大小而不是仅检查内部字段。
class _WaveCanvas extends Fake implements Canvas {
  final heights = <double>[];
  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      heights.add((p2.dy - p1.dy).abs());
}

/// 根工作区测试不打包feature资源，直接读取已存在的同源表情，其他资源仍由测试Bundle解析。
class _ProjectAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    const prefix = 'packages/feature_tim/';
    if (key.startsWith(prefix)) {
      return ByteData.sublistView(
          File('features/feature_tim/${key.substring(prefix.length)}')
              .readAsBytesSync());
    }
    return rootBundle.load(key);
  }
}

/// 测试采音只生成本地片段，真实手势和浮层生命周期仍走生产组件。
class _Recorder extends AudioRecorder {
  _Recorder(this.directory);
  final Directory directory;
  final paths = <String>[];
  final limits = <int?>[];
  final starts = <Completer<void>>[Completer<void>(), Completer<void>()];
  AudioRecordCompleteCallback? complete;
  bool active = false;
  RecordInfo? pending;
  @override
  Future<bool> startRecord(
      {required String filePath,
      required AudioRecordCompleteCallback onComplete,
      int? maxDurationMs}) async {
    complete = onComplete;
    limits.add(maxDurationMs);
    active = true;
    final index = paths.length;
    final file = File('${directory.path}/segment_$index.m4a')
      ..writeAsStringSync('$index');
    paths.add(file.path);
    starts[index].complete();
    return true;
  }

  @override
  void stopRecord() {
    if (!active) return;
    active = false;
    pending = RecordInfo(path: paths.last, duration: 1);
  }

  void deliver() {
    complete?.call(pending);
    pending = null;
  }

  @override
  Future<void> cancelRecord() async {
    active = false;
  }

  @override
  void dispose() {}
}

/// 识别结果由测试逐次交付，覆盖取消和续录期间的迟到结果。
class _Asr extends AiMediaProcessManager {
  final requests = <Completer<void>>[Completer<void>(), Completer<void>()];
  final results = <Completer<AiAsrResult>>[];
  @override
  Future<AiAsrResult> convert(String path) {
    final result = Completer<AiAsrResult>();
    results.add(result);
    requests[results.length - 1].complete();
    return result.future;
  }
}

void main() {
  late Directory directory;
  late _Recorder recorder;
  late _Asr asr;
  late GlobalKey<VoiceRecordPreviewState> key;
  var closed = 0;
  bool sendResult = true;
  Completer<bool>? pendingSend;
  final texts = <String>[];
  final audios = <RecordInfo>[];
  const channel = MethodChannel('tencent_chat_uikit/audio_recorder');

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('voice_preview_widget_');
    recorder = _Recorder(directory);
    asr = _Asr();
    key = GlobalKey<VoiceRecordPreviewState>();
    closed = 0;
    sendResult = true;
    pendingSend = null;
    SharedPreferences.setMockInitialValues({});
    configureEmojiFixture();
    texts.clear();
    audios.clear();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await directory.delete(recursive: true);
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(DefaultAssetBundle(
        bundle: _ProjectAssets(),
        child: MaterialApp(
          theme: AppThemeFactory.create(
              const AppLightColorScheme(), Brightness.light),
          home: Scaffold(
              resizeToAvoidBottomInset: false,
              body: Builder(
                  builder: (context) => VoiceRecordPreview(
                        key: key,
                        guard: ActionGuard(),
                        recorder: recorder,
                        mediaProcessManager: asr,
                        onClose: () {
                          closed++;
                          Navigator.of(context)
                              .popUntil((route) => route.isFirst);
                        },
                        onSendAudio: (record) async {
                          audios.add(record);
                          return pendingSend?.future ?? sendResult;
                        },
                        onSendText: (text) async {
                          texts.add(text);
                          return true;
                        },
                      ))),
        )));
    await tester.runAsync(
        () => key.currentState!.startRecord(origin: const Offset(195, 780)));
    await tester.pump();
  }

  Future<void> release(WidgetTester tester, AiAsrResult result,
      [int request = 0]) async {
    await tester.runAsync(() async {
      key.currentState!.stopRecord();
      recorder.deliver();
      await asr.requests[request].future;
    });
    expect(texts, isEmpty);
    expect(audios, isEmpty);
    await tester.runAsync(() async {
      asr.results[request].complete(result);
      await Future<void>.value();
    });
    await tester.pump();
  }

  testWidgets('录音波形随真实分贝增大，静音和越界音量不会反向放大', (tester) async {
    await mount(tester);
    double height() {
      final wave = tester
          .widgetList<CustomPaint>(find.descendant(
            of: find.bySemanticsIdentifier('chat.voice.preview_text'),
            matching: find.byType(CustomPaint),
          ))
          .last;
      final canvas = _WaveCanvas();
      wave.painter!.paint(canvas, const Size(108, 24));
      return canvas.heights.reduce((a, b) => a > b ? a : b);
    }

    expect(height(), 3);
    final measured = <double>[];
    for (final db in [-160, -90, -60, -30, 0, 30]) {
      recorder.onPowerLevel!(db);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      measured.add(height());
    }
    expect(measured.take(3), everyElement(3));
    expect(measured[3], greaterThan(3));
    expect(measured[4], greaterThan(measured[3]));
    expect(measured[4], greaterThan(20));
    expect(measured[5], measured[4]);
    expect(texts, isEmpty);
    expect(audios, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('音量柱原地不规则变化，同位置平滑形变且静音收平', (tester) async {
    await mount(tester);
    List<double> heights() {
      final wave = tester
          .widgetList<CustomPaint>(find.descendant(
            of: find.bySemanticsIdentifier('chat.voice.preview_text'),
            matching: find.byType(CustomPaint),
          ))
          .last;
      final canvas = _WaveCanvas();
      wave.painter!.paint(canvas, const Size(108, 24));
      return canvas.heights;
    }

    recorder.onPowerLevel!(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final before = heights();
    expect(before, everyElement(inInclusiveRange(6, 23)));
    expect(before, contains(23));
    recorder.onPowerLevel!(0);
    await tester.pump();
    expect(heights(), orderedEquals(before));
    await tester.pump(const Duration(milliseconds: 50));
    final halfway = heights();
    await tester.pump(const Duration(milliseconds: 50));
    final after = heights();
    expect(after, isNot(orderedEquals(before)));
    // 中间帧只在同一柱的起点和终点之间变化，不向相邻柱推进。
    for (var i = 0; i < 22; i++) {
      expect(halfway[i], closeTo((before[i] + after[i]) / 2, .01));
    }
    recorder.onPowerLevel!(-90);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(heights(), everyElement(3));
    await tester.pump(const Duration(seconds: 2));
    expect(heights(), everyElement(3));
    expect(texts, isEmpty);
    expect(audios, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('键盘首帧不跳位，正文与确认按钮随遮挡高度连续往返', (tester) async {
    await mount(tester);
    await release(tester, const AiAsrSuccess('识别正文'));
    final bubble = find.bySemanticsIdentifier('chat.voice.preview_text');
    final confirm = find.bySemanticsIdentifier('chat.voice.confirm');
    final original = tester.getTopLeft(bubble).dy;
    final originalButton = tester.getTopLeft(confirm).dy;
    await tester.tap(find.byType(ExtendedTextField));
    await tester.pump();
    expect(tester.getTopLeft(bubble).dy, original);
    expect(tester.getTopLeft(confirm).dy, originalButton);
    var previous = original;
    for (final inset in [60.0, 120.0, 180.0, 240.0, 300.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
      final top = tester.getTopLeft(bubble).dy;
      expect(top, lessThan(previous));
      expect(previous - top, lessThanOrEqualTo(60));
      previous = top;
    }
    for (final inset in [240.0, 180.0, 120.0, 60.0, 0.0]) {
      tester.view.viewInsets = FakeViewPadding(bottom: inset);
      await tester.pump();
      final top = tester.getTopLeft(bubble).dy;
      expect(top, greaterThan(previous));
      expect(top - previous, lessThanOrEqualTo(60));
      previous = top;
    }
    expect(tester.getTopLeft(bubble).dy, original);
    expect(tester.getTopLeft(confirm).dy, originalButton);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('编辑换行向上增高，删除回落且五行后滚动，表情切换不改变底边', (tester) async {
    await mount(tester);
    await release(tester, const AiAsrSuccess('第一行'));
    await tester.tap(find.byType(ExtendedTextField));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final bubble = find.bySemanticsIdentifier('chat.voice.preview_text');
    final field =
        tester.widget<ExtendedTextField>(find.byType(ExtendedTextField));
    final original = tester.getRect(bubble);
    final button =
        tester.getRect(find.bySemanticsIdentifier('chat.voice.confirm'));
    for (var lines = 2; lines <= 7; lines++) {
      // 保留末尾换行，覆盖输入法刚按下回车、下一行还没有文字的状态。
      field.controller!.text = '${List.filled(lines - 1, '正文').join('\n')}\n';
      await tester.pump();
      final rect = tester.getRect(bubble);
      expect(rect.bottom, closeTo(original.bottom, .01));
      expect(rect.height,
          closeTo(original.height + 22 * (lines.clamp(1, 5) - 1), .01));
      expect(tester.getRect(find.bySemanticsIdentifier('chat.voice.confirm')),
          button);
    }
    field.controller!.text = '第一行';
    await tester.pump();
    expect(tester.getRect(bubble), original);
    await tester.tap(find.bySemanticsIdentifier('chat.voice.emoji'));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump();
    field.controller!.text = '第一行\n';
    await tester.pump();
    expect(tester.getRect(bubble).bottom, closeTo(original.bottom, .01));
    expect(tester.getRect(bubble).top, closeTo(original.top - 22, .01));
    expect(texts, isEmpty);
    expect(audios, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('系统键盘收起后失焦并保留编辑正文，再次点击可继续编辑', (tester) async {
    await mount(tester);
    await release(tester, const AiAsrSuccess('识别原文'));
    await tester.tap(find.byType(ExtendedTextField));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final field =
        tester.widget<ExtendedTextField>(find.byType(ExtendedTextField));
    field.controller!.text = '编辑后的正文';
    expect(field.focusNode!.hasFocus, isTrue);
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump();
    expect(field.focusNode!.hasFocus, isFalse);
    expect(field.controller!.text, '编辑后的正文');
    expect(find.text('按住 继续说话'), findsOneWidget);
    await tester.tap(find.byType(ExtendedTextField));
    await tester.pump();
    expect(field.focusNode!.hasFocus, isTrue);
    expect(texts, isEmpty);
    expect(audios, isEmpty);
    tester.view.resetViewInsets();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('切到表情引起键盘收起时仍保留表情编辑面板', (tester) async {
    await mount(tester);
    await release(tester, const AiAsrSuccess('识别正文'));
    await tester.tap(find.byType(ExtendedTextField));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier('chat.voice.emoji'));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pump();
    expect(find.text('最常使用'), findsOneWidget);
    expect(find.text('默认表情'), findsOneWidget);
    expect(find.text('按住 继续说话'), findsNothing);
    tester.view.resetViewInsets();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('取消录音气泡固定102宽，说明紧随气泡而非停留底部', (tester) async {
    await mount(tester);
    key.currentState!.updatePointerPosition(const Offset(195, 600));
    await tester.pump();
    final bubble = find.bySemanticsIdentifier('chat.voice.preview_text');
    expect(tester.getSize(bubble), const Size(102, 94));
    expect(tester.getTopLeft(bubble), const Offset(144, 374));
    expect(tester.getTopLeft(find.text('松开 取消')).dy, 492);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('耗时识别提示位于气泡上方，保持214乘42的圆角提示框', (tester) async {
    await mount(tester);
    await tester.runAsync(() async {
      key.currentState!.stopRecord();
      recorder.deliver();
      await asr.requests.first.future;
    });
    // 采音完成在真实异步区交付，等待同一区域创建的8秒提示计时器。
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 8100)));
    await tester.pump();
    final notice = find
        .ancestor(
          of: find.text('网络不佳，正在识别，请稍后'),
          matching: find.byType(Container),
        )
        .first;
    expect(tester.getSize(notice), const Size(214, 42));
    expect(tester.getTopLeft(notice).dy, 281);
    expect(find.text('仅发语音'), findsOneWidget);
    expect(texts, isEmpty);
    expect(audios, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('松手识别不发送，确认发送最新编辑值且没有额外AI入口', (tester) async {
    await mount(tester);
    await release(tester, const AiAsrSuccess('识别原文'));
    final decoration = tester
        .widget<ExtendedTextField>(find.byType(ExtendedTextField))
        .decoration!;
    expect(decoration.filled, isFalse);
    expect(decoration.focusedBorder, InputBorder.none);
    expect(
        tester
            .widget<ExtendedTextField>(find.byType(ExtendedTextField))
            .controller!
            .text,
        '识别原文');
    expect(find.text('仅发语音'), findsOneWidget);
    expect(find.text('翻译'), findsNothing);
    expect(find.text('朗读'), findsNothing);
    await tester.tap(find.byType(ExtendedTextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    tester
        .widget<ExtendedTextField>(find.byType(ExtendedTextField))
        .controller!
        .text = '编辑后的文字';
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier('chat.voice.confirm'));
    await tester.pump();
    expect(texts, ['编辑后的文字']);
    expect(audios, isEmpty);
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('未识别出文字时仍能仅发送原音，不能发送空文字', (tester) async {
    await mount(tester);
    await release(tester, const AiAsrFailure(code: -1));
    expect(find.text('未识别出文字'), findsOneWidget);
    await tester.tap(find.bySemanticsIdentifier('chat.voice.confirm'));
    await tester.pump();
    expect(texts, isEmpty);
    await tester.tap(find.bySemanticsIdentifier('chat.voice.audio_only'));
    await tester.pump();
    expect(audios.single.path, recorder.paths.first);
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('取消后迟到的识别结果不能发送或重开预览', (tester) async {
    await mount(tester);
    await tester.runAsync(() async {
      key.currentState!.stopRecord();
      recorder.deliver();
      await asr.requests.first.future;
    });
    key.currentState!.cancel();
    asr.results.first.complete(const AiAsrSuccess('迟到结果'));
    await tester.pump();
    expect(texts, isEmpty);
    expect(audios, isEmpty);
    expect(closed, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('长按续录松手后保留编辑并只发送一条完整拼接音频', (tester) async {
    await mount(tester);
    await release(tester, const AiAsrSuccess('原文A'));
    await tester.tap(find.byType(ExtendedTextField));
    await tester.pump();
    tester
        .widget<ExtendedTextField>(find.byType(ExtendedTextField))
        .controller!
        .text = '编辑A';
    await tester.pump();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final args = call.arguments as Map;
      final paths = (args['paths'] as List).cast<String>();
      final output = args['destination'] as String;
      File(output).writeAsStringSync(
          [for (final path in paths) File(path).readAsStringSync()].join());
      return {'filePath': output, 'durationMs': 2000};
    });
    final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsIdentifier('chat.voice.confirm')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(recorder.starts[1].isCompleted, isTrue);
    await gesture.up();
    await tester.runAsync(() async {
      expect(recorder.pending, isNotNull);
      recorder.deliver();
      await asr.requests[1].future.timeout(const Duration(seconds: 3));
    });
    await tester.runAsync(() async {
      asr.results[1].complete(const AiAsrSuccess('新增B'));
      await Future<void>.value();
    });
    await tester.pump();
    expect(texts, isEmpty);
    expect(
        tester
            .widget<ExtendedTextField>(find.byType(ExtendedTextField))
            .controller!
            .text,
        '编辑A\n新增B');
    await tester.tap(find.bySemanticsIdentifier('chat.voice.audio_only'));
    await tester.pump();
    expect(audios, hasLength(1));
    expect(audios.single.durationMs, 2000);
    expect(File(audios.single.path).readAsStringSync(), '01');
    expect(audios.single.path, isNot(recorder.paths.last));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('语音发送失败可重试，重复点击合并且退出不删除SDK正在读取的文件', (tester) async {
    await mount(tester);
    await release(tester, const AiAsrSuccess('文字'));
    sendResult = false;
    await tester.tap(find.bySemanticsIdentifier('chat.voice.audio_only'));
    await tester.pump();
    expect(closed, 0);
    expect(audios, hasLength(1));
    pendingSend = Completer<bool>();
    await tester.tap(find.bySemanticsIdentifier('chat.voice.audio_only'));
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier('chat.voice.audio_only'));
    await tester.pump();
    expect(audios, hasLength(2));
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.value();
      expect(File(audios.last.path).existsSync(), isTrue);
      pendingSend!.complete(false);
    });
    expect(closed, 0);
  });

  testWidgets('语音表情编辑复用目录和完整令牌，保留唯一确认发送入口', (tester) async {
    await mount(tester);
    tester.view.padding = const FakeViewPadding(top: 42, bottom: 16);
    addTearDown(tester.view.resetPadding);
    await release(tester, const AiAsrSuccess('正文'));
    await tester.tap(find.byType(ExtendedTextField));
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    await tester.tap(find.bySemanticsIdentifier('chat.voice.emoji'));
    await tester.pump();
    expect(find.text('最常使用'), findsOneWidget);
    expect(find.text('默认表情'), findsOneWidget);
    final recent = find
        .byWidgetPredicate((widget) =>
            widget is Semantics &&
            (widget.properties.identifier
                    ?.startsWith('chat.voice.emoji.recent.') ??
                false))
        .first;
    expect(
        tester.getTopLeft(recent).dy -
            tester.getBottomLeft(find.text('最常使用')).dy,
        12);
    expect(tester.getSize(recent).height, 32);
    final panelBackground = find
        .ancestor(
            of: recent,
            matching: find.byWidgetPredicate((widget) =>
                widget is ColoredBox &&
                widget.color ==
                    const AppLightColorScheme().groupedPageBackground))
        .first;
    expect(tester.getRect(panelBackground).bottom, 844);
    expect(find.text('发送'), findsNothing);
    await tester.tap(
        find.bySemanticsIdentifier('chat.voice.emoji.recent.[ZDEmoji_Like]'));
    await tester.pump();
    final field =
        tester.widget<ExtendedTextField>(find.byType(ExtendedTextField));
    expect(field.controller!.text, contains('[ZDEmoji_Like]'));
    await tester.tap(find.bySemanticsIdentifier('chat.voice.emoji_delete'));
    await tester.pump();
    expect(field.controller!.text, '正文');
    await tester.tap(find.bySemanticsIdentifier('chat.voice.confirm'));
    await tester.pump();
    expect(texts, ['正文']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('原生60秒自动结束只进入预览，随后抬手不重复识别或发送', (tester) async {
    await mount(tester);
    expect(recorder.limits.single, 60000);
    await tester.runAsync(() async {
      recorder.active = false;
      recorder.complete!(RecordInfo(path: recorder.paths.single, duration: 60)
        ..errorCode = AudioRecordResultCode.successExceedMaxDuration);
      await asr.requests.first.future;
      key.currentState!.stopRecord();
      asr.results.first.complete(const AiAsrSuccess('六十秒正文'));
      await Future<void>.value();
    });
    await tester.pump();
    expect(asr.results, hasLength(1));
    expect(texts, isEmpty);
    expect(audios, isEmpty);
    await tester.longPress(find.bySemanticsIdentifier('chat.voice.confirm'));
    await tester.pump();
    expect(recorder.paths, hasLength(1));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('系统中断正在录音时取消草稿，返回前台不补发', (tester) async {
    await mount(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(closed, 1);
    expect(recorder.active, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(texts, isEmpty);
    expect(audios, isEmpty);
    expect(asr.results, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
