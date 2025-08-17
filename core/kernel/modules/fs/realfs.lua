local realfs = {}

function realfs.open(kfs, path, mode)
    local handle = kfs.open(path, mode)
    function handle:readAll()
        local chunkedData = {}
        while true do
            local chunk = handle.read(8192)
            if not chunk or #chunk == 0 then break end
            table.insert(chunkedData, chunk)
        end
        return table.concat(chunkedData)
    end
    return handle
end

function realfs.exists(kfs, path)
    return kfs.exists(path)
end

function realfs.isFile(kfs, path)
    return kfs.isFile(path)
end

function realfs.isDir(kfs, dir)
    return kfs.isDir(dir)
end

function realfs.delete(kfs, path)
    return kfs.delete(path)
end

function realfs.makeDir(kfs, path)
    return kfs.makeDir(path)
end

function realfs.getChildren(kfs, path)
    return kfs.getChildren(path)
end

return realfs
