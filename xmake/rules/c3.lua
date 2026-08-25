-- xmake/rules/c3.lua
-- C3 语言构建规则（通过 c3c 接入 xmake）

rule("c3")
    set_extensions(".c3", ".c3i")

    on_build(function (target)
        local function as_list(v)
            if type(v) == "string" then
                return {v}
            elseif type(v) == "table" then
                return v
            end
            return {}
        end

        local c3c = import("lib.detect.find_tool")("c3c")

        local c3files = {}
        for _, src in ipairs(target:sourcefiles()) do
            local p = tostring(src)
            table.insert(c3files, p)
        end

        if #c3files == 0 then
            return
        end

        local targetfile = target:targetfile()
        if not targetfile then
            raise("targetfile is nil for target %s", target:name())
        end
        target:set("targetfile", targetfile)
        local dir = path.directory(targetfile)

        -- 确保输出目录存在
        os.mkdir(dir)

        local argv = {}
        local kind = target:kind()

        if kind == "binary" then
            table.insert(argv, "compile")
        elseif kind == "static" then
            table.insert(argv, "static-lib")
        elseif kind == "shared" then
            table.insert(argv, "dynamic-lib")
        else
            raise("unsupported target kind '%s' for c3 rule (supported: binary, static, shared)", kind)
        end

        table.insert(argv, "-o")
        table.insert(argv, path.join(dir, target:name()))

        for _, f in ipairs(c3files) do
            table.insert(argv, f)
        end

        for _, dep in pairs(target:deps()) do
            local kind = dep:targetkind()
            if kind == "object" then
                for _, o in ipairs(dep:objectfiles()) do
                    table.insert(argv, o)
                end 
            end
        end

        if is_mode("release") then
            table.insert(argv, "-O5")
            table.insert(argv, "-g0")
        else
            table.insert(argv, "-O0")
            table.insert(argv, "-g")
        end

        local c3flags = as_list(target:get("c3c_flags"))
        for _, flag in ipairs(c3flags) do
            table.insert(argv, flag)
        end

        -- 处理 xmake 包依赖
        for _, pkg in pairs(target:pkgs()) do
            local links = as_list(pkg:get("links"))
            for _, link in ipairs(links) do
                table.insert(argv, "-l")
                table.insert(argv, link)
            end

            local linkdirs = as_list(pkg:get("linkdirs"))
            for _, dir in ipairs(linkdirs) do
                table.insert(argv, "-L")
                table.insert(argv, dir)
            end
        end

        os.vrunv(c3c.program, argv)
    end)
