# =============================================================================
# dates & times — CivilParts core (no Dates dependency) + format programs
# =============================================================================

"""
    CivilParts

A parsed civil timestamp: pure integers, no calendar library. `nanosecond`
carries full sub-second precision; adapters truncate per target type.
"""
struct CivilParts
    year::Int32
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
# A compiled pattern is a flat vector of ops. Numeric fields consume 1..width
# digits (fixed = exactly width); literals must match exactly; month/day-name
# ops consume letters and match the plain String tables stored in DatePattern.
# The default tables are English. dates.jl copies a DateFormat's locale tables
# into the pattern without making this kernel depend on Dates types.

struct PatternOp
    kind::UInt8     # 1=year 2=month 3=day 4=hour 5=minute 6=second 7=subsec
                    # 8=literal 9=monthname-abbrev 10=monthname-full
                    # 11=hour12 12=am/pm 13=dayname-abbrev 14=dayname-full
    width::UInt8    # numeric: max digits; fixed ⇒ exactly; literal: byte
    fixed::Bool
end

# Compact description for all-fixed numeric formats. Literal positions are
# validated eight bytes at a time. Numeric offsets then feed direct field
# readers. A zero byte count means that the general pattern interpreter is
# required (variable widths, names, AM/PM, long patterns, or duplicate fields).
struct FixedDatePattern
    nbytes::UInt8
    offsets::NTuple{7, UInt8}
    widths::NTuple{7, UInt8}
    masks::NTuple{4, UInt64}
    values::NTuple{4, UInt64}
end
FixedDatePattern() = FixedDatePattern(0, ntuple(_ -> 0x00, 7), ntuple(_ -> 0x00, 7),
                                      ntuple(_ -> UInt64(0), 4), ntuple(_ -> UInt64(0), 4))

"""
    DatePattern

A compiled, plain-data date/time parse program. Create one with
[`compilepattern`](@ref), then reuse it with [`parsecivil`](@ref) or as the
`dateformat` keyword of [`Parsers.parse`](@ref). The pattern stores its literal
bytes, numeric field rules, and month/day name tables.

A pattern is a heap object that is never mutated after construction, so passing
one around costs a pointer rather than a copy of its name tables.
"""
mutable struct DatePattern
    ops::Vector{PatternOp}
    hasdate::Bool
    hastime::Bool
    months_abbr::NTuple{12, String}
    months_full::NTuple{12, String}
    days_abbr::NTuple{7, String}
    days_full::NTuple{7, String}
    fixed::FixedDatePattern
end

const ENGLISH_MONTHS_ABBR = ("Jan", "Feb", "Mar", "Apr", "May", "Jun",
                             "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
const ENGLISH_DAYS_ABBR = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
const ENGLISH_DAYS_FULL = ("Monday", "Tuesday", "Wednesday", "Thursday", "Friday",
                           "Saturday", "Sunday")
const ENGLISH_MONTHS_FULL = ("January", "February", "March", "April", "May", "June",
                             "July", "August", "September", "October", "November",
                             "December")

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
            widths[field] = op.width
            pos += Int(op.width)
        else
            return FixedDatePattern()
        end
    end
    1 < pos <= 33 || return FixedDatePattern()
    return FixedDatePattern(UInt8(pos - 1), Tuple(offsets), Tuple(widths),
                            Tuple(masks), Tuple(values))
end

DatePattern(ops::Vector{PatternOp}, hasdate::Bool, hastime::Bool,
            months_abbr::NTuple{12, String}, months_full::NTuple{12, String},
            days_abbr::NTuple{7, String}, days_full::NTuple{7, String}) =
    DatePattern(ops, hasdate, hastime, months_abbr, months_full, days_abbr, days_full,
                _fixeddatepattern(ops))

DatePattern(ops::Vector{PatternOp}, hasdate::Bool, hastime::Bool) =
    DatePattern(ops, hasdate, hastime, ENGLISH_MONTHS_ABBR, ENGLISH_MONTHS_FULL,
                ENGLISH_DAYS_ABBR, ENGLISH_DAYS_FULL)

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

Compile a Dates-style format string (tokens `y m d H M S s u U`, plus literal
separators) with `Dates.DateFormat`'s width rules: a numeric field is
fixed-width only when another field follows it directly (`yyyymmdd`);
otherwise it is greedy, so `mm/dd/yyyy` accepts `3/14/2021`.
A backslash escapes a token letter, as in `yyyy\\mdd`, and literals are stored
as their UTF-8 bytes. Unsupported tokens throw at compile time — configuration
errors surface when the format is pinned, never per cell.
"""
function compilepattern(fmt::AbstractString)
    ops = PatternOp[]
    natural = PatternOp[]
    hasdate = false
    hastime = false
    i = firstindex(fmt)
    while i <= lastindex(fmt)
        c = fmt[i]

        # Dates recognizes a token only when a backslash does not immediately
        # precede it. Consume escape pairs without first rebuilding a String;
        # this also reproduces DateFormat's `\\\\m` -> literal `\\m` rule.
        if c == '\\'
            ni = nextind(fmt, i)
            if ni <= lastindex(fmt)
                _pushliteralchar!(ops, fmt[ni])
                _pushliteralchar!(natural, fmt[ni])
                i = nextind(fmt, ni)
            else
                _pushliteralchar!(ops, c)
                _pushliteralchar!(natural, c)
                i = ni
            end
            continue
        elseif !_isdateformattoken(c)
            c in ('Q', 'q') &&
                throw(ArgumentError("unsupported date format token '$c' in \"$fmt\""))
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
            n <= typemax(UInt8) ||
                throw(ArgumentError("token run exceeds 255 bytes in \"$fmt\""))
            fixed ? UInt8(n) : typemax(UInt8)
        elseif kind == 7
            (!fixed || n <= 9) ||
                throw(ArgumentError("subsecond token run exceeds 9 digits in \"$fmt\""))
            fixed ? UInt8(n) : UInt8(9)
        else
            UInt8(0)
        end
        op = PatternOp(kind, width, fixed)
        push!(ops, op)
        push!(natural, 1 <= kind <= 7 ? PatternOp(kind, UInt8(n), true) : op)
        hasdate |= _kindhasdate(kind)
        hastime |= _kindhastime(kind)
        i = ni
    end
    return DatePattern(ops, hasdate, hastime, ENGLISH_MONTHS_ABBR, ENGLISH_MONTHS_FULL,
                       ENGLISH_DAYS_ABBR, ENGLISH_DAYS_FULL, _fixeddatepattern(natural))
end

# The default ISO patterns, precompiled.
const ISO_DATE     = compilepattern("yyyy-mm-dd")
const ISO_TIME     = compilepattern("HH:MM:SS.s")
const ISO_DATETIME = compilepattern("yyyy-mm-ddTHH:MM:SS.s")

# digits an Int accumulates without any overflow check (18 for Int64, 9 for Int32)
const _SAFEDIGITS = sizeof(Int) == 8 ? 18 : 9

@inline function _readnum(buf, i, j, maxw, fixed)
    v = 0
    k = i
    lim = min(j, i + Int(maxw) - 1)
    # a whole word in bounds: take the digit run at once when it ends inside
    # the word or at the field's width limit (longer runs use the byte loop)
    @inbounds if k + 7 <= j
        w = _load8(buf, k)
        room = lim - k + 1
        cnt = min(_firstnondigit8(w), room)
        if cnt < 8 || room <= 8
            d, _ = _rundigits(w, cnt)
            k += cnt
            cnt == 0 && return (0, i, false)
            fixed && cnt != Int(maxw) && return (Int(d), k, false)
            return (Int(d), k, true)
        end
    end
    @inbounds while k <= lim
        d = buf[k] - UInt8('0')
        d > 0x09 && break
        k - i >= _SAFEDIGITS && v > (typemax(Int) - Int(d)) ÷ 10 && return (0, k, false)
        v = v * 10 + Int(d)
        k += 1
    end
    ndig = k - i
    ndig == 0 && return (0, i, false)
    fixed && ndig != Int(maxw) && return (v, k, false)
    return (v, k, true)
end

@inline function _readyear(buf, i, j, maxw, fixed)
    i <= j || return (0, i, false)
    @inbounds signed = buf[i] == UInt8('-') || buf[i] == UInt8('+')
    sign = @inbounds signed && buf[i] == UInt8('-') ? -1 : 1
    firstdigit = i + signed
    v, k, ok = _readnum(buf, firstdigit, j, maxw, fixed)
    return (sign * v, k, ok)
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

@inline function _parsefixeddate(buf, i::Int, j::Int, pat::DatePattern)
    fixed = pat.fixed
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
    pat.hasdate && !_validymd(y, mo, d) && return (CivilParts(), RC_INVALID)
    pat.hastime && !_validhms(h, mi, s) && return (CivilParts(), RC_INVALID)
    typemin(Int32) <= y <= typemax(Int32) || return (CivilParts(), RC_INVALID)
    return (CivilParts(Int32(y), Int8(mo), Int8(d), Int8(h), Int8(mi), Int8(s), Int32(ns)), RC_OK)
end

@inline _lowernamebyte(b::UInt8) = UInt8('A') <= b <= UInt8('Z') ? b + 0x20 : b

@inline function _matchenglishmonthabbr(buf, i::Int, j::Int)
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
    return idx == 0 ? (0, i, false) : (idx, i + 3, true)
end

function _matchname(buf, i, j, table)
    # Reusable String patterns use this exact tuple for the common English
    # abbreviation grammar. Avoid scanning all twelve names on that hot path.
    if table === ENGLISH_MONTHS_ABBR
        idx, k, ok = _matchenglishmonthabbr(buf, i, j)
        ok && return (idx, k, true)
    end

    # Fast ASCII case-insensitive prefix match against table entries.
    bestidx = 0
    bestn = 0
    @inbounds for (mi, name) in enumerate(table)
        ncu = ncodeunits(name)
        i + ncu - 1 <= j || continue
        ok = true
        for k in 1:ncu
            _lowernamebyte(buf[i + k - 1]) == _lowernamebyte(UInt8(codeunit(name, k))) ||
                (ok = false; break)
        end
        if ok && ncu > bestn
            bestidx = mi
            bestn = ncu
        end
    end

    # Dates locales may contain non-ASCII names. Keep the common path
    # allocation-free, then use Julia's Unicode lowercase rules when the byte
    # comparison cannot distinguish (for example, `É` from `é`).
    for (mi, name) in enumerate(table)
        ncu = ncodeunits(name)
        ncu > bestn || continue
        i + ncu - 1 <= j || continue
        bytes = Vector{UInt8}(undef, ncu)
        @inbounds for k in 1:ncu
            bytes[k] = buf[i + k - 1]
        end
        candidate = String(bytes)
        if isvalid(candidate) && lowercase(candidate) == lowercase(name)
            bestidx = mi
            bestn = ncu
        end
    end
    bestidx != 0 && return (bestidx, i + bestn, true)
    return (0, i, false)
end

# --- fixed-width ISO fast paths ----------------------------------------------
# The ISO defaults dominate real data and have fixed shapes; the pattern
# interpreter costs ~18 ns/date walking its op list. These accelerators handle
# exactly the fixed-width spellings ("yyyy-mm-dd" in 10 bytes, the 19-byte
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
[`parsecivil`](@ref), which agrees on every 10-byte input.
"""
@inline function parseiso10(buf::AbstractVector{UInt8}, i::Int)
    y, m, d, ok = _iso_ymd(buf, i)
    (ok && _validymd(y, m, d)) || return (CivilParts(), RC_INVALID)
    return (CivilParts(Int32(y), Int8(m), Int8(d), Int8(0), Int8(0), Int8(0), Int32(0)), RC_OK)
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
    return (CivilParts(Int32(y), Int8(mo), Int8(d), Int8(h), Int8(mi), Int8(s), Int32(0)), RC_OK)
end

"""
    parseiso8(buf, i) -> (CivilParts, rc)

`HH:MM:SS` in exactly 8 bytes.
"""
@inline function parseiso8(buf::AbstractVector{UInt8}, i::Int)
    h, mi, s, ok = _iso_hms(buf, i)
    (ok && _validhms(h, mi, s)) || return (CivilParts(), RC_INVALID)
    return (CivilParts(Int32(1), Int8(1), Int8(1), Int8(h), Int8(mi), Int8(s), Int32(0)), RC_OK)
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
    return (CivilParts(Int32(y), Int8(mo), Int8(d), Int8(h), Int8(mi), Int8(s), Int32(ns)), RC_OK)
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
    return (CivilParts(Int32(1), Int8(1), Int8(1), Int8(h), Int8(mi), Int8(s), Int32(ns)), RC_OK)
end

"""
    parsecivil(buf, i, j, pat::DatePattern) -> (CivilParts, rc)

Run a compiled pattern over the exact span. Trailing sub-second precision
beyond the pattern (`.s` matching 1–9 digits) is scaled to nanoseconds. The
whole span must be consumed. Calendar validity (month/day ranges, leap years)
is checked here — structurally valid but impossible dates are INVALID.
"""
function parsecivil(buf::AbstractVector{UInt8}, i::Int, j::Int, pat::DatePattern)
    # The three default pattern identities use dedicated ISO kernels. Other
    # all-fixed numeric programs use the compiled fixed-pattern path below;
    # variable-width and locale-aware programs use the interpreter.
    n = j - i + 1
    if n == 10 && pat === ISO_DATE
        c, rc = parseiso10(buf, i)
        rc == RC_OK && return (c, rc)
    elseif n == 19 && pat === ISO_DATETIME
        c, rc = parseiso19(buf, i)
        rc == RC_OK && return (c, rc)
    elseif n == 8 && pat === ISO_TIME
        c, rc = parseiso8(buf, i)
        rc == RC_OK && return (c, rc)
    elseif 21 <= n <= 29 && pat === ISO_DATETIME
        c, rc = parseiso19frac(buf, i, j)
        rc == RC_OK && return (c, rc)
    elseif 10 <= n <= 18 && pat === ISO_TIME
        c, rc = parseiso8frac(buf, i, j)
        rc == RC_OK && return (c, rc)
    end
    if pat.fixed.nbytes != 0
        c, rc = _parsefixeddate(buf, i, j, pat)
        rc == RC_OK && return (c, rc)
    end

    return _interpretcivil(buf, i, j, pat)
end

# The pattern interpreter: every op in order, no fast paths.
@noinline function _interpretcivil(buf::AbstractVector{UInt8}, i::Int, j::Int, pat::DatePattern)
    y = 1; mo = 1; dy = 1; h = 0; mi = 0; s = 0; ns = 0
    ampm = 0x00                                          # 0 none, 1 AM, 2 PM
    k = i
    ops = pat.ops
    oi = 1
    @inbounds while oi <= length(ops)
        op = ops[oi]
        kind = op.kind
        if kind <= 0x06 || kind == 0x0b                  # numeric fields: the common case
            v, k2, ok = kind == 0x01 ? _readyear(buf, k, j, op.width, op.fixed) :
                                       _readnum(buf, k, j, op.width, op.fixed)
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
        elseif op.kind == 8
            (k <= j && buf[k] == op.width) || begin
                # a trailing optional subsecond group (".s" at pattern end) may be absent
                if oi + 1 <= length(ops) && ops[oi + 1].kind == 7 && oi + 1 == length(ops) && k > j
                    oi = length(ops) + 1
                    break
                end
                return (CivilParts(), RC_INVALID)
            end
            k += 1
        elseif op.kind == 9 || op.kind == 10
            table = op.kind == 9 ? pat.months_abbr : pat.months_full
            idx, k2, ok = _matchname(buf, k, j, table)
            ok || return (CivilParts(), RC_INVALID)
            mo = idx
            k = k2
        elseif op.kind == 13 || op.kind == 14
            table = op.kind == 13 ? pat.days_abbr : pat.days_full
            _, k2, ok = _matchname(buf, k, j, table)
            ok || return (CivilParts(), RC_INVALID)      # validated, value unused (Dates' rule)
            k = k2
        elseif op.kind == 12
            k + 1 <= j || return (CivilParts(), RC_INVALID)
            a = _lower(buf[k])
            (a == UInt8('a') || a == UInt8('p')) && _lower(buf[k + 1]) == UInt8('m') ||
                return (CivilParts(), RC_INVALID)
            ampm = a == UInt8('a') ? 0x01 : 0x02
            k += 2
        elseif op.kind == 7
            v, k2, ok = _readnum(buf, k, j, op.width, op.fixed)
            ok || return (CivilParts(), RC_INVALID)
            nd = k2 - k
            ns = v * Int(10)^(9 - nd)
            k = k2
        end
        oi += 1
    end
    k <= j && return (CivilParts(), RC_INVALID)          # unconsumed bytes
    # Dates: with AM/PM present the hour must be 1..12; then adjusthour —
    # PM below 12 adds 12, AM at 12 is midnight
    if ampm != 0x00
        1 <= h <= 12 || return (CivilParts(), RC_INVALID)
        ampm == 0x02 ? (h < 12 && (h += 12)) : (h == 12 && (h = 0))
    end
    pat.hasdate && !_validymd(y, mo, dy) && return (CivilParts(), RC_INVALID)
    pat.hastime && !_validhms(h, mi, s) && return (CivilParts(), RC_INVALID)
    typemin(Int32) <= y <= typemax(Int32) || return (CivilParts(), RC_INVALID)
    return (CivilParts(Int32(y), Int8(mo), Int8(dy), Int8(h), Int8(mi), Int8(s), Int32(ns)), RC_OK)
end
