cmake_minimum_required(VERSION 3.5)
project(chat_voice)
set(CMAKE_CXX_STANDARD 17)
add_library(chat_voice SHARED audio_clip_merger.cpp)
target_link_libraries(chat_voice PUBLIC ace_napi.z native_media_core
    native_media_codecbase native_media_avsource native_media_avdemuxer native_media_avmuxer)
