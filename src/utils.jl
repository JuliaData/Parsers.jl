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
    * `NEWLINE`: a non-quoted newline character (`'\n'`), return character (`'\r'`), or CRLF (`"\r\n"`) was detected while parsing (check via `Parsers.newline(code)`)
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

function checksentinel(source::AbstractVector{UInt8}, pos, len, sentinel)
    sentinelpos = 0
    startptr = pointer(source, pos)
    # sentinel is an iterable of Tuple{Ptr{UInt8}, Int}, sorted from longest sentinel string to shortest
    for (ptr, ptrlen) in sentinel
        if pos + ptrlen - 1 <= len
            match = memcmp(startptr, ptr, ptrlen)
            if match
                sentinelpos = pos + ptrlen
                break
            end
        end
    end
    return sentinelpos
end

function checksentinel(source::IO, pos, len, sentinel)
    sentinelpos = 0
    origpos = position(source)
    for (ptr, ptrlen) in sentinel
        matched = match!(source, ptr, ptrlen)
        if matched
            sentinelpos = pos + ptrlen
            break
        end
    end
    fastseek!(source, origpos)
    return sentinelpos
end

function checkdelim(source::AbstractVector{UInt8}, pos, len, (ptr, ptrlen))
    startptr = pointer(source, pos)
    delimpos = pos
    if pos + ptrlen - 1 <= len
        match = memcmp(startptr, ptr, ptrlen)
        if match
            delimpos = pos + ptrlen
        end
    end
    return delimpos
end

function checkdelim(source::IO, pos, len, (ptr, ptrlen))
    delimpos = pos
    matched = match!(source, ptr, ptrlen)
    if matched
        delimpos = pos + ptrlen
    end
    return delimpos
end

@inline function match!(source::IO, ptr, ptrlen)
    b = peekbyte(source)
    c = unsafe_load(ptr)
    if b != c
        return false
    elseif ptrlen == 1
        incr!(source)
        return true
    end
    pos = position(source)
    i = 1
    while true
        incr!(source)
        if Base.eof(source)
            fastseek!(source, pos)
            return false
        end
        b = peekbyte(source)
        c = unsafe_load(ptr + i)
        if b != c
            fastseek!(source, pos)
            return false
        elseif i == ptrlen - 1
            break
        end
        i += 1
    end
    incr!(source)
    return true
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

function incr!(from::IOBuffer)
    from.ptr += 1
    return
end

incr!(::AbstractVector{UInt8}) = nothing
peekbyte(from::IO, pos) = peekbyte(from)
function peekbyte(from::AbstractVector{UInt8}, pos)
    @inbounds b = from[pos]
    return b
end

eof(::AbstractVector{UInt8}, pos::Integer, len::Integer) = pos > len
eof(source::IO, pos::Integer, len::Integer) = Base.eof(source)

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

ptrlen(s::String) = (pointer(s), sizeof(s))

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

@inline function getstring(source::Union{IO, AbstractVector{UInt8}}, x::PosLen, e::UInt8)
    x.escapedvalue && return unescape(source, x, e)
    if source isa AbstractVector{UInt8}
        return _unsafe_string(pointer(source, x.pos), x.len)
    else
        vpos, vlen = x.pos, x.len
        fastseek!(source, vpos - 1)
        str = Base.StringVector(vlen)
        readbytes!(source, str, vlen)
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
