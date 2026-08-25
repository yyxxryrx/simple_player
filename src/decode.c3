module simple_player::decoder;

import std::thread;
import std::thread::channel;
import simple_player::ffmpeg::ffi;
import simple_player::util;
import ffi::sws;

struct DecoderArgs
{
	FormatContext* format_ctx;
	CodecContext* codec_ctx;
	int video_index;
	UnbufferedChannel{Frame*}* channel;
}

fn int decoder(void* input)
{
	DecoderArgs* args = (DecoderArgs*)input;
	Frame* frame      = ffi::frame_alloc();
	defer ffi::frame_free(&frame);

	Frame* yuv_frame = ffi::frame_alloc();
	defer ffi::frame_free(&yuv_frame);
	ffmpeg::set_to_yuv(args.codec_ctx, yuv_frame);

	Packet* pkt = ffi::packet_alloc();
	defer ffi::packet_free(&pkt);

	sws::SwsContext* sws_ctx = ffmpeg::new_sws_context(args.codec_ctx);
	defer sws::free_context(sws_ctx);


	while (ffi::read_frame(args.format_ctx, pkt) >= 0)
	{
		defer ffi::packet_unref(pkt);
		if (pkt.stream_index != args.video_index) continue;

		ffi::send_packet(args.codec_ctx, pkt);
		while (ffi::receive_frame(args.codec_ctx, frame) >= 0)
		{
			log::info("Decode %d pts", pkt.pts);
			ffmpeg::scale(sws_ctx, frame, yuv_frame);
			(void)args.channel.push(ffi::frame_clone(yuv_frame));
		}
	}
	return 0;
}

fn UnbufferedChannel{Frame*}*? start(FormatContext* fmt_ctx, CodecContext* codec_ctx, int index)
{
	UnbufferedChannel{Frame*}* channel = channel::create_unbuffered{Frame*}(mem)!;
	defer catch channel.destroy();

	DecoderArgs* args = mem::malloc(DecoderArgs::size);
	*args = (DecoderArgs) { .channel = channel, .codec_ctx = codec_ctx, .format_ctx = fmt_ctx, .video_index = index };

	Thread thread;
	thread.create(
		&decoder,
		args,
	)!;
	return channel;
}
