local b64 = {}

local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local indexChar = {}
for i = 1, #chars do
    indexChar[chars:sub(i,i)] = i - 1
end

function b64.encode(data)
    local bytes = {data:byte(1, #data)}
    local result = {}
    for i = 1, #bytes, 3 do
        local a, b, c = bytes[i], bytes[i+1] or 0, bytes[i+2] or 0
        local n = bit32.lshift(a,16) + bit32.lshift(b,8) + c
        local n1 = bit32.rshift(n,18) % 64
        local n2 = bit32.rshift(n,12) % 64
        local n3 = bit32.rshift(n,6) % 64
        local n4 = n % 64
        table.insert(result, chars:sub(n1+1,n1+1) .. chars:sub(n2+1,n2+1) ..
                             (i+1 <= #bytes and chars:sub(n3+1,n3+1) or '=') ..
                             (i+2 <= #bytes and chars:sub(n4+1,n4+1) or '='))
    end
    return table.concat(result)
end

function b64.decode(data)
    local result = {}
    data = data:gsub("%s","")
    for i = 1, #data, 4 do
        local n1 = indexChar[data:sub(i,i)]
        local n2 = indexChar[data:sub(i+1,i+1)]
        local n3 = indexChar[data:sub(i+2,i+2)] or 0
        local n4 = indexChar[data:sub(i+3,i+3)] or 0
        local n = bit32.lshift(n1,18) + bit32.lshift(n2,12) + bit32.lshift(n3,6) + n4
        local a = bit32.rshift(n,16) % 256
        local b = bit32.rshift(n,8) % 256
        local c = n % 256
        table.insert(result,string.char(a))
        if data:sub(i+2,i+2) ~= '=' then table.insert(result,string.char(b)) end
        if data:sub(i+3,i+3) ~= '=' then table.insert(result,string.char(c)) end
    end
    return table.concat(result)
end

return b64
