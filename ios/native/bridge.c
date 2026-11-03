/*
 * Native media engine over libav*. LGPL-compatible: uses only the
 * built-in codecs plus VideoToolbox/AudioToolbox hardware paths.
 */
#include "ffmpeg_bridge.h"

#include <string.h>

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/avutil.h>
#include <libavutil/hwcontext.h>
#include <libavutil/imgutils.h>
#include <libavutil/opt.h>
#include <libavutil/time.h>
#include <libavutil/channel_layout.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>

static const char *stream_type_name(enum AVMediaType t) {
  switch (t) {
  case AVMEDIA_TYPE_VIDEO: return "video";
  case AVMEDIA_TYPE_AUDIO: return "audio";
  case AVMEDIA_TYPE_SUBTITLE: return "subtitle";
  default: return "other";
  }
}

int ff_probe(const char *path, char *out, int out_size) {
  AVFormatContext *fmt = NULL;
  int ret = avformat_open_input(&fmt, path, NULL, NULL);
  if (ret < 0)
    return ret;
  ret = avformat_find_stream_info(fmt, NULL);
  if (ret < 0) {
    avformat_close_input(&fmt);
    return ret;
  }

  int w = snprintf(out, out_size,
                   "{\"duration\":%lld,\"format\":\"%s\",\"bitrate\":%lld,\"streams\":[",
                   (long long)(fmt->duration / AV_TIME_BASE),
                   fmt->iformat ? fmt->iformat->name : "unknown",
                   (long long)fmt->bit_rate);
  for (unsigned i = 0; i < fmt->nb_streams && w > 0 && w < out_size; i++) {
    AVStream *st = fmt->streams[i];
    AVCodecParameters *cp = st->codecpar;
    const AVCodecDescriptor *desc = avcodec_descriptor_get(cp->codec_id);
    char rate[32] = "null", extra[128] = "";
    if (cp->codec_type == AVMEDIA_TYPE_VIDEO) {
      if (st->avg_frame_rate.den)
        snprintf(rate, sizeof rate, "%.2f",
                 av_q2d(st->avg_frame_rate));
      snprintf(extra, sizeof extra, ",\"width\":%d,\"height\":%d,\"frameRate\":%s",
               cp->width, cp->height, rate);
    } else if (cp->codec_type == AVMEDIA_TYPE_AUDIO) {
      snprintf(extra, sizeof extra, ",\"sampleRate\":%d,\"channels\":%d",
               cp->sample_rate, cp->ch_layout.nb_channels);
    }
    w += snprintf(out + w, out_size - w,
                  "%s{\"index\":%u,\"codec\":\"%s\",\"type\":\"%s\"%s}",
                  i ? "," : "", i,
                  desc ? desc->name : "unknown",
                  stream_type_name(cp->codec_type), extra);
  }
  if (w < 0 || w + 2 > out_size) {
    avformat_close_input(&fmt);
    return -1;
  }
  snprintf(out + w, out_size - w, "]}");
  avformat_close_input(&fmt);
  return 0;
}

struct stream_job {
  int in_idx;
  int out_idx;
  AVCodecContext *dec;
  AVCodecContext *enc;
  struct SwsContext *sws;
  SwrContext *swr;
  AVFrame *hw_frame;
  int is_hw;
};

static AVCodecContext *open_decoder(AVFormatContext *fmt, int idx) {
  AVCodecParameters *cp = fmt->streams[idx]->codecpar;
  const AVCodec *dec = avcodec_find_decoder(cp->codec_id);
  AVCodecContext *ctx = NULL;
  if (!dec)
    return NULL;
  ctx = avcodec_alloc_context3(dec);
  if (!ctx)
    return NULL;
  if (avcodec_parameters_to_context(ctx, cp) < 0 ||
      avcodec_open2(ctx, dec, NULL) < 0) {
    avcodec_free_context(&ctx);
    return NULL;
  }
  return ctx;
}

static enum AVPixelFormat pick_hw_format(AVCodecContext *ctx,
                                         const enum AVPixelFormat *fmts) {
  (void)ctx;
  for (const enum AVPixelFormat *p = fmts; *p != AV_PIX_FMT_NONE; p++)
    if (*p == AV_PIX_FMT_VIDEOTOOLBOX)
      return *p;
  return fmts[0];
}

static const AVCodec *pick_video_encoder(const char *want, int *is_hw) {
  const char *chain[3] = { want, "h264_videotoolbox", "mpeg4" };
  for (int i = 0; i < 3; i++) {
    if (!chain[i] || !*chain[i])
      continue;
    const AVCodec *c = avcodec_find_encoder_by_name(chain[i]);
    if (c) {
      *is_hw = !strcmp(chain[i], "h264_videotoolbox");
      return c;
    }
  }
  return NULL;
}

static int setup_video(struct stream_job *job, AVFormatContext *in_fmt,
                       AVFormatContext *out_fmt, const char *want) {
  AVStream *in_st = in_fmt->streams[job->in_idx];
  job->dec = open_decoder(in_fmt, job->in_idx);
  if (!job->dec)
    return AVERROR_DECODER_NOT_FOUND;

  int is_hw = 0;
  const AVCodec *enc = pick_video_encoder(want, &is_hw);
  if (!enc) {
    avcodec_free_context(&job->dec);
    return AVERROR_ENCODER_NOT_FOUND;
  }
  job->is_hw = is_hw;
  job->enc = avcodec_alloc_context3(enc);
  if (!job->enc) {
    avcodec_free_context(&job->dec);
    return AVERROR(ENOMEM);
  }

  AVCodecContext *d = job->dec, *e = job->enc;
  e->width = d->width;
  e->height = d->height;
  e->sample_aspect_ratio = d->sample_aspect_ratio;
  AVRational fps = in_st->avg_frame_rate.den ? in_st->avg_frame_rate
                                             : (AVRational){ 30, 1 };
  e->framerate = fps;
  e->time_base = av_inv_q(fps);
  e->bit_rate = 2000000;
  e->pix_fmt = is_hw ? AV_PIX_FMT_VIDEOTOOLBOX : AV_PIX_FMT_YUV420P;
  if (out_fmt->oformat->flags & AVFMT_GLOBALHEADER)
    e->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

  if (is_hw) {
    AVBufferRef *hw = NULL;
    if (av_hwdevice_ctx_create(&hw, AV_HWDEVICE_TYPE_VIDEOTOOLBOX,
                               NULL, NULL, 0) < 0)
      return AVERROR_EXTERNAL;
    e->hw_device_ctx = hw;
    e->get_format = pick_hw_format;
    /* The encoder does not create its own frames context: describe the
       NV12 software frames it must receive. */
    {
      AVBufferRef *frames = av_hwframe_ctx_alloc(hw);
      AVHWFramesContext *fc;
      if (!frames)
        return AVERROR(ENOMEM);
      fc = (AVHWFramesContext *)frames->data;
      fc->format = AV_PIX_FMT_VIDEOTOOLBOX;
      fc->sw_format = AV_PIX_FMT_NV12;
      fc->width = e->width;
      fc->height = e->height;
      if (av_hwframe_ctx_init(frames) < 0) {
        av_buffer_unref(&frames);
        return AVERROR_EXTERNAL;
      }
      e->hw_frames_ctx = frames;
    }
  }

  int ret = avcodec_open2(e, enc, NULL);
  if (ret < 0) {
    avcodec_free_context(&job->dec);
    avcodec_free_context(&job->enc);
    return ret;
  }
  if (is_hw) {
    job->hw_frame = av_frame_alloc();
    if (!job->hw_frame)
      return AVERROR(ENOMEM);
  }

  AVStream *out_st = avformat_new_stream(out_fmt, NULL);
  if (!out_st)
    return AVERROR(ENOMEM);
  if (avcodec_parameters_from_context(out_st->codecpar, e) < 0)
    return AVERROR(ENOMEM);
  out_st->time_base = e->time_base;
  job->out_idx = out_st->index;
  return 0;
}

static enum AVSampleFormat pick_sample_fmt(const AVCodec *c) {
  const void *cfg = NULL;
  int num = 0;
  if (avcodec_get_supported_config(NULL, c, AV_CODEC_CONFIG_SAMPLE_FORMAT,
                                   0, &cfg, &num) < 0 || !cfg || num <= 0)
    return AV_SAMPLE_FMT_FLTP;
  const enum AVSampleFormat *p = cfg;
  for (int i = 0; i < num; i++)
    if (p[i] == AV_SAMPLE_FMT_FLTP)
      return AV_SAMPLE_FMT_FLTP;
  return p[0];
}

static int setup_audio(struct stream_job *job, AVFormatContext *in_fmt,
                       AVFormatContext *out_fmt, const char *want) {
  job->dec = open_decoder(in_fmt, job->in_idx);
  if (!job->dec)
    return AVERROR_DECODER_NOT_FOUND;

  const AVCodec *enc = avcodec_find_encoder_by_name(
      (want && *want) ? want : "aac");
  if (!enc)
    enc = avcodec_find_encoder(AV_CODEC_ID_AAC);
  if (!enc) {
    avcodec_free_context(&job->dec);
    return AVERROR_ENCODER_NOT_FOUND;
  }
  job->enc = avcodec_alloc_context3(enc);
  if (!job->enc) {
    avcodec_free_context(&job->dec);
    return AVERROR(ENOMEM);
  }

  AVCodecContext *d = job->dec, *e = job->enc;
  e->sample_fmt = pick_sample_fmt(enc);
  e->sample_rate = d->sample_rate;
  if (av_channel_layout_copy(&e->ch_layout, &d->ch_layout) < 0)
    return AVERROR(ENOMEM);
  e->time_base = (AVRational){ 1, e->sample_rate };
  if (out_fmt->oformat->flags & AVFMT_GLOBALHEADER)
    e->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

  int ret = avcodec_open2(e, enc, NULL);
  if (ret < 0) {
    avcodec_free_context(&job->dec);
    avcodec_free_context(&job->enc);
    return ret;
  }
  ret = swr_alloc_set_opts2(&job->swr, &e->ch_layout, e->sample_fmt,
                            e->sample_rate, &d->ch_layout, d->sample_fmt,
                            d->sample_rate, 0, NULL);
  if (ret < 0 || swr_init(job->swr) < 0)
    return ret < 0 ? ret : AVERROR_EXTERNAL;

  AVStream *out_st = avformat_new_stream(out_fmt, NULL);
  if (!out_st)
    return AVERROR(ENOMEM);
  if (avcodec_parameters_from_context(out_st->codecpar, e) < 0)
    return AVERROR(ENOMEM);
  out_st->time_base = e->time_base;
  job->out_idx = out_st->index;
  return 0;
}

static int write_packet(AVFormatContext *out_fmt, struct stream_job *job,
                        AVPacket *pkt) {
  AVCodecContext *e = job->enc;
  AVStream *out_st = out_fmt->streams[job->out_idx];
  av_packet_rescale_ts(pkt, e->time_base, out_st->time_base);
  pkt->stream_index = job->out_idx;
  return av_interleaved_write_frame(out_fmt, pkt);
}

static int encode_frame(AVFormatContext *out_fmt, struct stream_job *job,
                        AVFrame *frame) {
  int ret = avcodec_send_frame(job->enc, frame);
  if (ret < 0)
    return ret;
  for (;;) {
    AVPacket *pkt = av_packet_alloc();
    if (!pkt)
      return AVERROR(ENOMEM);
    ret = avcodec_receive_packet(job->enc, pkt);
    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
      av_packet_free(&pkt);
      return 0;
    }
    if (ret < 0) {
      av_packet_free(&pkt);
      return ret;
    }
    ret = write_packet(out_fmt, job, pkt);
    av_packet_free(&pkt);
    if (ret < 0)
      return ret;
  }
}

static int push_video_frame(AVFormatContext *out_fmt, struct stream_job *job,
                            AVFrame *dec_frame) {
  AVCodecContext *e = job->enc;
  if (job->is_hw) {
    /* The hardware frames context accepts NV12 software frames. */
    AVFrame *sw = dec_frame;
    AVFrame *conv = NULL;
    AVFrame *hw = job->hw_frame;
    if (dec_frame->format != AV_PIX_FMT_NV12) {
      job->sws = sws_getCachedContext(
          job->sws, dec_frame->width, dec_frame->height, dec_frame->format,
          e->width, e->height, AV_PIX_FMT_NV12, SWS_BICUBIC,
          NULL, NULL, NULL);
      if (!job->sws)
        return AVERROR(ENOMEM);
      conv = av_frame_alloc();
      if (!conv)
        return AVERROR(ENOMEM);
      conv->width = e->width;
      conv->height = e->height;
      conv->format = AV_PIX_FMT_NV12;
      if (av_frame_get_buffer(conv, 0) < 0) {
        av_frame_free(&conv);
        return AVERROR(ENOMEM);
      }
      sws_scale(job->sws, (const uint8_t *const *)dec_frame->data,
                dec_frame->linesize, 0, dec_frame->height, conv->data,
                conv->linesize);
      conv->pts = dec_frame->pts;
      sw = conv;
    }
    av_frame_unref(hw);
    if (av_hwframe_get_buffer(e->hw_frames_ctx, hw, 0) < 0) {
      av_frame_free(&conv);
      return AVERROR_EXTERNAL;
    }
    if (av_hwframe_transfer_data(hw, sw, 0) < 0) {
      av_frame_free(&conv);
      return AVERROR_EXTERNAL;
    }
    av_frame_free(&conv);
    hw->pts = dec_frame->pts;
    return encode_frame(out_fmt, job, hw);
  }
  if (dec_frame->format != e->pix_fmt) {
    job->sws = sws_getCachedContext(
        job->sws, dec_frame->width, dec_frame->height, dec_frame->format,
        e->width, e->height, e->pix_fmt, SWS_BICUBIC, NULL, NULL, NULL);
    if (!job->sws)
      return AVERROR(ENOMEM);
    AVFrame *conv = av_frame_alloc();
    if (!conv)
      return AVERROR(ENOMEM);
    conv->width = e->width;
    conv->height = e->height;
    conv->format = e->pix_fmt;
    if (av_frame_get_buffer(conv, 0) < 0) {
      av_frame_free(&conv);
      return AVERROR(ENOMEM);
    }
    sws_scale(job->sws, (const uint8_t *const *)dec_frame->data,
              dec_frame->linesize, 0, dec_frame->height, conv->data,
              conv->linesize);
    conv->pts = dec_frame->pts;
    int ret = encode_frame(out_fmt, job, conv);
    av_frame_free(&conv);
    return ret;
  }
  return encode_frame(out_fmt, job, dec_frame);
}

static int push_audio_frame(AVFormatContext *out_fmt, struct stream_job *job,
                            AVFrame *dec_frame) {
  AVCodecContext *e = job->enc;
  AVFrame *filt = av_frame_alloc();
  if (!filt)
    return AVERROR(ENOMEM);
  if (av_channel_layout_copy(&filt->ch_layout, &e->ch_layout) < 0) {
    av_frame_free(&filt);
    return AVERROR(ENOMEM);
  }
  filt->sample_rate = e->sample_rate;
  filt->format = e->sample_fmt;
  int ret;
  if (swr_convert_frame(job->swr, filt, dec_frame) < 0) {
    av_frame_free(&filt);
    return AVERROR_EXTERNAL;
  }
  /* swr_convert_frame already sets output pts from the input timing;
     fall back to a rescale only when it is missing. */
  if (filt->pts == AV_NOPTS_VALUE)
    filt->pts = av_rescale_q(dec_frame->pts,
                             job->dec->time_base, e->time_base);
  ret = encode_frame(out_fmt, job, filt);
  av_frame_free(&filt);
  return ret;
}

static int decode_and_push(AVFormatContext *in_fmt, AVFormatContext *out_fmt,
                           struct stream_job *job, AVPacket *pkt,
                           int is_video, int64_t duration,
                           ff_progress_cb progress, ff_cancel_cb cancel,
                           void *pctx) {
  int ret = avcodec_send_packet(job->dec, pkt);
  if (ret < 0 && ret != AVERROR_EOF)
    return ret;
  for (;;) {
    AVFrame *frame = av_frame_alloc();
    if (!frame)
      return AVERROR(ENOMEM);
    ret = avcodec_receive_frame(job->dec, frame);
    if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
      av_frame_free(&frame);
      return 0;
    }
    if (ret < 0) {
      av_frame_free(&frame);
      return ret;
    }
    if (cancel && cancel(pctx)) {
      av_frame_free(&frame);
      return AVERROR_EXIT;
    }
    ret = is_video ? push_video_frame(out_fmt, job, frame)
                   : push_audio_frame(out_fmt, job, frame);
    if (progress && duration > 0) {
      int64_t pts = frame->pts == AV_NOPTS_VALUE ? 0 : frame->pts;
      double done = (double)av_rescale_q(pts, job->dec->time_base,
                                         AV_TIME_BASE_Q) /
                    (double)duration;
      progress(done > 1.0 ? 1.0 : done, pctx);
    }
    av_frame_free(&frame);
    if (ret < 0)
      return ret;
  }
}

static void free_job(struct stream_job *job) {
  avcodec_free_context(&job->dec);
  avcodec_free_context(&job->enc);
  sws_freeContext(job->sws);
  swr_free(&job->swr);
  av_frame_free(&job->hw_frame);
}

int ff_transcode(const char *input, const char *output,
                 const char *video_codec, const char *audio_codec,
                 ff_progress_cb progress, ff_cancel_cb cancel, void *ctx) {
  AVFormatContext *in_fmt = NULL, *out_fmt = NULL;
  struct stream_job vjob,ajob;
  int ret;

  memset(&vjob, 0, sizeof vjob);
  memset(&ajob, 0, sizeof ajob);
  vjob.in_idx = ajob.in_idx = -1;

  if ((ret = avformat_open_input(&in_fmt, input, NULL, NULL)) < 0)
    return ret;
  if ((ret = avformat_find_stream_info(in_fmt, NULL)) < 0)
    goto done;
  if (avformat_alloc_output_context2(&out_fmt, NULL, "mp4", NULL) < 0) {
    ret = AVERROR(ENOMEM);
    goto done;
  }

  vjob.in_idx = av_find_best_stream(in_fmt, AVMEDIA_TYPE_VIDEO, -1, -1,
                                    NULL, 0);
  ajob.in_idx = av_find_best_stream(in_fmt, AVMEDIA_TYPE_AUDIO, -1, -1,
                                    NULL, 0);
  if (vjob.in_idx < 0 && ajob.in_idx < 0) {
    ret = AVERROR_STREAM_NOT_FOUND;
    goto done;
  }
  if (vjob.in_idx >= 0 &&
      (ret = setup_video(&vjob, in_fmt, out_fmt, video_codec)) < 0)
    goto done;
  if (ajob.in_idx >= 0 &&
      (ret = setup_audio(&ajob, in_fmt, out_fmt, audio_codec)) < 0)
    goto done;

  if (!(out_fmt->oformat->flags & AVFMT_NOFILE)) {
    if ((ret = avio_open(&out_fmt->pb, output, AVIO_FLAG_WRITE)) < 0)
      goto done;
  }
  if ((ret = avformat_write_header(out_fmt, NULL)) < 0)
    goto done;

  {
    AVPacket *pkt = av_packet_alloc();
    if (!pkt) {
      ret = AVERROR(ENOMEM);
      goto done;
    }
    int64_t duration = in_fmt->duration;
    while ((ret = av_read_frame(in_fmt, pkt)) >= 0) {
      struct stream_job *job = NULL;
      int is_video = 0;
      if (pkt->stream_index == vjob.in_idx) {
        job = &vjob;
        is_video = 1;
      } else if (pkt->stream_index == ajob.in_idx) {
        job = &ajob;
      }
      if (job) {
        ret = decode_and_push(in_fmt, out_fmt, job, pkt, is_video,
                              duration, progress, cancel, ctx);
        av_packet_unref(pkt);
        if (ret < 0)
          break;
      } else {
        av_packet_unref(pkt);
      }
    }
    av_packet_free(&pkt);
    if (ret == AVERROR_EOF)
      ret = 0;
    if (ret < 0)
      goto done;
    /* Drain decoders then encoders. */
    if (vjob.dec &&
        (ret = decode_and_push(in_fmt, out_fmt, &vjob, NULL, 1,
                               duration, progress, cancel, ctx)) < 0)
      goto done;
    if (ajob.dec &&
        (ret = decode_and_push(in_fmt, out_fmt, &ajob, NULL, 0,
                               duration, progress, cancel, ctx)) < 0)
      goto done;
    if (vjob.enc && (ret = encode_frame(out_fmt, &vjob, NULL)) < 0)
      goto done;
    if (ajob.enc && (ret = encode_frame(out_fmt, &ajob, NULL)) < 0)
      goto done;
    ret = av_write_trailer(out_fmt);
    if (progress)
      progress(1.0, ctx);
  }

done:
  free_job(&vjob);
  free_job(&ajob);
  avformat_close_input(&in_fmt);
  if (out_fmt) {
    if (!(out_fmt->oformat->flags & AVFMT_NOFILE))
      avio_closep(&out_fmt->pb);
    avformat_free_context(out_fmt);
  }
  return ret;
}
