function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(Parsers.parse), Type{Int64}, String})
    precompile(Tuple{typeof(Parsers.parse), Type{Float64}, String})
    precompile(Tuple{typeof(Parsers.parse), Type{Date}, String})

    options = Parsers.Options()
    pos = 1
    val = "a"
    len = length(val)
    for T in (Char, String), buf in (codeunits(val), Vector(codeunits(val)))
        Parsers.xparse(T, buf, pos, len, options)
        Parsers.xparse(T, buf, pos, len, options, Any)
    end

    for T in (Char, Symbol), buf in (val, Vector(codeunits(val)))
        Parsers.xparse2(T, buf, pos, len, options)
        Parsers.xparse2(T, buf, pos, len, options, T)
        Parsers.xparse2(T, buf, pos, len, options, Any)
    end

    val = "123"
    len = length(val)
    for T in (Int8, Int16, Int32, Int64, Float16, Float32, Float64, BigFloat, Dates.Date, Dates.DateTime, Dates.Time, Bool), 
        buf in (codeunits(val), Vector(codeunits(val)))
        Parsers.xparse(T, buf, pos, len, options)
        Parsers.xparse(T, buf, pos, len, options, T)
        Parsers.xparse(T, buf, pos, len, options, Any)
    end
    for T in (Int8, Int16, Int32, Int64, Float16, Float32, Float64, BigFloat, Dates.Date, Dates.DateTime, Dates.Time, Bool), 
        buf in (val, SubString(val, 1:3), Vector(codeunits(val)), view(Vector(codeunits(val)), 1:3))
        Parsers.xparse2(T, buf, pos, len, options)
        Parsers.xparse2(T, buf, pos, len, options, T)
        Parsers.xparse2(T, buf, pos, len, options, Any)
    end
    for T in (Int8, Int16, Int32, Int64, Float16, Float32, Float64, BigFloat, Dates.Date, Dates.DateTime), 
        buf in (val, SubString(val, 1:3), Vector(codeunits(val)), view(Vector(codeunits(val)), 1:3))
        Parsers.parse(T, buf)
        Parsers.parse(T, buf, options)
        Parsers.tryparse(T, buf)
    end
end
_precompile_()
