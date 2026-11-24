-- RFC 4648 Base64 (standard and URL-safe) encoder and decoder.
-- Pure Luam over built-in `bit`, zero external C dependencies.

const base64 = {}

const STD_ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
const URL_ALPHA = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

function build_encode_table(alpha)
    tbl = {}
    for i = 1, 64 do
        tbl[i - 1] = string.sub(alpha, i, i)
    end
    return tbl
end

function build_decode_table(alpha)
    tbl = {}
    for i = 1, 64 do
        tbl[string.byte(alpha, i)] = i - 1
    end
    return tbl
end

const STD_ENC = build_encode_table(STD_ALPHA)
const URL_ENC = build_encode_table(URL_ALPHA)
const STD_DEC = build_decode_table(STD_ALPHA)
const URL_DEC = build_decode_table(URL_ALPHA)

function encode_with(bytes, enc, pad)
    if type(bytes) != "string" then
        error("bad argument #1 to 'encode' (string expected, got " .. type(bytes) .. ")", 2)
    end
    len = #bytes
    if len == 0 then
        return ""
    end

    out = {}
    idx = 1
    full_end = len - (len % 3)

    while idx <= full_end do
        b1, b2, b3 = string.byte(bytes, idx, idx + 2)
        n = bit.bor(bit.lshift(b1, 16), bit.lshift(b2, 8), b3)
        c1 = enc[bit.band(bit.rshift(n, 18), 63)]
        c2 = enc[bit.band(bit.rshift(n, 12), 63)]
        c3 = enc[bit.band(bit.rshift(n, 6), 63)]
        c4 = enc[bit.band(n, 63)]
        table.insert(out, c1 .. c2 .. c3 .. c4)
        idx = idx + 3
    end

    rem = len - full_end
    if rem == 1 then
        b1 = string.byte(bytes, full_end + 1)
        c1 = enc[bit.band(bit.rshift(b1, 2), 63)]
        c2 = enc[bit.band(bit.lshift(b1, 4), 63)]
        if pad then
            table.insert(out, c1 .. c2 .. "==")
        else
            table.insert(out, c1 .. c2)
        end
    elseif rem == 2 then
        b1, b2 = string.byte(bytes, full_end + 1, full_end + 2)
        n = bit.bor(bit.lshift(b1, 8), b2)
        c1 = enc[bit.band(bit.rshift(n, 10), 63)]
        c2 = enc[bit.band(bit.rshift(n, 4), 63)]
        c3 = enc[bit.band(bit.lshift(n, 2), 63)]
        if pad then
            table.insert(out, c1 .. c2 .. c3 .. "=")
        else
            table.insert(out, c1 .. c2 .. c3)
        end
    end

    return table.concat(out)
end

function decode_quads(str, dec)
    len = #str
    if len == 0 then
        return "", nil
    end
    if len % 4 != 0 then
        return nil, "invalid base64 length"
    end

    eq_byte = string.byte("=")
    out = {}
    idx = 1

    while idx <= len do
        is_last = (idx + 3 == len)
        ch1, ch2, ch3, ch4 = string.byte(str, idx, idx + 3)

        v1 = dec[ch1]
        v2 = dec[ch2]
        if v1 == nil or v2 == nil then
            return nil, "invalid base64 character"
        end

        if ch3 == eq_byte then
            if (not is_last) or ch4 != eq_byte then
                return nil, "invalid base64 padding"
            end
            b1 = bit.band(bit.bor(bit.lshift(v1, 2), bit.rshift(v2, 4)), 255)
            table.insert(out, string.char(b1))
        elseif ch4 == eq_byte then
            if not is_last then
                return nil, "invalid base64 padding"
            end
            v3 = dec[ch3]
            if v3 == nil then
                return nil, "invalid base64 character"
            end
            n = bit.bor(bit.lshift(v1, 12), bit.lshift(v2, 6), v3)
            b1 = bit.band(bit.rshift(n, 10), 255)
            b2 = bit.band(bit.rshift(n, 2), 255)
            table.insert(out, string.char(b1, b2))
        else
            v3 = dec[ch3]
            v4 = dec[ch4]
            if v3 == nil or v4 == nil then
                return nil, "invalid base64 character"
            end
            n = bit.bor(bit.lshift(v1, 18), bit.lshift(v2, 12), bit.lshift(v3, 6), v4)
            b1 = bit.band(bit.rshift(n, 16), 255)
            b2 = bit.band(bit.rshift(n, 8), 255)
            b3 = bit.band(n, 255)
            table.insert(out, string.char(b1, b2, b3))
        end

        idx = idx + 4
    end

    return table.concat(out), nil
end

function base64.encode(bytes)
    return encode_with(bytes, STD_ENC, true)
end

function base64.decode(b64_str, opts)
    if type(b64_str) != "string" then
        return nil, "base64 input must be a string"
    end
    clean = b64_str
    if opts != nil and opts.ignore_whitespace == true then
        clean = string.gsub(clean, "[ \t\r\n]+", "")
    end
    return decode_quads(clean, STD_DEC)
end

function base64.encode_url(bytes, no_padding)
    pad = (no_padding == false)
    return encode_with(bytes, URL_ENC, pad)
end

function base64.decode_url(b64_str)
    if type(b64_str) != "string" then
        return nil, "base64url input must be a string"
    end
    if #b64_str == 0 then
        return "", nil
    end
    rem = #b64_str % 4
    padded = b64_str
    if rem == 1 then
        return nil, "invalid base64url length"
    elseif rem == 2 then
        padded = b64_str .. "=="
    elseif rem == 3 then
        padded = b64_str .. "="
    end
    return decode_quads(padded, URL_DEC)
end

return base64
