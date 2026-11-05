#include <napi/native_api.h>
#include <multimedia/player_framework/native_avsource.h>
#include <multimedia/player_framework/native_avdemuxer.h>
#include <multimedia/player_framework/native_avmuxer.h>
#include <multimedia/player_framework/native_avmemory.h>
#include <multimedia/player_framework/native_avformat.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
// 时间戳为微秒；续录沿用整条语音的60秒上限。
constexpr int64_t MAX_DURATION_US = 60000000;

void Check(bool valid, const char *message)
{
    if (!valid) throw std::runtime_error(message);
}

// 文件描述符随当前片段作用域释放，输入文件始终只读。
struct InputFile {
    int fd;
    explicit InputFile(const std::string &path) : fd(open(path.c_str(), O_RDONLY))
    {
        Check(fd >= 0, "Cannot open audio clip");
    }
    ~InputFile() { close(fd); }
};

// 只有本次成功创建的新文件可被失败清理，绝不能删除已有目标或原草稿。
struct OutputFile {
    std::string path;
    int fd;
    // 只有重新解析并确认时长有效后才保留输出，异常退出自动删除半成品。
    bool committed = false;
    explicit OutputFile(const std::string &value)
        : path(value), fd(open(value.c_str(), O_CREAT | O_EXCL | O_RDWR, 0600))
    {
        Check(fd >= 0, "Output must be a new audio file");
    }
    ~OutputFile()
    {
        close(fd);
        if (!committed) unlink(path.c_str());
    }
};

// 压缩音频帧顺序复用，避免把M4A容器字节直接追加成损坏文件。
int64_t Merge(const std::vector<std::string> &paths, const std::string &destination)
{
    OutputFile output(destination);
    auto muxer = std::unique_ptr<OH_AVMuxer, decltype(&OH_AVMuxer_Destroy)>(
        OH_AVMuxer_Create(output.fd, AV_OUTPUT_FORMAT_M4A), OH_AVMuxer_Destroy);
    Check(muxer != nullptr, "Cannot create audio muxer");
    auto memory = std::unique_ptr<OH_AVMemory, decltype(&OH_AVMemory_Destroy)>(
        OH_AVMemory_Create(1024 * 1024), OH_AVMemory_Destroy);
    Check(memory != nullptr, "Cannot allocate audio buffer");
    int32_t outputTrack = -1;
    int32_t expectedRate = 0;
    int32_t expectedChannels = 0;
    int64_t offsetUs = 0;

    for (const auto &path : paths) {
        InputFile input(path);
        struct stat info {};
        Check(fstat(input.fd, &info) == 0 && info.st_size > 0, "Empty audio file");
        auto source = std::unique_ptr<OH_AVSource, decltype(&OH_AVSource_Destroy)>(
            OH_AVSource_CreateWithFD(input.fd, 0, info.st_size), OH_AVSource_Destroy);
        Check(source != nullptr, "Cannot parse audio clip");
        auto sourceFormat = std::unique_ptr<OH_AVFormat, decltype(&OH_AVFormat_Destroy)>(
            OH_AVSource_GetSourceFormat(source.get()), OH_AVFormat_Destroy);
        int32_t count = 0;
        Check(sourceFormat && OH_AVFormat_GetIntValue(
            sourceFormat.get(), OH_MD_KEY_TRACK_COUNT, &count), "Missing audio tracks");
        int32_t inputTrack = -1;
        std::unique_ptr<OH_AVFormat, decltype(&OH_AVFormat_Destroy)> format(nullptr, OH_AVFormat_Destroy);
        for (int32_t index = 0; index < count; ++index) {
            format.reset(OH_AVSource_GetTrackFormat(source.get(), index));
            int32_t type = -1;
            if (format && OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_TRACK_TYPE, &type) &&
                type == MEDIA_TYPE_AUD) {
                inputTrack = index;
                break;
            }
        }
        Check(inputTrack >= 0, "Audio track not found");
        int32_t rate = 0;
        int32_t channels = 0;
        const char *mime = nullptr;
        Check(OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_AUD_SAMPLE_RATE, &rate) &&
            OH_AVFormat_GetIntValue(format.get(), OH_MD_KEY_AUD_CHANNEL_COUNT, &channels) &&
            OH_AVFormat_GetStringValue(format.get(), OH_MD_KEY_CODEC_MIME, &mime) &&
            mime && std::string(mime) == OH_AVCODEC_MIMETYPE_AUDIO_AAC &&
            rate > 0 && channels > 0, "Unsupported recording format");
        if (outputTrack < 0) {
            expectedRate = rate;
            expectedChannels = channels;
            Check(OH_AVMuxer_AddTrack(muxer.get(), &outputTrack, format.get()) == AV_ERR_OK,
                "Cannot add audio track");
            Check(OH_AVMuxer_Start(muxer.get()) == AV_ERR_OK, "Cannot start audio muxer");
        } else {
            Check(rate == expectedRate && channels == expectedChannels, "Incompatible audio clips");
        }
        auto demuxer = std::unique_ptr<OH_AVDemuxer, decltype(&OH_AVDemuxer_Destroy)>(
            OH_AVDemuxer_CreateWithSource(source.get()), OH_AVDemuxer_Destroy);
        Check(demuxer && OH_AVDemuxer_SelectTrackByID(demuxer.get(), inputTrack) == AV_ERR_OK,
            "Cannot select audio track");
        int64_t firstPts = -1;
        int64_t endUs = offsetUs;
        const int64_t frameUs = 1024000000LL / rate;
        while (true) {
            OH_AVCodecBufferAttr attr {};
            Check(OH_AVDemuxer_ReadSample(demuxer.get(), inputTrack, memory.get(), &attr) == AV_ERR_OK,
                "Cannot read audio sample");
            if (attr.flags & AVCODEC_BUFFER_FLAGS_EOS) break;
            if (firstPts < 0) firstPts = attr.pts;
            attr.pts = offsetUs + attr.pts - firstPts;
            if (attr.pts + frameUs > MAX_DURATION_US) break;
            Check(OH_AVMuxer_WriteSample(muxer.get(), outputTrack, memory.get(), attr) == AV_ERR_OK,
                "Cannot write audio sample");
            endUs = attr.pts + frameUs;
        }
        Check(endUs > offsetUs, "No audio samples appended");
        offsetUs = endUs;
        if (offsetUs >= MAX_DURATION_US) break;
    }
    // 封装器落盘并释放后再解析输出，不能把写帧成功当成完整M4A已经可用。
    Check(OH_AVMuxer_Stop(muxer.get()) == AV_ERR_OK, "Cannot finalize audio");
    muxer.reset();
    struct stat written {};
    Check(fstat(output.fd, &written) == 0 && written.st_size > 0, "Empty merged audio");
    auto verified = std::unique_ptr<OH_AVSource, decltype(&OH_AVSource_Destroy)>(
        OH_AVSource_CreateWithFD(output.fd, 0, written.st_size), OH_AVSource_Destroy);
    Check(verified != nullptr, "Cannot reopen merged audio");
    auto metadata = std::unique_ptr<OH_AVFormat, decltype(&OH_AVFormat_Destroy)>(
        OH_AVSource_GetSourceFormat(verified.get()), OH_AVFormat_Destroy);
    int64_t durationUs = 0;
    Check(metadata && OH_AVFormat_GetLongValue(metadata.get(), OH_MD_KEY_DURATION, &durationUs) &&
        durationUs >= 1000000 && durationUs <= MAX_DURATION_US, "Invalid merged duration");
    output.committed = true;
    return durationUs / 1000;
}

// 异步任务拥有参数和结果，文件合并不能阻塞ArkTS界面线程。
struct MergeWork {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::vector<std::string> paths;
    std::string destination;
    std::string error;
    int64_t durationMs = 0;
};

// 在NAPI边界拒绝空路径和非字符串，避免原生文件操作接收错误类型。
std::string ReadString(napi_env env, napi_value value)
{
    size_t length = 0;
    Check(napi_get_value_string_utf8(env, value, nullptr, 0, &length) == napi_ok && length > 0,
        "Invalid audio path");
    std::string result(length, '\0');
    Check(napi_get_value_string_utf8(env, value, result.data(), length + 1, &length) == napi_ok,
        "Invalid audio path");
    return result;
}

// 校验调用参数后移交后台任务，Promise仅在新文件验证或失败清理后兑现。
napi_value MergeRecordings(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    auto task = std::make_unique<MergeWork>();
    try {
        bool array = false;
        uint32_t count = 0;
        Check(argc == 2 && napi_is_array(env, argv[0], &array) == napi_ok && array &&
            napi_get_array_length(env, argv[0], &count) == napi_ok && count >= 2 && count <= 60,
            "Invalid audio clips");
        for (uint32_t index = 0; index < count; ++index) {
            napi_value path;
            napi_get_element(env, argv[0], index, &path);
            task->paths.push_back(ReadString(env, path));
        }
        task->destination = ReadString(env, argv[1]);
    } catch (const std::exception &error) {
        napi_throw_type_error(env, nullptr, error.what());
        return nullptr;
    }
    // 文件与媒体处理放到原生任务队列，ArkTS线程只负责交付最终结果。
    napi_value promise;
    napi_value name;
    napi_create_promise(env, &task->deferred, &promise);
    napi_create_string_utf8(env, "chat.voice.merge", NAPI_AUTO_LENGTH, &name);
    const auto execute = [](napi_env, void *data) {
        auto *job = static_cast<MergeWork *>(data);
        try {
            job->durationMs = Merge(job->paths, job->destination);
        } catch (const std::exception &error) {
            job->error = error.what();
        }
    };
    const auto complete = [](napi_env env, napi_status status, void *data) {
        std::unique_ptr<MergeWork> job(static_cast<MergeWork *>(data));
        napi_value value;
        if (status == napi_ok && job->error.empty()) {
            napi_create_int64(env, job->durationMs, &value);
            napi_resolve_deferred(env, job->deferred, value);
        } else {
            napi_value message;
            const auto text = job->error.empty() ? "Audio merge cancelled" : job->error;
            napi_create_string_utf8(env, text.c_str(), NAPI_AUTO_LENGTH, &message);
            napi_create_error(env, nullptr, message, &value);
            napi_reject_deferred(env, job->deferred, value);
        }
        napi_delete_async_work(env, job->work);
    };
    if (napi_create_async_work(env, nullptr, name, execute, complete, task.get(), &task->work) != napi_ok ||
        napi_queue_async_work(env, task->work) != napi_ok) {
        napi_value message;
        napi_value error;
        napi_create_string_utf8(env, "Cannot queue audio merge", NAPI_AUTO_LENGTH, &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, task->deferred, error);
        if (task->work) napi_delete_async_work(env, task->work);
        return promise;
    }
    task.release();
    return promise;
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_value function;
    napi_create_function(env, "mergeRecordings", NAPI_AUTO_LENGTH, MergeRecordings, nullptr, &function);
    napi_set_named_property(env, exports, "mergeRecordings", function);
    return exports;
}

napi_module module = {1, 0, nullptr, Init, "chat_voice", nullptr, {0}};
} // 私有命名空间

extern "C" __attribute__((constructor)) void RegisterChatVoice()
{
    napi_module_register(&module);
}
