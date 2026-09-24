add_rules("mode.debug", "mode.release")

includes("xmake/rules/c3.lua")
includes("xmake/rules/odin.lua")

add_requireconfs("*", { configs = { shared = true } })
add_requires("ffmpeg", { configs = { gpl = false } })

target("wrapper")
set_kind("object")
add_files("src-c/*.c")
add_packages("ffmpeg")

target("miniaudio")
set_kind("shared")
add_rules("odin")
add_files("src-odin/main.odin")

target("simple_player")
set_kind("binary")
add_rules("c3")
add_deps("wrapper", "miniaudio")
add_files("src/*.c3", "src/*.c3i")
add_packages("ffmpeg")
if not is_os("windows") then
	add_syslinks("m")
end
on_load(function(target)
	target:add("c3lib", "sdl2")
	target:add("c3lib", "clip")
	target:add("c3libdir", path.join(target:scriptdir(), "lib"))
end)
