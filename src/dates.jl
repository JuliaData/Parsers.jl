make(df::Dates.DateFormat) = df
make(df::String) = Dates.DateFormat(df)

@inline parse!(d::Delimited{ignorerepeated, newline}, io::IO, r::Result{T}; kwargs...) where {ignorerepeated, newline, T <: Dates.TimeType} =
    parse!(d.next, io, r, d.delims, ignorerepeated, newline; kwargs...)
@inline parse!(q::Quoted, io::IO, r::Result{T}, delims=nothing, ignorerepeated=false, newline=false; kwargs...) where {T <: Dates.TimeType} =
    parse!(q.next, io, r, delims, ignorerepeated, newline, q.openquotechar, q.closequotechar, q.escapechar, q.ignore_quoted_whitespace; kwargs...)
@inline parse!(s::Strip, io::IO, r::Result{T}, delims=nothing, ignorerepeated=false, newline=false, openquotechar=nothing, closequotechar=nothing, escapechar=nothing, ignore_quoted_whitespace=false; kwargs...) where {T <: Dates.TimeType} =
    parse!(s.next, io, r, delims, ignorerepeated, newline, openquotechar, closequotechar, escapechar, ignore_quoted_whitespace; kwargs...)
@inline parse!(s::Sentinel, io::IO, r::Result{T}, delims=nothing, ignorerepeated=false, newline=false, openquotechar=nothing, closequotechar=nothing, escapechar=nothing, ignore_quoted_whitespace=false; kwargs...) where {T <: Dates.TimeType} =
    parse!(s.next, io, r, delims, ignorerepeated, newline, openquotechar, closequotechar, escapechar, ignore_quoted_whitespace, s.sentinels; kwargs...)
@inline parse!(::typeof(defaultparser), io::IO, r::Result{T}, delims=nothing, ignorerepeated=false, newline=false, openquotechar=nothing, closequotechar=nothing, escapechar=nothing, ignore_quoted_whitespace=false, node=nothing; kwargs...) where {T <: Dates.TimeType} =
    defaultparser(io, r, delims, ignorerepeated, newline, openquotechar, closequotechar, escapechar, ignore_quoted_whitespace, node; kwargs...)

@inline function defaultparser(io::IO, r::Result{T},
    delims=nothing, ignorerepeated=false, newline=false, openquotechar=nothing, closequotechar=nothing,
    escapechar=nothing, ignore_quoted_whitespace=false, node=nothing;
    dateformat::Union{String, Dates.DateFormat}=Dates.default_format(T),
    kwargs...) where {T <: Dates.TimeType}
    setfield!(r, 3, Int64(position(io)))
    res = defaultparser(io, Result(String), delims, ignorerepeated, newline, openquotechar, closequotechar, escapechar, ignore_quoted_whitespace, node)
    setfield!(r, 1, missing)
    code = res.code
    if ok(res.code)
        res.result isa Missing && @goto done
        str = res.result::String
        if !isempty(str)
            dt = Base.tryparse(T, str, make(dateformat))
            if dt !== nothing
                r.result = dt
                code |= OK
                @goto done
            end
        end
    end
    code = (INVALID | (code & ~OK))
@label done
    r.code |= code
    return r
end
