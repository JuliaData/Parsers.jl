# high-level convenience functions like in Base
"Attempt to parse a value of type `T` from string `str`. Throws `Parsers.Error` on parser failures and invalid values."
function parse end

"Attempt to parse a value of type `T` from `IO` `io`. Returns `nothing` on parser failures and invalid values."
function tryparse end

const INT_RESULT = Result(Int)
function parse(str::String, ::Type{Int})
    defaultparser(IOBuffer(str), INT_RESULT)
    return INT_RESULT.code === OK ? INT_RESULT.result : throw(Error(INT_RESULT))
end
function parse(io::IOBuffer, ::Type{Int})
    defaultparser(io, INT_RESULT)
    return INT_RESULT.code === OK ? INT_RESULT.result : throw(Error(INT_RESULT))
end
function tryparse(str::String, ::Type{Int})
    defaultparser(IOBuffer(str), INT_RESULT)
    return INT_RESULT.code === OK ? INT_RESULT.result : nothing
end
function tryparse(io::IOBuffer, ::Type{Int})
    defaultparser(io, INT_RESULT)
    return INT_RESULT.code === OK ? INT_RESULT.result : nothing
end

const FLOAT_RESULT = Result(Float64)
function parse(str::String, ::Type{Float64}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(IOBuffer(str), FLOAT_RESULT; decimal=decimal)
    return FLOAT_RESULT.code === OK ? FLOAT_RESULT.result : throw(Error(FLOAT_RESULT))
end
function parse(io::IOBuffer, ::Type{Float64}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(io, FLOAT_RESULT; decimal=decimal)
    return FLOAT_RESULT.code === OK ? FLOAT_RESULT.result : throw(Error(FLOAT_RESULT))
end
function tryparse(str::String, ::Type{Float64}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(IOBuffer(str), FLOAT_RESULT; decimal=decimal)
    return FLOAT_RESULT.code === OK ? FLOAT_RESULT.result : nothing
end
function tryparse(io::IOBuffer, ::Type{Float64}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(io, FLOAT_RESULT; decimal=decimal)
    return FLOAT_RESULT.code === OK ? FLOAT_RESULT.result : nothing
end

const FLOAT32_RESULT = Result(Float32)
function parse(str::String, ::Type{Float32}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(IOBuffer(str), FLOAT32_RESULT; decimal=decimal)
    return FLOAT32_RESULT.code === OK ? FLOAT32_RESULT.result : throw(Error(FLOAT32_RESULT))
end
function parse(io::IOBuffer, ::Type{Float32}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(io, FLOAT32_RESULT; decimal=decimal)
    return FLOAT32_RESULT.code === OK ? FLOAT32_RESULT.result : throw(Error(FLOAT32_RESULT))
end
function tryparse(str::String, ::Type{Float32}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(IOBuffer(str), FLOAT32_RESULT; decimal=decimal)
    return FLOAT32_RESULT.code === OK ? FLOAT32_RESULT.result : nothing
end
function tryparse(io::IOBuffer, ::Type{Float32}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(io, FLOAT32_RESULT; decimal=decimal)
    return FLOAT32_RESULT.code === OK ? FLOAT32_RESULT.result : nothing
end

const FLOAT16_RESULT = Result(Float16)
function parse(str::String, ::Type{Float16}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(IOBuffer(str), FLOAT16_RESULT; decimal=decimal)
    return FLOAT16_RESULT.code === OK ? FLOAT16_RESULT.result : throw(Error(FLOAT16_RESULT))
end
function parse(io::IOBuffer, ::Type{Float16}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(io, FLOAT16_RESULT; decimal=decimal)
    return FLOAT16_RESULT.code === OK ? FLOAT16_RESULT.result : throw(Error(FLOAT16_RESULT))
end
function tryparse(str::String, ::Type{Float16}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(IOBuffer(str), FLOAT16_RESULT; decimal=decimal)
    return FLOAT16_RESULT.code === OK ? FLOAT16_RESULT.result : nothing
end
function tryparse(io::IOBuffer, ::Type{Float16}; decimal::Union{Char, UInt8}=UInt8('.'))
    defaultparser(io, FLOAT16_RESULT; decimal=decimal)
    return FLOAT16_RESULT.code === OK ? FLOAT16_RESULT.result : nothing
end

const BOOL_RESULT = Result(Bool)
function parse(str::String, ::Type{Bool}; bools::Trie=BOOLS)
    defaultparser(IOBuffer(str), BOOL_RESULT; bools=bools)
    return BOOL_RESULT.code === OK ? BOOL_RESULT.result : throw(Error(BOOL_RESULT))
end
function parse(io::IOBuffer, ::Type{Bool}; bools::Trie=BOOLS)
    defaultparser(io, BOOL_RESULT; bools=bools)
    return BOOL_RESULT.code === OK ? BOOL_RESULT.result : throw(Error(BOOL_RESULT))
end
function tryparse(str::String, ::Type{Bool}; bools::Trie=BOOLS)
    defaultparser(IOBuffer(str), BOOL_RESULT; bools=bools)
    return BOOL_RESULT.code === OK ? BOOL_RESULT.result : nothing
end
function tryparse(io::IOBuffer, ::Type{Bool}; bools::Trie=BOOLS)
    defaultparser(io, BOOL_RESULT; bools=bools)
    return BOOL_RESULT.code === OK ? BOOL_RESULT.result : nothing
end

const DATE_RESULT = Result(Date)
function parse(str::String, ::Type{Date}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(Date))
    defaultparser(IOBuffer(str), DATE_RESULT; dateformat=make(dateformat))
    return DATE_RESULT.code === OK ? DATE_RESULT.result : throw(Error(DATE_RESULT))
end
function parse(io::IOBuffer, ::Type{Date}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(Date))
    defaultparser(io, DATE_RESULT; dateformat=make(dateformat))
    return DATE_RESULT.code === OK ? DATE_RESULT.result : throw(Error(DATE_RESULT))
end
function tryparse(str::String, ::Type{Date}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(Date))
    defaultparser(IOBuffer(str), DATE_RESULT; dateformat=make(dateformat))
    return DATE_RESULT.code === OK ? DATE_RESULT.result : nothing
end
function tryparse(io::IOBuffer, ::Type{Date}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(Date))
    defaultparser(io, DATE_RESULT; dateformat=make(dateformat))
    return DATE_RESULT.code === OK ? DATE_RESULT.result : nothing
end

const DATETIME_RESULT = Result(DateTime)
function parse(str::String, ::Type{DateTime}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(DateTime))
    defaultparser(IOBuffer(str), DATETIME_RESULT; dateformat=make(dateformat))
    return DATETIME_RESULT.code === OK ? DATETIME_RESULT.result : throw(Error(DATETIME_RESULT))
end
function parse(io::IOBuffer, ::Type{DateTime}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(DateTime))
    defaultparser(io, DATETIME_RESULT; dateformat=make(dateformat))
    return DATETIME_RESULT.code === OK ? DATETIME_RESULT.result : throw(Error(DATETIME_RESULT))
end
function tryparse(str::String, ::Type{DateTime}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(DateTime))
    defaultparser(IOBuffer(str), DATETIME_RESULT; dateformat=make(dateformat))
    return DATETIME_RESULT.code === OK ? DATETIME_RESULT.result : nothing
end
function tryparse(io::IOBuffer, ::Type{DateTime}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(DateTime))
    defaultparser(io, DATETIME_RESULT; dateformat=make(dateformat))
    return DATETIME_RESULT.code === OK ? DATETIME_RESULT.result : nothing
end

const TIME_RESULT = Result(Time)
function parse(str::String, ::Type{Time}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(Time))
    defaultparser(IOBuffer(str), TIME_RESULT; dateformat=make(dateformat))
    return TIME_RESULT.code === OK ? TIME_RESULT.result : throw(Error(TIME_RESULT))
end
function parse(io::IOBuffer, ::Type{Time}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(Time))
    defaultparser(io, TIME_RESULT; dateformat=make(dateformat))
    return TIME_RESULT.code === OK ? TIME_RESULT.result : throw(Error(TIME_RESULT))
end
function tryparse(str::String, ::Type{Time}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(Time))
    defaultparser(IOBuffer(str), TIME_RESULT; dateformat=make(dateformat))
    return TIME_RESULT.code === OK ? TIME_RESULT.result : nothing
end
function tryparse(io::IOBuffer, ::Type{Time}; dateformat::Union{String, Dates.DateFormat}=Dates.default_format(Time))
    defaultparser(io, TIME_RESULT; dateformat=make(dateformat))
    return TIME_RESULT.code === OK ? TIME_RESULT.result : nothing
end

# generic fallbacks
function parse(str::String, ::Type{T}; kwargs...) where {T}
    res = parse(defaultparser, IOBuffer(str), T; kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end
function parse(io::IO, ::Type{T}; kwargs...) where {T}
    res = parse(defaultparser, io, T; kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end
function parse(f::Base.Callable, str::String, ::Type{T}; kwargs...) where {T}
    res = parse!(f, IOBuffer(str), Result(T); kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end
function parse(f::Base.Callable, io::IO, ::Type{T}; kwargs...) where {T}
    res = parse!(f, io, Result(T); kwargs...)
    return res.code === OK ? res.result : throw(Error(res))
end

function tryparse(str::String, ::Type{T}; kwargs...) where {T}
    res = parse(defaultparser, IOBuffer(str), T; kwargs...)
    return res.code === OK ? res.result : nothing
end
function tryparse(io::IO, ::Type{T}; kwargs...) where {T}
    res = parse(defaultparser, io, T; kwargs...)
    return res.code === OK ? res.result : nothing
end
function tryparse(f::Base.Callable, str::String, ::Type{T}; kwargs...) where {T}
    res = parse!(f, IOBuffer(str), Result(T); kwargs...)
    return res.code === OK ? res.result : nothing
end
function tryparse(f::Base.Callable, io::IO, ::Type{T}; kwargs...) where {T}
    res = parse!(f, io, Result(T); kwargs...)
    return res.code === OK ? res.result : nothing
end
