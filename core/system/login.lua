local systemRegistry, _ = kernel.readTableFile("system:registry/system.reg")

kernel.term.print("KairOS "..os.version)
kernel.term.print("NexCore "..kernel.version.."\n\n")

local newUID

while true do
    kernel.term.write("login: ")
	local username = kernel.term.input()

    kernel.term.write("\npassword: ")
    local password = kernel.term.input("*")
    kernel.term.write("\n")

    local foundUID, foundUser
    for uid, data in pairs(systemRegistry.USERS) do
        print(uid, data.name)
        if data.name == username then
            foundUID, foundUser = uid, data
            break
        end
    end

    if not foundUser then
        kernel.term.print("Username not found")
        goto end_while
    end

    if not kernel.hashlib.compare(password, foundUser.hash) then
        kernel.term.print("Incorrect password")
        goto end_while
    end

    newUID = tonumber(foundUID)
    break

    ::end_while::
end

kernel.term.write("\n")

kernel.scheduler.setRUID(newUID)
kernel.scheduler.setEUID(newUID)

local pid, err = kernel.scheduler.spawnFile("system:bin/shell.lua", 0)
if err then print(err) end
