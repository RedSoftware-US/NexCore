local libraries = kernel.fs.getChildren("system:lib/core")
local lib = {}
local os = {
    version = "0.2.0"
}

kernel.addGlobal("os", os)

for _, v in ipairs(libraries) do
	if kernel.fs.isFile("system:lib/core/"..v) then
        local fn, err = loadfile("system:lib/core/"..v, "t", _G)
        if not fn then
            kernel.term.logMessage("Core library could not be loaded. See console for error", "init.lua", "ERROR")
            kernel.term.flush()
            print("Library error:", err)
        else
            lib[v:sub(1, -5)] = fn()
        end
    end
end

kernel.addGlobal("lib", lib)

local systemRegistry, _ = kernel.readTableFile("system:registry/system.reg")

if not systemRegistry.USERS["0"].hash then
	kernel.changeHash(0, kernel.hashlib.encode("root"))
end

kernel.scheduler.spawnFile("system:core/system/login.lua", 0)
