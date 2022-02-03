function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(Parsers.parse), Type{Int64}, String})
    precompile(Tuple{typeof(Parsers.parse), Type{Float64}, String})
    precompile(Tuple{typeof(Parsers.parse), Type{Date}, String})

    options = Parsers.Options()
    pos = 0
    source = codeunits("a")
    len = length(source)
    for T in (Char, String)
        Parsers.xparse(T, source, pos, len, options)
        Parsers.xparse(T, source, pos, len, options, Any)
        source = Vector(source)
        Parsers.xparse(T, source, pos, len, options)
        Parsers.xparse(T, source, pos, len, options, Any)
    end
    source = codeunits("123")
    len = length(source)
    for T in (Int8, Int16, Int32, Int64, Float16, Float32, Float64, BigFloat, Dates.Date, Dates.DateTime, Dates.Time, Bool)
        Parsers.xparse(T, source, pos, len, options)
        Parsers.xparse(T, source, pos, len, options, T)
        Parsers.xparse(T, source, pos, len, options, Any)
        source = Vector(source)
        Parsers.xparse(T, source, pos, len, options)
        Parsers.xparse(T, source, pos, len, options, T)
        Parsers.xparse(T, source, pos, len, options, Any)
    end
end
_precompile_()
