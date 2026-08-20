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
