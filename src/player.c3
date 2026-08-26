module simple_player::player;

import sdl;
import std::thread;
import std::thread::channel;
import simple_player::decoder;
import simple_player::ffmpeg::ffi;

fn void audio_callback(void* userdata, char* stream, int len)
{
	char[] buf = mem::new_array(char, len);
	defer mem::free(buf);
	if (try buffer = simple_player::audio_buffer.pop_into(buf))
	{
		sdl::memcpy(stream, buffer, (usz)len);
	}
	else
	{
		sdl::memset(stream, 0, (usz)len);
	}
}

struct RecArgs
{
	FrameChannel* rec;
	sdl::Renderer* renderer;
	sdl::Texture* texture;
	sdl::AudioDeviceID id;
	Rational video_time_base;
}

fn int rec(void* input)
{
	RecArgs* args = input;
	while (true)
	{
		if (try DecodeFrame frame = args.rec.pop())
		{
			defer frame.free();

			char** data   = ffmpeg::get_data(frame.frame);
			int* linesize = ffmpeg::get_linesize(frame.frame);
			sdl::updateYUVTexture(args.texture, null, data[0], linesize[0], data[1], linesize[1], data[2], linesize[2]);
			sdl::renderClear(args.renderer);
			sdl::renderCopy(args.renderer, args.texture, null, null);
			sdl::renderPresent(args.renderer);
			thread::sleep_ms(40);
		}
	}
}

faultdef AUDIO_DEVICE_OPEN_FAILED;

fn thread::Thread? video_play(sdl::Renderer* renderer, sdl::Texture* texture, FrameChannel* channel)
{
	sdl::AudioSpec obtained;
	sdl::AudioSpec desired = {
		.freq = 48000,
		.format = ffi::AUDIO_S16SYS,
		.channels = 2,
		.samples = 1024,
		.callback = &audio_callback,
	};

	sdl::AudioDeviceID device = sdl::openAudioDevice(null, 0, &desired, &obtained, 0);
	if (device == 0)
	{
		log::error("SDL error: %s", sdl::getError());
		return AUDIO_DEVICE_OPEN_FAILED~;
	}

	sdl::pauseAudioDevice(device, 0);

	RecArgs* args = mem::tmalloc(RecArgs::size);
	*args = (RecArgs) { .id = device, .rec = channel, .renderer = renderer, .texture = texture };

	thread::Thread thread;
	thread.create(&rec, args)!;
	return thread;
}
