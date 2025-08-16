local kInternal = {}
kInternal.term  = {}
_G.kernel       = {}
_G.kernel.term  = {}
_G.kernel.ipc   = {}
_G.kernel.hashlib = {}

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
        parts[#parts + 1] = tostring(select(i, ...))
    end

    local str = table.concat(parts, "\t")

    NexB.writeScr(str .. "\n", kInternal.term.foregroundColor, kInternal.term.backgroundColor)
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
        kernel.term.flush()

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
local messageList = {}

function kernel.ipc.register(name, aclrule)
    if type(name) ~= "string" then return false, "Expected name to be a string" end
    if aclrule ~= true and type(aclrule) ~= "table" then
        return false, "Expected aclrule to be table or true"
    end

    if acl[name] then return false, "Name is already registered" end

    acl[name] = { owner = scheduler.current, rules = aclrule }
    return true
end

function kernel.ipc.canTransmit(targetName)
    local entry = acl[targetName]
    if not entry then
        return false
    end

    if scheduler.current == entry.owner then
        return true
    end

    local rules = entry.rules
    if rules == true then
        return true
    elseif type(rules) == "table" then
        for _, allowedPID in ipairs(rules) do
            if allowedPID == scheduler.current then
                return true
            end
        end
    end

    return false
end

function kernel.ipc.messages()
    local pid = scheduler.current
    messageList[pid] = messageList[pid] or {}
    return messageList[pid]
end

function kernel.ipc.collectMessages()
    local pid = scheduler.current
    local msgs = kernel.ipc.messages()
    messageList[pid] = {}
    return msgs
end

function kernel.ipc.send(name, message)
    local entry = acl[name]
    if not entry then return false end
    if not kernel.ipc.canTransmit(name) then return false end

    local recipientPID = entry.owner
    messageList[recipientPID] = messageList[recipientPID] or {}
    table.insert(messageList[recipientPID], { pid = scheduler.current, msg = message })
    return true
end

kernel.term.logMessage("kernel IPC loaded", "kernel", "OK")
kernel.term.flush()

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

local fn, err = loadfile("system:lib/sha.lua", "t", _ENV)
if err then print("ERROR: "..err) end
local sha256 = fn()

local charset = "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890"

function kernel.hashlib.generateSalt()
	local ret = {}
	local r
	for i = 1, 32 do
		r = math.random(1, #charset)
		table.insert(ret, charset:sub(r, r))
	end
	return table.concat(ret)
end

function kernel.hashlib.encode(str, salt)
    salt = salt or kernel.hashlib.generateSalt()
    return salt .. ":" .. sha256(salt .. str)
end

function kernel.hashlib.compare(str, combined)
    local sep_pos = combined:find(":")
    if not sep_pos then return false end

    local salt = combined:sub(1, sep_pos - 1)
    local stored_hash = combined:sub(sep_pos + 1)
    local test_hash = sha256(salt .. str)
    return test_hash == stored_hash
end

kernel.term.logMessage("kernel hashlib loaded", "kernel", "OK")
kernel.term.flush()
