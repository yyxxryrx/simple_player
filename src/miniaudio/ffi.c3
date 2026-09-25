module simple_player::miniaudio::ffi;

typedef Device = void;

extern fn Device* alloc_device();

alias DataCallback = fn void(Device* device, void* p_output, void* p_input, uint frame_count);
extern fn bool init_device(Device* device, uint channels, uint simple_rate, void* data, DataCallback data_callback);

extern fn bool device_start(Device* device);

extern fn void device_uninit(Device* device);

extern fn void device_free(Device* device);
