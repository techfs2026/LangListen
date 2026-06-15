#include "owl_whisper_bridge.h"

#include "whisper.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>

struct owl_whisper_context {
    whisper_context * value;
};

struct callback_context {
    owl_whisper_progress_callback progress_callback;
    owl_whisper_cancel_callback cancel_callback;
    void * user_data;
};

static char * copy_string(const std::string & value) {
    char * result = static_cast<char *>(std::malloc(value.size() + 1));
    if (result == nullptr) {
        return nullptr;
    }
    std::memcpy(result, value.c_str(), value.size() + 1);
    return result;
}

static void set_error(char ** error_message, const std::string & message) {
    if (error_message != nullptr) {
        *error_message = copy_string(message);
    }
}

static void report_progress(
    whisper_context *,
    whisper_state *,
    int progress,
    void * user_data
) {
    auto * callbacks = static_cast<callback_context *>(user_data);
    if (callbacks != nullptr && callbacks->progress_callback != nullptr) {
        callbacks->progress_callback(progress, callbacks->user_data);
    }
}

static bool should_abort(void * user_data) {
    auto * callbacks = static_cast<callback_context *>(user_data);
    return callbacks != nullptr &&
        callbacks->cancel_callback != nullptr &&
        callbacks->cancel_callback(callbacks->user_data);
}

owl_whisper_context * owl_whisper_load_model(
    const char * model_path,
    char ** error_message
) {
    if (model_path == nullptr) {
        set_error(error_message, "model path is null");
        return nullptr;
    }

    setenv("GGML_METAL_NO_RESIDENCY", "1", 0);
    whisper_context_params params = whisper_context_default_params();
    params.use_gpu = true;
    whisper_context * value = whisper_init_from_file_with_params(model_path, params);
    if (value == nullptr) {
        set_error(error_message, "failed to load whisper model");
        return nullptr;
    }

    auto * context = new owl_whisper_context;
    context->value = value;
    return context;
}

void owl_whisper_free_model(owl_whisper_context * context) {
    if (context == nullptr) {
        return;
    }
    whisper_free(context->value);
    delete context;
}

char * owl_whisper_transcribe(
    owl_whisper_context * context,
    const float * samples,
    int sample_count,
    owl_whisper_progress_callback progress_callback,
    owl_whisper_cancel_callback cancel_callback,
    void * user_data,
    char ** error_message
) {
    if (context == nullptr || context->value == nullptr) {
        set_error(error_message, "whisper model is not loaded");
        return nullptr;
    }
    if (samples == nullptr || sample_count <= 0) {
        set_error(error_message, "audio contains no samples");
        return nullptr;
    }

    callback_context callbacks {
        progress_callback,
        cancel_callback,
        user_data,
    };
    whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    params.n_threads = std::max(
        1,
        std::min(4, static_cast<int>(std::thread::hardware_concurrency()))
    );
    params.language = "en";
    params.translate = false;
    params.no_context = true;
    params.no_timestamps = true;
    params.print_special = false;
    params.print_progress = false;
    params.print_realtime = false;
    params.print_timestamps = false;
    params.greedy.best_of = 1;
    params.progress_callback = report_progress;
    params.progress_callback_user_data = &callbacks;
    params.abort_callback = should_abort;
    params.abort_callback_user_data = &callbacks;

    const int result = whisper_full(context->value, params, samples, sample_count);
    if (result != 0) {
        set_error(error_message, should_abort(&callbacks)
            ? "transcription cancelled"
            : "whisper transcription failed");
        return nullptr;
    }

    std::string text;
    const int segment_count = whisper_full_n_segments(context->value);
    for (int index = 0; index < segment_count; ++index) {
        const char * segment = whisper_full_get_segment_text(context->value, index);
        if (segment == nullptr) {
            continue;
        }
        if (!text.empty()) {
            text.push_back(' ');
        }
        text.append(segment);
    }

    return copy_string(text);
}

void owl_whisper_free_string(char * value) {
    std::free(value);
}
