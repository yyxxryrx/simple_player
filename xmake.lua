add_rules("mode.debug", "mode.release")

includes("xmake/rules/c3.lua")

add_requireconfs("*", { configs = { shared = true } })
add_requires("ffmpeg")

target("wrapper")
    set_kind("object")
    add_files("src-c/*.c")
    add_packages("ffmpeg")

target("simple_player")
    set_kind("binary")
    add_rules("c3")
    add_deps("wrapper")
    add_files("src/*.c3", "src/*.c3i")
    add_packages("ffmpeg")
    on_load(function (target)
        target:add("c3c_flags", "--lib")
        target:add("c3c_flags", "sdl2")
        target:add("c3c_flags", "--libdir")
        target:add("c3c_flags", path.join(target:scriptdir(), "lib"))
    end)