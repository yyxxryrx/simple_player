module simple_player::player;

import sdl;
import std::thread;
import std::thread::channel;
import simple_player::decoder;
import simple_player::ffmpeg::ffi;

struct RecArgs
{
	FrameChannel* rec;
	sdl::Renderer* renderer;
	sdl::Texture* texture;
	sdl::AudioDeviceID id;
}

fn int rec(void* input)
{
	RecArgs* args = input;
	while (true)
	{
		if (try DecodeFrame frame = args.rec.pop())
		{
			if (frame.type == DecodeFrameType.AUDIO)
			{
				if (frame.frame == null)
				{
					log::warn("Empty audio frame");
					continue;
				}

				int data_size = ffmpeg::get_size(frame.frame);
				if (sdl::queueAudio(args.id, ffmpeg::get_data(frame.frame)[0], (uint)data_size) < 0)
				{
					log::error("SDL queue audio failed: %s", sdl::getError());
				}
				continue;
			}

			char** data   = ffmpeg::get_data(frame.frame);
			int* linesize = ffmpeg::get_linesize(frame.frame);
			sdl::updateYUVTexture(args.texture, null, data[0], linesize[0], data[1], linesize[1], data[2], linesize[2]);
			sdl::renderClear(args.renderer);
			sdl::renderCopy(args.renderer, args.texture, null, null);
			sdl::renderPresent(args.renderer);
			frame.free();
		}
	}
}

faultdef AUDIO_DEVICE_OPEN_FAILED;

fn thread::Thread*? video_play(sdl::Renderer* renderer, sdl::Texture* texture, FrameChannel* channel)
{
	sdl::AudioSpec obtained;
	sdl::AudioSpec desired = {
		.freq = 48000,
		.format = ffi::AUDIO_S16SYS,
		.channels = 2,
		.samples = 1024,
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
