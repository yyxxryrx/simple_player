rule("odin")
set_extensions(".odin")
on_load(function(target)
	local odin = import("lib.detect.find_tool")("odin", { check = "version" })
	if odin ~= nil then
		target:add("odin", odin.program)
	end
end)

on_build(function(target)
	local odin = target:get("odin")
	if odin == nil then
		raise("Cannot found odin toolchain")
	end

	local argv = { "build" }

	local files = target:sourcefiles()
	if #files > 0 then
		table.insert(argv, path.directory(files[1]))
	end

	local kind = target:kind()

	if kind == "shared" then
		table.insert(argv, "-build-mode:dynamic")
	end

	local targetfile = target:targetfile()
	table.insert(argv, "-out:" .. targetfile)

	os.vrunv(odin, argv)
end)
