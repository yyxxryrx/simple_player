module simple_player;
import std::io;
import std::math;
import std::thread;
import std::atomic;
import sdl;
import simple_player::ringbuffer;

RingBuffer{char, 2 * mem::MB} audio_buffer = { };
Atomic{bool} is_running;
Atomic{sdl::Rect} rect;

fn int main(String[] args) {
    if (args.len < 2) return 0;

    is_running.store(true, AtomicOrdering.RELEASE);

    ffi::init();
    defer ffi::deinit();

    FormatContext* ctx;
    int ret = ffi::open_input(&ctx, (ZString)args[1].ptr, null, null);
    if (ret != 0) {
        log::error("FFmpeg error: %s", ffmpeg::err2str(ret));
        return 1;
    }
    defer ffi::close_input(&ctx);

    int video_index = ffmpeg::find_best_video(ctx);
    if (video_index < 0) {
        log::error("FFmpeg error: %s", ffmpeg::err2str(video_index));
        return 1;
    }

    int audio_index = ffmpeg::find_best_audio(ctx);
    if (audio_index < 0) log::warn("FFmpeg warn: %s", ffmpeg::err2str(audio_index));


    InfoResult res;
    if (!ffmpeg::get_info(ctx, video_index, &res)) {
        log::error("Cannot get video info");
        return 1;
    }
    defer ffi::free_context(&res.ctx);

    if (res.code != 0) {
        log::error("FFmpeg error: %s", ffmpeg::err2str(res.code));
        return 1;
    }
    VideoInfo info = res.info;
    util::@display(VideoInfo, info);

    if (sdl::init(sdl::INIT_VIDEO | sdl::INIT_AUDIO) < 0) {
        log::error("SDL Init failed: %s", (ZString)sdl::getError());
        return -1;
    }
    defer sdl::quit();

    Window* w = sdl::createWindow((ZString)args[1].ptr, 100, 100, info.width, info.height, 0);
    if (w == null) {
        log::error("SDL create window failed: %s", (ZString)sdl::getError());
        return -1;
    }
    defer sdl::destroyWindow(w);
    log::info("SDL create window sucessed");
    sdl::setWindowResizable(w, true);

    Renderer* renderer = sdl::createRenderer(w, -1, 0);
    if (renderer == null) {
        log::error("SDL create renderer failed: %s", (ZString)sdl::getError());
        return -1;
    }

    Texture* texture = sdl::createTexture(
        renderer,
        (uint)sdl::PixelFormatEnum.IYUV,
        (int)sdl::TextureAccess.TEXTUREACCESS_STREAMING,
        info.width,
        info.height
    );

    CodecContext* audio_ctx = ffi::alloc_codec_ctx(null);
    if (ffmpeg::new_codec_ctx(ctx, audio_index, audio_ctx) != 0) {
        log::error("FFmpeg create audio codec context failed");
        return -1;
    }
    defer ffi::free_context(&audio_ctx);

    DecodeHandle handle = decoder::start(ctx, res.ctx, audio_ctx, video_index, audio_index)!!;
    defer handle.channel.destroy();

    thread::Thread thread = player::video_play(
        renderer,
        texture,
        handle.channel,
        info.time_base,
        ffmpeg::get_time(info.rate, 1)
    )!!;

    rect.store({ .w = info.width, .h = info.height }, AtomicOrdering.RELEASE);

    Event event;
    while MAIN: (true) {
        if (sdl::pollEvent(&event)) {
            switch (event.type) {
                case EventType.QUIT:
                    log::debug("SDL Event: Quit the window");
                    is_running.store(false, AtomicOrdering.RELEASE);
                    break MAIN;
                case EventType.WINDOWEVENT:
                    switch ((WindowEventID)event.window.event) {
                        // case WindowEventID.WINDOWEVENT_RESIZED:
                        case WindowEventID.WINDOWEVENT_SIZE_CHANGED:
                            int width = event.window.data1;
                            int height = event.window.data2;
                            log::info("Resize to: %dx%d", width, height);
                            sdl::renderFlush(renderer);
                            int height2 = width * info.height / info.width;
                            int width2 = height * info.width / info.height;
                            sdl::Rect new_rect;
                            if (width * height2 < width2 * height) {
                                new_rect = { .w = width, .h = height2, .y = (height - height2) / 2 };
                            } else {
                                new_rect = { .w = width2, .h = height, .x = (width - width2) / 2 };
                            }
                            rect.store(new_rect, AtomicOrdering.RELEASE);
                        default:
                    }
            }
        }
        thread::sleep_ms(50);
    }

    (void)handle.thread.join();

    return 0;
}
