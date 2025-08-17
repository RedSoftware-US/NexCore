local boot = {}

function boot.start_boot()
    local base64 = kernel.lib("core/libbase64.lua")
    local img    = kernel.lib("core/libimg.lua")
    local qoi = kernel.lib("core/libqoi.lua")

    local qoi_image, err = kernel.fs.open("system:core/system/boot/boot.bqoi", "r")
    if err then error(err) end

    local chunkedData = {}
    while true do
        local chunk = qoi_image.read(8192)
        if not chunk or #chunk == 0 then break end
        table.insert(chunkedData, chunk)
    end

    local qoi_image_data = table.concat(chunkedData)

    qoi_image.close()

    local buffer, _ = qoi.decode(base64.decode(qoi_image_data))

    img.drawImage(buffer, 0, 0, -1)

    kernel.term.draw()
end

function boot.end_boot()
    kernel.term.clear()
end

return boot
