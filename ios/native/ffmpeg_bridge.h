#ifndef FFMPEG_BRIDGE_H
#define FFMPEG_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

/* Progress callback: progress in [0, 1]. */
typedef void (*ff_progress_cb)(double progress, void *ctx);
/* Cancel callback: return non-zero to abort the operation. */
typedef int (*ff_cancel_cb)(void *ctx);

/*
 * Probe: write stream metadata JSON into out (out_size bytes).
 * Returns 0 on success, negative AVERROR on failure, -1 if out is too small.
 */
int ff_probe(const char *path, char *out, int out_size);

/*
 * Transcode: decode input, encode video as H.264 and audio as AAC.
 * video_codec selects the H.264 encoder ("h264_videotoolbox" default,
 * falls back to software); audio_codec selects the audio encoder
 * ("aac" default). progress/cancel may be NULL.
 * Returns 0 on success, negative AVERROR on failure.
 */
int ff_transcode(const char *input, const char *output,
                 const char *video_codec, const char *audio_codec,
                 ff_progress_cb progress, ff_cancel_cb cancel, void *ctx);

#ifdef __cplusplus
}
#endif

#endif /* FFMPEG_BRIDGE_H */
