struct Error <: Exception
    str::String
    T
    code
end

Error(buf::AbstractString, T, code, pos, tlen) = Error(buf, T, code)
Error(buf::AbstractVector{UInt8}, T, code, pos, tlen) = Error(String(buf[pos:(pos + tlen - 1)]), T, code)

function Error(buf::IO, T, code, pos, tlen)
    fastseek!(buf, pos - 1)
    bytes = read(buf, tlen)
    return Error(String(bytes), T, code)
end

function Base.showerror(io::IO, e::Error)
    c = e.code
    println(io, "Parsers.Error ($(codes(c))):")
    println(io, text(c))
    println(io, "attempted to parse $(e.T) from: \"$(escape_string(e.str))\"")
end

"""
A bitmask value, with various bits corresponding to different parsing signals and scenarios.

`Parsers.xparse` returns a `code` value with various bits set according to the various scenarios
encountered while parsing a value.

* `INVALID`: there are a number of invalid parsing states, all include the INVALID bit set (check via `Parsers.invalid(code)`)
* `OK`: signals specifically that a valid value of type `T` was parsed (check via `Parsers.ok(code)`)
* `SENTINEL`: signals that a valid sentinel value was detected while parsing, passed via the `sentinel` keyword argument to `Parsers.Options` (check via `Parsers.sentinel(code)`)
* `QUOTED`: a `openquotechar` from `Parsers.Options` was detected at the beginning of parsing (check via `Parsers.quoted(code)`)
* `DELIMITED`: a `delim` character or string from `Parsers.Options` was detected while parsing (check via `Parsers.delimited(code)`)
* `NEWLINE`: a non-quoted newline character (`'\\n'`), return character (`'\\r'`), or CRLF (`"\\r\\n"`) was detected while parsing (check via `Parsers.newline(code)`)
* `EOF`: the end of file was reached while parsing
* `ESCAPED_STRING`: an `escapechar` from `Parsers.Options` was encountered while parsing (check via `Parsers.escapedstring(code)`)
* `INVALID_QUOTED_FIELD`: a `openquotechar` were detected when parsing began, but no corresponding `closequotechar` were found to correctly close a quoted field, this is usually a fatal parsing error because parsing will continue until EOF to look for the close quote character (check via `Parsers.invalidquotedfield(code)`)
* `INVALID_DELIMITER`: a `delim` character or string were eventually detected, but not at the expected position (directly after parsing a valid value), indicating there are extra, invalid characters between a valid value and the expected delimiter (check via `Parsers.invaliddelimiter(code)`)
* `OVERFLOW`: overflow occurred while parsing a type, like `Integer`, that have limits on valid values (check via `Parsers.overflow(code)`)

One additional convenience function is provided, `Parsers.quotednotescaped(code)`, which checks if a value was quoted,
but didn't contain any escape characters, useful to indicate if a string may be used "as-is", instead of needing to be unescaped.
"""
const ReturnCode = Int16

const SUCCESS = 0b0000000000000000 % ReturnCode
const INVALID = 0b1000000000000000 % ReturnCode

# success flags
const OK                   = 0b0000000000000001 % ReturnCode
const SENTINEL             = 0b0000000000000010 % ReturnCode

# property flags
const QUOTED               = 0b0000000000000100 % ReturnCode
const DELIMITED            = 0b0000000000001000 % ReturnCode
const NEWLINE              = 0b0000000000010000 % ReturnCode
const EOF                  = 0b0000000000100000 % ReturnCode
const ESCAPED_STRING       = 0b0000001000000000 % ReturnCode

# invalid flags
const INVALID_QUOTED_FIELD = 0b1000000001000000 % ReturnCode
const INVALID_DELIMITER    = 0b1000000010000000 % ReturnCode
const OVERFLOW             = 0b1000000100000000 % ReturnCode
const INVALID_TOKEN        = 0b1000010000000000 % ReturnCode

const EOF_BYTE = 0xFF

valueok(x::ReturnCode) = (x & OK) == OK
ok(x::ReturnCode) = (x & (OK | INVALID)) == OK
invalid(x::ReturnCode) = x < SUCCESS
sentinel(x::ReturnCode) = (x & SENTINEL) == SENTINEL
quoted(x::ReturnCode) = (x & QUOTED) == QUOTED
delimited(x::ReturnCode) = (x & DELIMITED) == DELIMITED
newline(x::ReturnCode) = (x & NEWLINE) == NEWLINE
escapedstring(x::ReturnCode) = (x & ESCAPED_STRING) == ESCAPED_STRING
invalidquotedfield(x::ReturnCode) = (x & INVALID_QUOTED_FIELD) == INVALID_QUOTED_FIELD
invaliddelimiter(x::ReturnCode) = (x & INVALID_DELIMITER) == INVALID_DELIMITER
overflow(x::ReturnCode) = (x & OVERFLOW) == OVERFLOW
quotednotescaped(x::ReturnCode) = (x & (QUOTED | ESCAPED_STRING)) == QUOTED
invalidtoken(x::ReturnCode) = (x & INVALID_TOKEN) == INVALID_TOKEN
eof(x::ReturnCode) = (x & EOF) == EOF

memcmp(a::Ptr{UInt8}, b::Ptr{UInt8}, len::Int) = ccall(:memcmp, Cint, (Ptr{UInt8}, Ptr{UInt8}, Csize_t), a, b, len) == 0

struct RegexAndMatchData
    re::Regex
    data::Ptr{Cvoid}
end

function mkregex(re::Regex)
    Base.compile(re)
    return RegexAndMatchData(re, Base.PCRE.create_match_data(re.regex))
end

const ByteStringRegex = Union{UInt8, String, RegexAndMatchData}

struct Token
    token::ByteStringRegex
end
import Base: ==
==(a::Token, b::Token) = a.token == b.token
_contains(a::Token, str::String) = _contains(a.token, str)
_contains(a::UInt8, str::String) = a == UInt8(str[1])
_contains(a::Char, str::String) = a == str[1]
_contains(a::String, str::String) = contains(a, str)
_contains(a::RegexAndMatchData, str::String) = contains(a.re.pattern, str)
Base.isempty(x::Token) = x.token isa String && isempty(x.token)

@noinline notsupported(source) = error("Regex matching not supported on this source type: $(typeof(source))")

function checktoken(source, pos, len, b, token::Token)
    tok = token.token
    if tok isa UInt8
        check = tok == b
        if check
            incr!(source)
        end
        return check, pos + check
    elseif tok isa String
        if source isa Vector{UInt8}
            # specialize common case
            return checktoken(source, pos, len, b, tok)
        else
            return checktoken(source, pos, len, b, tok)
        end
    elseif tok isa Regex
        if source isa Vector{UInt8}
            return checktoken(source, pos, len, b, tok)
        else
            notsupported(source)
        end
    else
        error() # unreachable
    end
end

function checktoken(source::AbstractVector{UInt8}, pos, len, b, tok::RegexAndMatchData)
    rc = ccall((:pcre2_match_8, Base.PCRE.PCRE_LIB), Cint,
        (Ptr{Cvoid}, Ptr{UInt8}, Csize_t, Csize_t, UInt32, Ptr{Cvoid}, Ptr{Cvoid}),
        tok.re.regex, source, len, pos - 1, tok.re.match_options, tok.data, Base.PCRE.get_local_match_context())
    rc < -2 && error("PCRE.exec error: $(Base.PCRE.err_message(rc))")
    check = rc >= 0
    return check, pos + (!check ? 0 : Base.PCRE.substring_length_bynumber(tok.data, 0))
end

function checktoken(source::AbstractVector{UInt8}, pos, len, b, tok::String)
    sz = sizeof(tok)
    check = (pos + sz - 1) <= len && memcmp(pointer(source, pos), pointer(tok), sz)
    return check, pos + (check * sz)
end

function checktoken(source::IO, pos, len, b, tok::String)
    bytes = codeunits(tok)
    startpos = pos
    blen = length(bytes)
    for i = 1:blen
        @inbounds b2 = bytes[i]
        if b2 != b
            fastseek!(source, startpos - 1)
            return false, startpos
        end
        pos += 1
        incr!(source)
        i == blen && break
        if eof(source, pos, len)
            fastseek!(source, startpos - 1)
            return false, startpos
        end
        b = peekbyte(source, pos)
    end
    return true, pos
end

function checktokens(source, pos, len, b, tokens::Union{Vector{String}, Vector{Token}}, consume=false)
    if source isa IO && !consume
        origpos = position(source)
    end
    for token in tokens
        check, pos = checktoken(source, pos, len, b, token)
        if check
            source isa IO && !consume && fastseek!(source, origpos)
            return true, pos
        end
    end
    source isa IO && !consume && fastseek!(source, origpos)
    return false, pos
end

function checkcmtemptylines(source, pos, len, cmt, ignoreemptylines)
    while !eof(source, pos, len)
        skipped = false
        if ignoreemptylines
            b = peekbyte(source, pos)
            if b == UInt8('\n')
                pos += 1
                incr!(source)
                skipped = true
            elseif b == UInt8('\r')
                pos += 1
                incr!(source)
                if !eof(source, pos, len) && peekbyte(source, pos) == UInt8('\n')
                    pos += 1
                    incr!(source)
                end
                skipped = true
            end
        end
        matched = false
        if !isempty(cmt) && !eof(source, pos, len)
            b = peekbyte(source, pos)
            matched, pos = checktoken(source, pos, len, b, cmt)
            if matched
                eof(source, pos, len) && break
                b = peekbyte(source, pos)
                while true
                    # consume the rest of the line/row until we hit the newline
                    if b == UInt8('\n')
                        pos += 1
                        incr!(source)
                        break
                    elseif b == UInt8('\r')
                        pos += 1
                        incr!(source)
                        if !eof(source, pos, len) && peekbyte(source, pos) == UInt8('\n')
                            pos += 1
                            incr!(source)
                        end
                        break
                    end
                    pos += 1
                    incr!(source)
                    eof(source, pos, len) && break
                    b = peekbyte(source, pos)
                end
            end
        end
        (skipped | matched) || break
    end
    return pos
end

"""
    Parsers.fastseek!(io::IO, n::Integer)

    Without valididty checks, seek an `IO` to desired byte position `n`. Used in Parsers.jl to
    seek back to a previous location already parsed.
"""
function fastseek! end

fastseek!(io::IO, n::Integer) = seek(io, n)
function fastseek!(io::IOBuffer, n::Integer)
    io.ptr = n + 1
    return
end
fastseek!(io::AbstractVector{UInt8}, n::Integer) = nothing

"""
    Parsers.readbyte(io::IO)::UInt8

    Consume a single byte from an `IO` without checking `eof(io)`.
"""
function readbyte end

"""
    Parsers.peekbyte(io::IO)::UInt8

    Return, but do not consume, the next byte from an `IO` without checking `eof(io)`.
"""
function peekbyte end

incr!(io::IO) = readbyte(io)
readbyte(from::IO) = Base.read(from, UInt8)
peekbyte(from::IO) = UInt8(Base.peek(from))
function dpeekbyte(s::IO)
    mark(s)
    b = EOF_BYTE
    nb = EOF_BYTE
    try
        b = read(s, UInt8)::UInt8
        nb = read(s, UInt8)::UInt8
    finally
        reset(s)
    end
    return (b, nb)
end

function readbyte(from::IOBuffer)
    i = from.ptr
    @inbounds byte = from.data[i]
    from.ptr = i + 1
    return byte
end

function peekbyte(from::IOBuffer)
    @inbounds byte = from.data[from.ptr]
    return byte
end
function dpeekbyte(from::IOBuffer)
    @inbounds byte = from.data[from.ptr]
    return byte, from.ptr >= from.size ? EOF_BYTE : @inbounds from.data[from.ptr+1]
end

function incr!(from::IOBuffer)
    from.ptr += 1
    return
end

incr!(::AbstractVector{UInt8}) = nothing
peekbyte(from::IO, pos) = peekbyte(from)
dpeekbyte(from::IO, pos) = dpeekbyte(from)
function peekbyte(from::AbstractVector{UInt8}, pos)
    @inbounds b = from[pos]
    return b
end
function dpeekbyte(from::AbstractVector{UInt8}, pos)
    @inbounds b = from[pos]
    return b, get(from, pos+1, EOF_BYTE)
end

eof(::AbstractVector{UInt8}, pos::Integer, len::Integer) = pos > len
eof(source::IO, pos::Integer, len::Integer) = Base.eof(source)
eof(io::Base.GenericIOBuffer, pos::Integer, len::Integer) = (io.ptr - 1) >= io.size

function text(r)
    str = ""
    if r & QUOTED > 0
        str = "encountered an opening quote character, initial value parsing "
    else
        str = "initial value parsing "
    end
    if r & OK > 0
        str *= "succeeded"
    else
        str *= "failed"
    end
    if r & (~INVALID & OVERFLOW) > 0
        str *= ", value overflowed"
    end
    if r & SENTINEL > 0
        str *= ", a sentinel value was parsed"
    end
    if r & ESCAPED_STRING > 0
        str *= ", encountered escape character"
    end
    if r & (~INVALID & INVALID_QUOTED_FIELD) > 0
        str *= ", invalid quoted value"
    end
    if r & DELIMITED > 0
        str *= ", a valid delimiter was parsed"
    end
    if r & NEWLINE > 0
        str *= ", a newline was encountered"
    end
    if r & EOF > 0
        str *= ", reached EOF"
    end
    if r & (~INVALID & INVALID_DELIMITER) > 0
        str *= ", invalid delimiter"
    end
    return str
end

codes(r) = chop(chop(string(
    ifelse(r > 0, "SUCCESS: ", "INVALID: "),
    ifelse(r & OK > 0, "OK | ", ""),
    ifelse(r & SENTINEL > 0, "SENTINEL | ", ""),
    ifelse(r & QUOTED > 0, "QUOTED | ", ""),
    ifelse(r & ESCAPED_STRING > 0, "ESCAPED_STRING | ", ""),
    ifelse(r & DELIMITED > 0, "DELIMITED | ", ""),
    ifelse(r & NEWLINE > 0, "NEWLINE | ", ""),
    ifelse(r & EOF > 0, "EOF | ", ""),
    ifelse(r & (~INVALID & INVALID_QUOTED_FIELD) > 0, "INVALID_QUOTED_FIELD | ", ""),
    ifelse(r & (~INVALID & INVALID_DELIMITER) > 0, "INVALID_DELIMITER | ", ""),
    ifelse(r & (~INVALID & OVERFLOW) > 0, "OVERFLOW | ", "")
)))

"""
    PosLen(pos, len, ismissing, escaped)

A custom 64-bit primitive that allows efficiently storing the byte position
and length of a value within a byte array, along with whether a sentinel
value was parsed, and whether the parsed value includes escaped characters.
Specifically, the use of 64-bits is:
  * 1 bit to indicate whether a sentinel value was encountered while parsing
  * 1 bit to indicate whether the escape character was encountered while parsing
  * 42 bits to note the byte position as an integer where a value is located in a byte array (max array size ~4.4TB)
  * 20 bits to note the length of a parsed value (max length of ~1MB)

These individual "fields" can be retrieved via dot access, like `poslen.missingvalue`, `poslen.escapedvalue`,
`poslen.pos`, `poslen.len`.

`Parsers.xparse(String, buf, pos, len, opts)` returns `Parsers.Result{PosLen}`, where the `x.val` is a `PosLen`.
"""
primitive type PosLen 64 end

const MAX_POS = 4398046511104
const MAX_LEN = 1048575
@noinline postoolarge(pos) = throw(ArgumentError("position argument to Parsers.PosLen ($pos) is too large; max position allowed is $MAX_POS"))
@noinline lentoolarge(len) = throw(ArgumentError("length argument to Parsers.PosLen ($len) is too large; max length allowed is $MAX_LEN"))

@inline function PosLen(pos::Integer, len::Integer, ismissing=false, escaped=false)
    pos > MAX_POS && postoolarge(pos)
    len > MAX_LEN && lentoolarge(len)
    pos = Int64(pos) << 20
    pos |= ifelse(ismissing, MISSING_BIT, 0)
    pos |= ifelse(escaped, ESCAPE_BIT, 0)
    return Base.bitcast(PosLen, pos | Int64(len))
end

poslen(pos::Integer, len::Integer) = Base.bitcast(PosLen, (Int64(pos) << 20) | Int64(len))
withmissing(pl::PosLen) = Base.or_int(pl, Base.bitcast(PosLen, MISSING_BIT))
withescaped(pl::PosLen) = Base.or_int(pl, Base.bitcast(PosLen, ESCAPE_BIT))

const MISSING_BIT = Base.bitcast(Int64, 0x8000000000000000)
const ESCAPE_BIT = Base.bitcast(Int64, 0x4000000000000000)
const POS_BITS = Base.bitcast(Int64, 0x3ffffffffff00000)
const LEN_BITS = Base.bitcast(Int64, 0x00000000000fffff)

@noinline invalidproperty(nm) = throw(ArgumentError("invalid property $nm for PosLen"))

function Base.getproperty(x::PosLen, nm::Symbol)
    y = Base.bitcast(Int64, x)
    nm === :pos && return (y & POS_BITS) >> 20
    nm === :len && return y & LEN_BITS
    nm === :missingvalue && return (y & MISSING_BIT) == MISSING_BIT
    nm === :escapedvalue && return (y & ESCAPE_BIT) == ESCAPE_BIT
    invalidproperty(nm)
end
Base.propertynames(::PosLen) = (:pos, :len, :missingvalue, :escapedvalue)

Base.show(io::IO, x::PosLen) = print(io, "PosLen(pos=$(x.pos), len=$(x.len), missingvalue=$(x.missingvalue), escapedvalue=$(x.escapedvalue))")

"""
    Parsers.getstring(buf_or_io, poslen::PosLen, e::UInt8) => String

When calling `Parsers.xparse` with a `String` type argument, a `Parsers.Result{PosLen}` is returned, which has 3 fields:
  * `val`: a [`PosLen`](@ref) value which stores the starting byte position and length of the parsed string value
  * `code`: a parsing return code indicating success/failure
  * `tlen`: the total number of bytes parsed, which may differ from `val.len` if delimiters or open/close quotes were parsed

If the actual parsed `String` _is_ needed, however, you can pass your source and the `res.val::PosLen` to `Parsers.getstring`
to get the actual parsed `String` value.
"""
function getstring end

_unsafe_string(p, len) = ccall(:jl_pchar_to_string, Ref{String}, (Ptr{UInt8}, Int), p, len)

getstring(source::Union{IO, AbstractVector{UInt8}}, x::PosLen, e::Token) =
    getstring(source, x, e.token)

@inline function getstring(source::Union{IO, AbstractVector{UInt8}}, x::PosLen, e::UInt8)
    x.escapedvalue && return unescape(source, x, e)
    if source isa AbstractVector{UInt8}
        return _unsafe_string(pointer(source, x.pos), x.len)
    else
        pos = position(source)
        vpos, vlen = x.pos, x.len
        fastseek!(source, vpos - 1)
        str = Base.StringVector(vlen)
        readbytes!(source, str, vlen)
        fastseek!(source, pos) # reset IO to earlier position
        return String(str)
    end
end

getstring(str::AbstractString, poslen::PosLen, e::UInt8) = getstring(codeunits(str), poslen, e)

# if a cell value of a csv file has escape characters, we need to unescape it
@noinline function unescape(origbuf, x::PosLen, e)
    n = x.len
    if origbuf isa AbstractVector{UInt8}
        source = view(origbuf, x.pos:(x.pos + x.len - 1))
    else
        origpos = position(origbuf)
        fastseek!(origbuf, x.pos - 1)
        source = origbuf
    end
    out = Base.StringVector(n)
    len = 1
    i = 1
    @inbounds begin
        while i <= n
            b = peekbyte(source, i)
            if b == e
                incr!(source)
                i += 1
                b = peekbyte(source, i)
            end
            out[len] = b
            len += 1
            incr!(source)
            i += 1
        end
    end
    if origbuf isa IO
        fastseek!(origbuf, origpos)
    end
    resize!(out, len - 1)
    return String(out)
end
