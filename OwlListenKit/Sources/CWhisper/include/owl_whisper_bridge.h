#ifndef OWL_WHISPER_BRIDGE_H
#define OWL_WHISPER_BRIDGE_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct owl_whisper_context owl_whisper_context;
typedef void (*owl_whisper_progress_callback)(int progress, void * user_data);
typedef bool (*owl_whisper_cancel_callback)(void * user_data);

owl_whisper_context * owl_whisper_load_model(
    const char * model_path,
    char ** error_message
);

void owl_whisper_free_model(owl_whisper_context * context);

char * owl_whisper_transcribe(
    owl_whisper_context * context,
    const float * samples,
    int sample_count,
    owl_whisper_progress_callback progress_callback,
    owl_whisper_cancel_callback cancel_callback,
    void * user_data,
    char ** error_message
);

void owl_whisper_free_string(char * value);

#ifdef __cplusplus
}
#endif

#endif
