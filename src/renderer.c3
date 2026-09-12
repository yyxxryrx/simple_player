module simple_player::renderer;

import sdl;
import std::thread;

struct Renderer {
    thread::Mutex mutex;
    ConditionVariable cv;
    sdl::Renderer* renderer;
    bool held;
    bool closed;
}

fn void? Renderer.init(&self, sdl::Renderer* renderer) {
    self.mutex.init()!;
    self.cv.init()!;
    self.renderer = renderer;
}

macro void? Renderer.lock(&self) {
    self.mutex.lock()!;
    defer self.mutex.unlock();

    while (self.held && !self.closed) {
        self.cv.wait(&self.mutex);
    }

    self.held = true;
}

macro void? Renderer.unlock(&self) {
    self.mutex.lock()!;
    defer self.mutex.unlock();

    self.held = false;
    self.cv.signal()!;
}

macro void? Renderer.@with(&self; @body(sdl::Renderer* renderer)) {
    self.lock()!;
    defer (void)self.unlock();

    @body(self.renderer);
}

macro void? Renderer.destroy(&self) {
    self.mutex.lock()!;
    self.closed = true;
    self.cv.broadcast()!;
    self.mutex.lock();
    self.cv.destroy()!;
    self.mutex.destroy();
}
