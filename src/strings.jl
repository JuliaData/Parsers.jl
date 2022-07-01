isgreedy(::Type{T}) where {T <: AbstractString} = true
isgreedy(T) = false

function typeparser(::Type{T}, source, pos, len, b, code, pl, opts) where {T <: AbstractString}
    if quoted(code)
        return findendquoted(T, source, pos, len, b, code, pl, true, opts.cq, opts.e, opts.stripquoted)
    elseif opts.checkdelim
        return finddelimiter(T, source, pos, len, b, code, pl, opts.delim, opts.ignorerepeated, opts.cmt, opts.ignoreemptylines, opts.stripwhitespace)
    else
        # no delimiter, so read until EOF
        while !eof(source, pos, len)
            b = peekbyte(source, pos)
            if !opts.stripwhitespace || (b != UInt8(' ') && b != UInt8('\t'))
                pl = poslen(pl.pos, (pos - pl.pos) + 1)
            end
            pos += 1
            incr!(source)
        end
        return pos, code, pl, pl
    end
end

function xparse(::Type{Char}, source, pos, len, options, ::Type{S}=Char) where {S}
    res = xparse(String, source, pos, len, options)
    code = res.code
    poslen = res.val
    if !Parsers.invalid(code) && !Parsers.sentinel(code)
        return Result{S}(code, res.tlen, first(getstring(source, poslen, options.e)))
    else
        return Result{S}(code, res.tlen)
    end
end

function xparse(::Type{Symbol}, source, pos, len, options, ::Type{S}=Symbol) where {S}
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
