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

	int index = ffmpeg::find_best_video(ctx);
	if (index < 0)
	{
		log::error("FFmpeg error: %s", ffmpeg::err2str(index));
		return 1;
	}

	InfoResult res;
	if (!ffmpeg::get_info(ctx, index, &res))
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

	UnbufferedChannel{Frame*}* channel = decoder::start(ctx, res.ctx, index)!!;
	defer channel.destroy();

	sdl::Event event;
	while MAIN: (true)
	{
		if (try frame = channel.try_pop())
		{
			char** data   = ffmpeg::get_data(frame);
			int* linesize = ffmpeg::get_linesize(frame);
			sdl::updateYUVTexture(texture, null, data[0], linesize[0], data[1], linesize[1], data[2], linesize[2]);
			sdl::renderClear(renderer);
			sdl::renderCopy(renderer, texture, null, null);
			sdl::renderPresent(renderer);
		}

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
	return 0;
}
