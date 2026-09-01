#include "libavcodec/codec_par.h"
#include "libavutil/channel_layout.h"
#include "libavutil/frame.h"
#include "libavutil/pixfmt.h"
#include "libavutil/samplefmt.h"
#include <libavcodec/avcodec.h>
#include <libavcodec/codec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/error.h>
#include <libavutil/rational.h>
#include <libswresample/swresample.h>
#include <libswscale/swscale.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    int64_t frame_count, dur;
    int32_t width, height;
    AVRational rate, time_base;
} VideoInfo;

typedef struct {
    int code;
    AVCodecContext *ctx;
    VideoInfo info;
} InfoResult;

char *err2str(int err) { return av_err2str(err); }

int32_t find_best_video(AVFormatContext *ctx) {
    return av_find_best_stream(ctx, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
}

int32_t find_best_audio(AVFormatContext *ctx) {
    return av_find_best_stream(ctx, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
}

int32_t new_codec_ctx(AVFormatContext *ctx, int32_t index,
                      AVCodecContext *codec_ctx) {
    if (ctx == NULL || codec_ctx == NULL || index < 0 ||
        index >= ctx->nb_streams)
        return -1;

    AVStream *stream = ctx->streams[index];
    if (stream == NULL)
        return -1;

    const AVCodecParameters *codec_params = stream->codecpar;

    const AVCodec *codec = avcodec_find_decoder(codec_params->codec_id);
    if (codec == NULL)
        return -1;

    int ret = avcodec_parameters_to_context(codec_ctx, codec_params);
    if (ret != 0) {
        avcodec_free_context(&codec_ctx);
        return ret;
    }

    ret = avcodec_open2(codec_ctx, codec, NULL);
    if (ret != 0) {
        avcodec_free_context(&codec_ctx);
        return ret;
    }
    return 0;
}

bool get_info(AVFormatContext *ctx, int32_t index, InfoResult *res) {
    if (ctx == NULL || res == NULL || index < 0 || index >= ctx->nb_streams)
        return false;

    AVStream *stream = ctx->streams[index];
    if (stream == NULL)
        return false;

    const AVCodecParameters *codec_params = stream->codecpar;
    if (codec_params->codec_type != AVMEDIA_TYPE_VIDEO)
        return false;

    const AVCodec *codec = avcodec_find_decoder(codec_params->codec_id);
    if (codec == NULL)
        return false;

    AVCodecContext *codec_ctx = avcodec_alloc_context3(codec);
    if (codec_ctx == NULL)
        return false;

    int ret = avcodec_parameters_to_context(codec_ctx, codec_params);
    if (ret != 0) {
        avcodec_free_context(&codec_ctx);
        res->code = ret;
        return false;
    }

    ret = avcodec_open2(codec_ctx, codec, NULL);
    if (ret != 0) {
        avcodec_free_context(&codec_ctx);
        res->code = ret;
        return false;
    }

    res->ctx = codec_ctx;
    res->code = 0;
    res->info = (VideoInfo){
        .frame_count = stream->nb_frames,
        .dur = stream->duration,
        .width = codec_params->width,
        .height = codec_params->height,
        .rate = stream->avg_frame_rate,
        .time_base = stream->time_base,
    };
    return true;
}

struct SwsContext *new_sws_context(const AVFrame *frame) {
    return sws_getContext(frame->width, frame->height, frame->format,
                          frame->width, frame->height, AV_PIX_FMT_YUV420P,
                          SWS_BILINEAR, NULL, NULL, NULL);
}

void set_to_yuv(const AVCodecContext *ctx, AVFrame *frame) {
    frame->format = AV_PIX_FMT_YUV420P;
    frame->width = ctx->width;
    frame->height = ctx->height;
    av_frame_get_buffer(frame, 0);
}

int scale(struct SwsContext *ctx, AVFrame *src, AVFrame *dst) {
    return sws_scale(ctx, (const uint8_t *const *)src->data, src->linesize, 0,
                     src->height, dst->data, dst->linesize);
}

uint8_t **get_data(AVFrame *frame) { return frame->data; }

int32_t *get_linesize(AVFrame *frame) { return frame->linesize; }

int32_t new_swr(SwrContext **swr, AVCodecContext *const ctx,
                int32_t out_sample_rate) {
    AVChannelLayout layout = AV_CHANNEL_LAYOUT_STEREO;
    int ret = swr_alloc_set_opts2(swr, &layout, AV_SAMPLE_FMT_S16,
                                  out_sample_rate, &ctx->ch_layout,
                                  ctx->sample_fmt, ctx->sample_rate, 0, NULL);
    if (ret < 0)
        return ret;

    ret = swr_init(*swr);
    if (ret < 0) {
        swr_free(swr);
        return ret;
    }
    return 0;
}

int32_t resample_frame(SwrContext *swr, const AVFrame *in_frame,
                       AVFrame *out_frame, int out_sample_rate) {
    if (in_frame == NULL || out_frame == NULL)
        return 0;

    int out_nb_samples = swr_get_out_samples(swr, in_frame->nb_samples);
    if (out_nb_samples <= 0)
        return 0;

    out_frame->format = AV_SAMPLE_FMT_S16;
    out_frame->ch_layout = (AVChannelLayout)AV_CHANNEL_LAYOUT_STEREO;
    out_frame->sample_rate = out_sample_rate;
    out_frame->nb_samples = out_nb_samples;

    int ret = av_frame_get_buffer(out_frame, 0);
    if (ret < 0)
        return ret;

    ret = swr_convert(swr, out_frame->data, out_nb_samples,
                      (const uint8_t **)in_frame->data, in_frame->nb_samples);
    if (ret < 0) {
        av_frame_unref(out_frame);
        return ret;
    }

    out_frame->nb_samples = ret;
    out_frame->sample_rate = out_sample_rate;

    return out_frame->linesize[0];
}

int32_t get_size(AVFrame *frame) {
    return frame->nb_samples * 2 * av_get_bytes_per_sample(frame->format);
}

double get_time(AVRational time_base, int64_t pts) {
    return av_q2d(time_base) * pts;
}

int64_t get_pts(const AVFrame *frame) { return frame->pts; }