module simple_player::player;

import sdl;
import std::math;
import std::time;
import std::thread;
import std::thread::channel;
import simple_player::util;
import simple_player::decoder;
import simple_player::ffmpeg::ffi;

long total_len;

fn void audio_callback(void* userdata, char* stream, int len) {
    char[] buf = mem::new_array(char, len);
    defer mem::free(buf);
    if (try buffer = simple_player::audio_buffer.pop_into(buf)) {
        sdl::memcpy(stream, buffer, (usz)len);
        total_len += len;
    } else {
        sdl::memset(stream, 0, (usz)len);
    }
}


const long SEC              = 1_000_000l;
const long BYTES_PER_SECOND = 48000 * 2 * 2;

fn long get_pos() => SEC * total_len / BYTES_PER_SECOND - SEC;

struct RecArgs {
    FrameChannel* rec;
    sdl::Renderer* renderer;
    sdl::Texture* texture;
    sdl::AudioDeviceID id;
    Rational video_time_base;
    double fps;
}

fn int rec(void* input) {
    RecArgs* args = input;
    while (true) {
        if (try DecodeFrame frame = args.rec.pop()) {
            defer frame.free();

            long pts      = (long)(ffmpeg::get_time(args.video_time_base, frame.pts) * (long)time::SEC);
            long offset   = get_pos() - pts;
            char** data   = ffmpeg::get_data(frame.frame);
            int* linesize = ffmpeg::get_linesize(frame.frame);
            // Time timer    = time::now();
            Duration wait = (Duration)(math::round(SEC / args.fps) - offset);

            sdl::updateYUVTexture(args.texture, null, data[0], linesize[0], data[1], linesize[1], data[2], linesize[2]);
            sdl::renderClear(args.renderer);
            sdl::renderCopy(args.renderer, args.texture, null, null);

            log::debug("w: %d, o: %d, a: %d, v: %d, p: %d", wait, offset, get_pos(), pts, frame.pts);
            thread::sleep(wait);
            sdl::renderPresent(args.renderer);
        }
    }
}

faultdef AUDIO_DEVICE_OPEN_FAILED;

fn thread::Thread? video_play(
    sdl::Renderer* renderer,
    sdl::Texture* texture,
    FrameChannel* channel,
    Rational time_base,
    double fps
) {
    sdl::AudioSpec obtained;
    sdl::AudioSpec desired = {
        .freq = 48000,
        .format = ffi::AUDIO_S16SYS,
        .channels = 2,
        .samples = 1024,
        .callback = &audio_callback,
    };

    sdl::AudioDeviceID device = sdl::openAudioDevice(null, 0, &desired, &obtained, 0);
    if (device == 0) {
        log::error("SDL error: %s", sdl::getError());
        return AUDIO_DEVICE_OPEN_FAILED~;
    }

    util::@display(sdl::AudioSpec, obtained);

    sdl::pauseAudioDevice(device, 0);

    RecArgs* args = mem::tmalloc(RecArgs::size);
    *args = (RecArgs) {
        .id = device,
        .rec = channel,
        .renderer = renderer,
        .texture = texture,
        .video_time_base = time_base,
        .fps = fps,
    };

    thread::Thread thread;
    thread.create(&rec, args)!;
    return thread;
}
