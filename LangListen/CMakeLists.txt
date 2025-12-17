cmake_minimum_required(VERSION 3.16)

project(LangListen VERSION 1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Qt设置
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# 查找Qt6组件
find_package(Qt6 REQUIRED COMPONENTS Core Quick Qml)

# Whisper.cpp路径配置
set(WHISPER_INCLUDE_DIR "D:/Ext-Lib/whisper-win-x64/include" CACHE PATH "Whisper include directory")
set(WHISPER_LIB_DIR "D:/Ext-Lib/whisper-win-x64/lib/Debug" CACHE PATH "Whisper library directory")
set(WHISPER_BIN_DIR "D:/Ext-Lib/whisper-win-x64/bin/Debug" CACHE PATH "Whisper binary directory")

# ===== 检测 Whisper 是否支持 CUDA =====
message(STATUS "===========================================")
message(STATUS "检测 Whisper CUDA 支持...")

# 方法1: 检查 whisper.h 中的宏定义
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

message(STATUS "===========================================")

# 源文件
set(PROJECT_SOURCES
    main.cpp
    whisperworker.cpp
    whisperworker.h
    applicationcontroller.cpp
    applicationcontroller.h
)

# QML资源文件
set(QML_SOURCES
    qml/main.qml
    qml.qrc
)

# 创建可执行文件
qt_add_executable(LangListen
    ${PROJECT_SOURCES}
)

# 添加QML模块
qt_add_qml_module(LangListen
    URI LangListen
    VERSION 1.0
    QML_FILES
        qml/main.qml
    RESOURCES
        ${QML_SOURCES}
)

target_include_directories(LangListen PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${WHISPER_INCLUDE_DIR}
)

# ===== 添加 CUDA 宏定义 =====
if(WHISPER_HAS_CUDA)
    message(STATUS "✓ 为项目添加 GGML_USE_CUDA 宏定义")
    target_compile_definitions(LangListen PRIVATE 
        GGML_USE_CUDA
        GGML_USE_CUBLAS  # 兼容旧版本
    )
endif()

# 链接Qt库
target_link_libraries(LangListen PRIVATE
    Qt6::Core
    Qt6::Quick
    Qt6::Qml
)

# 链接Whisper库
target_link_directories(LangListen PRIVATE ${WHISPER_LIB_DIR})
target_link_libraries(LangListen PRIVATE whisper)

# Windows特定设置
if(WIN32)
    set_target_properties(LangListen PROPERTIES
        WIN32_EXECUTABLE FALSE
    )

    # 查找并复制 CUDA DLLs
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
    
    # 如果检测到 CUDA 支持，复制 CUDA 运行时 DLLs
    if(WHISPER_HAS_CUDA)
        message(STATUS "尝试查找并复制 CUDA 运行时 DLLs...")
        
        # 查找 CUDA bin 目录
        find_program(CUDA_NVCC nvcc)
        if(CUDA_NVCC)
            get_filename_component(CUDA_BIN_DIR "${CUDA_NVCC}" DIRECTORY)
            message(STATUS "  CUDA bin 目录: ${CUDA_BIN_DIR}")
            
            # 查找并复制 CUDA DLLs
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
endif()

# 设置输出目录
set_target_properties(LangListen PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# ===== 打印最终配置摘要 =====
message(STATUS "")
message(STATUS "=================== 配置摘要 ===================")
message(STATUS "Qt 版本: ${Qt6_VERSION}")
message(STATUS "构建类型: ${CMAKE_BUILD_TYPE}")
message(STATUS "Whisper CUDA 支持: ${WHISPER_HAS_CUDA}")
message(STATUS "输出目录: ${CMAKE_BINARY_DIR}/bin")
message(STATUS "==============================================")
message(STATUS "")