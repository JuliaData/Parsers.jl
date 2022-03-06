function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing

    options = Parsers.Options()
    pos = 1
    val = "123"
    len = length(val)
    for T in (String, Int32, Int64, Float64, BigFloat, Bool)
        for buf in (codeunits(val), Vector(codeunits(val)))
            Parsers.xparse(T, buf, pos, len, options)
            Parsers.xparse(T, buf, pos, len, options, Any)
        end
    end

    for T in (Int32, Int64, Float64, BigFloat, Bool)
        for buf in (val, SubString(val, 1:3), Vector(codeunits(val)), view(Vector(codeunits(val)), 1:3))
            Parsers.tryparse(T, buf, options)
        end
    end

end
_precompile_()
