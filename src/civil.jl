# =============================================================================
# dates & times — CivilParts core (no Dates dependency) + format programs
# =============================================================================

"""
    CivilParts

A parsed civil timestamp: pure integers, no calendar library. `nanosecond`
carries full sub-second precision; adapters truncate per target type.
"""
struct CivilParts
    year::Int64
    month::Int8
    day::Int8
    hour::Int8
    minute::Int8
    second::Int8
    nanosecond::Int32
end
CivilParts() = CivilParts(1, 1, 1, 0, 0, 0, 0)

const _DAYSINMONTH = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
@inline _isleap(y::Integer) = (y % 4 == 0) && ((y % 100 != 0) || (y % 400 == 0))
@inline function _validymd(y::Integer, m::Integer, d::Integer)
    1 <= m <= 12 || return false
    dim = @inbounds _DAYSINMONTH[m] + ((m == 2 && _isleap(y)) ? 1 : 0)
    return 1 <= d <= dim
end
@inline _validhms(h, mi, s) = (0 <= h <= 23) & (0 <= mi <= 59) & (0 <= s <= 59)

"""
    daysfromcivil(y, m, d) -> Int64

Days since 0000-12-31 (Rata Die), matching `Dates.value(Date(y,m,d))` — this
IS the Dates stdlib's `totaldays` formula (shift the year to start on March 1
so the leap day is the year's last day; then days + month offset + year days),
carried here without a Dates dependency so Dates can one day call it instead.
Equivalence is pinned exhaustively (every day of years -1000..3000 and the
extremes) in the test suite; the earlier Hinnant era/year-of-era form was
identical over ±9999 but ~35% slower.
"""
const _SHIFTEDMONTHDAYS = (306, 337, 0, 31, 61, 92, 122, 153, 184, 214, 245, 275)
@inline function daysfromcivil(y::Integer, m::Integer, d::Integer)
    z = Int64(y) - (m < 3)
    return Int64(d) + @inbounds(_SHIFTEDMONTHDAYS[m]) + 365z + fld(z, 4) - fld(z, 100) +
           fld(z, 400) - 306
end

# --- format programs -----------------------------------------------------------
#
# Pattern compilation first uses a flat vector of ops. Numeric fields consume
# 1..width digits (fixed = exactly width); literals must match exactly;
# month/day-name ops consume letters and match the supplied name tables. The
# builder then takes ownership of the ops behind an immutable plan handle.
# `dates.jl` translates and caches DateFormat values. Both adapters feed this
# private plan-construction input.

struct PatternOp
    kind::UInt8     # 1=year 2=month 3=day 4=hour 5=minute 6=second 7=subsec
                    # 8=literal 9=monthname-abbrev 10=monthname-full
                    # 11=hour12 12=am/pm 13=dayname-abbrev 14=dayname-full
    width::Int      # numeric: max digits; fixed ⇒ exactly; literal: byte
    fixed::Bool
end

PatternOp(kind::Integer, width::Integer, fixed::Bool) =
    PatternOp(UInt8(kind), Int(width), fixed)

# Compact description for all-fixed numeric formats. Literal positions are
# validated eight bytes at a time. Numeric offsets then feed direct field
# readers. A zero byte count disables this fixed-width path.
struct FixedDatePattern
    nbytes::UInt8
    offsets::NTuple{7, UInt8}
    widths::NTuple{7, UInt8}
    masks::NTuple{4, UInt64}
    values::NTuple{4, UInt64}
end
FixedDatePattern() = FixedDatePattern(0, ntuple(_ -> 0x00, 7), ntuple(_ -> 0x00, 7),
                                      ntuple(_ -> UInt64(0), 4), ntuple(_ -> UInt64(0), 4))

# Direct descriptor for three numeric date fields separated by one-byte
# literals. Compilation proves the field set and stores its order, so the
# executor does not decode the general civil bytecode for each value.
struct NumericDelimitedDatePattern
    delimiters::NTuple{2, UInt8}
    widths::NTuple{3, UInt8}
    fixed::UInt8
    order::UInt8
end
NumericDelimitedDatePattern() =
    NumericDelimitedDatePattern((0x00, 0x00), (0x00, 0x00, 0x00), 0x00, 0x00)

struct CivilNameTrie
    nodes::String
    edges::String
end
CivilNameTrie() = CivilNameTrie("", "")

struct CivilNameTable{N}
    raw::NTuple{N, String}
    values::NTuple{N, Int8}
    trie::CivilNameTrie
    maxchars::Int
    executor::UInt8
end

function CivilNameTrie(raw::NTuple{N, String}, values::NTuple{N, Int8}) where {N}
    # The packed accelerator uses UInt16 states. This conservative preflight
    # avoids constructing a large transient trie when the keys cannot fit.
    # An empty trie selects the allocation-free tuple matcher below; it is not
    # a public limit on locale-name length.
    maxnodes = 1
    for key in raw
        nchars = length(key)
        nchars > Int(typemax(UInt16)) - maxnodes && return CivilNameTrie()
        maxnodes += nchars
    end
    nodes = [Dict{UInt32, Int}()]
    nodevalues = Int8[0]
    for i in 1:N
        isempty(raw[i]) && continue
        state = 1
        for c in raw[i]
            code = UInt32(c)
            next = get(nodes[state], code, 0)
            if next == 0
                push!(nodes, Dict{UInt32, Int}())
                push!(nodevalues, 0)
                next = length(nodes)
                nodes[state][code] = next
            end
            state = next
        end
        nodevalues[state] = values[i]
    end
    length(nodes) <= typemax(UInt16) || return CivilNameTrie()
    nodewords = UInt64[]
    edgewords = UInt64[]
    for state in eachindex(nodes)
        edges = nodes[state]
        value = UInt64(reinterpret(UInt8, nodevalues[state])) << 56
        if length(edges) == 1
            code, next = first(edges)
            push!(nodewords, value | UInt64(code) | (UInt64(next) << 32))
        else
            length(edges) <= typemax(UInt8) || return CivilNameTrie()
            firstedge = length(edgewords) + 1
            firstedge <= typemax(UInt16) || return CivilNameTrie()
            push!(nodewords, value | (UInt64(firstedge) << 32) |
                             (UInt64(length(edges)) << 48))
            for (code, next) in sort!(collect(edges); by=first)
                push!(edgewords, UInt64(code) | (UInt64(next) << 32))
            end
        end
    end
    nodebytes = String(reinterpret(UInt8, htol.(nodewords)))
    edgebytes = String(reinterpret(UInt8, htol.(edgewords)))
    return CivilNameTrie(nodebytes, edgebytes)
end

# Trie storage is a little-endian sequence of packed UInt64 words. A node with
# a nonzero low UInt32 has one edge: bits 0:31 are the Unicode scalar, bits
# 32:47 are its UInt16 target, and bits 56:63 are the terminal Int8 value. A
# zero low UInt32 marks a branch: bits 32:47 are the first edge index, bits
# 48:55 are the edge count, and bits 56:63 retain the terminal value. Each edge
# word stores its scalar in bits 0:31 and target in bits 32:47. Construction
# uses `htol`; every load uses `ltoh`, so the byte layout is host-independent.
# Empty `nodes` is the explicit oversized-table sentinel.
@inline function _civiltrieword(bytes::String, index::Int)
    GC.@preserve bytes return ltoh(unsafe_load(Ptr{UInt64}(pointer(bytes, 8index - 7))))
end

@inline function _civiltrienext(trie::CivilNameTrie, state::UInt16, c::Char)
    state == 0 && return UInt16(0)
    node = _civiltrieword(trie.nodes, Int(state))
    single = UInt32(node & 0xffffffff)
    single != 0 && return single == UInt32(c) ?
        UInt16((node >> 32) & 0xffff) : UInt16(0)
    lo = Int(UInt16((node >> 32) & 0xffff))
    hi = lo + Int(UInt8((node >> 48) & 0xff)) - 1
    code = UInt32(c)
    while lo <= hi
        mid = (lo + hi) >>> 1
        edge = _civiltrieword(trie.edges, mid)
        candidate = UInt32(edge & 0xffffffff)
        if candidate == code
            return UInt16((edge >> 32) & 0xffff)
        elseif candidate < code
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return UInt16(0)
end

@inline _civiltrievalue(trie::CivilNameTrie, state::UInt16) =
    Int8(UInt8((_civiltrieword(trie.nodes, Int(state)) >> 56) & 0xff))

struct CivilNames
    months_abbr::CivilNameTable{24}
    months_full::CivilNameTable{24}
    days_abbr::CivilNameTable{14}
    days_full::CivilNameTable{14}
end

# Keep GC-bearing locale tables behind one write-once pointer. Numeric pattern
# execution must not root all locale lookup keys in its hot frame.
mutable struct CivilNamesBox
    const names::CivilNames
end

# A compiled program is immutable bytecode, not text. Common ops own two bytes:
# kind plus flags, then width or literal. Widths above 255 use an unsigned
# variable-length integer. `String` supplies a compact immutable byte buffer
# for any program length. Consumers use only `ncodeunits` and `codeunit`; bytes
# such as 0xff are deliberately not UTF-8.
struct CivilProgram
    code::String
end

const _WIDE_PATTERN_OP = UInt8(0x20)

function CivilProgram(ops::Vector{PatternOp})
    bytes = UInt8[]
    sizehint!(bytes, 2length(ops))
    for op in ops
        op.width >= 0 || throw(ArgumentError("negative civil pattern width"))
        tag = op.kind | (op.fixed ? 0x10 : 0x00)
        if op.width <= typemax(UInt8)
            push!(bytes, tag, UInt8(op.width))
        else
            push!(bytes, tag | _WIDE_PATTERN_OP)
            value = UInt(op.width)
            while value >= 0x80
                push!(bytes, UInt8(value & 0x7f) | 0x80)
                value >>= 7
            end
            push!(bytes, UInt8(value))
        end
    end
    return CivilProgram(String(bytes))
end

# The plan and its op program are immutable. A private write-once box below
# keeps the public handle pointer-sized without copying the locale tables and
# compiled descriptors each time the handle is passed.
struct CivilPlan
    ops::CivilProgram
    flags::UInt8
    executor::UInt8
    names::CivilNamesBox
    fixed::FixedDatePattern
    numeric::NumericDelimitedDatePattern
end

mutable struct CivilPlanBox
    const plan::CivilPlan
end

"""
    DatePattern

A compiled, immutable date/time parse plan. Create one with `compilepattern`,
then reuse it with `parsecivil` or as the `dateformat` keyword of
`Parsers.parse`. Its representation is internal. The plan owns its op program,
fast-path choice, and month/day name tables.
Use `compilepattern` rather than constructing or inspecting a plan directly.
"""
struct DatePattern
    _storage::CivilPlanBox

    # Prevent the representation constructor from becoming an accidental
    # interface. Every plan must pass through `_makepattern` below.
    DatePattern(storage::CivilPlanBox, ::Val{:compiled}) = new(storage)
end

Base.show(io::IO, ::DatePattern) = print(io, "Parsers.DatePattern(<compiled>)")

const ENGLISH_MONTHS_ABBR = ("Jan", "Feb", "Mar", "Apr", "May", "Jun",
                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
const ENGLISH_DAYS_ABBR = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
const ENGLISH_DAYS_FULL = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                           "Saturday", "Sunday")
const ENGLISH_MONTHS_FULL = ("January", "February", "March", "April", "May", "June",
                             "July", "August", "September", "October", "November",
                             "December")

const _EXECUTE_NAMES = UInt8(0x00)
const _EXECUTE_ENGLISH_MONTHS_ABBR = UInt8(0x01)

function _civilnametable(entries::AbstractDict{String, <:Integer}, ::Val{N},
                         executor::UInt8) where {N}
    length(entries) <= N || throw(ArgumentError("too many civil name keys"))
    pairs = sort!(collect(entries); by=first)
    raw = ntuple(i -> i <= length(pairs) ? String(pairs[i].first) : "", N)
    values = ntuple(i -> begin
        i <= length(pairs) || return Int8(0)
        value = pairs[i].second
        1 <= value <= typemax(Int8) ||
            throw(ArgumentError("civil name value $value is outside the supported range"))
        Int8(value)
    end, N)
    maxchars = 0
    for i in 1:N
        maxchars = max(maxchars, length(raw[i]))
    end
    return CivilNameTable{N}(raw, values, CivilNameTrie(raw, values),
                             maxchars, executor)
end

function CivilNameTable(names::NTuple{N, String}) where {N}
    2N <= typemax(Int8) || throw(ArgumentError("too many civil names"))
    entries = Dict{String, Int8}()
    for i in 1:N
        entries[names[i]] = Int8(i)
        entries[lowercase(names[i])] = Int8(i)
    end
    executor = names == ENGLISH_MONTHS_ABBR ? _EXECUTE_ENGLISH_MONTHS_ABBR :
               _EXECUTE_NAMES
    return _civilnametable(entries, Val(2N), executor)
end

CivilNameTable(entries::AbstractDict{String, <:Integer}, size::Val) =
    _civilnametable(entries, size, _EXECUTE_NAMES)

CivilNames(months_abbr::NTuple{12, String}, months_full::NTuple{12, String},
           days_abbr::NTuple{7, String}, days_full::NTuple{7, String}) =
    CivilNames(CivilNameTable(months_abbr), CivilNameTable(months_full),
               CivilNameTable(days_abbr), CivilNameTable(days_full))

const _ENGLISH_CIVIL_NAMES = CivilNames(ENGLISH_MONTHS_ABBR, ENGLISH_MONTHS_FULL,
                                        ENGLISH_DAYS_ABBR, ENGLISH_DAYS_FULL)
const _ENGLISH_CIVIL_NAMES_BOX = CivilNamesBox(_ENGLISH_CIVIL_NAMES)

const _HAS_DATE = UInt8(0x01)
const _HAS_TIME = UInt8(0x02)
const _EXECUTE_PROGRAM = UInt8(0x00)
const _EXECUTE_ISO_DATE = UInt8(0x01)
const _EXECUTE_ISO_DATETIME = UInt8(0x02)
const _EXECUTE_ISO_TIME = UInt8(0x03)
const _EXECUTE_NUMERIC_DATE = UInt8(0x04)
const _ORDER_YMD = UInt8(0x39)
const _ORDER_YDM = UInt8(0x2d)
const _ORDER_MYD = UInt8(0x36)
const _ORDER_MDY = UInt8(0x1e)
const _ORDER_DYM = UInt8(0x27)
const _ORDER_DMY = UInt8(0x1b)

function _fixeddatepattern(ops::Vector{PatternOp})
    offsets = fill(UInt8(0), 7)
    widths = fill(UInt8(0), 7)
    masks = fill(UInt64(0), 4)
    values = fill(UInt64(0), 4)
    pos = 1
    for op in ops
        if op.kind == 8
            pos <= 32 || return FixedDatePattern()
            block = (pos - 1) ÷ 8 + 1
            shift = 8 * ((pos - 1) % 8)
            masks[block] |= UInt64(0xff) << shift
            values[block] |= UInt64(op.width) << shift
            pos += 1
        elseif 1 <= op.kind <= 7 && op.fixed && op.width > 0
            field = Int(op.kind)
            offsets[field] == 0 || return FixedDatePattern()
            pos + Int(op.width) - 1 <= 32 || return FixedDatePattern()
            offsets[field] = UInt8(pos)
            widths[field] = UInt8(op.width)
            pos += Int(op.width)
        else
            return FixedDatePattern()
        end
    end
    1 < pos <= 33 || return FixedDatePattern()
    return FixedDatePattern(UInt8(pos - 1), Tuple(offsets), Tuple(widths),
                            Tuple(masks), Tuple(values))
end

function _numericdatepattern(ops::Vector{PatternOp})
    length(ops) == 5 || return NumericDelimitedDatePattern()
    @inbounds begin
        ops[2].kind == 8 || return NumericDelimitedDatePattern()
        ops[4].kind == 8 || return NumericDelimitedDatePattern()
        kinds = (ops[1].kind, ops[3].kind, ops[5].kind)
        all(kind -> 1 <= kind <= 3, kinds) || return NumericDelimitedDatePattern()
        (UInt8(1) << kinds[1]) | (UInt8(1) << kinds[2]) | (UInt8(1) << kinds[3]) ==
            0x0e || return NumericDelimitedDatePattern()
        all(op -> 0 < op.width <= typemax(UInt8), (ops[1], ops[3], ops[5])) ||
            return NumericDelimitedDatePattern()
        widths = (UInt8(ops[1].width), UInt8(ops[3].width), UInt8(ops[5].width))
        fixed = UInt8(ops[1].fixed) | (UInt8(ops[3].fixed) << 1) |
                (UInt8(ops[5].fixed) << 2)
        order = kinds[1] | (kinds[2] << 2) | (kinds[3] << 4)
        return NumericDelimitedDatePattern((UInt8(ops[2].width), UInt8(ops[4].width)),
                                           widths, fixed, order)
    end
end

const _ISO_DATE_OPS = (
    PatternOp(0x01, 0xff, false), PatternOp(0x08, UInt8('-'), true),
    PatternOp(0x02, 0xff, false), PatternOp(0x08, UInt8('-'), true),
    PatternOp(0x03, 0xff, false),
)
const _ISO_TIME_OPS = (
    PatternOp(0x04, 0xff, false), PatternOp(0x08, UInt8(':'), true),
    PatternOp(0x05, 0xff, false), PatternOp(0x08, UInt8(':'), true),
    PatternOp(0x06, 0xff, false), PatternOp(0x08, UInt8('.'), true),
    PatternOp(0x07, 0x09, false),
)
const _ISO_DATETIME_OPS = (
    PatternOp(0x01, 0xff, false), PatternOp(0x08, UInt8('-'), true),
    PatternOp(0x02, 0xff, false), PatternOp(0x08, UInt8('-'), true),
    PatternOp(0x03, 0xff, false), PatternOp(0x08, UInt8('T'), true),
    PatternOp(0x04, 0xff, false), PatternOp(0x08, UInt8(':'), true),
    PatternOp(0x05, 0xff, false), PatternOp(0x08, UInt8(':'), true),
    PatternOp(0x06, 0xff, false), PatternOp(0x08, UInt8('.'), true),
    PatternOp(0x07, 0x09, false),
)

@inline function _sameops(ops::Vector{PatternOp}, expected::Tuple)
    length(ops) == length(expected) || return false
    @inbounds for i in eachindex(ops)
        ops[i] == expected[i] || return false
    end
    return true
end

@inline function _executor(ops::Vector{PatternOp}, numeric::NumericDelimitedDatePattern)
    _sameops(ops, _ISO_DATE_OPS) && return _EXECUTE_ISO_DATE
    _sameops(ops, _ISO_DATETIME_OPS) && return _EXECUTE_ISO_DATETIME
    _sameops(ops, _ISO_TIME_OPS) && return _EXECUTE_ISO_TIME
    numeric.order != 0 && return _EXECUTE_NUMERIC_DATE
    return _EXECUTE_PROGRAM
end

function _makepattern(ops::Vector{PatternOp}, natural::Vector{PatternOp},
                      hasdate::Bool, hastime::Bool, names::CivilNamesBox)
    flags = (hasdate ? _HAS_DATE : 0x00) | (hastime ? _HAS_TIME : 0x00)
    numeric = _numericdatepattern(ops)
    executor = _executor(ops, numeric)
    plan = CivilPlan(CivilProgram(ops), flags, executor, names,
                     _fixeddatepattern(natural), numeric)
    return DatePattern(CivilPlanBox(plan), Val(:compiled))
end

@inline _hasdate(flags::UInt8) = (flags & _HAS_DATE) != 0
@inline _hastime(flags::UInt8) = (flags & _HAS_TIME) != 0

# `Dates.DateFormat` is compiled directly in dates.jl and passes the resulting
# pattern through the existing API hook. Keeping this identity method here
# avoids converting a typed token program back to a format string.
compilepattern(p::DatePattern) = p

@inline _patternkind(c::Char) =
    c == 'y' || c == 'Y' ? UInt8(1) :
    c == 'm' ? UInt8(2) : c == 'd' ? UInt8(3) : c == 'H' ? UInt8(4) :
    c == 'M' ? UInt8(5) : c == 'S' ? UInt8(6) : c == 's' ? UInt8(7) :
    c == 'u' ? UInt8(9) : c == 'U' ? UInt8(10) : c == 'I' ? UInt8(11) :
    c == 'p' ? UInt8(12) : c == 'e' ? UInt8(13) : c == 'E' ? UInt8(14) : UInt8(0)

@inline _kindhasdate(kind::UInt8) = kind in (0x01, 0x02, 0x03, 0x09, 0x0a)
@inline _kindhastime(kind::UInt8) = kind in (0x04, 0x05, 0x06, 0x07, 0x0b, 0x0c)
@inline _isdateformattoken(c::Char) = _patternkind(c) != 0

function _pushliteralchar!(ops::Vector{PatternOp}, c::Char)
    for b in codeunits(string(c))
        push!(ops, PatternOp(8, b, true))
    end
    return ops
end

"""
    compilepattern(fmt::AbstractString) -> DatePattern

Compile a Dates-style format string (numeric tokens `y Y m d H I M S s u U`,
AM/PM token `p`, named weekday tokens `e E`, plus literal separators) with
`Dates.DateFormat`'s width rules: a numeric field is
fixed-width only when another field follows it directly (`yyyymmdd`);
otherwise it is greedy, so `mm/dd/yyyy` accepts `3/14/2021`.
A backslash escapes a token letter, as in `yyyy\\mdd`, and literals are stored
as their UTF-8 bytes. Fractional-second runs above the supported nanosecond
precision throw when the format is compiled, never per cell.
"""
function compilepattern(fmt::AbstractString)
    ops = PatternOp[]
    natural = PatternOp[]
    hasdate = false
    hastime = false
    i = firstindex(fmt)
    while i <= lastindex(fmt)
        c = fmt[i]

        # Dates first applies the equivalent of `replace(r"\\(.)" => s"\\1")`.
        # Consume a complete slash run so an even run still suppresses the
        # token immediately after it (`\\\\m` -> literal `\\m`). Regex `.`
        # does not match LF, so a trailing odd slash before LF remains literal.
        if c == '\\'
            nslashes = 0
            ni = i
            while ni <= lastindex(fmt) && fmt[ni] == '\\'
                nslashes += 1
                ni = nextind(fmt, ni)
            end
            kept = nslashes ÷ 2
            ni > lastindex(fmt) && isodd(nslashes) && (kept += 1)
            ni <= lastindex(fmt) && fmt[ni] == '\n' && isodd(nslashes) &&
                (kept += 1)
            for _ in 1:kept
                _pushliteralchar!(ops, '\\')
                _pushliteralchar!(natural, '\\')
            end
            if ni <= lastindex(fmt)
                _pushliteralchar!(ops, fmt[ni])
                _pushliteralchar!(natural, fmt[ni])
                i = nextind(fmt, ni)
            else
                i = ni
            end
            continue
        elseif !_isdateformattoken(c)
            _pushliteralchar!(ops, c)
            _pushliteralchar!(natural, c)
            i = nextind(fmt, i)
            continue
        end

        n = 1
        ni = nextind(fmt, i)
        while ni <= lastindex(fmt) && fmt[ni] == c
            n += 1
            ni = nextind(fmt, ni)
        end
        kind = _patternkind(c)
        # Dates' width rule: a numeric field is fixed-width only when another
        # field follows it directly; otherwise it is greedy (one digit or
        # more). The natural width still drives the fixed fast path.
        fixed = ni <= lastindex(fmt) && _isdateformattoken(fmt[ni])
        width = if kind == 1 || kind in (0x02, 0x03, 0x04, 0x05, 0x06, 0x0b)
            fixed ? n : Int(typemax(UInt8))
        elseif kind == 7
            n <= 9 ||
                throw(ArgumentError("subsecond token run exceeds 9 digits in \"$fmt\""))
            fixed ? n : 9
        elseif kind in (9, 10, 13, 14)
            fixed ? n : 0
        else
            0
        end
        op = PatternOp(kind, width, fixed)
        push!(ops, op)
        push!(natural, 1 <= kind <= 7 ? PatternOp(kind, n, true) : op)
        hasdate |= _kindhasdate(kind)
        hastime |= _kindhastime(kind)
        i = ni
    end
    return _makepattern(ops, natural, hasdate, hastime,
                        _ENGLISH_CIVIL_NAMES_BOX)
end

# The default ISO patterns, precompiled.
const ISO_DATE     = compilepattern("yyyy-mm-dd")
const ISO_TIME     = compilepattern("HH:MM:SS.s")
const ISO_DATETIME = compilepattern("yyyy-mm-ddTHH:MM:SS.s")

# Pattern cache policy lives with the compiled plan. Readers use an immutable
# table snapshot without locking. A writer publishes a copied table, so no
# reader can observe a Dict while it resizes. String keys are copied only when
# inserted; SubString and other AbstractString lookups remain allocation-free.
mutable struct PatternCache
    @atomic table::Dict{Any, DatePattern}
end
const _PATTERNCACHE = PatternCache(Dict{Any, DatePattern}(
    "yyyy-mm-dd" => ISO_DATE, "yyyy-mm-ddTHH:MM:SS.s" => ISO_DATETIME,
    "yyyy-mm-dd\\THH:MM:SS.s" => ISO_DATETIME, "HH:MM:SS.s" => ISO_TIME))
const _PATTERNLOCK = ReentrantLock()
const _PATTERNCACHEMAX = 256
const _PINNED_PATTERN_KEYS = ("yyyy-mm-dd", "yyyy-mm-ddTHH:MM:SS.s",
                              "yyyy-mm-dd\\THH:MM:SS.s", "HH:MM:SS.s")

@inline function _cachedpattern(key)
    table = @atomic :acquire _PATTERNCACHE.table
    pattern = get(table, key, nothing)
    pattern === nothing || return pattern
    return _cachepattern!(key)
end

@noinline function _cachepattern!(key)
    Base.@nospecialize key
    return lock(_PATTERNLOCK) do
        table = @atomic :acquire _PATTERNCACHE.table
        pattern = get(table, key, nothing)
        pattern === nothing || return pattern
        pattern = compilepattern(key)
        updated = copy(table)
        if length(updated) >= _PATTERNCACHEMAX
            victim = nothing
            for candidate in keys(updated)
                candidate in _PINNED_PATTERN_KEYS && continue
                victim = candidate
                break
            end
            victim === nothing || delete!(updated, victim)
        end
        updated[key isa AbstractString ? String(key) : key] = pattern
        @atomic :release _PATTERNCACHE.table = updated
        return pattern
    end
end

# CivilParts supports Dates' Int64 year input on every architecture. Accumulate
# numeric fields in Int64 and use an unsigned fallback for the one magnitude
# (`abs(typemin(Int64))`) that a positive Int64 cannot hold.
const _CIVIL_SAFE_DIGITS = 18

@inline function _readnum(buf, i, j, maxw, fixed)
    v = Int64(0)
    k = i
    # A non-fixed 0xff width is the bytecode sentinel for a greedy numeric
    # field, not a 255-byte input limit. Leading zeros can make a valid Dates
    # field arbitrarily long without overflowing the accumulated value.
    lim = !fixed && maxw == typemax(UInt8) ? j :
          min(j, i + Int(maxw) - 1)
    # a whole word in bounds: take the digit run at once when it ends inside
    # the word or at the field's width limit (longer runs use the byte loop)
    @inbounds if k + 7 <= j
        w = _load8(buf, k)
        room = lim - k + 1
        cnt = min(_firstnondigit8(w), room)
        if cnt < 8 || room <= 8
            d, _ = _rundigits(w, cnt)
            k += cnt
            cnt == 0 && return (Int64(0), i, false)
            fixed && cnt != Int(maxw) && return (Int64(d), k, false)
            return (Int64(d), k, true)
        end
    end
    @inbounds while k <= lim
        d = buf[k] - UInt8('0')
        d > 0x09 && break
        k - i >= _CIVIL_SAFE_DIGITS &&
            v > (typemax(Int64) - Int64(d)) ÷ 10 &&
            return (Int64(0), k, false)
        v = v * 10 + Int64(d)
        k += 1
    end
    ndig = k - i
    ndig == 0 && return (Int64(0), i, false)
    fixed && ndig != Int(maxw) && return (v, k, false)
    return (v, k, true)
end

@inline function _readyear(buf, i, j, maxw, fixed)
    i <= j || return (Int64(0), i, false)
    @inbounds signed = buf[i] == UInt8('-') || buf[i] == UInt8('+')
    negative = @inbounds signed && buf[i] == UInt8('-')
    firstdigit = i + signed
    v, k, ok = _readnum(buf, firstdigit, j, maxw, fixed)
    ok && return (negative ? -v : v, k, true)
    negative || return (Int64(0), k, false)

    # `_readnum` rejects magnitudes above typemax(Int64). Retry the negative
    # boundary with UInt64 so -9223372036854775808 remains representable.
    magnitude = UInt64(0)
    k = firstdigit
    lim = !fixed && maxw == typemax(UInt8) ? j :
          min(j, firstdigit + Int(maxw) - 1)
    limit = UInt64(typemax(Int64)) + UInt64(1)
    @inbounds while k <= lim
        d = buf[k] - UInt8('0')
        d > 0x09 && break
        magnitude > (limit - UInt64(d)) ÷ UInt64(10) &&
            return (Int64(0), k, false)
        magnitude = UInt64(10) * magnitude + UInt64(d)
        k += 1
    end
    ndig = k - firstdigit
    ndig == 0 && return (Int64(0), firstdigit, false)
    fixed && ndig != Int(maxw) && return (Int64(0), k, false)
    magnitude == limit || return (Int64(0), k, false)
    return (typemin(Int64), k, true)
end

@inline function _fixednum(buf, i::Int, offset::UInt8, width::UInt8)
    offset == 0 && return (0, true)
    k = i + Int(offset) - 1
    if width == 2
        @inbounds begin
            d0 = buf[k] - UInt8('0')
            d1 = buf[k + 1] - UInt8('0')
        end
        ((d0 <= 0x09) & (d1 <= 0x09)) || return (0, false)
        return (10Int(d0) + Int(d1), true)
    elseif width == 4
        @inbounds begin
            d0 = buf[k] - UInt8('0')
            d1 = buf[k + 1] - UInt8('0')
            d2 = buf[k + 2] - UInt8('0')
            d3 = buf[k + 3] - UInt8('0')
        end
        ((d0 <= 0x09) & (d1 <= 0x09) & (d2 <= 0x09) & (d3 <= 0x09)) || return (0, false)
        return (1000Int(d0) + 100Int(d1) + 10Int(d2) + Int(d3), true)
    end
    value = 0
    @inbounds for p in 0:Int(width)-1
        d = buf[k + p] - UInt8('0')
        d <= 0x09 || return (0, false)
        value > (typemax(Int) - Int(d)) ÷ 10 && return (0, false)
        value = 10value + Int(d)
    end
    return (value, true)
end

@inline function _fixedliterals(buf, i::Int, fixed::FixedDatePattern)
    n = Int(fixed.nbytes)
    if n >= 8
        ((_load8(buf, i) ⊻ fixed.values[1]) & fixed.masks[1]) == 0 || return false
    end
    if n >= 16
        ((_load8(buf, i + 8) ⊻ fixed.values[2]) & fixed.masks[2]) == 0 || return false
    end
    if n >= 24
        ((_load8(buf, i + 16) ⊻ fixed.values[3]) & fixed.masks[3]) == 0 || return false
    end
    if n >= 32
        ((_load8(buf, i + 24) ⊻ fixed.values[4]) & fixed.masks[4]) == 0 || return false
    end
    firsttail = (n ÷ 8) * 8 + 1
    @inbounds for p in firsttail:n
        block = (p - 1) ÷ 8 + 1
        shift = 8 * ((p - 1) % 8)
        mask = UInt8((fixed.masks[block] >> shift) & 0xff)
        expected = UInt8((fixed.values[block] >> shift) & 0xff)
        mask == 0x00 || buf[i + p - 1] == expected || return false
    end
    return true
end

@inline function _parsefixeddate(buf, i::Int, j::Int,
                                 fixed::FixedDatePattern, flags::UInt8)
    j - i + 1 == Int(fixed.nbytes) || return (CivilParts(), RC_INVALID)
    _fixedliterals(buf, i, fixed) || return (CivilParts(), RC_INVALID)
    y, ok = _fixednum(buf, i, fixed.offsets[1], fixed.widths[1]); ok || return (CivilParts(), RC_INVALID)
    mo, ok = _fixednum(buf, i, fixed.offsets[2], fixed.widths[2]); ok || return (CivilParts(), RC_INVALID)
    d, ok = _fixednum(buf, i, fixed.offsets[3], fixed.widths[3]); ok || return (CivilParts(), RC_INVALID)
    h, ok = _fixednum(buf, i, fixed.offsets[4], fixed.widths[4]); ok || return (CivilParts(), RC_INVALID)
    mi, ok = _fixednum(buf, i, fixed.offsets[5], fixed.widths[5]); ok || return (CivilParts(), RC_INVALID)
    s, ok = _fixednum(buf, i, fixed.offsets[6], fixed.widths[6]); ok || return (CivilParts(), RC_INVALID)
    frac, ok = _fixednum(buf, i, fixed.offsets[7], fixed.widths[7]); ok || return (CivilParts(), RC_INVALID)
    y = fixed.offsets[1] == 0 ? 1 : y
    mo = fixed.offsets[2] == 0 ? 1 : mo
    d = fixed.offsets[3] == 0 ? 1 : d
    ns = fixed.offsets[7] == 0 ? 0 : frac * Int(10)^(9 - Int(fixed.widths[7]))
    _hasdate(flags) && !_validymd(y, mo, d) && return (CivilParts(), RC_INVALID)
    _hastime(flags) && !_validhms(h, mi, s) && return (CivilParts(), RC_INVALID)
    return (CivilParts(Int64(y), Int8(mo), Int8(d), Int8(h), Int8(mi), Int8(s), Int32(ns)), RC_OK)
end

@inline _lowernamebyte(b::UInt8) = UInt8('A') <= b <= UInt8('Z') ? b + 0x20 : b
@inline _asciiletter(b::UInt8) =
    UInt8('A') <= b <= UInt8('Z') || UInt8('a') <= b <= UInt8('z')

@inline function _matchenglishmonthabbr(buf, i::Int, j::Int,
                                        maxchars::Integer)
    maxchars != 0 && maxchars < 3 && return (0, i, false)
    i + 2 <= j || return (0, i, false)
    @inbounds begin
        a = _lowernamebyte(buf[i])
        b = _lowernamebyte(buf[i + 1])
        c = _lowernamebyte(buf[i + 2])
    end
    idx = if a == UInt8('j')
        b == UInt8('a') && c == UInt8('n') ? 1 :
        b == UInt8('u') && c == UInt8('n') ? 6 :
        b == UInt8('u') && c == UInt8('l') ? 7 : 0
    elseif a == UInt8('f')
        b == UInt8('e') && c == UInt8('b') ? 2 : 0
    elseif a == UInt8('m')
        b == UInt8('a') && c == UInt8('r') ? 3 :
        b == UInt8('a') && c == UInt8('y') ? 5 : 0
    elseif a == UInt8('a')
        b == UInt8('p') && c == UInt8('r') ? 4 :
        b == UInt8('u') && c == UInt8('g') ? 8 : 0
    elseif a == UInt8('s')
        b == UInt8('e') && c == UInt8('p') ? 9 : 0
    elseif a == UInt8('o')
        b == UInt8('c') && c == UInt8('t') ? 10 : 0
    elseif a == UInt8('n')
        b == UInt8('o') && c == UInt8('v') ? 11 : 0
    elseif a == UInt8('d')
        b == UInt8('e') && c == UInt8('c') ? 12 : 0
    else
        0
    end
    idx == 0 && return (0, i, false)
    k = i + 3
    (maxchars == 3 || k > j) && return (idx, k, true)
    @inbounds nextbyte = buf[k]
    if nextbyte < 0x80
        _asciiletter(nextbyte) && return (0, i, false)
    else
        c, _, valid = _utf8char(buf, k, j)
        valid && !isletter(c) || return (0, i, false)
    end
    return (idx, k, true)
end

@inline function _bytesmatch(buf, i::Int, n::Int, key::String)
    ncodeunits(key) == n || return false
    @inbounds for offset in 0:(n - 1)
        buf[i + offset] == codeunit(key, offset + 1) || return false
    end
    return true
end

@inline function _matchrawname(buf, i::Int, n::Int,
                               table::CivilNameTable{N}) where {N}
    # The table is a snapshot of DateLocale's final lookup dictionary. Its
    # values, not tuple positions, preserve lowercase collision semantics.
    @inbounds for mi in 1:N
        _bytesmatch(buf, i, n, table.raw[mi]) && return Int(table.values[mi])
    end
    return 0
end

@inline function _utf8char(buf, i::Int, j::Int)
    @inbounds b1 = buf[i]
    b1 < 0x80 && return (Char(b1), 1, true)
    if 0xc2 <= b1 <= 0xdf
        i < j || return ('\0', 0, false)
        @inbounds b2 = buf[i + 1]
        b2 & 0xc0 == 0x80 || return ('\0', 0, false)
        value = (UInt32(b1 & 0x1f) << 6) | UInt32(b2 & 0x3f)
        return (Char(value), 2, true)
    elseif 0xe0 <= b1 <= 0xef
        j - i >= 2 || return ('\0', 0, false)
        @inbounds b2, b3 = buf[i + 1], buf[i + 2]
        b3 & 0xc0 == 0x80 || return ('\0', 0, false)
        secondok = b1 == 0xe0 ? 0xa0 <= b2 <= 0xbf :
                   b1 == 0xed ? 0x80 <= b2 <= 0x9f : b2 & 0xc0 == 0x80
        secondok || return ('\0', 0, false)
        value = (UInt32(b1 & 0x0f) << 12) | (UInt32(b2 & 0x3f) << 6) |
                UInt32(b3 & 0x3f)
        return (Char(value), 3, true)
    elseif 0xf0 <= b1 <= 0xf4
        j - i >= 3 || return ('\0', 0, false)
        @inbounds b2, b3, b4 = buf[i + 1], buf[i + 2], buf[i + 3]
        (b3 & 0xc0 == 0x80 && b4 & 0xc0 == 0x80) ||
            return ('\0', 0, false)
        secondok = b1 == 0xf0 ? 0x90 <= b2 <= 0xbf :
                   b1 == 0xf4 ? 0x80 <= b2 <= 0x8f : b2 & 0xc0 == 0x80
        secondok || return ('\0', 0, false)
        value = (UInt32(b1 & 0x07) << 18) | (UInt32(b2 & 0x3f) << 12) |
                (UInt32(b3 & 0x3f) << 6) | UInt32(b4 & 0x3f)
        return (Char(value), 4, true)
    end
    return ('\0', 0, false)
end

@inline function _foldedunicodematch(buf, i::Int, k::Int, key::String)
    p = firstindex(key)
    last = ncodeunits(key)
    q = i
    while q < k
        p <= last || return false
        c, width, valid = _utf8char(buf, q, k - 1)
        valid || return false
        lowercase(c) == key[p] || return false
        p = nextind(key, p)
        q += width
    end
    return p > last
end

# Oversized locale keys retain the immutable raw/value snapshot but omit the
# packed accelerator. This cold matcher preserves DateLocale's two-step lookup:
# exact bytes win before a character-wise lowercase retry. It scans no farther
# than the compiled token width or one character beyond the longest frozen key.
@noinline function _matchunicodefallback(buf, i::Int, j::Int,
                                         table::CivilNameTable{N},
                                         maxchars::Integer) where {N}
    k = i
    nchars = 0
    while k <= j
        maxchars != 0 && nchars >= maxchars && break
        @inbounds byte = buf[k]
        if byte < 0x80
            _asciiletter(byte) || break
            width = 1
        else
            c, width, valid = _utf8char(buf, k, j)
            valid || return (0, i, false)
            isletter(c) || break
        end
        nchars += 1
        maxchars == 0 && nchars > table.maxchars && return (0, i, false)
        k += width
    end
    nchars == 0 && return (0, i, false)
    n = k - i
    matched = _matchrawname(buf, i, n, table)
    matched != 0 && return (matched, k, true)
    @inbounds for mi in 1:N
        _foldedunicodematch(buf, i, k, table.raw[mi]) &&
            return (Int(table.values[mi]), k, true)
    end
    return (0, i, false)
end

@inline function _matchunicodename(buf, i::Int, j::Int,
                                     table::CivilNameTable{N},
                                     maxchars::Integer) where {N}
    isempty(table.trie.nodes) &&
        return _matchunicodefallback(buf, i, j, table, maxchars)
    # An unbounded Dates word can match only a locale key. Stop after one more
    # Unicode character than the longest frozen key, so a large record
    # tail cannot force a record-sized temporary allocation.
    k = i
    nchars = 0
    rawstate = UInt16(1)
    foldedstate = UInt16(1)
    while k <= j
        maxchars != 0 && nchars >= maxchars && break
        @inbounds byte = buf[k]
        if byte < 0x80
            _asciiletter(byte) || break
            c = Char(byte)
            folded = Char(_lowernamebyte(byte))
            width = 1
        else
            c, width, valid = _utf8char(buf, k, j)
            valid || return (0, i, false)
            isletter(c) || break
            folded = lowercase(c)
        end
        rawstate != 0 && (rawstate = _civiltrienext(table.trie, rawstate, c))
        foldedstate != 0 &&
            (foldedstate = _civiltrienext(table.trie, foldedstate, folded))
        (rawstate | foldedstate) == 0 && return (0, i, false)
        nchars += 1
        maxchars == 0 && nchars > table.maxchars && return (0, i, false)
        k += width
    end
    nchars == 0 && return (0, i, false)
    if rawstate != 0
        trievalue = _civiltrievalue(table.trie, rawstate)
        trievalue != 0 && return (Int(trievalue), k, true)
    end
    if foldedstate != 0
        trievalue = _civiltrievalue(table.trie, foldedstate)
        trievalue != 0 && return (Int(trievalue), k, true)
    end
    return (0, i, false)
end

function _matchname(buf, i, j, table::CivilNameTable, maxchars::Integer)
    i <= j || return (0, i, false)
    table.executor == _EXECUTE_ENGLISH_MONTHS_ABBR &&
        return _matchenglishmonthabbr(buf, i, j, maxchars)

    # The packed raw/folded trie consumes both ASCII and Unicode names once.
    # An empty trie selects the cold tuple fallback for oversized locale keys.
    return _matchunicodename(buf, i, j, table, maxchars)
end

# These cold boundaries keep locale tuples out of numeric interpreter frames.
# Each named op loads only the table it uses.
@noinline _matchmonthabbr(buf, i, j, box::CivilNamesBox, maxchars::Integer) =
    _matchname(buf, i, j, box.names.months_abbr, maxchars)
@noinline _matchmonthfull(buf, i, j, box::CivilNamesBox, maxchars::Integer) =
    _matchname(buf, i, j, box.names.months_full, maxchars)
@noinline _matchdayabbr(buf, i, j, box::CivilNamesBox, maxchars::Integer) =
    _matchname(buf, i, j, box.names.days_abbr, maxchars)
@noinline _matchdayfull(buf, i, j, box::CivilNamesBox, maxchars::Integer) =
    _matchname(buf, i, j, box.names.days_full, maxchars)

# --- fixed-width ISO fast paths ----------------------------------------------
# The ISO defaults dominate real data and have fixed shapes. These accelerators
# avoid the general interpreter for exactly the fixed-width spellings
# ("yyyy-mm-dd" in 10 bytes, the 19-byte
# datetime without subseconds, "HH:MM:SS" in 8) and REJECT to the interpreter
# on any guard failure — equivalence with parsecivil is by construction, and
# only invalid cells (already the problems path) pay both.

@inline _dig(b::UInt8) = b - UInt8('0')

@inline function _iso_ymd(buf::AbstractVector{UInt8}, i::Int)
    @inbounds begin
        (buf[i + 4] == UInt8('-')) & (buf[i + 7] == UInt8('-')) || return (0, 0, 0, false)
        y0 = _dig(buf[i]); y1 = _dig(buf[i + 1]); y2 = _dig(buf[i + 2]); y3 = _dig(buf[i + 3])
        m0 = _dig(buf[i + 5]); m1 = _dig(buf[i + 6])
        d0 = _dig(buf[i + 8]); d1 = _dig(buf[i + 9])
        (y0 <= 0x09) & (y1 <= 0x09) & (y2 <= 0x09) & (y3 <= 0x09) &
        (m0 <= 0x09) & (m1 <= 0x09) & (d0 <= 0x09) & (d1 <= 0x09) ||
            return (0, 0, 0, false)
        return (Int(y0) * 1000 + Int(y1) * 100 + Int(y2) * 10 + Int(y3),
                Int(m0) * 10 + Int(m1), Int(d0) * 10 + Int(d1), true)
    end
end

@inline function _iso_hms(buf::AbstractVector{UInt8}, i::Int)
    @inbounds begin
        (buf[i + 2] == UInt8(':')) & (buf[i + 5] == UInt8(':')) || return (0, 0, 0, false)
        h0 = _dig(buf[i]); h1 = _dig(buf[i + 1])
        m0 = _dig(buf[i + 3]); m1 = _dig(buf[i + 4])
        s0 = _dig(buf[i + 6]); s1 = _dig(buf[i + 7])
        (h0 <= 0x09) & (h1 <= 0x09) & (m0 <= 0x09) & (m1 <= 0x09) &
        (s0 <= 0x09) & (s1 <= 0x09) || return (0, 0, 0, false)
        return (Int(h0) * 10 + Int(h1), Int(m0) * 10 + Int(m1), Int(s0) * 10 + Int(s1), true)
    end
end

"""
    parseiso10(buf, i) -> (CivilParts, rc)

`yyyy-mm-dd` in exactly 10 bytes (caller checks the length). RC_INVALID means
"not this shape or not a real date" — the caller falls through to
`parsecivil`, which agrees on every 10-byte input.
"""
@inline function parseiso10(buf::AbstractVector{UInt8}, i::Int)
    y, m, d, ok = _iso_ymd(buf, i)
    (ok && _validymd(y, m, d)) || return (CivilParts(), RC_INVALID)
    return (CivilParts(Int64(y), Int8(m), Int8(d), Int8(0), Int8(0), Int8(0), Int32(0)), RC_OK)
end

"""
    parseiso19(buf, i) -> (CivilParts, rc)

`yyyy-mm-ddTHH:MM:SS` in exactly 19 bytes (no subseconds; those fall through).
"""
@inline function parseiso19(buf::AbstractVector{UInt8}, i::Int)
    @inbounds buf[i + 10] == UInt8('T') || return (CivilParts(), RC_INVALID)
    y, mo, d, okd = _iso_ymd(buf, i)
    h, mi, s, okt = _iso_hms(buf, i + 11)
    (okd && okt && _validymd(y, mo, d) && _validhms(h, mi, s)) ||
        return (CivilParts(), RC_INVALID)
    return (CivilParts(Int64(y), Int8(mo), Int8(d), Int8(h), Int8(mi), Int8(s), Int32(0)), RC_OK)
end

"""
    parseiso8(buf, i) -> (CivilParts, rc)

`HH:MM:SS` in exactly 8 bytes.
"""
@inline function parseiso8(buf::AbstractVector{UInt8}, i::Int)
    h, mi, s, ok = _iso_hms(buf, i)
    (ok && _validhms(h, mi, s)) || return (CivilParts(), RC_INVALID)
    return (CivilParts(Int64(1), Int8(1), Int8(1), Int8(h), Int8(mi), Int8(s), Int32(0)), RC_OK)
end

const _NSSCALE = (1_000_000_000, 100_000_000, 10_000_000, 1_000_000, 100_000,
                  10_000, 1_000, 100, 10, 1)

# One to nine fraction digits at buf[k:j], scaled to nanoseconds exactly as
# the interpreter scales a subsecond field.
@inline function _isofraction(buf::AbstractVector{UInt8}, k::Int, j::Int)
    nd = j - k + 1
    1 <= nd <= 9 || return (0, false)
    v = 0
    @inbounds for p in k:j
        d = _dig(buf[p])
        d <= 0x09 || return (0, false)
        v = 10v + Int(d)
    end
    return (v * @inbounds(_NSSCALE[nd + 1]), true)
end

"""
    parseiso19frac(buf, i, j) -> (CivilParts, rc)

`yyyy-mm-ddTHH:MM:SS.s` with one to nine fraction digits (21–29 bytes; the
caller checks the length). Agrees with `parsecivil` and `ISO_DATETIME`.
"""
@inline function parseiso19frac(buf::AbstractVector{UInt8}, i::Int, j::Int)
    @inbounds (buf[i + 10] == UInt8('T')) & (buf[i + 19] == UInt8('.')) ||
        return (CivilParts(), RC_INVALID)
    y, mo, d, okd = _iso_ymd(buf, i)
    h, mi, s, okt = _iso_hms(buf, i + 11)
    ns, okf = _isofraction(buf, i + 20, j)
    (okd && okt && okf && _validymd(y, mo, d) && _validhms(h, mi, s)) ||
        return (CivilParts(), RC_INVALID)
    return (CivilParts(Int64(y), Int8(mo), Int8(d), Int8(h), Int8(mi), Int8(s), Int32(ns)), RC_OK)
end

"""
    parseiso8frac(buf, i, j) -> (CivilParts, rc)

`HH:MM:SS.s` with one to nine fraction digits (10–18 bytes).
"""
@inline function parseiso8frac(buf::AbstractVector{UInt8}, i::Int, j::Int)
    @inbounds buf[i + 8] == UInt8('.') || return (CivilParts(), RC_INVALID)
    h, mi, s, ok = _iso_hms(buf, i)
    ns, okf = _isofraction(buf, i + 9, j)
    (ok && okf && _validhms(h, mi, s)) || return (CivilParts(), RC_INVALID)
    return (CivilParts(Int64(1), Int8(1), Int8(1), Int8(h), Int8(mi), Int8(s), Int32(ns)), RC_OK)
end

"""
    parsecivil(buf, i, j, pat::DatePattern) -> (CivilParts, rc)

Run a compiled pattern over the exact span. Trailing sub-second precision
beyond the pattern (`.s` matching 1–9 digits) is scaled to nanoseconds. The
whole span must be consumed. Calendar validity (month/day ranges, leap years)
is checked here — structurally valid but impossible dates are INVALID.
"""
@inline function parsecivil(buf::AbstractVector{UInt8}, i::Int, j::Int, pat::DatePattern)
    return _parsecivilvalidated(buf, i, j, pat, pat._storage.plan.flags)
end

@noinline function _parsecivilvalidated(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                        pat::DatePattern, validation::UInt8)
    if _needsindexwindow(j)
        window, first, final = _indexwindow(buf, i, j)
        return _parsecivilexact(window, first, final, pat, validation)
    end
    return _parsecivilexact(buf, i, j, pat, validation)
end

@noinline function _parsecivilexact(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                    pat::DatePattern, validation::UInt8)
    storage = pat._storage
    validation == storage.plan.flags ||
        return _interpretcivil(buf, i, j, storage, validation)
    executor = storage.plan.executor
    executor == _EXECUTE_PROGRAM && return _fallbackcivil(buf, i, j, storage)
    executor == _EXECUTE_ISO_DATE &&
        return _executecivil(buf, i, j, storage, Val(_EXECUTE_ISO_DATE))
    executor == _EXECUTE_ISO_DATETIME &&
        return _executecivil(buf, i, j, storage, Val(_EXECUTE_ISO_DATETIME))
    executor == _EXECUTE_ISO_TIME &&
        return _executecivil(buf, i, j, storage, Val(_EXECUTE_ISO_TIME))
    return _executecivil(buf, i, j, storage, Val(_EXECUTE_NUMERIC_DATE))
end

@inline function _fallbackcivil(buf, i::Int, j::Int, storage::CivilPlanBox)
    fixed = storage.plan.fixed
    if fixed.nbytes != 0
        c, rc = _parsefixeddate(buf, i, j, fixed, storage.plan.flags)
        rc == RC_OK && return (c, rc)
    end
    return _interpretcivil(buf, i, j, storage, storage.plan.flags)
end

@inline function _executecivil(buf, i::Int, j::Int, storage::CivilPlanBox,
                               ::Val{_EXECUTE_ISO_DATE})
    if j - i == 9
        c, rc = parseiso10(buf, i)
        rc == RC_OK && return (c, rc)
    end
    return _fallbackcivil(buf, i, j, storage)
end

@inline function _executecivil(buf, i::Int, j::Int, storage::CivilPlanBox,
                               ::Val{_EXECUTE_ISO_DATETIME})
    n = j - i + 1
    if n == 19
        c, rc = parseiso19(buf, i)
        rc == RC_OK && return (c, rc)
    elseif 21 <= n <= 29
        c, rc = parseiso19frac(buf, i, j)
        rc == RC_OK && return (c, rc)
    end
    return _fallbackcivil(buf, i, j, storage)
end

@inline function _executecivil(buf, i::Int, j::Int, storage::CivilPlanBox,
                               ::Val{_EXECUTE_ISO_TIME})
    n = j - i + 1
    if n == 8
        c, rc = parseiso8(buf, i)
        rc == RC_OK && return (c, rc)
    elseif 10 <= n <= 18
        c, rc = parseiso8frac(buf, i, j)
        rc == RC_OK && return (c, rc)
    end
    return _fallbackcivil(buf, i, j, storage)
end

@inline _readnumericdatefield(::Val{1}, buf, i, j, width, fixed) =
    _readyear(buf, i, j, width, fixed)
@inline _readnumericdatefield(::Val, buf, i, j, width, fixed) =
    _readnum(buf, i, j, width, fixed)

@inline function _executenumericdate(buf, i::Int, j::Int, storage::CivilPlanBox,
                                     ::Val{K1}, ::Val{K2}, ::Val{K3}) where {K1,K2,K3}
    pattern = storage.plan.numeric
    a, k, ok = _readnumericdatefield(Val(K1), buf, i, j, pattern.widths[1],
                                     (pattern.fixed & 0x01) != 0)
    ok && k <= j && @inbounds(buf[k]) == pattern.delimiters[1] ||
        return (CivilParts(), RC_INVALID)
    b, k, ok = _readnumericdatefield(Val(K2), buf, k + 1, j, pattern.widths[2],
                                     (pattern.fixed & 0x02) != 0)
    ok && k <= j && @inbounds(buf[k]) == pattern.delimiters[2] ||
        return (CivilParts(), RC_INVALID)
    c, k, ok = _readnumericdatefield(Val(K3), buf, k + 1, j, pattern.widths[3],
                                     (pattern.fixed & 0x04) != 0)
    y = K1 == 1 ? a : K2 == 1 ? b : c
    mo = K1 == 2 ? a : K2 == 2 ? b : c
    dy = K1 == 3 ? a : K2 == 3 ? b : c
    ok && k > j && _validymd(y, mo, dy) || return (CivilParts(), RC_INVALID)
    return (CivilParts(y, Int8(mo), Int8(dy), 0, 0, 0, 0), RC_OK)
end

@inline function _executecivil(buf, i::Int, j::Int, storage::CivilPlanBox,
                               ::Val{_EXECUTE_NUMERIC_DATE})
    fixed = storage.plan.fixed
    if fixed.nbytes != 0 && j - i + 1 == Int(fixed.nbytes)
        civil, rc = _parsefixeddate(buf, i, j, fixed, storage.plan.flags)
        rc == RC_OK && return (civil, rc)
    end
    order = storage.plan.numeric.order
    order == _ORDER_YMD && return _executenumericdate(buf, i, j, storage,
                                                       Val(1), Val(2), Val(3))
    order == _ORDER_YDM && return _executenumericdate(buf, i, j, storage,
                                                       Val(1), Val(3), Val(2))
    order == _ORDER_MYD && return _executenumericdate(buf, i, j, storage,
                                                       Val(2), Val(1), Val(3))
    order == _ORDER_MDY && return _executenumericdate(buf, i, j, storage,
                                                       Val(2), Val(3), Val(1))
    order == _ORDER_DYM && return _executenumericdate(buf, i, j, storage,
                                                       Val(3), Val(1), Val(2))
    return _executenumericdate(buf, i, j, storage, Val(3), Val(2), Val(1))
end

# The pattern interpreter: every op in order, no fast paths. Ordinary ops keep
# the two-byte decode used by common formats. Only a width above 255 enters the
# variable-length branch.
@inline function _decodepatternop(code::String, q::Int, tag::UInt8)
    if (tag & _WIDE_PATTERN_OP) == 0
        return Int(codeunit(code, q + 1)), q + 2
    end
    value = UInt(0)
    shift = 0
    r = q + 1
    while true
        byte = codeunit(code, r)
        value |= UInt(byte & 0x7f) << shift
        r += 1
        (byte & 0x80) == 0 && return Int(value), r
        shift += 7
    end
end

@inline function _optionaltrailingfraction(code::String, q::Int, nbytes::Int,
                                           previouskind::UInt8)
    previouskind == 8 && return false
    r = q
    @inbounds while r <= nbytes
        tag = codeunit(code, r)
        (tag & 0x0f) == 8 || break
        _, r = _decodepatternop(code, r, tag)
    end
    r <= nbytes || return false
    tag = codeunit(code, r)
    (tag & 0x0f) == 7 || return false
    _, next = _decodepatternop(code, r, tag)
    return next == nbytes + 1
end

@noinline function _interpretcivil(buf::AbstractVector{UInt8}, i::Int, j::Int,
                                   storage::CivilPlanBox, validation::UInt8)
    y = 1; mo = 1; dy = 1; h = 0; mi = 0; s = 0; ns = 0
    ampm = 0x00                                          # 0 none, 1 AM, 2 PM
    k = i
    code = storage.plan.ops.code
    q = 1
    nbytes = ncodeunits(code)
    previouskind = UInt8(0)
    @inbounds while q <= nbytes
        tag = codeunit(code, q)
        kind = tag & 0x0f
        width, nextq = _decodepatternop(code, q, tag)
        fixed = (tag & 0x10) != 0
        if kind <= 0x06 || kind == 0x0b                  # numeric fields: the common case
            v, k2, ok = kind == 0x01 ? _readyear(buf, k, j, width, fixed) :
                                       _readnum(buf, k, j, width, fixed)
            ok || return (CivilParts(), RC_INVALID)
            if kind == 0x01
                y = v
            elseif kind == 0x02
                mo = v
            elseif kind == 0x03
                dy = v
            elseif kind == 0x04 || kind == 0x0b
                h = v
            elseif kind == 0x05
                mi = v
            else
                s = v
            end
            k = k2
        elseif kind == 8
            (k <= j && buf[k] == width) || begin
                # A complete trailing delimiter + subsecond group may be absent.
                # A partly consumed multi-byte delimiter must still fail.
                if k > j && _optionaltrailingfraction(code, q, nbytes,
                                                       previouskind)
                    q = nbytes + 1
                    break
                end
                return (CivilParts(), RC_INVALID)
            end
            k += 1
        elseif kind == 9 || kind == 10
            names = storage.plan.names
            idx, k2, ok = kind == 9 ? _matchmonthabbr(buf, k, j, names, width) :
                                      _matchmonthfull(buf, k, j, names, width)
            ok || return (CivilParts(), RC_INVALID)
            mo = idx
            k = k2
        elseif kind == 13 || kind == 14
            names = storage.plan.names
            _, k2, ok = kind == 13 ? _matchdayabbr(buf, k, j, names, width) :
                                     _matchdayfull(buf, k, j, names, width)
            ok || return (CivilParts(), RC_INVALID)      # validated, value unused (Dates' rule)
            k = k2
        elseif kind == 12
            k + 1 <= j || return (CivilParts(), RC_INVALID)
            a = _lower(buf[k])
            (a == UInt8('a') || a == UInt8('p')) && _lower(buf[k + 1]) == UInt8('m') ||
                return (CivilParts(), RC_INVALID)
            ampm = a == UInt8('a') ? 0x01 : 0x02
            k += 2
        elseif kind == 7
            v, k2, ok = _readnum(buf, k, j, width, fixed)
            ok || return (CivilParts(), RC_INVALID)
            nd = k2 - k
            ns = v * Int(10)^(9 - nd)
            k = k2
        end
        previouskind = kind
        q = nextq
    end
    k <= j && return (CivilParts(), RC_INVALID)          # unconsumed bytes
    if _hasdate(validation)
        _validymd(y, mo, dy) || return (CivilParts(), RC_INVALID)
    else
        y = 1; mo = 1; dy = 1
    end
    if _hastime(validation)
        # Dates applies AM/PM range and adjustment only when the destination
        # consumes time fields.
        if ampm != 0x00
            1 <= h <= 12 || return (CivilParts(), RC_INVALID)
            ampm == 0x02 ? (h < 12 && (h += 12)) : (h == 12 && (h = 0))
        end
        _validhms(h, mi, s) || return (CivilParts(), RC_INVALID)
    else
        h = 0; mi = 0; s = 0; ns = 0
    end
    return (CivilParts(Int64(y), Int8(mo), Int8(dy), Int8(h), Int8(mi), Int8(s), Int32(ns)), RC_OK)
end
