package main

import "base:runtime"
import "vendor:miniaudio"

@(export = true)
alloc_device :: proc "c" () -> ^miniaudio.device {
	context = runtime.default_context()
	ptr, err := new(miniaudio.device)
	if err != nil {
		return nil
	}
	return ptr
}

@(export = true)
init_device :: proc "c" (
	device: ^miniaudio.device,
	channels, simple_rate: u32,
	data: rawptr,
	data_callback: miniaudio.device_data_proc,
) -> bool {
	deviceConfig := miniaudio.device_config_init(miniaudio.device_type.playback)
	deviceConfig.sampleRate = simple_rate
	deviceConfig.playback.channels = channels
	deviceConfig.playback.format = miniaudio.format.s16
	deviceConfig.pUserData = data
	deviceConfig.dataCallback = data_callback
	return miniaudio.device_init(nil, &deviceConfig, device) == .SUCCESS
}

@(export = true)
device_start :: proc "c" (device: ^miniaudio.device) -> bool {
	return miniaudio.device_start(device) == .SUCCESS
}

@(export = true)
device_uninit :: proc "c" (device: ^miniaudio.device) {
	miniaudio.device_uninit(device)
}

@(export = true)
free_device :: proc "c" (device: ^miniaudio.device) {
	context = runtime.default_context()
	free(device)
}
