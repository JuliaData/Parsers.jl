# Shared test helpers. Keep these definitions in one file so each included
# kernel suite does not overwrite the same methods in Main.
b(s) = Vector{UInt8}(codeunits(s))
pint(s) = Parsers.parseint64(b(s), 1, ncodeunits(s))
pint128(s) = Parsers.parseint128(b(s), 1, ncodeunits(s))
pflt(s) = Parsers.parsefloat64(b(s), 1, ncodeunits(s))
pbool(s) = Parsers.parsebool(b(s), 1, ncodeunits(s))

const todate = Parsers.todate
const todatetime = Parsers.todatetime
const totime = Parsers.totime

# Function barriers for allocation assertions. Local closures can box tuple
# returns on Julia 1.10 even when the package call itself does not allocate.
parsecustombool(source, trues, falses) =
    Parsers.parse(Bool, source; trues, falses)
tryparsecustombool(source, trues, falses) =
    Parsers.tryparse(Bool, source; trues, falses)
parsenextcustombool(source, trues, falses) =
    Parsers.parsenext(Bool, source, 1, length(source); trues, falses)
parsenextdefault(::Type{T}, source) where {T} =
    Parsers.parsenext(T, source, 1, length(source))
parsegroupedint64(source) = Parsers.parse(Int64, source; groupmark=',')

# A dependency-free offset-axis vector for the public one-based-input contract.
struct OffsetBytes <: AbstractVector{UInt8}
    data::Vector{UInt8}
    offset::Int
end
OffsetBytes(data::Vector{UInt8}) = OffsetBytes(data, 0)
Base.size(source::OffsetBytes) = size(source.data)
Base.axes(source::OffsetBytes) = (source.offset:source.offset + length(source.data) - 1,)
Base.IndexStyle(::Type{OffsetBytes}) = IndexCartesian()
@inline Base.getindex(source::OffsetBytes, i::Int) =
    source.data[i - source.offset + 1]

# A one-based, allocation-free source that exposes a token above Int32's index
# range without allocating the preceding bytes.
struct HugeIndexedBytes <: AbstractVector{UInt8}
    n::Int
    tokenpos::Int
end
Base.size(source::HugeIndexedBytes) = (source.n,)
Base.IndexStyle(::Type{HugeIndexedBytes}) = IndexLinear()
@inline Base.getindex(source::HugeIndexedBytes, i::Int) =
    i == source.tokenpos ? UInt8('1') : UInt8(';')

# A bounds-checking lazy vector for cursor arithmetic at the top of the Int
# index space. Only `tail` is stored; every earlier byte is a delimiter.
struct CheckedTailBytes <: AbstractVector{UInt8}
    n::Int
    tailstart::Int
    tail::Vector{UInt8}
end
function CheckedTailBytes(n::Int, tail::AbstractString)
    bytes = Vector{UInt8}(codeunits(tail))
    0 < length(bytes) <= n || throw(ArgumentError("tail must fit in source"))
    return CheckedTailBytes(n, n - length(bytes) + 1, bytes)
end
Base.size(source::CheckedTailBytes) = (source.n,)
Base.IndexStyle(::Type{CheckedTailBytes}) = IndexLinear()
@inline function Base.getindex(source::CheckedTailBytes, i::Int)
    1 <= i <= source.n || throw(BoundsError(source, i))
    offset = i - source.tailstart + 1
    return 1 <= offset <= length(source.tail) ? source.tail[offset] : UInt8(';')
end

# A lazy byte vector that records reads. It proves bounded scanners without
# allocating a record-sized input buffer.
struct CountingRepeatedBytes <: AbstractVector{UInt8}
    byte::UInt8
    n::Int
    reads::Base.RefValue{Int}
end
Base.size(source::CountingRepeatedBytes) = (source.n,)
Base.IndexStyle(::Type{CountingRepeatedBytes}) = IndexLinear()
@inline function Base.getindex(source::CountingRepeatedBytes, i::Int)
    @boundscheck checkbounds(source, i)
    source.reads[] += 1
    return source.byte
end

# A minimal non-UTF-8 AbstractString for custom Bool sentinel normalization.
struct UTF16TestString <: AbstractString
    data::Vector{UInt16}
end
UTF16TestString(source::AbstractString) = UTF16TestString(transcode(UInt16, String(source)))
Base.ncodeunits(source::UTF16TestString) = length(source.data)
Base.codeunit(::Type{UTF16TestString}) = UInt16
Base.codeunit(source::UTF16TestString, i::Integer) = source.data[i]
Base.isvalid(source::UTF16TestString, i::Integer) = checkbounds(Bool, source.data, i)
Base.length(source::UTF16TestString) = length(source.data)
Base.getindex(source::UTF16TestString, i::Int) = Char(source.data[i])
Base.iterate(source::UTF16TestString, i::Int=1) =
    i > length(source.data) ? nothing : (Char(source.data[i]), i + 1)
parsedateformat(source, dateformat) = Parsers.parse(Date, source; dateformat)
parsenextbigfloat(source) = Parsers.parsenext(BigFloat, source, 1, length(source))
matchcivilname(source, table) =
    Parsers._matchname(source, 1, length(source), table, UInt8(0))
civilnamealloc(source, table) = @allocated matchcivilname(source, table)
