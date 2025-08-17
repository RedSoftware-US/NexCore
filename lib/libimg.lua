local img = {
    version = "1.1.0",
}

function img.clone(buffer)
    local newBuf = {}
    for i, row in ipairs(buffer) do
        newBuf[i] = {}
        for j, pixel in ipairs(row) do
            if type(pixel) == "table" then
                newBuf[i][j] = { table.unpack(pixel) }
            else
                newBuf[i][j] = { pixel, pixel, pixel }
            end
        end
    end
    return newBuf
end

function img.rotate(buffer, angle)
    local w, h = #buffer[1], #buffer
    local result
    if angle == 90 then
        result = {}
        for j = 1, w do
            result[j] = {}
            for i = h, 1, -1 do
                result[j][h-i+1] = table.unpack(buffer[i][j])
            end
        end
    elseif angle == 180 then
        result = {}
        for i = h, 1, -1 do
            local row = {}
            for j = w, 1, -1 do
                row[w-j+1] = table.unpack(buffer[i][j])
            end
            table.insert(result, row)
        end
    elseif angle == 270 then
        result = {}
        for j = w, 1, -1 do
            result[w-j+1] = {}
            for i = 1, h do
                result[w-j+1][i] = table.unpack(buffer[i][j])
            end
        end
    else
        return img.clone(buffer)
    end
    return result
end

function img.flip(buffer, horizontal, vertical)
    local w, h = #buffer[1], #buffer
    local result = img.clone(buffer)
    if horizontal then
        for i = 1, h do
            for j = 1, math.floor(w/2) do
                result[i][j], result[i][w-j+1] = result[i][w-j+1], result[i][j]
            end
        end
    end
    if vertical then
        for i = 1, math.floor(h/2) do
            result[i], result[h-i+1] = result[h-i+1], result[i]
        end
    end
    return result
end

function img.tint(buffer, tr, tg, tb)
    local result = img.clone(buffer)
    for i, row in ipairs(result) do
        for j, pixel in ipairs(row) do
            pixel[1] = math.min(255, pixel[1] + tr)
            pixel[2] = math.min(255, pixel[2] + tg)
            pixel[3] = math.min(255, pixel[3] + tb)
        end
    end
    return result
end

function img.grayscale(buffer)
    local result = img.clone(buffer)
    for i, row in ipairs(result) do
        for j, pixel in ipairs(row) do
            local avg = math.floor((pixel[1] + pixel[2] + pixel[3]) / 3)
            pixel[1], pixel[2], pixel[3] = avg, avg, avg
        end
    end
    return result
end

function img.invert(buffer)
    local result = img.clone(buffer)
    for i, row in ipairs(result) do
        for j, pixel in ipairs(row) do
            pixel[1] = 255 - pixel[1]
            pixel[2] = 255 - pixel[2]
            pixel[3] = 255 - pixel[3]
        end
    end
    return result
end

function img.pixelate(buffer, blockSize)
    blockSize = math.max(1, blockSize or 2)
    local w, h = #buffer[1], #buffer
    local result = img.clone(buffer)
    for i = 1, h, blockSize do
        for j = 1, w, blockSize do
            local rSum, gSum, bSum, count = 0, 0, 0, 0
            for dy = 0, blockSize-1 do
                for dx = 0, blockSize-1 do
                    local y, x = i+dy, j+dx
                    if y <= h and x <= w then
                        local p = buffer[y][x]
                        rSum = rSum + p[1]
                        gSum = gSum + p[2]
                        bSum = bSum + p[3]
                        count = count + 1
                    end
                end
            end
            local rAvg = math.floor(rSum / count)
            local gAvg = math.floor(gSum / count)
            local bAvg = math.floor(bSum / count)
            for dy = 0, blockSize-1 do
                for dx = 0, blockSize-1 do
                    local y, x = i+dy, j+dx
                    if y <= h and x <= w then
                        result[y][x][1] = rAvg
                        result[y][x][2] = gAvg
                        result[y][x][3] = bAvg
                    end
                end
            end
        end
    end
    return result
end

function img.drawImage(buffer, x, y, scale)
    local img_h = #buffer
    local img_w = #buffer[1]

    if scale == -1 then
        local scr_w, scr_h = kernel.term.getSize()
        scale = { w = scr_w / img_w, h = scr_h / img_h }
    else
        scale = { w = scale or 1, h = scale or 1 }
    end

    local paletteID = kernel.term.saveColorPalette()

    for i, row in ipairs(buffer) do
        for j, pixel in ipairs(row) do
            kernel.term.setColor(pixel[1], pixel[2], pixel[3])
            local draw_x = math.floor((j - 1) * scale.w + x)
            local draw_y = math.floor((i - 1) * scale.h + y)
            local w = math.ceil(scale.w)
            local h = math.ceil(scale.h)
            for dy = 0, h-1 do
                for dx = 0, w-1 do
                    kernel.term.drawPixel(draw_x + dx, draw_y + dy)
                end
            end
        end
    end

    kernel.term.draw()
    kernel.term.restoreColorPalette(paletteID)
end

return img
