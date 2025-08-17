local qoi = {
    version = "1.1.0-decode",
}

local CHARS = {}
for i = 0, 255 do CHARS[i] = string.char(i) end

local band = bit32.band
local lshift = bit32.lshift
local rshift = bit32.rshift

local function get_byte(s, pos)
    return (pos <= #s) and string.byte(s, pos) or nil
end

local function norm_byte(x)
    return x % 256
end

function qoi.decode(s)
    if type(s) ~= "string" then error("qoi.decode: expected string", 2) end

    local pos = 1
    if s:sub(pos, pos+3) ~= "qoif" then
        return nil, "Invalid signature."
    end
    pos = pos + 4

    if #s < 14 then
        return nil, "Missing part of header."
    end

    local getByte = string.byte

    local w = 256^3 * getByte(s, pos) + 256^2 * getByte(s, pos+1) + 256 * getByte(s, pos+2) + getByte(s, pos+3)
    if w == 0 then return nil, "Invalid width (0)." end
    pos = pos + 4

    local h = 256^3 * getByte(s, pos) + 256^2 * getByte(s, pos+1) + 256 * getByte(s, pos+2) + getByte(s, pos+3)
    if h == 0 then return nil, "Invalid height (0)." end
    pos = pos + 4

    local channels = getByte(s, pos)
    if not (channels == 3 or channels == 4) then
        return nil, "Invalid channel count."
    end
    pos = pos + 1

    local colorSpaceByte = getByte(s, pos)
    if colorSpaceByte == nil then return nil, "Missing color space byte." end
    if colorSpaceByte > 1 then return nil, "Invalid color space value." end
    local colorSpace = (colorSpaceByte == 0) and "srgb" or "linear"
    pos = pos + 1

    local seen = {}
    for i = 1, 64*4 do seen[i] = 0 end

    local prevR, prevG, prevB, prevA = 0, 0, 0, 255
    local r, g, b, a = 0, 0, 0, 255
    local run = 0

    local totalPixels = w * h
    local buffer = {}
    for row = 1, h do buffer[row] = {} end

    for pix = 1, totalPixels do
        if run > 0 then
            run = run - 1
            r, g, b, a = prevR, prevG, prevB, prevA

        else
            local byte1 = get_byte(s, pos)
            if not byte1 then return nil, "Unexpected end of data stream." end
            pos = pos + 1

            if byte1 == 254 then
                local br = get_byte(s, pos)
                local bg = get_byte(s, pos+1)
                local bb = get_byte(s, pos+2)
                if not bb then return nil, "Unexpected end of data stream." end
                pos = pos + 3
                r, g, b = br, bg, bb
                a = prevA

            elseif byte1 == 255 then
                local br = get_byte(s, pos)
                local bg = get_byte(s, pos+1)
                local bb = get_byte(s, pos+2)
                local ba = get_byte(s, pos+3)
                if not ba then return nil, "Unexpected end of data stream." end
                pos = pos + 4
                r, g, b, a = br, bg, bb, ba

            elseif byte1 < 64 then
                local hash4 = lshift(byte1, 2)
                r = seen[hash4 + 1]
                g = seen[hash4 + 2]
                b = seen[hash4 + 3]
                a = seen[hash4 + 4]

            elseif byte1 < 128 then
                local v = byte1 - 64
                local dr = rshift(band(v, 48), 4) - 2
                local dg = rshift(band(v, 12), 2) - 2
                local db = band(v, 3) - 2
                r = norm_byte(prevR + dr)
                g = norm_byte(prevG + dg)
                b = norm_byte(prevB + db)
                a = prevA

            elseif byte1 < 192 then
                local byte2 = get_byte(s, pos)
                if not byte2 then return nil, "Unexpected end of data stream." end
                pos = pos + 1

                local diffG = byte1 - 160
                g = norm_byte(prevG + diffG)
                local dg = diffG
                local dr_dg = rshift(band(byte2, 240), 4) - 8
                local db_dg = band(byte2, 15) - 8
                r = norm_byte(prevR + dg + dr_dg)
                b = norm_byte(prevB + dg + db_dg)
                a = prevA

            else
                run = byte1 - 192
                r, g, b, a = prevR, prevG, prevB, prevA
            end

            prevR, prevG, prevB, prevA = r, g, b, a
        end

        local row = math.floor((pix-1) / w) + 1
        local col = ((pix-1) % w) + 1
        if channels == 3 then
            buffer[row][col] = { r, g, b }
        else
            buffer[row][col] = { r, g, b, a }
        end

        local hash = band((r*3 + g*5 + b*7 + a*11), 63)
        local hash4 = lshift(hash, 2)
        seen[hash4 + 1] = r
        seen[hash4 + 2] = g
        seen[hash4 + 3] = b
        seen[hash4 + 4] = a
    end

    if run > 0 then
        return nil, "Corrupt data."
    end

    if s:sub(pos, pos+7) ~= "\0\0\0\0\0\0\0\1" then
        return nil, "Missing data end marker."
    end
    pos = pos + 8

    if pos <= #s then
        return nil, "Junk after data."
    end

    return buffer, channels, colorSpace
end

return qoi
