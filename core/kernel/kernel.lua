local kInternal = {}
kInternal.term  = {}
_G.kernel       = {}
_G.kernel.term  = {}
_G.kernel.ipc   = {}

kInternal.term.backgroundColor            = {0, 0, 0}
kInternal.term.foregroundColor            = {255, 255, 255}
kInternal.term.setColor                   = screen.setColor
kInternal.term.savedPalettes              = {}
kInternal.scrBackup                       = {}
kInternal.uid                             = 0

for k,v in pairs(screen) do kernel.term[k] = v end
for k,v in pairs(screen) do kInternal.scrBackup[k] = v end
kernel.term.setColor = nil
_ENV.screen = nil

math.randomseed(math.abs(chip.getTime()))

--compatibility
_G.loadstring = load
_G.loadfile = function(filename, mode, env)
    local file = fs.open(filename, "r")
    print("Reading and loading file")
    local fn, err = load(file.read("a"), "="..filename, mode, env)
    print("Complete")
    file.close()
    return fn, err
end

function _G.dofile(filename)
    return loadfile(filename, "="..filename, "bt", _ENV)()
end

function _G.sleep(time)
    local t = chip.getTime()
    while true do
        coroutine.yield()
        if t + (time * 1000) <= chip.getTime() then
            break
        end
    end
end

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
kernel.term.flush        = NexB.flush
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
    local paletteID = math.random(0xFFFF) * 0x10000 + math.random(0xFFFF)
    kInternal.term.savedPalettes[paletteID] = {kInternal.term.foregroundColor, kInternal.term.backgroundColor}
    return paletteID
end
function kernel.term.restoreColorPalette(ID)
    if not kernel.term.expect(ID, "number", "Expected number for palette ID") then return end

    if not kInternal.term.savedPalettes[ID] then kernel.term.print("Palette ID "..ID.." does not exist!"); return end

    kInternal.term.foregroundColor = kInternal.term.savedPalettes[ID][1]
    kInternal.term.backgroundColor = kInternal.term.savedPalettes[ID][2]

    kInternal.term.savedPalettes[ID] = nil
end

local typeColor = {
    ["INFO"]      = {{248, 249, 250}, {0, 0, 0}},
    ["OK"]        = {{40, 167, 69}, {0, 0, 0}},
    ["DEBUG"]     = {{23, 162, 184}, {0, 0, 0}},
    ["TRACE"]     = {{108, 117, 125}, {0, 0, 0}},
    ["NOTICE"]    = {{32, 201, 151}, {0, 0, 0}},
    ["WARNING"]   = {{255, 193, 7}, {0, 0, 0}},
    ["ERROR"]     = {{220, 53, 69}, {0, 0, 0}},
    ["FAIL"]      = {{255, 0, 0}, {0, 0, 0}},
    ["CRITICAL"]  = {{255, 0, 0}, {0, 0, 0}},
    ["ALERT"]     = {{255, 7, 58}, {0, 0, 0}},
    ["EMERGENCY"] = {{255, 255, 255}, {220, 53, 69}},
}

function kernel.term.logMessage(msg, name, msgType)
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

kernel.term.logMessage("kernel term functions loaded", "kernel", "OK")
kernel.term.flush()

function _ENV.error(message, level)
    kernel.term.logMessage(message, "error", "ERROR")
end

local scheduler = {
    procs = {},
    current = nil,
    nextPid = 1,
    baseQuantum = 500
}

local function spawn(fn, nice)
    local pid = scheduler.nextPid
    scheduler.nextPid = scheduler.nextPid + 1
    local co = coroutine.create(fn)
    scheduler.procs[pid] = { co = co, pid = pid, nice = nice or 0, fn = fn, uid = kInternal.uid }
    return pid
end

function _G.fork()
    local cur = scheduler.current
    if not cur then error("fork() called outside process") end

    local proc = scheduler.procs[cur]
    if proc and proc._force_fork_return ~= nil then
        local ret = proc._force_fork_return
        proc._force_fork_return = nil
        return ret
    end

    local parentProc = scheduler.procs[cur]
    local childPid = spawn(parentProc.fn, parentProc.nice)
    scheduler.procs[childPid]._force_fork_return = 0
    return childPid
end

function _G.setNice(value)
    local pid = scheduler.current
    if pid and scheduler.procs[pid] then
        scheduler.procs[pid].nice = value
    end
end

function scheduler.run()
    local BASE_QUANTUM = scheduler.baseQuantum

    while next(scheduler.procs) do
        local runnable = {}
        for _, proc in pairs(scheduler.procs) do
            if coroutine.status(proc.co) ~= "dead" then
                table.insert(runnable, proc)
            end
        end
        if #runnable == 0 then break end

        table.sort(runnable, function(a, b)
            return a.nice < b.nice
        end)

        local weights = {}
        local totalWeight = 0
        local BASE = 1.08
        for i, proc in ipairs(runnable) do
            local nice = math.max(-20, math.min(19, proc.nice or 0))
            local weight = 1024 * (BASE ^ (-nice))
            weights[i] = weight
            totalWeight = totalWeight + weight
        end

        for i, proc in ipairs(runnable) do
            scheduler.current = proc.pid
            local weight = weights[i]
            local quantum = math.floor(BASE_QUANTUM * (weight / totalWeight) * #runnable)
            if quantum < 1 then quantum = 1 end

            kInternal.uid = proc.uid

            debug.sethook(proc.co, function() coroutine.yield() end, "", quantum)
            local ok, err = coroutine.resume(proc.co)
            if not ok then error(err) end
            debug.sethook(proc.co)
        end
        NexB.flush()

        for pid, proc in pairs(scheduler.procs) do
            if coroutine.status(proc.co) == "dead" then
                scheduler.procs[pid] = nil
            end
        end
    end
end

function kernel.getUID()
    return kInternal.uid
end

function kernel.isRoot()
    return kInternal.uid == 0
end

function kernel.getPID()
    return scheduler.current
end

kernel.term.logMessage("kernel scheduler loaded", "kernel", "OK")
kernel.term.flush()

local acl = {}

function kernel.ipc.register(name, aclrule)
    if type(name) ~= "string" then return false, "Expected name to be a string" end
    if type(aclrule) ~= "table" then return false, "Expected aclrule to be a table" end

    if acl[name] then return false, "Name is already registered" end

    acl[name] = {currentPID, aclrule}

    return true
end

function kernel.ipc.canTransmit(pid)
    for _, v in acl do
        if v[1] == pid then

        end
    end
end

--[[
spawn(function()
    local pid = fork()
    if pid == 0 then
        kernel.term.print("Child (high-priority) running")
        for i = 1, 5 do
            kernel.term.print("Child iteration", i)
        end
    elseif pid then
        kernel.term.print("Parent (high-priority) running, child pid="..pid)
        for i = 1, 5 do
            kernel.term.print("Parent iteration", i)
        end
    end
end, -10)


spawn(function()
    for i = 1, 5 do
        kernel.term.print("Low-priority process iteration", i)
    end
end, 10)

scheduler.run()
]]

local fn, err = loadfile("system:lib/sha2.lua", "t", _ENV)
if err then kernel.logMessage(err, "kernel", "ERROR") end
local sha = fn()

local fn, err = loadfile("system:lib/base64.lua", "t", _ENV)
if err then kernel.logMessage(err, "kernel", "ERROR") end
local base64 = fn()




local function random_bytes(len)
    local t = {}
    local addr = tostring(t)
    print("Table address "..addr)
    local seed = tonumber(addr:match(":%s*(%x+)"), 16) or 0
    seed = bit32.bxor(seed, chip.getTime())
    seed = bit32.bxor(seed, math.random(0xFFFF) * 0x10000 + math.random(0xFFFF))
    math.randomseed(seed)

    local out = {}
    for i = 1, len do
        out[i] = string.char(math.random(0, 255))
    end
    return table.concat(out)
end
local function b2(message)
    return sha.blake2b_512(message, nil, nil)
end

local function pack_inputs(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        if type(v) == "string" then
            parts[#parts+1] = "\x01" .. string.char(#v % 256) .. v
        else
            local s = tostring(v)
            parts[#parts+1] = "\x02" .. string.char(#s % 256) .. s
        end
    end
    return table.concat(parts)
end

local function H(...)
    return b2(pack_inputs(...))
end

local function balloon_hash(password, salt, space_cost, time_cost, delta)
    assert(type(password) == "string" and #password > 0, "password required")
    assert(type(salt) == "string" and #salt >= 16, "salt >= 16 bytes")
    assert(space_cost and space_cost >= 8, "space_cost >= 8")
    assert(time_cost and time_cost >= 1, "time_cost >= 1")
    assert(delta and delta >= 1, "delta >= 1")

    local m = space_cost
    local buf = {}

    buf[1] = H("init", salt, password)
    for i = 2, m do
        buf[i] = H("expand", buf[i-1])
    end
    for r = 0, time_cost - 1 do
        for i = 1, m do
            print(r, i)
            buf[i] = H("mix", r, i, buf[i])

            for j = 0, delta - 1 do
                local pr = H("idx", r, i, j, buf[i])
                local v = 0
                for k = 1, 8 do
                    v = (v * 256 + pr:byte(k)) % 0x7fffffff
                end
                local idx = (v % m) + 1
                buf[i] = H("mix2", buf[i], buf[idx])
            end
        end
    end

    return H("final", salt, time_cost, m, delta, buf[m])
end

local DEFAULT_SPACE = 4096
local DEFAULT_TIME  = 3
local DEFAULT_DELTA = 3

local function hash_password(password, opts)
    opts = opts or {}
    local space = opts.space_cost or DEFAULT_SPACE
    local timec = opts.time_cost  or DEFAULT_TIME
    local delta = opts.delta      or DEFAULT_DELTA

    local salt = random_bytes(16) -- 128-bit salt
    local tag  = balloon_hash(password, salt, space, timec, delta)
    return table.concat({
        "balloon-b2b",
        tostring(space),
        tostring(timec),
        tostring(delta),
        base64.encode(salt),
        base64.encode(tag)
    }, "$")
end

local function verify_password(password, stored)
    -- Format: balloon-b2b$space$time$delta$salt_b64$tag_b64
    local alg, space, timec, delta, salt_b64, tag_b64 =
        stored:match("^([^$]+)%$(%d+)%$(%d+)%$(%d+)%$(.-)%$(.+)$")
    if alg ~= "balloon-b2b" then return false end

    space  = tonumber(space)
    timec  = tonumber(timec)
    delta  = tonumber(delta)
    local salt = base64.decode(salt_b64)
    local tag_expected = base64.decode(tag_b64)

    local tag = balloon_hash(password, salt, space, timec, delta)

    if #tag ~= #tag_expected then return false end
    local diff = 0
    for i = 1, #tag do
        diff = bit32.bxor(diff, bit32.bxor(tag:byte(i), tag_expected:byte(i)))
    end
    return diff == 0
end

local stored = hash_password("hunter2", { space_cost = 8, time_cost = 1, delta = 2 })
print("Stored:", stored)
print("OK:", verify_password("hunter2", stored))
print("NO:", verify_password("nope", stored))
