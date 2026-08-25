module simple_player;
import std::io;
import std::thread;
import sdl;

fn int main(String[] args)
{
	if (args.len < 2) return 0;

	ffi::init();
	defer ffi::deinit();

	FormatContext* ctx;
	int ret = ffi::open_input(&ctx, (ZString)args[1], null, null);
	if (ret != 0)
	{
		log::error("FFmpeg error: %s", ffmpeg::err2str(ret));
		return 1;
	}
	defer ffi::close_input(&ctx);

	int video_index = ffmpeg::find_best_video(ctx);
	if (video_index < 0)
	{
		log::error("FFmpeg error: %s", ffmpeg::err2str(video_index));
		return 1;
	}

	int audio_index = ffmpeg::find_best_audio(ctx);

	InfoResult res;
	if (!ffmpeg::get_info(ctx, video_index, &res))
	{
		log::error("Cannot get video info");
		return 1;
	}
	defer ffi::free_context(&res.ctx);

	if (res.code != 0)
	{
		log::error("FFmpeg error: %s", ffmpeg::err2str(res.code));
		return 1;
	}
	VideoInfo info = res.info;

	if (sdl::init(sdl::INIT_VIDEO | sdl::INIT_AUDIO) < 0)
	{
		log::error("SDL Init failed: %s", (ZString)sdl::getError());
		return -1;
	}
	defer sdl::quit();

	sdl::Window* w = sdl::createWindow("Hi", 100, 100, info.width, info.height, 0);
	if (w == null)
	{
		log::error("SDL create window failed: %s", (ZString)sdl::getError());
		return -1;
	}
	defer sdl::destroyWindow(w);
	log::info("SDL create window sucessed");

	sdl::Renderer* renderer = sdl::createRenderer(w, -1, 0);
	if (renderer == null)
	{
		log::error("SDL create renderer failed: %s", (ZString)sdl::getError());
		return -1;
	}

	sdl::Texture* texture = sdl::createTexture(
		renderer,
		(uint)sdl::PixelFormatEnum.IYUV,
		(int)sdl::TextureAccess.TEXTUREACCESS_STREAMING,
		info.width,
		info.height
	);

	CodecContext* audio_ctx = ffi::alloc_codec_ctx(null);
	if (ffmpeg::new_codec_ctx(ctx, audio_index, audio_ctx) != 0)
	{
		log::error("FFmpeg create audio codec context failed");
		return -1;
	}

	decoder::FrameChannel* channel = decoder::start(ctx, res.ctx, audio_ctx, video_index, audio_index)!!;
	defer channel.destroy();

	thread::Thread* thread = player::video_play(renderer, texture, channel)!!;

	sdl::Event event;
	while MAIN: (true)
	{
		if (sdl::pollEvent(&event))
		{
			switch (event.type)
			{
				case sdl::EventType.QUIT:
					log::debug("SDL Event: Quit the window");
					break MAIN;
			}
		}
		thread::sleep_ms(50);
	}

	(void)thread.join();
	return 0;
}
