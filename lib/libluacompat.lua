local luacompat = {}

local error_mt = {}
function error_mt.__tostring(self)
    return (self.src or "unknown") .. ":" .. self.line .. ": " .. self.text
end

local function util_error(line, col, text)
    error(setmetatable({line = line, col = col, text = text}, error_mt), 0)
end

local classes = {
    operator = "^([;:=%.,%[%]%(%)%{%}%+%-%*/%^%%<>~#&|][=%.<>/]?%.?)()",
    name = "^([%a_][%w_]*)()",
    number = "^(%d+%.?%d*)()",
    scinumber = "^(%d+%.?%d*[eE][%+%-]?%d+)()",
    hexnumber = "^(0[xX]%x+%.?%x*)()",
    scihexnumber = "^(0[xX]%x+%.?%x*[pP][%+%-]?%x+)()",
    linecomment = "^(%-%-[^\n]*)()",
    blockcomment = "^(%-%-%[(=*)%[.-%]%2%])()",
    emptyblockcomment = "^(%-%-%[(=*)%[%]%2%])()",
    blockquote = "^(%[(=*)%[.-%]%2%])()",
    emptyblockquote = "^(%[(=*)%[%]%2%])()",
    dquote = '^("[^"]*")()',
    squote = "^('[^']*')()",
    whitespace = "^(%s+)()",
    invalid = "^([^%w%s_;:=%.,%[%]%(%)%{%}%+%-%*/%^%%<>~#&|]+)()",
}

local classes_precedence = {"name", "scihexnumber", "hexnumber", "scinumber", "number", "blockcomment", "emptyblockcomment", "linecomment", "blockquote", "emptyblockquote", "operator", "dquote", "squote", "whitespace", "invalid"}

local keywords = {
    ["break"] = true,
    ["do"] = true,
    ["else"] = true,
    ["elseif"] = true,
    ["end"] = true,
    ["for"] = true,
    ["function"] = true,
    ["if"] = true,
    ["in"] = true,
    ["local"] = true,
    ["repeat"] = true,
    ["return"] = true,
    ["then"] = true,
    ["until"] = true,
    ["while"] = true,
}

local operators = {
    ["and"] = 0,
    ["not"] = 0,
    ["or"] = 0,
    ["+"] = 0,
    ["-"] = 0,
    ["*"] = 0,
    ["/"] = 0,
    ["%"] = 1,
    ["^"] = 0,
    ["#"] = 1,
    ["=="] = 0,
    ["~="] = 0,
    ["<="] = 0,
    [">="] = 0,
    ["<"] = 0,
    [">"] = 0,
    ["="] = 0,
    ["("] = 0,
    [")"] = 0,
    ["{"] = 0,
    ["}"] = 0,
    ["["] = 0,
    ["]"] = 0,
    ["::"] = 2,
    [";"] = 0,
    [":"] = 0,
    [","] = 0,
    ["."] = 0,
    [".."] = 0,
    ["&"] = 3,
    ["~"] = 3,
    ["|"] = 3,
    ["<<"] = 3,
    [">>"] = 3,
    ["//"] = 3,
}

local constants = {
    ["true"] = true,
    ["false"] = true,
    ["nil"] = true,
    ["..."] = true,
}

local function tokenize(state, text)
    local start = 1
    text = state.pending .. text
    state.pending = ""
    while true do
        local found = false
        for i, v in ipairs(classes_precedence) do
            local s, e, e2 = text:match(classes[v], start)
            if s then
                if v == "dquote" or v == "squote" then
                    local ok = true
                    while not s:gsub("\\.", ""):match(classes[v]) do
                        local s2
                        s2, e = text:match(classes[v], e - 1)
                        if not s2 then ok = false break end
                        s = s .. s2:sub(2)
                    end
                    if not ok then break end
                elseif v == "operator" and #s > 1 then
                    while not (operators[s] or s == "...") and #s > 1 do s, e = s:sub(1, -2), e - 1 end
                end
                if e2 then e = e2 end
                found = true
                state[#state+1] = {type = v, text = s, line = state.line, col = state.col}
                start = e
                local nl = select(2, s:gsub("\n", "\n"))
                if nl == 0 then
                    state.col = state.col + #s
                else
                    state.line = state.line + nl
                    state.col = #s:match("[^\n]*$")
                end
                break
            end
        end
        if not found then state.pending = text:sub(start) break end
    end
end

-- valid token types: operator, constant, keyword, string, number, name, whitespace, comment
local function reduce(state, version, trim)
    for _, v in ipairs(state) do
        if v.type == "operator" then
            if v.text == "..." then v.type = "constant"
            elseif not operators[v.text] or operators[v.text] > version then util_error(v.line, v.col, "invalid operator '" .. v.text .. "'") end
        elseif v.type == "name" then
            if v.text == "goto" then
                if version >= 2 then v.type = "keyword" end
            elseif keywords[v.text] then v.type = "keyword"
            elseif operators[v.text] then v.type = "operator"
            elseif constants[v.text] then v.type = "constant" end
        elseif v.type == "dquote" or v.type == "squote" or v.type == "blockquote" or v.type == "emptyblockquote" then v.type = "string"
        elseif v.type == "linecomment" or v.type == "blockcomment" or v.type == "emptyblockcomment" then v.type = "comment"
        elseif v.type == "hexnumber" or v.type == "scinumber" or v.type == "scihexnumber" then v.type = "number"
        elseif v.type == "invalid" then util_error(v.line, v.col, "invalid characters") end
    end
    if trim then
        local retval = {}
        for _, v in ipairs(state) do
            if v.type == "number" and retval[#retval].type == "operator" and retval[#retval].text == "-" then
                local op = retval[#retval-1]
                if (op.type == "operator" and op.text ~= "}" and op.text ~= "]" and op.text ~= ")") or (op.type == "keyword" and op.text ~= "end") then
                    v.text = "-" .. v.text
                    retval[#retval] = nil
                end
            end
            if v.type ~= "whitespace" and (trim ~= 2 or v.type ~= "comment") then retval[#retval+1] = v end
        end
        return retval
    end
    state.pending, state.line, state.col = nil
    return state
end

local function lex(reader, version, trim)
    if type(reader) == "string" then
        local data = reader
        function reader() local d = data data = nil return d end
    end
    local state = {pending = "", line = 1, col = 1}
    while true do
        local data = reader()
        if not data then break end
        tokenize(state, data)
    end
    if state.pending ~= "" then util_error(state.line, state.col, "unfinished string") end
    return reduce(state, version, trim)
end

---@class (exact) State
---@field new function
---@field readName function
---@field readString function
---@field consume function
---@field next function
---@field back function
---@field peek function
---@field error function
---@field pos number
local State = {}

function State.new(tokens)
    return setmetatable({
        tokens = tokens,
        pos = 1,
        filename = "?",
    }, {__index = State})
end

function State:readName()
    local tok = self:peek()
    if not (tok and tok.type == "name") then self:error("expected name near '" .. (tok and tok.text or "<eof>") .. "'") end
    self:next()
    return {type = "name", value = tok.text}
end

function State:readString()
    local tok = self:peek()
    if not (tok and tok.type == "string") then self:error("expected string near '" .. (tok and tok.text or "<eof>") .. "'") end
    local str = assert(load("return " .. tok.text, "=string", "t", {}))()
    self:next()
    return {type = "string", value = str}
end

function State:readNumber()
    local tok = self:peek()
    if not (tok and tok.type == "number") then self:error("expected number near '" .. (tok and tok.text or "<eof>") .. "'") end
    local num = tonumber(tok.text)
    if not num then self:error("malformed number near '" .. tok.text .. "'") end
    self:next()
    return {type = "number", value = num}
end

function State:consume(type, token)
    local tok = self:peek()
    if not tok then self:error("expected '" .. token .. "' near '<eof>'") end
    if tok.type ~= type or tok.text ~= token then self:error("expected '" .. token .. "' near '" .. tok.text .. "'") end
    self:next()
end

function State:next()
    self.pos = self.pos + 1
end

function State:back()
    self.pos = self.pos - 1
end

function State:peek()
    return self.tokens[self.pos]
end

function State:error(msg)
    local tok = self:peek()
    if tok then error(debug.traceback(self.filename .. ":" .. tok.line .. ":" .. tok.col .. ": " .. msg), 0)
    else error(msg, 0) end
end

local reader = {}

---@param state State
---@return table
---@nodiscard
function reader.block(state)
    local res = {
        type = "block",
        children = {}
    }
    while true do
        --print(":block stat", state.pos)
        local tok = state:peek()
        if not tok then return res end
        if tok.type == "operator" then
            if tok.text == "::" then
                state:next()
                res.children[#res.children+1] = {type = "label", value = state:readName()}
                state:consume("operator", "::")
            elseif tok.text == ";" then state:next()
            elseif tok.text == "(" then res.children[#res.children+1] = reader.callorassign(state)
            else state:error("unexpected token '" .. tok.text .. "'") end
        elseif tok.type == "keyword" then
            if tok.text == "until" or tok.text == "end" or tok.text == "elseif" or tok.text == "else" then
                return res
            elseif tok.text == "break" then
                res.children[#res.children+1] = {type = "break"}
                state:next()
            elseif tok.text == "goto" then
                state:next()
                res.children[#res.children+1] = {type = "goto", value = state:readName()}
            elseif tok.text == "do" then
                state:next()
                res.children[#res.children+1] = reader.block(state)
                state:consume("keyword", "end")
            elseif tok.text == "while" then
                state:next()
                local condition = reader.exp(state)
                state:consume("keyword", "do")
                res.children[#res.children+1] = {type = "while", children = {condition, reader.block(state)}}
                state:consume("keyword", "end")
            elseif tok.text == "repeat" then
                state:next()
                local block = reader.block(state)
                state:consume("keyword", "until")
                res.children[#res.children+1] = {type = "repeat", children = {block, reader.exp(state)}}
            elseif tok.text == "if" then
                state:next()
                local condition = reader.exp(state)
                state:consume("keyword", "then")
                local children = {condition, reader.block(state)}
                while true do
                    tok = state:peek()
                    if not tok then state:error("expected 'end' near '<eof>'") end
                    if tok.type == "keyword" then
                        if tok.text == "elseif" then
                            state:next()
                            children[#children+1] = reader.exp(state)
                            state:consume("keyword", "then")
                            children[#children+1] = reader.block(state)
                        elseif tok.text == "else" then
                            state:next()
                            children[#children+1] = reader.block(state)
                            state:consume("keyword", "end")
                            break
                        elseif tok.text == "end" then
                            state:next()
                            break
                        else state:error("expected 'end' near '" .. tok.text .. "'") end
                    else state:error("expected 'end' near '" .. tok.text .. "'") end
                end
                res.children[#res.children+1] = {type = "if", children = children}
            elseif tok.text == "for" then
                state:next()
                state:next() -- skip name for now
                tok = state:peek()
                if tok.type == "operator" and tok.text == "=" then
                    state:back()
                    local name = state:readName()
                    state:next() -- skip `=`
                    local initial = reader.exp(state)
                    state:consume("operator", ",")
                    local limit = reader.exp(state)
                    tok = state:peek()
                    local step
                    if tok and tok.type == "operator" and tok.text == "," then
                        state:next()
                        step = reader.exp(state)
                    end
                    state:consume("keyword", "do")
                    res.children[#res.children+1] = {type = "for range", children = {name, initial, limit, step, reader.block(state)}}
                    state:consume("keyword", "end")
                elseif (tok.type == "operator" and tok.text == ",") or (tok.type == "keyword" and tok.text == "in") then
                    state:back()
                    local namelist = {state:readName()}
                    tok = state:peek()
                    while tok and tok.type == "operator" and tok.text == "," do
                        state:next()
                        namelist[#namelist+1] = state:readName()
                        tok = state:peek()
                    end
                    state:consume("keyword", "in")
                    local explist = {reader.exp(state)}
                    tok = state:peek()
                    while tok and tok.type == "operator" and tok.text == "," do
                        state:next()
                        explist[#explist+1] = reader.exp(state)
                        tok = state:peek()
                    end
                    state:consume("keyword", "do")
                    res.children[#res.children+1] = {type = "for iter", children = {{type = "namelist", children = namelist}, {type = "explist", children = explist}, reader.block(state)}}
                    state:consume("keyword", "end")
                else state:error("expected 'in' near '" .. tok.text .. "'") end
            elseif tok.text == "function" then
                state:next()
                local name = {state:readName()}
                while true do
                    tok = state:peek()
                    if tok and tok.type == "operator" then
                        if tok.text == "." then
                            state:next()
                            name[#name+1] = state:readName()
                        elseif tok.text == ":" then
                            name[#name+1] = {type = "self"}
                            state:next()
                            name[#name+1] = state:readName()
                            break
                        elseif tok.text == "(" then
                            break
                        else state:error("expected '(' near '" .. tok.text .. "'") end
                    else state:error("expected '(' near '" .. tok.text .. "'") end
                end
                res.children[#res.children+1] = {type = "function", children = {{type = "funcname", children = name}, reader.funcbody(state)}}
            elseif tok.text == "local" then
                state:next()
                tok = state:peek()
                if tok and tok.type == "keyword" and tok.text == "function" then
                    state:next()
                    local name = state:readName()
                    res.children[#res.children+1] = {type = "local function", children = {name, reader.funcbody(state)}}
                else
                    local namelist = {state:readName()}
                    tok = state:peek()
                    if state.version >= 4 and tok and tok.type == "operator" and tok.text == "<" then
                        state:next()
                        namelist[#namelist] = {type = "attribname", children = {namelist[#namelist], state:readName()}}
                        state:consume("operator", ">")
                        tok = state:peek()
                    end
                    while tok and tok.type == "operator" and tok.text == "," do
                        state:next()
                        namelist[#namelist+1] = state:readName()
                        tok = state:peek()
                        if state.version >= 4 and tok and tok.type == "operator" and tok.text == "<" then
                            state:next()
                            namelist[#namelist] = {type = "attribname", children = {namelist[#namelist], state:readName()}}
                            state:consume("operator", ">")
                            tok = state:peek()
                        end
                    end
                    local explist
                    if tok and tok.type == "operator" and tok.text == "=" then
                        state:next()
                        explist = {reader.exp(state)}
                        tok = state:peek()
                        while tok and tok.type == "operator" and tok.text == "," do
                            local1 = false
                            state:next()
                            explist[#explist+1] = reader.exp(state)
                            tok = state:peek()
                        end
                    end
                    res.children[#res.children+1] = {type = "local", children = {{type = "namelist", children = namelist}, explist and {type = "explist", children = explist}}}
                end
            elseif tok.text == "return" then
                state:next()
                tok = state:peek()
                if not tok or (tok.type == "keyword" and (tok.text == "until" or tok.text == "end" or tok.text == "elseif" or tok.text == "else")) then
                    res.children[#res.children+1] = {type = "return", children = {}}
                else
                    local explist = {reader.exp(state)}
                    tok = state:peek()
                    while tok and tok.type == "operator" and tok.text == "," do
                        state:next()
                        explist[#explist+1] = reader.exp(state)
                        tok = state:peek()
                    end
                    res.children[#res.children+1] = {type = "return", children = {{type = "explist", children = explist}}}
                end
            else state:error("unexpected token '" .. tok.text .. "'") end
        elseif tok.type == "name" then res.children[#res.children+1] = reader.callorassign(state)
        else state:error("unexpected token '" .. tok.text .. "'") end
    end
end

---@param state State
---@return table
---@nodiscard
function reader.callorassign(state)
    --print(":callorassign", state.pos)
    local count = 0
    local function next()
        count = count + 1
        return state:next()
    end
    local function brackets(s, e)
        local pc = 1
        while pc > 0 do
            next()
            local tok = state:peek()
            if tok and tok.type == "operator" then
                if tok.text == s then pc = pc + 1
                elseif tok.text == e then pc = pc - 1 end
            end
        end
        next()
    end
    -- skip first part
    local tok = state:peek()
    if tok and tok.type == "operator" and tok.text == "(" then
        brackets("(", ")")
        tok = state:peek()
    elseif tok and tok.type == "name" then
        next()
        tok = state:peek()
    end
    -- find which comes first: parentheses/string/table following a prefixexp, or an equals sign
    local iscall
    while true do
        if tok and tok.type == "operator" then
            if tok.text == "." then
                -- skip .Name
                next() next()
            elseif tok.text == "[" then
                -- skip [:exp]
                brackets("[", "]")
            elseif tok.text == ":" then
                -- this is a call (self-call)
                iscall = 1
                break
            elseif tok.text == "(" then
                -- this is a call
                iscall = true
                break
            elseif tok.text == "{" then
                -- this is a call (table call)
                iscall = true
                break
            elseif tok.text == "=" then
                -- this is an assignment
                iscall = false
                break
            elseif tok.text == "," then
                -- this is an assignment (calls cannot have lists)
                iscall = false
                break
            else state:error("expected '=' near '" .. tok.text .. "'") end
        elseif tok and tok.type == "string" then
            -- this is a call (string call)
            iscall = true
            break
        else state:error("expected '=' near '" .. (tok and tok.text or "<eof>") .. "'")end
        tok = state:peek()
    end
    -- rewind to the start, and execute reader
    for _ = 1, count do state:back() end
    if iscall then
        return reader.call(state)
    else
        return reader.assign(state)
    end
end

---@param state State
---@return table
---@nodiscard
function reader.call(state)
    return reader.prefixexp(state)
end

---@param state State
---@return table
---@return table|nil
---@nodiscard
function reader.assign(state)
    --print(":assign", state.pos)
    local varlist = {reader.var(state)}
    local tok = state:peek()
    while tok and tok.type == "operator" and tok.text == "," do
        state:next()
        varlist[#varlist+1] = reader.var(state)
        tok = state:peek()
    end
    state:consume("operator", "=")
    local explist = {reader.exp(state)}
    tok = state:peek()
    while tok and tok.type == "operator" and tok.text == "," do
        state:next()
        explist[#explist+1] = reader.exp(state)
        tok = state:peek()
    end
    return {type = "assign", children = {{type = "varlist", children = varlist}, {type = "explist", children = explist}}}
end

---@param state State
---@return table
---@nodiscard
function reader.var(state)
    --print(":var", state.pos)
    local names = {state:readName()}
    while true do
        local tok = state:peek()
        if tok and tok.type == "operator" then
            if tok.text == "." then
                state:next()
                names[#names+1] = state:readName()
            elseif tok.text == "[" then
                state:next()
                names[#names+1] = reader.exp(state)
                state:consume("operator", "]")
            else
                return {type = "var", children = names}
            end
        else
            return {type = "var", children = names}
        end
    end
end

---@param state State
---@return table
---@nodiscard
function reader.args(state)
    --print(":args", state.pos)
    local tok = state:peek()
    if tok and tok.type == "string" then
        return {type = "explist", children = {state:readString()}}
    elseif tok and tok.type == "operator" then
        if tok.text == "{" then
            return {type = "explist", children = {reader.table(state)}}
        elseif tok.text == "(" then
            state:next()
            tok = state:peek()
            if tok and tok.type == "operator" and tok.text == ")" then
                state:next()
                return {type = "explist", children = {}}
            end
            local explist = {reader.exp(state)}
            tok = state:peek()
            while tok and tok.type == "operator" and tok.text == "," do
                state:next()
                explist[#explist+1] = reader.exp(state)
                tok = state:peek()
            end
            state:consume("operator", ")")
            --print(":args done", state.pos)
            return {type = "explist", children = explist}
        else state:error("expected '(' near '" .. (tok and tok.text or "<eof>") .. "'") end
    else state:error("expected '(' near '" .. (tok and tok.text or "<eof>") .. "'") end
end

-- prefixexp = [exp(`(` exp `)`)] {name | exp(`[` exp `]`) | explist(`(` explist `)`) | self name explist}

---@param state State
---@return table
---@nodiscard
function reader.prefixexp(state)
    --print(":var", state.pos)
    local tok = state:peek()
    local children
    if tok and tok.type == "operator" and tok.text == "(" then
        state:next()
        children = {reader.exp(state)}
        state:consume("operator", ")")
    elseif tok and tok.type == "name" then
        children = {state:readName()}
    else state:error("expected name near '" .. (tok and tok.text or "<eof>") .. "'") end
    while true do
        tok = state:peek()
        if tok and tok.type == "operator" then
            if tok.text == "." then
                state:next()
                children[#children+1] = state:readName()
            elseif tok.text == "[" then
                state:next()
                children[#children+1] = reader.exp(state)
                state:consume("operator", "]")
            elseif tok.text == "(" or tok.text == "{" then
                children[#children+1] = reader.args(state)
            elseif tok.text == ":" then
                state:next()
                children[#children+1] = {type = "self"}
                children[#children+1] = state:readName()
                children[#children+1] = reader.args(state)
            else
                return {type = "prefixexp", children = children}
            end
        elseif tok and tok.type == "string" then
            children[#children+1] = reader.args(state)
        else
            return {type = "prefixexp", children = children}
        end
    end
end

local binop = {
    ["+"] = 0,
    ["-"] = 0,
    ["*"] = 0,
    ["/"] = 0,
    ["^"] = 0,
    ["%"] = 1,
    [".."] = 0,
    ["<"] = 0,
    ["<="] = 0,
    [">"] = 0,
    [">="] = 0,
    ["=="] = 0,
    ["~="] = 0,
    ["and"] = 0,
    ["or"] = 0,
    ["&"] = 3,
    ["|"] = 3,
    ["~"] = 3,
    ["<<"] = 3,
    [">>"] = 3,
    ["//"] = 3
}

---@param state State
---@return table
---@nodiscard
function reader.exp(state)
    -- TODO: shunting yard
    --print(":exp", state.pos)
    local lhs
    local tok = state:peek()
    if tok then
        if tok.type == "constant" then
            if state.version == 0 and tok.text == "..." then state:error("unexpected '...'") end
            lhs = {type = "constant", value = tok.text}
            state:next()
        elseif tok.type == "number" then
            lhs = state:readNumber()
        elseif tok.type == "string" then lhs = state:readString()
        elseif tok.type == "keyword" then
            if tok.text == "function" then
                state:next()
                lhs = {type = "funcexp", children = {reader.funcbody(state)}}
            else state:error("unexpected '" .. tok.text .. "'") end
        elseif tok.type == "operator" then
            if tok.text == "(" then
                lhs = reader.prefixexp(state)
            elseif tok.text == "{" then
                lhs = reader.table(state)
            elseif tok.text == "-" then
                state:next()
                lhs = {type = "operator", value = "-", children = {reader.exp(state)}}
            elseif tok.text == "not" then
                state:next()
                lhs = {type = "operator", value = "not", children = {reader.exp(state)}}
            elseif tok.text == "#" then
                state:next()
                lhs = {type = "operator", value = "#", children = {reader.exp(state)}}
            else state:error("unexpected '" .. tok.text .. "'") end
        elseif tok.type == "name" then
            lhs = reader.prefixexp(state)
        else state:error("expected expression near '" .. tok.text .. "'") end
    else state:error("expected expression near '<eof>'") end
    tok = state:peek()
    if tok and (tok.type == "operator" or tok.type == "keyword") and binop[tok.text] then
        state:next()
        lhs = {type = "operator", value = tok.text, children = {lhs, reader.exp(state)}}
    end
    --print(":exp done", state.pos)
    return lhs
end

function reader.funcbody(state)
    --print(":funcbody", state.pos)
    local namelist
    state:consume("operator", "(")
    local tok = state:peek()
    if tok and tok.type == "operator" and tok.text == ")" then
        namelist = {type = "namelist", children = {}}
        state:next()
    elseif tok and tok.type == "constant" and tok.text == "..." then
        namelist = {type = "namelist", children = {{type = "constant", value = "..."}}}
        state:next()
        state:consume("operator", ")")
    else
        local names = {state:readName()}
        tok = state:peek()
        while tok and tok.type == "operator" and tok.text == "," do
            state:next()
            tok = state:peek()
            if tok and tok.type == "constant" and tok.text == "..." then
                names[#names+1] = {type = "constant", value = "..."}
                state:next()
                break
            end
            names[#names+1] = state:readName()
            tok = state:peek()
        end
        state:consume("operator", ")")
        namelist = {type = "namelist", children = names}
    end
    local block = reader.block(state)
    state:consume("keyword", "end")
    return {type = "funcbody", children = {namelist, block}}
end

function reader.table(state)
    --print(":table", state.pos)
    local res = {type = "table", children = {}}
    state:consume("operator", "{")
    while true do
        local tok = state:peek()
        if tok then
            if tok.type == "operator" then
                if tok.text == "[" then
                    state:next()
                    local key = reader.exp(state)
                    state:consume("operator", "]")
                    state:consume("operator", "=")
                    res.children[#res.children+1] = {type = "field", children = {key, reader.exp(state)}}
                elseif tok.text == "}" then
                    state:next()
                    return res
                else
                    res.children[#res.children+1] = {type = "field", children = {reader.exp(state)}}
                end
            elseif tok.type == "name" then
                state:next()
                tok = state:peek()
                if tok and tok.type == "operator" and tok.text == "=" then
                    state:back()
                    local key = state:readName()
                    state:next()
                    res.children[#res.children+1] = {type = "field", children = {key, reader.exp(state)}}
                else
                    state:back()
                    res.children[#res.children+1] = {type = "field", children = {reader.exp(state)}}
                end
            else
                res.children[#res.children+1] = {type = "field", children = {reader.exp(state)}}
            end
        else state:error("expected '}' near '<eof>'") end
        tok = state:peek()
        if tok and tok.type == "operator" and tok.text == "}" then
            state:next()
            return res
        elseif tok and tok.type == "operator" and (tok.text == "," or tok.text == ";") then
            state:next()
        else state:error("expected '}' near '" .. (tok and tok.text or "<eof>") .. "'") end
    end
end

local emit = {}

local function emitself(state, tree) return emit[tree.type](state, tree) end
local function addlocals(state, ...)
    local l = setmetatable({}, {__index = state.locals})
    for _, v in ipairs{...} do l[v] = true end
    return setmetatable({locals = l}, {__index = state})
end

function emit.name(state, tree)
    if tree.value == "arg" and state.version > 0 and state.vararg and not state.locals.arg then return state.version > 1 and "table.pack(...)" or "({n=select('#',...),...})" end
    return tree.value
end

function emit.string(state, tree) return ("%q"):format(tree.value) end

function emit.number(state, tree) return tostring(tree.value) end

function emit.block(state, tree)
    state = setmetatable({locals = setmetatable({}, {__index = state.locals})}, {__index = state})
    local retval = ""
    for _, v in ipairs(tree.children) do
        if v.type == "block" then retval = retval .. "do " end
        retval = retval .. emit[v.type](state, v)
        if v.type == "block" then retval = retval .. "end " end
        if v.type == "return" or v.type == "break" or v.type == "goto" then return retval end
    end
    if state.version < 4 then
        for k, v in pairs(state.locals) do
            if v == "close" then
                retval = retval .. "if " .. k .. " then getmetatable(" .. k .. ").__close(" .. k .. ")end "
            end
        end
    end
    return retval
end

function emit.label(state, tree)
    if state.version >= 2 then return "::" .. tree.value .. ":: " end
    -- TODO: goto backcompat
    error("labels not implemented for <5.2")
end

emit["break"] = function(state, tree)
    local retval = ""
    if state.version < 4 then
        for k, v in pairs(state.locals) do
            if v == "close" then
                retval = retval .. "if " .. k .. " then getmetatable(" .. k .. ").__close(" .. k .. ")end "
            end
        end
    end
    return retval .. "break "
end

emit["goto"] = function(state, tree)
    local retval = ""
    -- TODO: make this better
    if state.version < 4 then
        for k, v in pairs(state.locals) do
            if v == "close" then
                retval = retval .. "if " .. k .. " then getmetatable(" .. k .. ").__close(" .. k .. ")end "
            end
        end
    end
    if state.version >= 2 then return retval .. "goto " .. tree.value .. " " end
    -- TODO: goto backcompat
    error("goto not implemented for <5.2")
end

emit["while"] = function(state, tree)
    return "while " .. emitself(state, tree.children[1]) .. " do " .. emit.block(state, tree.children[2]) .. "end "
end

emit["repeat"] = function(state, tree)
    return "repeat " .. emit.block(state, tree.children[1]) .. "until " .. emitself(state, tree.children[2]) .. " "
end

emit["if"] = function(state, tree)
    local retval = "if " .. emitself(state, tree.children[1]) .. " then " .. emit.block(state, tree.children[2])
    local i = 3
    while tree.children[i] do
        if tree.children[i].type == "block" then
            return retval .. "else " .. emit.block(state, tree.children[i]) .. "end "
        else
            retval = retval .. "elseif " .. emitself(state, tree.children[i]) .. " then " .. emit.block(state, tree.children[i+1])
            i = i + 2
        end
    end
    return retval .. "end "
end

emit["for range"] = function(state, tree)
    local retval = "for " .. tree.children[1].value .. "=" .. emitself(state, tree.children[2]) .. "," .. emitself(state, tree.children[3])
    if tree.children[4] then retval = retval .. "," .. emitself(state, tree.children[4]) end
    return retval .. "do " .. emit.block(addlocals(state, tree.children[1].value), tree.children[5]) .. "end "
end

emit["for iter"] = function(state, tree)
    local l = setmetatable({}, {__index = state.locals})
    for _, v in ipairs(tree.children[1]) do l[v.value] = true end
    return "for " .. emit.namelist(state, tree.children[1]) .. " in " .. emit.explist(state, tree.children[2]) .. " do " .. emit.block(setmetatable({locals = l}, {__index = state}), tree.children[3]) .. "end "
end

emit["function"] = function(state, tree)
    local retval = "function "
    for i, v in ipairs(tree.children[1].children) do
        if v.type == "self" then
            retval = retval .. ":" .. tree.children[1].children[i+1].value
            break
        else retval = retval .. (retval == "function " and "" or ".") .. v.value end
    end
    return retval .. emit.funcbody(state, tree.children[2])
end

emit["local function"] = function(state, tree)
    return "local function " .. tree.children[1].value .. emit.funcbody(addlocals(state, tree.children[1].value), tree.children[2])
end

emit["attribname"] = function(state, tree)
    if state.version >= 4 then
        return tree.children[1].value .. "<" .. tree.children[2].value .. ">"
    else
        return tree.children[1].value
    end
end

emit["local"] = function(state, tree)
    local retval = "local " .. emit.namelist(state, tree.children[1])
    if tree.children[2] then retval = retval .. "=" .. emit.explist(state, tree.children[2]) end
    for _, v in ipairs(tree.children[1].children) do
        if v.type == "attribname" then
            state.locals[v.children[1].value] = v.children[2].value
        else state.locals[v.value] = true end
    end
    return retval .. " "
end

function emit.namelist(state, tree)
    local t = ""
    for _, v in ipairs(tree.children) do t = t .. (t == "" and "" or ",") .. emitself(state, v) end
    return t
end

function emit.explist(state, tree)
    local t = ""
    for _, v in ipairs(tree.children) do t = t .. (t == "" and "" or ",") .. emitself(state, v) end
    return t
end

emit["return"] = function(state, tree)
    local retval = ""
    -- TODO: go up the chain
    if state.version < 4 then
        for k, v in pairs(state.locals) do
            if v == "close" then
                retval = retval .. "if " .. k .. " then getmetatable(" .. k .. ").__close(" .. k .. ")end "
            end
        end
    end
    if tree.children[1] then return retval .. "return " .. emit.explist(state, tree.children[1]) .. " "
    else return retval .. "return " end
end

function emit.assign(state, tree)
    if state.version < 4 then
        for _, v in ipairs(tree.children[1]) do
            if #v.children[1] == 1 and v.children[1].type == "name" and state.locals[emit.name(state, v.children[1])] == "const" then
                error("cannot assign value to constant '" .. v.children[1].value .. "'")
            end
        end
    end
    return emit.varlist(state, tree.children[1]) .. "=" .. emit.explist(state, tree.children[2]) .. " "
end

function emit.varlist(state, tree)
    local t = ""
    for _, v in ipairs(tree.children) do t = t .. (t == "" and "" or ",") .. emitself(state, v) end
    return t
end

function emit.var(state, tree)
    local retval = ""
    for _, v in ipairs(tree) do
        if v.type == "name" then retval = retval .. (retval == "" and "" or ".") .. emit.name(state, v)
        else retval = retval .. "[" .. emitself(state, v) .. "]" end
    end
    return retval
end

function emit.constant(state, tree)
    if tree.value == "..." and state.version == 0 then return "unpack(arg)"
    else return tree.value end
end

local opcompat = {
    [0] = {
        ["%"] = "math.mod(%s,%s)",
        ["#"] = "table.getn(%s)",
        ["&"] = "bit_band(%s,%s)",
        ["|"] = "bit_bor(%s,%s)",
        ["~"] = "bit_bxor(%s,%s)",
        ["<<"] = "%s*2^(%s)",
        [">>"] = "math.floor(%s/2^(%s))",
        ["//"] = "math.floor(%s/%s)"
    },
    [1] = {
        ["&"] = "bit_band(%s,%s)",
        ["|"] = "bit_bor(%s,%s)",
        ["~"] = "bit_bxor(%s,%s)",
        ["<<"] = "%s*2^(%s)",
        [">>"] = "math.floor(%s/2^(%s))",
        ["//"] = "math.floor(%s/%s)"
    },
    [2] = {
        ["&"] = "bit32.band(%s,%s)",
        ["|"] = "bit32.bor(%s,%s)",
        ["~"] = "bit32.bxor(%s,%s)",
        ["<<"] = "bit32.lshift(%s,%s)",
        [">>"] = "bit32.rshift(%s,%s)",
        ["//"] = "math.floor(%s/%s)"
    },
    [3] = {},
    [4] = {},
}

function emit.operator(state, tree)
    if #tree.children == 1 then
        if tree.value == "~" and state.version < 3 then
            if state.version < 2 then return "(0xFFFFFFFF-(" .. emitself(state, tree.children[1]) .. "))"
            else return "bit32.bnot(" .. emitself(state, tree.children[1]) .. ")" end
        elseif opcompat[state.version][tree.value] then
            if state.version < 2 and (tree.value == "&" or tree.value == "|" or tree.value == "~") then
                state.needsbit.value = true
            end
            return opcompat[state.version][tree.value]:format(emitself(state, tree.children[1]))
        else return tree.value .. emitself(state, tree.children[1]) end
    else
        if opcompat[state.version][tree.value] then
            return opcompat[state.version][tree.value]:format(emitself(state, tree.children[1]), emitself(state, tree.children[2]))
        else return emitself(state, tree.children[1]) .. tree.value .. emitself(state, tree.children[2]) end
    end
end

function emit.prefixexp(state, tree)
    local retval
    if tree.children[1].type == "name" then retval = emit.name(state, tree.children[1])
    else retval = "(" .. emitself(state, tree.children[1]) .. ")" end
    local i = 2
    while tree.children[i] do
        local v = tree.children[i]
        if v.type == "name" then
            retval = retval .. "." .. v.value
            i = i + 1
        elseif v.type == "self" then
            retval = retval .. ":" .. tree.children[i+1].value
            i = i + 2
        elseif v.type == "explist" then
            retval = retval .. "(" .. emit.explist(state, v) .. ")"
            i = i + 1
        else
            retval = retval .. "[" .. emitself(state, v) .. "]"
            i = i + 1
        end
    end
    return retval
end

function emit.funcexp(state, tree) return "function" .. emit.funcbody(state, tree.children[1]) end

function emit.funcbody(state, tree)
    local vararg = tree.children[1][#tree.children[1]] and tree.children[1][#tree.children[1]].value == "..."
    return "(" .. emit.namelist(state, tree.children[1]) .. ")" .. emit.block(setmetatable({vararg = vararg}, {__index = state}), tree.children[2]) .. "end "
end

function emit.table(state, tree)
    local retval = "{"
    for _, v in ipairs(tree.children) do retval = retval .. emit.field(state, v) .. "," end
    return retval .. "}"
end

function emit.field(state, tree)
    if #tree.children == 1 then return emitself(state, tree.children[1])
    elseif tree.children[1].type == "name" then return tree.children[1].value .. "=" .. emitself(state, tree.children[2])
    else return "[" .. emitself(state, tree.children[1]) .. "]=" .. emitself(state, tree.children[2]) end
end

-- from https://github.com/davidm/lua-bit-numberlua/blob/master/lmod/bit/numberlua.lua (MIT)
local bitlib = [[
local bit_band, bit_bor, bit_bxor do
    local function memoize(f)
        local mt = {}
        local t = setmetatable({}, mt)
        function mt:__index(k)
            local v = f(k); t[k] = v
            return v
        end
        return t
    end

    local function make_bitop_uncached(t, m)
        local function bitop(a, b)
            local res,p = 0,1
            while a ~= 0 and b ~= 0 do
                local am, bm = a%m, b%m
                res = res + t[am][bm]*p
                a = (a - am) / m
                b = (b - bm) / m
                p = p*m
            end
            res = res + (a+b)*p
            return res
        end
        return bitop
    end

    local function make_bitop(t)
        local op1 = make_bitop_uncached(t,2^1)
        local op2 = memoize(function(a)
            return memoize(function(b)
                return op1(a, b)
            end)
        end)
        return make_bitop_uncached(op2, 2^(t.n or 1))
    end

    bit_bxor = make_bitop {[0]={[0]=0,[1]=1},[1]={[0]=1,[1]=0}, n=4}
    function bit_band(a,b) return ((a+b) - bxor(a,b))/2 end
    function bit_bor(a,b)  return MODM - band(MODM - a, MODM - b) end
end
]]

--- Parses a Lua code block to an AST.
---@param text string|function The code (or reader function) to parse
---@param version? string|number The version to parse as (0-4, or "Lua 5.[0-4]"); defaults to `_VERSION`
---@param filename? string The name of the file, for error messages
---@return table ast The generated AST
function luacompat.parse(text, version, filename)
    version = version or _VERSION
    if type(version) == "string" then version = assert(tonumber(version:match "^Lua 5%.(%d)$"), "invalid version string") end
    local tokens = lex(text, version, 2)
    local state = State.new(tokens)
    state.version = version
    state.filename = filename or state.filename
    local res = reader.block(state)
    if state:peek() then state:error("expected '<eof>' near '" .. state:peek().text .. "'") end
    return res
end

--- Emits Lua code for the passed AST.
---@param ast table The AST generated from `luacompat.parse`
---@param version? string|number The version to generate for (0-4, or "Lua 5.[0-4]"); defaults to `_VERSION`
---@return string code The generated Lua code
function luacompat.emit(ast, version)
    version = version or _VERSION
    if type(version) == "string" then version = assert(tonumber(version:match "^Lua 5%.(%d)$"), "invalid version string") end
    local needsbit = {}
    local res = emitself({version = version, locals = {}, vararg = true, needsbit = needsbit}, ast)
    if needsbit.value then res = bitlib .. res end
    return res
end

--- Translates a chunk of code between Lua versions.
---@param chunk string|function The code (or reader function) to translate
---@param from string|number The version to parse as (0-4, or "Lua 5.[0-4]")
---@param to? string|number The version to generate for (0-4, or "Lua 5.[0-4]"); defaults to `_VERSION`
---@param name? string The name of the file, for error messages
---@return string code The translated code
function luacompat.translate(chunk, from, to, name)
    if type(from) == "string" then from = assert(tonumber(from:match "^Lua 5%.(%d)$"), "invalid version string") end
    to = to or _VERSION
    if type(to) == "string" then to = assert(tonumber(to:match "^Lua 5%.(%d)$"), "invalid version string") end
    local tokens = lex(chunk, from, 2)
    local state = State.new(tokens)
    state.version = from
    state.filename = name or state.filename
    local res = reader.block(state)
    if state:peek() then state:error("expected '<eof>' near '" .. state:peek().text .. "'") end
    local needsbit = {}
    local code = emitself({version = to, locals = {}, vararg = true, needsbit = needsbit}, res)
    if needsbit.value then code = bitlib .. code end
    return code
end

--- Loads a chunk of Lua code from another version under the current interpreter.
---@param chunk string|function The code (or reader function) to translate
---@param version string|number The version to parse as (0-4, or "Lua 5.[0-4]")
---@param name? string The name of the chunk
---@param mode? string The mode to load the chunk in
---@param env? table The environment for the chunk
---@return function? fn The loaded function
---@return string? err An error if load failed
function luacompat.load(chunk, version, name, mode, env)
    if version == _VERSION then return load(chunk, name, mode, env) end
    if type(version) == "string" then version = assert(tonumber(version:match "^Lua 5%.(%d)$"), "invalid version string") end
    local ok, tokens = pcall(lex, chunk, version, 2)
    if not ok then return nil, tokens end
    local state = State.new(tokens)
    state.version = version
    state.filename = name or state.filename
    local ok, res = pcall(reader.block, state)
    if not ok then return nil, res end
    if state:peek() then return nil, "expected '<eof>' near '" .. state:peek().text .. "'" end
    local needsbit = {}
    local ok, code = pcall(emitself, {version = tonumber(_VERSION:match "^Lua 5%.(%d)$"), locals = {}, vararg = true, needsbit = needsbit}, res)
    if not ok then return nil, code end
    if needsbit.value then code = bitlib .. code end
    return load(code, name, mode, env)
end

return luacompat
