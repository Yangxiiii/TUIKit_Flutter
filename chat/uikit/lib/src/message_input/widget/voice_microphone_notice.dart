import 'package:app_ui/app_ui.dart';
import 'package:flutter/material.dart';

/// 麦克风已被系统永久禁用时的说明；只确认知悉，不擅自跳转系统设置。
class VoiceMicrophoneNotice extends StatelessWidget {
  const VoiceMicrophoneNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(32),
      child: SizedBox(
        width: 300,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('未开启麦克风权限，请前往系统设置开启麦克风权限',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 14,
                      height: 20 / 14)),
            ),
            const SizedBox(height: 18),
            Semantics(
              identifier: 'chat.voice.microphone_acknowledge',
              button: true,
              child: GestureDetector(
                onTap: () => AppDialog.dismiss<void>(),
                child: Container(
                  height: 42,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(21)),
                  child: Text('我知道了',
                      style: TextStyle(color: colors.onPrimary, fontSize: 14)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
