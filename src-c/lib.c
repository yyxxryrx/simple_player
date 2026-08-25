#include "libavcodec/codec_par.h"
#include "libavutil/frame.h"
#include "libavutil/pixfmt.h"
#include <libavcodec/avcodec.h>
#include <libavcodec/codec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/error.h>
#include <libavutil/rational.h>
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

struct SwsContext *new_sws_context(const AVCodecContext *codec_ctx) {
    return sws_getContext(codec_ctx->width, codec_ctx->height,
                          codec_ctx->pix_fmt, codec_ctx->width,
                          codec_ctx->height, AV_PIX_FMT_YUV420P, SWS_BILINEAR,
                          NULL, NULL, NULL);
}

void set_to_yuv(AVCodecContext *ctx, AVFrame *frame) {
    frame->format = AV_PIX_FMT_YUV420P;
    frame->width = ctx->width;
    frame->height = ctx->height;
    av_frame_get_buffer(frame, 0);
}

int scale(SwsContext *ctx, AVFrame *src, AVFrame *dst) {
    return sws_scale(ctx, (const uint8_t *const *)src->data, src->linesize, 0,
                     src->height, dst->data, dst->linesize);
}

uint8_t **get_data(AVFrame *frame) { return frame->data; }

int32_t *get_linesize(AVFrame *frame) { return frame->linesize; }
