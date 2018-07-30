make(df::Dates.DateFormat) = df
make(df::String) = Dates.DateFormat(df)

@inline parse!(d::Delimited, io::IO, r::Result{T}; kwargs...) where {T <: Dates.TimeType} =
    parse!(d.next, io, r, d.delims; kwargs...)
@inline parse!(q::Quoted, io::IO, r::Result{T}, delims=nothing; kwargs...) where {T <: Dates.TimeType} =
    parse!(q.next, io, r, delims, q.openquotechar, q.closequotechar, q.escapechar; kwargs...)
@inline parse!(s::Strip, io::IO, r::Result{T}, delims=nothing, openquotechar=nothing, closequotechar=nothing, escapechar=nothing; kwargs...) where {T <: Dates.TimeType} =
    parse!(s.next, io, r, delims, openquotechar, closequotechar, escapechar; kwargs...)
@inline parse!(s::Sentinel, io::IO, r::Result{T}, delims=nothing, openquotechar=nothing, closequotechar=nothing, escapechar=nothing; kwargs...) where {T <: Dates.TimeType} =
    parse!(s.next, io, r, delims, openquotechar, closequotechar, escapechar, s.sentinels; kwargs...)
@inline parse!(::typeof(defaultparser), io::IO, r::Result{T}, delims=nothing, openquotechar=nothing, closequotechar=nothing, escapechar=nothing, node=nothing; kwargs...) where {T <: Dates.TimeType} =
    defaultparser(io, r, delims, openquotechar, closequotechar, escapechar, node; kwargs...)

@inline function defaultparser(io::IO, r::Result{T},
    delims=nothing, openquotechar=nothing, closequotechar=nothing, escapechar=nothing, node=nothing;
    dateformat::Union{String, Dates.DateFormat}=Dates.default_format(T),
    kwargs...) where {T <: Dates.TimeType}
    res = defaultparser(io, Result(String), delims, openquotechar, closequotechar, escapechar, node)
    r.b = res.b
    setfield!(r, 1, missing)
    if res.code === OK
        if res.result isa Missing
            r.code = OK
            return r
        end
        str = res.result::String
        if !isempty(str)
            dt = Base.tryparse(T, str, make(dateformat))
            if dt !== nothing
                r.result = dt
                r.code = OK
                return r
            end
        end
        code = INVALID
    else
        code = res.code
    end
    r.code = code
    return r
end
