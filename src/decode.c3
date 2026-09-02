module simple_player::decoder;

import std::thread;
import std::thread::channel;
import simple_player::ffmpeg::ffi;
import simple_player::util;
import simple_player::ringbuffer;
import ffi::sws;

alias FrameChannel = BufferedChannel{DecodeFrame};

enum DecodeFrameType
{
	VIDEO,
	AUDIO,
}

struct DecodeFrame
{
	long pts;
	Frame* frame;
	DecodeFrameType type;
}

struct DecoderArgs
{
	FormatContext* format_ctx;
	CodecContext* video_ctx;
	CodecContext* audio_ctx;
	int video_index;
	int audio_index;
	FrameChannel* channel;
}

fn void DecodeFrame.free(&self)
{
	ffi::frame_free(&self.frame);
}

fn int decoder(void* input)
{
	DecoderArgs* args = (DecoderArgs*)input;
	Frame* frame      = ffi::frame_alloc();
	defer ffi::frame_free(&frame);

	Frame* yuv_frame = ffi::frame_alloc();
	defer ffi::frame_free(&yuv_frame);
	ffmpeg::set_to_yuv(args.video_ctx, yuv_frame);

	Frame* audio_frame = ffi::frame_alloc();
	defer ffi::frame_free(&audio_frame);

	Packet* pkt = ffi::packet_alloc();
	defer ffi::packet_free(&pkt);

	sws::SwsContext* sws_ctx;
	defer sws::free_context(sws_ctx);

	ffi::SwrContext* swr;
	int ret = ffmpeg::new_swr(&swr, args.audio_ctx, 48000);
	if (ret < 0)
	{
		log::error("FFmpeg swr create failed: %s", ffmpeg::err2str(ret));
		return -1;
	}


	while (ffi::read_frame(args.format_ctx, pkt) >= 0)
	{
		defer ffi::packet_unref(pkt);
		defer ffi::frame_unref(frame);

		switch (pkt.stream_index)
		{
			case args.video_index:
				ffi::send_packet(args.video_ctx, pkt);
				while (ffi::receive_frame(args.video_ctx, frame) >= 0)
				{
					if (sws_ctx == null) sws_ctx = ffmpeg::new_sws_context(frame);
					long pts = ffmpeg::get_pts(frame);
					log::debug("Decode %d pts video", pts);
					ffmpeg::scale(sws_ctx, frame, yuv_frame);
					(void)args.channel.push(
						(DecodeFrame) { .pts = pts, .frame = ffi::frame_clone(yuv_frame), .type = VIDEO }
					);
				}

			case args.audio_index:
				ffi::send_packet(args.audio_ctx, pkt);
				while (ffi::receive_frame(args.audio_ctx, frame) >= 0)
				{
					log::debug("Decode %d pts audio", pkt.pts);

					ret = ffmpeg::resample_frame(swr, frame, audio_frame, 48000);
					if (ret < 0)
					{
						log::error("resample failed: %s", ffmpeg::err2str(ret));
						continue;
					}
					defer ffi::frame_unref(audio_frame);

					simple_player::audio_buffer.push_all(ffmpeg::get_data(audio_frame)[0][:ret]);

					// (void)args.channel.push((DecodeFrame) { .frame = ffi::frame_clone(audio_frame), .type = AUDIO });
				}
		}
	}
	return 0;
}

struct DecodeResult
{
	FrameChannel* channel;
}

fn FrameChannel*? start(
	FormatContext* fmt_ctx,
	CodecContext* video_ctx,
	CodecContext* audio_ctx,
	int video_index,
	int audio_index
)
{
	FrameChannel* channel = channel::create_buffered{DecodeFrame}(mem, 30)!;
	defer catch channel.destroy();

	DecoderArgs* args = mem::tmalloc(DecoderArgs::size);
	*args = (DecoderArgs) {
		.channel = channel,
		.video_ctx = video_ctx,
		.audio_ctx = audio_ctx,
		.format_ctx = fmt_ctx,
		.video_index = video_index,
		.audio_index = audio_index
	};

	Thread thread;
	thread.create(
		&decoder,
		args,
	)!;
	return channel;
}
