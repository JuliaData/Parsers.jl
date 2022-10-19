isgreedy(::Type{T}) where {T <: AbstractString} = true
isgreedy(T) = false

function typeparser(::Type{T}, source, pos, len, b, code, pl, opts) where {T <: AbstractString}
    if quoted(code)
        code |= OK
        return findendquoted(T, source, pos, len, b, code, pl, true, opts.cq, opts.e, opts.flags.stripquoted)
    elseif opts.flags.checkdelim
        code |= OK
        return finddelimiter(T, source, pos, len, b, code, pl, opts.delim, opts.flags.ignorerepeated, opts.cmt, opts.flags.ignoreemptylines, opts.flags.stripwhitespace)
    else
        code |= OK
        return findeof(source, pos, len, b, code, pl, opts)
    end
end

function findeof(source, pos, len, b, code, pl, opts)
    # no delimiter, so read until EOF
    # if stripwhitespace, then we need to keep track of the last non-whitespace character
    # in order to strip trailing whitespace
    lastnonwhitepos = pos
    while !eof(source, pos, len)
        b = peekbyte(source, pos)
        wh = iswh(b)
        lastnonwhitepos = opts.flags.stripwhitespace ? (wh ? lastnonwhitepos : pos) : pos
        pos += 1
        incr!(source)
    end
    code |= EOF
    pl = poslen(pl.pos, (lastnonwhitepos - pl.pos) + 1)
    return pos, code, pl, pl
end

function typeparser(::Type{Char}, source, pos, len, b, code, pl, opts)
    l = 8 * (4 - leading_ones(b))
    c = UInt32(b) << 24
    s = 16
    while true
        pos += 1
        incr!(source)
        if eof(source, pos, len)
            code |= EOF
            @goto done
        end
        b = peekbyte(source, pos)
        if l >= 24 || s < l || (b & 0xc0) != 0x80
            @goto done
        end
        c |= UInt32(b) << s
        s -= 8
    end

@label done
    ch = reinterpret(Char, c)
    if Base.isoverlong(ch) || Base.ismalformed(ch)
        code |= INVALID
    else
        code |= OK
    end
    return pos, code, PosLen(pl.pos, pos - pl.pos), ch
end

xparse(::Type{Symbol}, source::Union{AbstractVector{UInt8}, IO}, pos, len, options, ::Type{S}=Symbol) where {S} =
    parsesymbol(source, pos, len, options, S)
xparse(::Type{Symbol}, source::AbstractString, pos, len, options, ::Type{Symbol}=Symbol) =
    parsesymbol(codeunits(source), pos, len, options, Symbol)

function parsesymbol(source::Union{AbstractVector{UInt8}, IO}, pos, len, options, ::Type{S}=Symbol) where {S}
    res = xparse(String, source, pos, len, options)
    code = res.code
    poslen = res.val
    if !Parsers.invalid(code) && !Parsers.sentinel(code)
        if source isa AbstractVector{UInt8}
            sym = ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), pointer(source, poslen.pos), poslen.len)
        else
            sym = Symbol(getstring(source, poslen, options.e))
        end
        return Result{S}(code, res.tlen, sym)
    else
        return Result{S}(code, res.tlen)
    end
end

function typeparser(::Type{Symbol}, source, pos, len, b, code, pl, opts)
    if quoted(code)
        code |= OK
        pos, code, pl, pl = findendquoted(Symbol, source, pos, len, b, code, pl, true, opts.cq, opts.e, opts.stripquoted)
    elseif opts.flags.checkdelim
        code |= OK
        pos, code, pl, pl = finddelimiter(Symbol, source, pos, len, b, code, pl, opts.delim, opts.flags.ignorerepeated, opts.cmt, opts.ignoreemptylines, opts.flags.stripwhitespace)
    else
        code |= OK
        pos, code, pl, pl = findeof(source, pos, len, b, code, pl, opts)
    end
    if source isa AbstractVector{UInt8}
        sym = ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), pointer(source, poslen.pos), poslen.len)
    else
        sym = Symbol(getstring(source, poslen, options.e))
    end
    return pos, code, pl, sym
end
