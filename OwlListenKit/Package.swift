// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OwlListenKit",
    platforms: [
        .macOS("12.4"),
    ],
    products: [
        .library(
            name: "OwlListenKit",
            targets: ["OwlListenKit"]
        ),
    ],
    targets: [
        .target(
            name: "OwlListenKit",
            dependencies: ["CWhisper"]
        ),
        .target(
            name: "CWhisper",
            path: "Sources/CWhisper",
            exclude: [
                "third_party/whisper.cpp/src/coreml",
                "third_party/whisper.cpp/src/openvino",
                "third_party/whisper.cpp/ggml/src/ggml-cann",
                "third_party/whisper.cpp/ggml/src/ggml-cuda",
                "third_party/whisper.cpp/ggml/src/ggml-hexagon",
                "third_party/whisper.cpp/ggml/src/ggml-hip",
                "third_party/whisper.cpp/ggml/src/ggml-metal",
                "third_party/whisper.cpp/ggml/src/ggml-musa",
                "third_party/whisper.cpp/ggml/src/ggml-opencl",
                "third_party/whisper.cpp/ggml/src/ggml-rpc",
                "third_party/whisper.cpp/ggml/src/ggml-sycl",
                "third_party/whisper.cpp/ggml/src/ggml-vulkan",
                "third_party/whisper.cpp/ggml/src/ggml-webgpu",
                "third_party/whisper.cpp/ggml/src/ggml-zdnn",
                "third_party/whisper.cpp/ggml/src/ggml-zendnn",
            ],
            sources: [
                "owl_whisper_bridge.cpp",
                "third_party/whisper.cpp/src/whisper.cpp",
                "third_party/whisper.cpp/ggml/src/ggml.c",
                "third_party/whisper.cpp/ggml/src/ggml.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-alloc.c",
                "third_party/whisper.cpp/ggml/src/ggml-backend.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-backend-reg.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-opt.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-threading.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-quants.c",
                "third_party/whisper.cpp/ggml/src/gguf.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/ggml-cpu.c",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/ggml-cpu.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/repack.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/hbm.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/quants.c",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/traits.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/binary-ops.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/unary-ops.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/vec.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/ops.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/arch/arm/quants.c",
                "third_party/whisper.cpp/ggml/src/ggml-cpu/arch/arm/repack.cpp",
                "third_party/whisper.cpp/ggml/src/ggml-blas/ggml-blas.cpp",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("third_party/whisper.cpp/include"),
                .headerSearchPath("third_party/whisper.cpp/src"),
                .headerSearchPath("third_party/whisper.cpp/ggml/include"),
                .headerSearchPath("third_party/whisper.cpp/ggml/src"),
                .headerSearchPath("third_party/whisper.cpp/ggml/src/ggml-cpu"),
                .define("GGML_VERSION", to: "\"0.9.5\""),
                .define("GGML_COMMIT", to: "\"c02de38\""),
                .define("GGML_SCHED_MAX_COPIES", to: "4"),
                .define("GGML_USE_CPU"),
                .define("GGML_USE_BLAS"),
                .define("GGML_USE_ACCELERATE"),
                .define("GGML_BLAS_USE_ACCELERATE"),
                .define("GGML_USE_CPU_REPACK"),
                .define("_DARWIN_C_SOURCE"),
                .define("_XOPEN_SOURCE", to: "600"),
            ],
            cxxSettings: [
                .headerSearchPath("third_party/whisper.cpp/include"),
                .headerSearchPath("third_party/whisper.cpp/src"),
                .headerSearchPath("third_party/whisper.cpp/ggml/include"),
                .headerSearchPath("third_party/whisper.cpp/ggml/src"),
                .headerSearchPath("third_party/whisper.cpp/ggml/src/ggml-cpu"),
                .define("WHISPER_VERSION", to: "\"1.8.3\""),
                .define("GGML_VERSION", to: "\"0.9.5\""),
                .define("GGML_COMMIT", to: "\"c02de38\""),
                .define("GGML_SCHED_MAX_COPIES", to: "4"),
                .define("GGML_USE_CPU"),
                .define("GGML_USE_BLAS"),
                .define("GGML_USE_ACCELERATE"),
                .define("GGML_BLAS_USE_ACCELERATE"),
                .define("GGML_USE_CPU_REPACK"),
                .define("_DARWIN_C_SOURCE"),
                .define("_XOPEN_SOURCE", to: "600"),
            ],
            linkerSettings: [
                .linkedFramework("Accelerate"),
            ]
        ),
        .testTarget(
            name: "OwlListenKitTests",
            dependencies: ["OwlListenKit"],
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ],
    cLanguageStandard: .c11,
    cxxLanguageStandard: .cxx17
)
