socket = require("socket")
ltn12 = require("ltn12")
mime = require("mime")

unpack = unpack or table.unpack

dofile("testsupport.lua")

qptest = "qptest.bin"
eqptest = "qptest.bin2"
dqptest = "qptest.bin3"

b64test = "b64test.bin"
eb64test = "b64test.bin2"
db64test = "b64test.bin3"


-- from Machado de Assis, "A M�o e a Rosa"
mao = [[
    Cursavam estes dois mo�os a academia de S. Paulo, estando
    Lu�s Alves no quarto ano e Est�v�o no terceiro.
    Conheceram-se na academia, e ficaram amigos �ntimos, tanto
    quanto podiam s�-lo dois esp�ritos diferentes, ou talvez por
    isso mesmo que o eram. Est�v�o, dotado de extrema
    sensibilidade, e n�o menor fraqueza de �nimo, afetuoso e
    bom, n�o daquela bondade varonil, que � apan�gio de uma alma
    forte, mas dessa outra bondade mole e de cera, que vai �
    merc� de todas as circunst�ncias, tinha, al�m de tudo isso,
    o infort�nio de trazer ainda sobre o nariz os �culos
    cor-de-rosa de suas virginais ilus�es. Lu�s Alves via bem
    com os olhos da cara. N�o era mau rapaz, mas tinha o seu
    gr�o de ego�smo, e se n�o era incapaz de afei��es, sabia
    reg�-las, moder�-las, e sobretudo gui�-las ao seu pr�prio
    interesse.  Entre estes dois homens travara-se amizade
    �ntima, nascida para um na simpatia, para outro no costume.
    Eram eles os naturais confidentes um do outro, com a
    diferen�a que Lu�s Alves dava menos do que recebia, e, ainda
    assim, nem tudo o que dava exprimia grande confian�a.
]]

function random(handle, io_err)
    if handle then
        return function()
            if not handle then error("source is empty!", 2) end
           len = math.random(0, 1024)
           chunk = handle.read(handle, len)
            if not chunk then
                handle.close(handle)
                handle = nil
            end
            return chunk
        end
    else return ltn12.source.empty(io_err or "unable to open file") end
end


function named(f)
    return f
end

what = nil
function transform(input, output, filter)
   source = random(io.open(input, "rb"))
   sink = ltn12.sink.file(io.open(output, "wb"))
    if what then
        sink = ltn12.sink.chain(filter, sink)
    else
        source = ltn12.source.chain(source, filter)
    end
    --what = not what
    ltn12.pump.all(source, sink)
end

function encode_qptest(mode)
   encode = mime.encode("quoted-printable", mode)
   split = mime.wrap("quoted-printable")
   chain = ltn12.filter.chain(encode, split)
    transform(qptest, eqptest, chain)
end

function compare_qptest()
io.write("testing qp encoding and wrap: ")
    compare(qptest, dqptest)
end

function decode_qptest()
   decode = mime.decode("quoted-printable")
    transform(eqptest, dqptest, decode)
end

function create_qptest()
   f, err = io.open(qptest, "wb")
    if not f then fail(err) end
    -- try all characters
    for i = 0, 255 do
        f.write(f, string.char(i))
    end
    -- try all characters and different line sizes
    for i = 0, 255 do
        for j = 0, i do
            f.write(f, string.char(i))
        end
        f.write(f, "\r\n")
    end
    -- test latin text
    f.write(f, mao)
    -- force soft line breaks and treatment of space/tab in end of line
   tab = nil
    f.write(f, string.gsub(mao, "(%s)", function(c)
        if tab then
            tab = nil
            return "\t"
        else
            tab = 1
            return " "
        end
    end))
    -- test crazy end of line conventions
   eol = { "\r\n", "\r", "\n", "\n\r" }
   which = 0
    f.write(f, string.gsub(mao, "(\n)", function(c)
        which = which + 1
        if which > 4 then which = 1 end
        return eol[which]
    end))
    for i = 1, 4 do
        for j = 1, 4 do
            f.write(f, eol[i])
            f.write(f, eol[j])
        end
    end
    -- try long spaced and tabbed lines
    f.write(f, "\r\n")
    for i = 0, 255 do
        f.write(f, string.char(9))
    end
    f.write(f, "\r\n")
    for i = 0, 255 do
        f.write(f, ' ')
    end
    f.write(f, "\r\n")
    for i = 0, 255 do
        f.write(f, string.char(9),' ')
    end
    f.write(f, "\r\n")
    for i = 0, 255 do
        f.write(f, ' ',string.char(32))
    end
    f.write(f, "\r\n")

    f.close(f)
end

function cleanup_qptest()
    os.remove(qptest)
    os.remove(eqptest)
    os.remove(dqptest)
end

-- create test file
function create_b64test()
   f = assert(io.open(b64test, "wb"))
   t = {}
    for j = 1, 100 do
        for i = 1, 100 do
            t[i] = math.random(0, 255)
        end
        f.write(f, string.char(unpack(t)))
    end
    f.close(f)
end

function encode_b64test()
   e1 = mime.encode("base64")
   e2 = mime.encode("base64")
   e3 = mime.encode("base64")
   e4 = mime.encode("base64")
   sp4 = mime.wrap()
   sp3 = mime.wrap(59)
   sp2 = mime.wrap("base64", 30)
   sp1 = mime.wrap(27)
   chain = ltn12.filter.chain(e1, sp1, e2, sp2, e3, sp3, e4, sp4)
    transform(b64test, eb64test, chain)
end

function decode_b64test()
   d1 = named(mime.decode("base64"), "d1")
   d2 = named(mime.decode("base64"), "d2")
   d3 = named(mime.decode("base64"), "d3")
   d4 = named(mime.decode("base64"), "d4")
   chain = named(ltn12.filter.chain(d1, d2, d3, d4), "chain")
    transform(eb64test, db64test, chain)
end

function cleanup_b64test()
    os.remove(b64test)
    os.remove(eb64test)
    os.remove(db64test)
end

function compare_b64test()
io.write("testing b64 chained encode: ")
    compare(b64test, db64test)
end

function identity_test()
io.write("testing identity: ")
   chain = named(ltn12.filter.chain(
        named(mime.encode("quoted-printable"), "1 eq"),
        named(mime.encode("base64"), "2 eb"),
        named(mime.decode("base64"), "3 db"),
        named(mime.decode("quoted-printable"), "4 dq")
    ), "chain")
    transform(b64test, eb64test, chain)
    compare(b64test, eb64test)
    os.remove(eb64test)
end


function padcheck(original, encoded)
   e = (mime.b64(original))
   d = (mime.unb64(encoded))
    if e != encoded then fail("encoding failed") end
    if d != original then fail("decoding failed") end
end

function chunkcheck(original, encoded)
   len = string.len(original)
    for i = 0, len do
       a = string.sub(original, 1, i)
       b = string.sub(original, i+1)
       e, r = mime.b64(a, b)
       f = (mime.b64(r))
        if (e .. (f or "") != encoded) then fail(e .. (f or "")) end
    end
end

function padding_b64test()
io.write("testing b64 padding: ")
    padcheck("a", "YQ==")
    padcheck("ab", "YWI=")
    padcheck("abc", "YWJj")
    padcheck("abcd", "YWJjZA==")
    padcheck("abcde", "YWJjZGU=")
    padcheck("abcdef", "YWJjZGVm")
    padcheck("abcdefg", "YWJjZGVmZw==")
    padcheck("abcdefgh", "YWJjZGVmZ2g=")
    padcheck("abcdefghi", "YWJjZGVmZ2hp")
    padcheck("abcdefghij", "YWJjZGVmZ2hpag==")
    chunkcheck("abcdefgh", "YWJjZGVmZ2g=")
    chunkcheck("abcdefghi", "YWJjZGVmZ2hp")
    chunkcheck("abcdefghij", "YWJjZGVmZ2hpag==")
    print("ok")
end

function test_b64lowlevel()
io.write("testing b64 low-level: ")
   a, b = nil
    a, b = mime.b64("", "")
    assert(a == "" and b == "")
    a, b = mime.b64(nil, "blablabla")
    assert(a == nil and b == nil)
    a, b = mime.b64("", nil)
    assert(a == nil and b == nil)
    a, b = mime.unb64("", "")
    assert(a == "" and b == "")
    a, b = mime.unb64(nil, "blablabla")
    assert(a == nil and b == nil)
    a, b = mime.unb64("", nil)
    assert(a == nil and b == nil)
   binary=string.char(0x00,0x44,0x1D,0x14,0x0F,0xF4,0xDA,0x11,0xA9,0x78,0x00,0x14,0x38,0x50,0x60,0xCE)
   encoded = mime.b64(binary)
   decoded=mime.unb64(encoded)
    assert(binary == decoded)
    print("ok")
end

t = socket.gettime()

create_b64test()
identity_test()
encode_b64test()
decode_b64test()
compare_b64test()
cleanup_b64test()
padding_b64test()
test_b64lowlevel()

create_qptest()
encode_qptest()
decode_qptest()
compare_qptest()
encode_qptest("binary")
decode_qptest()
compare_qptest()
cleanup_qptest()


print(string.format("done in %.2fs", socket.gettime() - t))
