isgreedy(::Type{T}) where {T <: AbstractString} = true
isgreedy(T) = false

function typeparser(::Type{T}, source, pos, len, b, code, pl, opts) where {T <: AbstractString}
    if quoted(code)
        code |= OK
        return findendquoted(T, source, pos, len, b, code, pl, true, opts.cq, opts.e, opts.stripquoted)
    elseif opts.checkdelim
        code |= OK
        return finddelimiter(T, source, pos, len, b, code, pl, opts.delim, opts.ignorerepeated, opts.cmt, opts.ignoreemptylines, opts.stripwhitespace)
    else
        code |= OK
        # no delimiter, so read until EOF
        # if stripwhitespace, then we need to keep track of the last non-whitespace character
        # in order to strip trailing whitespace
        lastnonwhitepos = pos
        while !eof(source, pos, len)
            b = peekbyte(source, pos)
            wh = iswh(b)
            lastnonwhitepos = opts.stripwhitespace == STRIP ? (wh ? lastnonwhitepos : pos) : pos
            pos += 1
            incr!(source)
        end
        code |= EOF
        pl = poslen(pl.pos, (lastnonwhitepos - pl.pos) + 1)
        return pos, code, pl, pl
    end
end

xparse(::Type{Char}, source::Union{AbstractVector{UInt8}, IO}, pos, len, options, ::Type{S}=Char) where {S} =
    parsechar(source, pos, len, options, S)
xparse(::Type{Char}, source::AbstractString, pos, len, options, ::Type{Char}=Char) =
    parsechar(codeunits(source), pos, len, options, Char)

function parsechar(source::Union{AbstractVector{UInt8}, IO}, pos, len, options, ::Type{S}=Char) where {S}
    res = xparse(String, source, pos, len, options)
    code = res.code
    poslen = res.val
    if !Parsers.invalid(code) && !Parsers.sentinel(code)
        return Result{S}(code, res.tlen, first(getstring(source, poslen, options.e)))
    else
        return Result{S}(code, res.tlen)
    end
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
    elseif opts.checkdelim
        code |= OK
        pos, code, pl, pl = finddelimiter(Symbol, source, pos, len, b, code, pl, opts.delim, opts.ignorerepeated, opts.cmt, opts.ignoreemptylines, opts.stripwhitespace)
    else
        code |= OK
        # no delimiter, so read until EOF
        # if stripwhitespace, then we need to keep track of the last non-whitespace character
        # in order to strip trailing whitespace
        lastnonwhitepos = pos
        while !eof(source, pos, len)
            b = peekbyte(source, pos)
            wh = iswh(b)
            lastnonwhitepos = opts.stripwhitespace == STRIP ? (wh ? lastnonwhitepos : pos) : pos
            pos += 1
            incr!(source)
        end
        code |= EOF
        pl = poslen(pl.pos, (lastnonwhitepos - pl.pos) + 1)
    end
    if source isa AbstractVector{UInt8}
        sym = ccall(:jl_symbol_n, Ref{Symbol}, (Ptr{UInt8}, Int), pointer(source, poslen.pos), poslen.len)
    else
        sym = Symbol(getstring(source, poslen, options.e))
    end
    return pos, code, pl, sym
end