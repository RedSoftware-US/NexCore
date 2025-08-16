local a = bit32.band
local b = bit32.bxor
local c = bit32.lshift
local d = table.unpack
local e = 2 ^ 32
local function f(g, h)
    local i = g / 2 ^ h
    local j = i % 1
    return i - j + j * e
end
local function k(l, m)
    local n = l / 2 ^ m
    return n - n % 1
end
local o = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19}
local p = {
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2
}
local function q(r, q)
    if e - 1 - r[1] < q then
        r[2] = r[2] + 1
        r[1] = q - (e - 1 - r[1]) - 1
    else
        r[1] = r[1] + q
    end
    return r
end
local function s(t)
    local u = #t
    t[#t + 1] = 0x80
    while #t % 64 ~= 56 do
        t[#t + 1] = 0
    end
    local v = q({0, 0}, u * 8)
    for w = 2, 1, -1 do
        t[#t + 1] = a(k(a(v[w], 0xFF000000), 24), 0xFF)
        t[#t + 1] = a(k(a(v[w], 0xFF0000), 16), 0xFF)
        t[#t + 1] = a(k(a(v[w], 0xFF00), 8), 0xFF)
        t[#t + 1] = a(v[w], 0xFF)
    end
    return t
end
local function x(y, w)
    return c(y[w] or 0, 24) + c(y[w + 1] or 0, 16) + c(y[w + 2] or 0, 8) + (y[w + 3] or 0)
end
local function z(t, w, A)
    local B = {}
    for C = 1, 16 do
        B[C] = x(t, w + (C - 1) * 4)
    end
    for C = 17, 64 do
        local D = B[C - 15]
        local E = b(b(f(B[C - 15], 7), f(B[C - 15], 18)), k(B[C - 15], 3))
        local F = b(b(f(B[C - 2], 17), f(B[C - 2], 19)), k(B[C - 2], 10))
        B[C] = (B[C - 16] + E + B[C - 7] + F) % e
    end
    local G, h, H, I, J, j, K, L = d(A)
    for C = 1, 64 do
        local M = b(b(f(J, 6), f(J, 11)), f(J, 25))
        local N = b(a(J, j), a(bit32.bnot(J), K))
        local O = (L + M + N + p[C] + B[C]) % e
        local P = b(b(f(G, 2), f(G, 13)), f(G, 22))
        local Q = b(b(a(G, h), a(G, H)), a(h, H))
        local R = (P + Q) % e
        L, K, j, J, I, H, h, G = K, j, J, (I + O) % e, H, h, G, (O + R) % e
    end
    A[1] = (A[1] + G) % e
    A[2] = (A[2] + h) % e
    A[3] = (A[3] + H) % e
    A[4] = (A[4] + I) % e
    A[5] = (A[5] + J) % e
    A[6] = (A[6] + j) % e
    A[7] = (A[7] + K) % e
    A[8] = (A[8] + L) % e
    return A
end
return function(t)
    t = t or ""
    t = type(t) == "string" and {t:byte(1, -1)} or t
    t = s(t)
    local A = {d(o)}
    for w = 1, #t, 64 do
        A = z(t, w, A)
    end
    return ("%08x"):rep(8):format(d(A))
end
