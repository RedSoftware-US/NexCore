local kInternal = {}
kInternal.term  = {}
_G.kernel       = {}
_G.kernel.term  = {}

kInternal.term.backgroundColor            = {0, 0, 0}
kInternal.term.foregroundColor            = {255, 255, 255}
kInternal.term.setColor = screen.setColor
kInternal.term.currentPaletteID           = 0
kInternal.term.savedPalettes              = {}
kInternal.scrBackup = {}

for k,v in pairs(screen) do kernel.term[k] = v end
for k,v in pairs(screen) do kInternal.scrBackup[k] = v end
kernel.term.setColor = nil
_ENV.screen = nil

function kernel.term.print(...)
    local n = select('#', ...)
    if n == 0 then
        NexB.writeScr("\n", kInternal.term.foregroundColor, kInternal.term.backgroundColor)
        return
    end

    local parts = {}
    for i = 1, n do
        local v = select(i, ...)
        parts[#parts + 1] = tostring(v)
    end

    NexB.writeScr(table.concat(parts, "\t") .. "\n", kInternal.term.foregroundColor, kInternal.term.backgroundColor)
    kInternal.scrBackup.draw()
end

function kernel.term.expect(value, vtype, message)
    local t = type(value)
    if type(vtype) == "string" then
        if t ~= vtype then
            kernel.term.print(message)
            return nil
        end
    elseif type(vtype) == "table" then
        local ok = false
        for _, allowed in ipairs(vtype) do
            if t == allowed then
                ok = true
                break
            end
        end
        if not ok then
            kernel.term.print(message)
            return nil
        end
    end
    return true
end

kernel.term.setCursorPos = NexB.setCursorPos
kernel.term.getCursorPos = NexB.getCursorPos
kernel.term.flush        = kInternal.term.draw; kInternal.term.draw = nil
function kernel.term.write(str)
    NexB.writeScr(str, kInternal.term.foregroundColor, kInternal.term.backgroundColor)
end
function kernel.term.clear()
    local scr_w, scr_h = kernel.term.getSize()

    kernel.term.fill(0,0,scr_w, scr_h)
end
function kernel.term.setForegroundColor(r, g, b)
    if not kernel.term.expect(r, "number", "Expected number for red value") then return end
    if not kernel.term.expect(g, "number", "Expected number for green value") then return end
    if not kernel.term.expect(b, "number", "Expected number for blue value") then return end

    kInternal.term.foregroundColor = {r, g, b}
end
function kernel.term.setBackgroundColor(r, g, b)
    if not kernel.term.expect(r, "number", "Expected number for red value") then return end
    if not kernel.term.expect(g, "number", "Expected number for green value") then return end
    if not kernel.term.expect(b, "number", "Expected number for blue value") then return end

    kInternal.term.backgroundColor = {r, g, b}
end
function kernel.term.saveColorPalette()
    kInternal.term.savedPalettes[kInternal.term.currentPaletteID] = {kInternal.term.foregroundColor, kInternal.term.backgroundColor}
    kInternal.term.currentPaletteID = kInternal.term.currentPaletteID + 1
    return kInternal.term.currentPaletteID - 1
end
function kernel.term.restoreColorPalette(ID)
    if not kernel.term.expect(ID, "number", "Expected number for palette ID") then return end

    if not kInternal.term.savedPalettes[ID] then kernel.term.print("Palette ID "..ID.." does not exist!"); return end

    kInternal.term.foregroundColor = kInternal.term.savedPalettes[ID][1]
    kInternal.term.backgroundColor = kInternal.term.savedPalettes[ID][2]

    kInternal.term.savedPalettes[ID] = nil
end

local typeColor = {
    ["INFO"] = {{248, 249, 250}, {0, 0, 0}},
    ["DEBUG"] = {{23, 162, 184}, {0, 0, 0}},
    ["TRACE"] = {{108, 117, 125}, {0, 0, 0}},
    ["NOTICE"] = {{32, 201, 151}, {0, 0, 0}},
    ["WARNING"] = {{255, 193, 7}, {0, 0, 0}},
    ["ERROR"] = {{220, 53, 69}, {0, 0, 0}},
    ["FAIL"] = {{255, 0, 0}, {0, 0, 0}},
    ["CRITICAL"] = {{255, 0, 0}, {0, 0, 0}},
    ["ALERT"] = {{255, 7, 58}, {0, 0, 0}},
    ["EMERGENCY"] = {{255, 255, 255}, {220, 53, 69}},
}

function kInternal.logMessage(msg, name, msgType)
    if name then name = name .. ": " else name = "" end

    if not typeColor[msgType] then return false end

    local msgFg = typeColor[msgType][1]
    local msgBg = typeColor[msgType][2]

    local colorPaletteID = kernel.term.saveColorPalette()

    kernel.term.write("[")

    kernel.term.setForegroundColor(msgFg[1], msgFg[2], msgFg[3])
    kernel.term.setBackgroundColor(msgBg[1], msgBg[2], msgBg[3])

    kernel.term.write(string.rep(" ", 9 - #msgType)..msgType)

    kernel.term.restoreColorPalette(colorPaletteID)

    kernel.term.print("] "..name..msg)
end

kInternal.logMessage("Testing info", "testprog", "INFO")
kInternal.logMessage("Testing debug", "testprog", "DEBUG")
kInternal.logMessage("Testing trace", "testprog", "TRACE")
kInternal.logMessage("Testing notice", "testprog", "NOTICE")
kInternal.logMessage("Testing warning", "testprog", "WARNING")
kInternal.logMessage("Testing error", "testprog", "ERROR")
kInternal.logMessage("Testing fail/critical", "testprog", "CRITICAL")
kInternal.logMessage("Testing alert", "testprog", "ALERT")
kInternal.logMessage("Testing emergency", "testprog", "EMERGENCY")
