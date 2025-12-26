cmake_minimum_required(VERSION 3.16)

project(LangListen VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Quick Qml Multimedia OpenGL OpenGLWidgets Concurrent)

set(WHISPER_INCLUDE_DIR "D:/Ext-Lib/whisper-win-x64/include" CACHE PATH "Whisper include directory")
set(WHISPER_LIB_DIR "D:/Ext-Lib/whisper-win-x64/lib/Debug" CACHE PATH "Whisper library directory")
set(WHISPER_BIN_DIR "D:/Ext-Lib/whisper-win-x64/bin/Debug" CACHE PATH "Whisper binary directory")

if(EXISTS "${WHISPER_INCLUDE_DIR}/ggml-cuda.h")
    message(STATUS "✓ 找到 ggml-cuda.h，Whisper 支持 CUDA")
    set(WHISPER_HAS_CUDA ON)
elseif(EXISTS "${WHISPER_INCLUDE_DIR}/ggml.h")
    file(READ "${WHISPER_INCLUDE_DIR}/ggml.h" GGML_HEADER_CONTENT)
    if(GGML_HEADER_CONTENT MATCHES "GGML_USE_CUDA|GGML_USE_CUBLAS")
        message(STATUS "✓ ggml.h 中定义了 CUDA 支持")
        set(WHISPER_HAS_CUDA ON)
    else()
        message(STATUS "✗ ggml.h 中未找到 CUDA 定义")
        set(WHISPER_HAS_CUDA OFF)
    endif()
else()
    message(WARNING "⚠ 无法检测 CUDA 支持，假设不支持")
    set(WHISPER_HAS_CUDA OFF)
endif()

set(FFMPEG_INCLUDE_DIR "D:/Ext-Lib/ffmpeg-win-x64/include" CACHE PATH "ffmpeg include directory")
set(FFMPEG_LIB_DIR "D:/Ext-Lib/ffmpeg-win-x64/lib" CACHE PATH "ffmpeg library directory")
set(FFMPEG_BIN_DIR "D:/Ext-Lib/ffmpeg-win-x64/bin" CACHE PATH "ffmpeg binary directory")

set(PORTAUDIO_INCLUDE_DIR "D:/Ext-Lib/portaudio-win-x64/include" CACHE PATH "PortAudio include directory")
set(PORTAUDIO_LIB_DIR "D:/Ext-Lib/portaudio-win-x64/lib" CACHE PATH "PortAudio library directory")
set(PORTAUDIO_BIN_DIR "D:/Ext-Lib/portaudio-win-x64/bin" CACHE PATH "PortAudio binary directory")

set(PROJECT_SOURCES
    main.cpp
    whisperworker.cpp
    whisperworker.h
    applicationcontroller.cpp
    applicationcontroller.h
    audioconverter.h
    audioconverter.cpp
    subtitlegenerator.h
    subtitlegenerator.cpp
    audioplaybackcontroller.h
    audioplaybackcontroller.cpp
    audioringbuffer.h
    audioringbuffer.cpp
    ffmpegaudioengine.h
    ffmpegaudioengine.cpp
    waveformgenerator.h
    waveformgenerator.cpp
    waveformview.h
    waveformview.cpp
)

qt_add_executable(LangListen
    ${PROJECT_SOURCES}
)

qt_add_qml_module(LangListen
    URI LangListen
    VERSION 1.0
    QML_FILES
        qml/main.qml
        qml/ListeningPracticePage.qml
        qml/TranscriptionPage.qml
    RESOURCES
        qml.qrc
)

target_include_directories(LangListen PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${WHISPER_INCLUDE_DIR}
    ${FFMPEG_INCLUDE_DIR}
    ${PORTAUDIO_INCLUDE_DIR}
)

if(WHISPER_HAS_CUDA)
    message(STATUS "✓ 为项目添加 GGML_USE_CUDA 宏定义")
    target_compile_definitions(LangListen PRIVATE 
        GGML_USE_CUDA
        GGML_USE_CUBLAS
    )
endif()

target_link_libraries(LangListen PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::Qml
    Qt6::Multimedia
    Qt6::OpenGL
    Qt6::OpenGLWidgets
    Qt6::Concurrent
)

target_link_directories(LangListen PRIVATE ${WHISPER_LIB_DIR})
target_link_libraries(LangListen PRIVATE whisper)

target_link_directories(LangListen PRIVATE ${FFMPEG_LIB_DIR})
target_link_libraries(LangListen PRIVATE 
    avformat
    avcodec
    avutil
    swresample
)

target_link_directories(LangListen PRIVATE ${PORTAUDIO_LIB_DIR})
target_link_libraries(LangListen PRIVATE portaudio_x64.lib)

if(WIN32)
    set_target_properties(LangListen PROPERTIES
        WIN32_EXECUTABLE FALSE
    )

    set(WHISPER_DLLS 
        "whisper.dll" 
        "ggml.dll"
        "ggml-base.dll"
        "ggml-cpu.dll"
        "ggml-cuda.dll"
    )
            
    foreach(whisper_dll ${WHISPER_DLLS})
        set(WHISPER_DLL_PATH "${WHISPER_BIN_DIR}/${whisper_dll}")
        if(EXISTS "${WHISPER_DLL_PATH}")
            add_custom_command(TARGET LangListen POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${WHISPER_DLL_PATH}"
                $<TARGET_FILE_DIR:LangListen>
                COMMENT "复制 ${whisper_dll}..."
            )
            message(STATUS "  ✓ 将复制: ${whisper_dll}")
        endif()
    endforeach()
    
    if(WHISPER_HAS_CUDA)
        message(STATUS "尝试查找并复制 CUDA 运行时 DLLs...")
        
        find_program(CUDA_NVCC nvcc)
        if(CUDA_NVCC)
            get_filename_component(CUDA_BIN_DIR "${CUDA_NVCC}" DIRECTORY)
            message(STATUS "  CUDA bin 目录: ${CUDA_BIN_DIR}")
            
            set(CUDA_DLLS 
                "cublas64_12.dll" 
                "cublasLt64_12.dll"
                "cudart64_12.dll" 
            )
            
            foreach(cuda_dll ${CUDA_DLLS})
                set(CUDA_DLL_PATH "${CUDA_BIN_DIR}/${cuda_dll}")
                if(EXISTS "${CUDA_DLL_PATH}")
                    add_custom_command(TARGET LangListen POST_BUILD
                        COMMAND ${CMAKE_COMMAND} -E copy_if_different
                        "${CUDA_DLL_PATH}"
                        $<TARGET_FILE_DIR:LangListen>
                        COMMENT "复制 ${cuda_dll}..."
                    )
                    message(STATUS "  ✓ 将复制: ${cuda_dll}")
                endif()
            endforeach()
        else()
            message(WARNING "  ⚠ 未找到 nvcc，无法自动复制 CUDA DLLs")
            message(WARNING "    请手动复制 CUDA DLLs 到应用程序目录")
        endif()
    endif()

    add_custom_command(TARGET LangListen POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${FFMPEG_BIN_DIR}"
        $<TARGET_FILE_DIR:LangListen>
    )
    
    # 复制 PortAudio DLL
    set(PORTAUDIO_DLLS 
        "portaudio_x64.dll"
    )
    
    foreach(portaudio_dll ${PORTAUDIO_DLLS})
        set(PORTAUDIO_DLL_PATH "${PORTAUDIO_BIN_DIR}/${portaudio_dll}")
        if(EXISTS "${PORTAUDIO_DLL_PATH}")
            add_custom_command(TARGET LangListen POST_BUILD
                COMMAND ${CMAKE_COMMAND} -E copy_if_different
                "${PORTAUDIO_DLL_PATH}"
                $<TARGET_FILE_DIR:LangListen>
                COMMENT "复制 ${portaudio_dll}..."
            )
            message(STATUS "  ✓ 将复制: ${portaudio_dll}")
        endif()
    endforeach()
endif()

set_target_properties(LangListen PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)