@inline parse!(d::Delimited, io::IO, r::Result{T}) where {T <: Dates.TimeType} = parse!(d.next, io, r; delims=d.delims)
@inline parse!(q::Quoted, io::IO, r::Result{T}; kwargs...) where {T <: Dates.TimeType} = parse!(q.next, io, r; openquotechar=q.openquotechar, closequotechar=q.closequotechar, escapechar=q.escapechar, kwargs...)
@inline parse!(s::Strip, io::IO, r::Result{T}; kwargs...) where {T <: Dates.TimeType} = parse!(s.next, io, r; kwargs...)
@inline parse!(s::Sentinel, io::IO, r::Result{T}; kwargs...) where {T <: Dates.TimeType} = parse!(s.next, io, r; node=s.sentinels, kwargs...)

@inline function defaultparser(io::IO, r::Result{T};
    delims::Union{Trie, Nothing}=nothing,
    openquotechar::Union{UInt8, Nothing}=nothing,
    closequotechar::Union{UInt8, Nothing}=nothing,
    escapechar::Union{UInt8, Nothing}=nothing,
    node::Union{Trie, Nothing}=nothing,
    dateformat::Union{String, Dates.DateFormat}=Dates.default_format(T),
    kwargs...) where {T <: Dates.TimeType}
    res = parse!(defaultparser, io, Result(String), delims, openquotechar, closequotechar, escapechar, node)
    r.b = res.b
    if res.code === OK
        r.code = OK
        if res.result === missing
            r.result = missing
        elseif isempty(res.result)
            r.code = INVALID
        else
            dt = Base.tryparse(T, res.result, dateformat)
            if dt === nothing
                r.code = INVALID
            else
                r.result = dt
            end
        end
    else
        r.code = res.code
    end
    return r
end

make(df::Dates.DateFormat) = df
make(df::String) = Dates.DateFormat(df)
