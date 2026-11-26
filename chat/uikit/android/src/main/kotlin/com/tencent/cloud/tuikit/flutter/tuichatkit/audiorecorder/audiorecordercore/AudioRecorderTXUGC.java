package com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.audiorecordercore;
import android.content.Context;
import android.util.Log;


import com.tencent.cloud.tuikit.flutter.tuichatkit.R;
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.ResultCode;
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.audiorecorderimpl.RecorderListener;
import org.jetbrains.annotations.Nullable;

import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.audiorecordercore.TXUGCAudioRecorderReflector.AudioConfig;
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.audiorecordercore.TXUGCAudioRecorderReflector.RecordResult;
import com.tencent.cloud.tuikit.flutter.tuichatkit.audiorecorder.audiorecordercore.TXUGCAudioRecorderReflector.TXUGCAudioRecorderReflectorListener;

/** 使用腾讯录音器采集声音，降噪授权失败后回退到普通录音。 */
public class AudioRecorderTXUGC implements AudioRecorderInternalInterface, TXUGCAudioRecorderReflectorListener {
    private final static String TAG = "TXUGCAudioRecorder";
    private final static int ERROR_LESS_THAN_MIN_DURATION = 1;
    private final static int SUCCESS_EXCEED_MAX_DURATION = 2;
    private final static int START_RECORD_ERR_LICENCE_VERIFICATION_FAILED = -5;

    static {
        AudioRecorderSignatureChecker.getInstance().startUpdateSignature();
    }

    private final TXUGCAudioRecorderReflector mTxUgcAudioRecorderReflector;
    private final Context mContext;
    private RecorderListener mListener;
    private boolean mEnableAiDeNoise = false;
    private String mFilePath;
    private int mMinRecordDurationMs = 1000;
    private int mMaxRecordDurationMs = 60000;

    private boolean isAppDebuggable() {
        return (mContext.getApplicationInfo().flags & android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0;
    }

    public AudioRecorderTXUGC(Context context) {
        Log.i(TAG, "TXUGCAudioRecorder construct");
        mContext = context;
        mTxUgcAudioRecorderReflector = new TXUGCAudioRecorderReflector();
    }

    public void init() throws Exception {
        Log.i(TAG, "TXUGCAudioRecorder init");
        mTxUgcAudioRecorderReflector.init(mContext);
        mTxUgcAudioRecorderReflector.setListener(this);
    }

    @Override
    public void setListener(@Nullable RecorderListener listener) {
        mListener = listener;
    }

    @Override
    public void startRecord(@Nullable String filePath, int minRecordDurationMs, int maxRecordDurationMs) {
        Log.i(TAG, "start record. file path: " + filePath);
        mFilePath = filePath;
        mMinRecordDurationMs = minRecordDurationMs;
        mMaxRecordDurationMs = maxRecordDurationMs;

        AudioConfig audioConfig = new AudioConfig();
        audioConfig.enableAIDeNoise = mEnableAiDeNoise;
        audioConfig.minDuration = minRecordDurationMs;
        audioConfig.maxDuration = maxRecordDurationMs;
        int result = mTxUgcAudioRecorderReflector.startRecord(filePath, audioConfig);
        Log.i(TAG, "start record. result : " + result);
        if (result == START_RECORD_ERR_LICENCE_VERIFICATION_FAILED) {
            handleLicenceVerificationFailed();
        } else if (result < 0) {
            mListener.onCompleted(ResultCode.ERROR_RECORD_INNER_FAIL, "");
        }
    }

    @Override
    public void stopRecord() {
        Log.i(TAG, "stop record");
        mTxUgcAudioRecorderReflector.stopRecord();
    }

    @Override
    public void enableAIDeNoise(boolean enable) {
        Log.i(TAG, enable ? "enable" : "disable" + "ai denoise");
        mEnableAiDeNoise = enable;
    }

    @Override
    public void onProgress(long milliSecond) {
        Log.i(TAG, "onProgress = " + milliSecond);
        if (mListener != null) {
            mListener.onRecordTime((int) milliSecond);
        }
    }

    @Override
    public void onComplete(RecordResult result) {
        if (mListener == null) {
            return;
        }

        Log.i(TAG, "On record complete. retCode: " + result.retCode + " videoPath:" + result.videoPath);
        if (result.retCode == ERROR_LESS_THAN_MIN_DURATION) {
            mListener.onCompleted(ResultCode.ERROR_LESS_THAN_MIN_DURATION, result.videoPath);
        } else if (result.retCode == SUCCESS_EXCEED_MAX_DURATION) {
            mListener.onCompleted(ResultCode.SUCCESS_EXCEED_MAX_DURATION, result.videoPath);
        } else if (result.retCode >= 0) {
            mListener.onCompleted(ResultCode.SUCCESS, result.videoPath);
        } else {
            mListener.onCompleted(ResultCode.ERROR_RECORD_INNER_FAIL, result.videoPath);
        }
    }

    private void handleLicenceVerificationFailed() {
        Log.i(TAG, "handle licence verification failed.");

        if (!mEnableAiDeNoise) {
            mListener.onCompleted(ResultCode.ERROR_RECORD_INNER_FAIL, "");
            return;
        }

        mEnableAiDeNoise = false;
        if (isAppDebuggable()) {
            // 降噪授权失败后仍会用普通录音重试，调试诊断无需占用用户提示。
            Log.w(TAG, mContext.getString(R.string.audio_authorization_prompter));
        }

        startRecord(mFilePath, mMinRecordDurationMs, mMaxRecordDurationMs);
    }
}
