local kInternal = {}
kInternal.term  = {}
_G.kernel       = {}
_G.kernel.term  = {}
_G.kernel.ipc   = {}
_G.kernel.hashlib = {}
_G.kernel.scheduler = {}

kernel.fs                                 = {}

kInternal.term.backgroundColor            = {0, 0, 0}
kInternal.term.foregroundColor            = {255, 255, 255}
kInternal.term.setColor                   = screen.setColor
kInternal.term.savedPalettes              = {}
kInternal.scrBackup                       = {}
kInternal.uid                             = 0
kInternal.ruid                            = 0
kInternal.gids                            = {0}
kInternal.rgids                           = {0}
kInternal.peripherals                     = peripherals
kInternal.fs                              = {}

for k,v in pairs(fs) do kernel.fs[k] = v end
for k,v in pairs(fs) do kInternal.fs[k] = v end
for k,v in pairs(screen) do kernel.term[k] = v end
for k,v in pairs(screen) do kInternal.scrBackup[k] = v end

kernel.term.setColor = nil
_ENV.screen = nil
_ENV.peripherals = nil
_G.fs = nil

math.randomseed(math.abs(chip.getTime()))

--compatibility
_G.loadstring = load
_G.loadfile = function(filename, mode, env)
    local file = kernel.fs.open(filename, "r")
    if not kInternal.fs.exists(filename) then print(filename.." does not exist") end
    local fn, err = load(file.read("a"), "="..filename, mode, env)
    file.close()
    return fn, err
end

function _G.dofile(filename)
    return loadfile(filename, "="..filename, "bt", _ENV)()
end

function kernel.readTableFile(path)
    local file = kernel.fs.open(path, "r")
    return load("local t = "..file.read("a").."\nreturn t", "="..path, "t", _ENV)()
end

kInternal.systemRegistry, err = kernel.readTableFile("system:registry/system.reg")
if err then kernel.term.write("CRITICAL: SYSTEM REGISTRY ERROR. SEE CONSOLE"); print(err); return end

if (not kInternal.systemRegistry) or (kInternal.systemRegistry == {}) then kernel.term.write("CRITICAL: COULD NOT LOCATE SYSTEM REGISTRY"); return end

function kInternal.readSysmeta()
    print(kInternal.systemRegistry.FILESYSTEM.METAFILE, kInternal.fs.exists(kInternal.systemRegistry.FILESYSTEM.METAFILE))
    local file = kInternal.fs.open(kInternal.systemRegistry.FILESYSTEM.METAFILE, "r")
    return load("local t = "..file.read("a").."\nreturn t", "="..kInternal.systemRegistry.FILESYSTEM.METAFILE, mode, _ENV)()
end

local modulePath = kInternal.systemRegistry.KERNEL.module_location
local mountPaths = kInternal.systemRegistry.FILESYSTEM.MOUNTS

local filesystems = {}
local cachedMounts = {}

for k,v in pairs(mountPaths) do
    if cachedMounts[v] then filesystems[k] = cachedMounts[v] else
        local fsFunc, err = dofile(modulePath.."/"..v)
        if err then kernel.term.write("CRITICAL: FS ERROR IN "..v..". SEE CONSOLE"); print(err); return end
        cachedMounts[v] = fsFunc
        filesystems[k] = cachedMounts[v]
    end
end

local function sanitizePath(path)
    path = tostring(path)

    path = path:gsub("/+", "/")

    local parts = {}
    for part in path:gmatch("[^/]+") do
        if part == ".." then
            if #parts > 0 then
                table.remove(parts)
            end
        elseif part ~= "." and part ~= "" then
            table.insert(parts, part)
        end
    end

    return table.concat(parts, "/")
end

function kernel.fs.open(path, mode)
    path = sanitizePath(path)
    if not kInternal.fs.exists(path) then return nil, "File does not exist" end

    local sysmeta = kInternal.readSysmeta()

    local uid = kInternal.uid
    local gids = kInternal.systemRegistry.USERS[tostring(uid)].gids

    while path ~= "" and not sysmeta[path] do
        local parent = path:match("(.+)/[^/]+$")
        path = parent or ""
    end

    local data = sysmeta[path]
    if not data then return nil, "Could not retrieve sysmeta information" end

    local str = tostring(data.privilege)
    if #str < 3 then
        str = string.rep("0", 3 - #str) .. str
    end

    local perms = { owner = {}, group = {}, others = {} }
    local categories = {"owner", "group", "others"}

    for i = 1, 3 do
        local digit = tonumber(str:sub(i, i))
        perms[categories[i]].read    = digit >= 4
        perms[categories[i]].write   = (digit % 4) >= 2
        perms[categories[i]].execute = (digit % 2) == 1
    end

    local currentPermissions

    if data.owner == uid then
        currentPermissions = perms.owner
    else
        local foundGroup = false
        for _,group in ipairs(gids) do
            if group == data.group then
                currentPermissions = perms.group
                foundGroup = true
                break
            end
        end
        if not foundGroup then currentPermissions = perms.others end
    end

    local modeFlags = {
        w = {write=true}, a = {write=true}, wb = {write=true}, ab = {write=true},
        r = {read=true}, rb = {read=true},
        ["r+"] = {read=true, write=true}, ["r+b"] = {read=true, write=true},
        ["a+"] = {read=true, write=true}, ["a+b"] = {read=true, write=true},
    }

    local flags = modeFlags[mode] or {}
    if (flags.read and not currentPermissions.read) or
    (flags.write and not currentPermissions.write) then
        return nil, "Refused"
    end

    return kInternal.fs.open(path, mode)
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

function kernel.scheduler.spawn(fn, nice)
    local pid = scheduler.nextPid
    scheduler.nextPid = scheduler.nextPid + 1
    local co = coroutine.create(fn)
    scheduler.procs[pid] = { co = co, pid = pid, nice = nice or 0, fn = fn, uid = kInternal.uid, gids = kInternal.gids, ruid = kInternal.ruid, rgids = kInternal.rgids, canSetUID = false }
    return pid
end

function kernel.scheduler.spawnFile(path, nice)
    local pid = scheduler.nextPid
    scheduler.nextPid = scheduler.nextPid + 1
    local fn, err = loadfile(path, "bt", _ENV)
    if not fn then return nil, err end
    local sysmeta = kInternal.readSysmeta()
    if not sysmeta[path] then return nil, "Could not find path in sysmeta" end

    local co = coroutine.create(fn)

    scheduler.procs[pid] = { co = co, pid = pid, nice = nice or 0, fn = fn, uid = kInternal.uid, gids = kInternal.gids, ruid = kInternal.ruid, rgids = kInternal.rgids, canSetUID = sysmeta[path].extra.setUID, owner = sysmeta[path].owner }
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

function kernel.scheduler.setNice(value)
    local pid = scheduler.current
    if pid and scheduler.procs[pid] then
        scheduler.procs[pid].nice = value
    end
end

function kernel.scheduler.setEUID(newUID)
    local pid = scheduler.current
    local proc = scheduler.procs[pid]

    if not proc then return nil, "No current process" end

    if newUID == proc.ruid then
        proc.uid = newUID
        proc.canSetUID = false
        return true
    end

    if proc.canSetUID then
        if newUID == proc.owner then
            proc.uid = newUID
            proc.canSetUID = false
            return true
        end
    end

    return nil, "Permission denied"
end

function kernel.scheduler.setRUID(newUID)
    local pid = scheduler.current
    local proc = scheduler.procs[pid]

    if not proc then return nil, "No current process" end

    if proc.uid == 0 then
        if type(newUID) ~= "number" or newUID < 0 then
            return nil, "Invalid UID"
        end
        proc.ruid = newUID
        return true
    end

    return nil, "Permission denied"
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
            kInternal.ruid = proc.ruid
            kInternal.gids = proc.gids
            kInternal.rgids = proc.rgids

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

function kernel.scheduler.getEUID()
    return kInternal.uid
end

function kernel.scheduler.getRUID()
    return kInternal.ruid
end

function kernel.scheduler.getEGID()
    return kInternal.gids
end

function kernel.scheduler.getRGID()
    return kInternal.rgids
end

function kernel.scheduler.isRoot()
    return kInternal.uid == 0
end

function kernel.scheduler.getPID()
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

local fn, err = loadfile(kInternal.systemRegistry.KERNEL.library_location.."/libsha.lua", "t", _ENV)
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
