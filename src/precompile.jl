function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(Parsers.parse), Type{Int64}, String})
    precompile(Tuple{typeof(Parsers.parse), Type{Float64}, String})
    precompile(Tuple{typeof(Parsers.parse), Type{Date}, String})
end
_precompile_()
