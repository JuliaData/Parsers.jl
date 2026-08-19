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
function daysfromcivil(y::Integer, m::Integer, d::Integer)
    z = Int64(y) - (m < 3)
    return Int64(d) + @inbounds(_SHIFTEDMONTHDAYS[m]) + 365z + fld(z, 4) - fld(z, 100) +
           fld(z, 400) - 306
end

# --- format programs -----------------------------------------------------------
#
# A compiled pattern is a flat vector of ops. Numeric fields consume 1..width
# digits (fixed = exactly width); literals must match exactly; month-name ops
# consume letters and match against a supplied table. This is the engine that
# Dates-the-stdlib would drive with its locales; here we carry the English
# month/day names it needs.

struct PatternOp
    kind::UInt8     # 1=year 2=month 3=day 4=hour 5=minute 6=second 7=subsec
                    # 8=literal 9=monthname-abbrev 10=monthname-full
                    # 11=hour12 12=am/pm 13=dayname-abbrev 14=dayname-full
    width::UInt8    # numeric: max digits; fixed ⇒ exactly; literal: byte
    fixed::Bool
end

struct DatePattern
    ops::Vector{PatternOp}
    hasdate::Bool
    hastime::Bool
end

const ENGLISH_MONTHS_ABBR = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
const ENGLISH_DAYS_ABBR = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]
const ENGLISH_DAYS_FULL = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
const ENGLISH_MONTHS_FULL = ["January","February","March","April","May","June","July",
                             "August","September","October","November","December"]

"""
    compilepattern(fmt::AbstractString) -> DatePattern

Compile a Dates-style format string (tokens `y m d H M S s u U`, plus literal
separators; repeated letters set the width, `yyyy`-style runs are fixed-width).
Unsupported tokens throw at compile time — configuration errors surface when
the format is pinned, never per cell.
"""
function compilepattern(fmt::AbstractString)
    ops = PatternOp[]
    hasdate = false
    hastime = false
    i = firstindex(fmt)
    while i <= lastindex(fmt)
        c = fmt[i]
        n = 1
        while i + n <= lastindex(fmt) && fmt[i + n] == c
            n += 1
        end
        if c == 'y' || c == 'Y'
            n <= typemax(UInt8) ||
                throw(ArgumentError("year token run exceeds 255 bytes in \"$fmt\""))
            push!(ops, PatternOp(1, UInt8(max(n, 4)), n >= 4)); hasdate = true
        elseif c == 'm'
            push!(ops, PatternOp(2, UInt8(2), n >= 2)); hasdate = true
        elseif c == 'd'
            push!(ops, PatternOp(3, UInt8(2), n >= 2)); hasdate = true
        elseif c == 'H'
            push!(ops, PatternOp(4, UInt8(2), n >= 2)); hastime = true
        elseif c == 'M'
            push!(ops, PatternOp(5, UInt8(2), n >= 2)); hastime = true
        elseif c == 'S'
            push!(ops, PatternOp(6, UInt8(2), n >= 2)); hastime = true
        elseif c == 's'
            push!(ops, PatternOp(7, UInt8(9), false)); hastime = true
        elseif c == 'u'
            push!(ops, PatternOp(9, UInt8(0), false)); hasdate = true
        elseif c == 'U'
            push!(ops, PatternOp(10, UInt8(0), false)); hasdate = true
        elseif c == 'I'
            # 12-hour clock: same width rules as 'H'; `p` (if present) adjusts
            push!(ops, PatternOp(11, UInt8(2), n >= 2)); hastime = true
        elseif c == 'p'
            # AM/PM: exactly two letters, case-insensitive (Dates' rule)
            push!(ops, PatternOp(12, UInt8(0), false)); hastime = true
        elseif c == 'e'
            # day-of-week names are consumed and validated, never used
            # (Dates' DayOfWeekToken) — they do not make a pattern a date
            push!(ops, PatternOp(13, UInt8(0), false))
        elseif c == 'E'
            push!(ops, PatternOp(14, UInt8(0), false))
        elseif c in ('Q', 'q')
            throw(ArgumentError("unsupported date format token '$c' in \"$fmt\""))
        elseif isascii(c)
            # any other ASCII char is a literal (Dates' rule: only token letters
            # are special — 'T' in ISO datetime is a plain separator)
            for _ in 1:n
                push!(ops, PatternOp(8, UInt8(c), true))
            end
        else
            throw(ArgumentError("non-ASCII literal '$c' in date format \"$fmt\""))
        end
        i += n
    end
    return DatePattern(ops, hasdate, hastime)
end

# The default ISO patterns, precompiled.
const ISO_DATE     = compilepattern("yyyy-mm-dd")
const ISO_TIME     = compilepattern("HH:MM:SS.s")
const ISO_DATETIME = compilepattern("yyyy-mm-ddTHH:MM:SS.s")

@inline function _readnum(buf, i, j, maxw, fixed)
    v = 0
    k = i
    lim = min(j, i + Int(maxw) - 1)
    @inbounds while k <= lim
        d = buf[k] - UInt8('0')
        d > 0x09 && break
        v > (typemax(Int) - Int(d)) ÷ 10 && return (0, k, false)
        v = v * 10 + Int(d)
        k += 1
    end
    ndig = k - i
    ndig == 0 && return (0, i, false)
    fixed && ndig != Int(maxw) && return (v, k, false)
    return (v, k, true)
end

function _matchname(buf, i, j, table)
    # case-insensitive prefix match against table entries; returns (idx, next, ok)
    @inbounds for (mi, name) in enumerate(table)
        ncu = ncodeunits(name)
        i + ncu - 1 <= j || continue
        ok = true
        for k in 1:ncu
            _lower(buf[i + k - 1]) == _lower(UInt8(codeunit(name, k))) || (ok = false; break)
        end
        ok && return (mi, i + ncu, true)
    end
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

@inline function _iso_ymd(buf::Vector{UInt8}, i::Int)
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

@inline function _iso_hms(buf::Vector{UInt8}, i::Int)
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
@inline function parseiso10(buf::Vector{UInt8}, i::Int)
    y, m, d, ok = _iso_ymd(buf, i)
    (ok && _validymd(y, m, d)) || return (CivilParts(), RC_INVALID)
    return (CivilParts(Int32(y), Int8(m), Int8(d), Int8(0), Int8(0), Int8(0), Int32(0)), RC_OK)
end

"""
    parseiso19(buf, i) -> (CivilParts, rc)

`yyyy-mm-ddTHH:MM:SS` in exactly 19 bytes (no subseconds; those fall through).
"""
@inline function parseiso19(buf::Vector{UInt8}, i::Int)
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
@inline function parseiso8(buf::Vector{UInt8}, i::Int)
    h, mi, s, ok = _iso_hms(buf, i)
    (ok && _validhms(h, mi, s)) || return (CivilParts(), RC_INVALID)
    return (CivilParts(Int32(1), Int8(1), Int8(1), Int8(h), Int8(mi), Int8(s), Int32(0)), RC_OK)
end

"""
    parsecivil(buf, i, j, pat::DatePattern) -> (CivilParts, rc)

Run a compiled pattern over the exact span. Trailing sub-second precision
beyond the pattern (`.s` matching 1–9 digits) is scaled to nanoseconds. The
whole span must be consumed. Calendar validity (month/day ranges, leap years)
is checked here — structurally valid but impossible dates are INVALID.
"""
function parsecivil(buf::Vector{UInt8}, i::Int, j::Int, pat::DatePattern)
    y = 1; mo = 1; dy = 1; h = 0; mi = 0; s = 0; ns = 0
    ampm = 0x00                                          # 0 none, 1 AM, 2 PM
    k = i
    ops = pat.ops
    oi = 1
    @inbounds while oi <= length(ops)
        op = ops[oi]
        if op.kind == 8
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
            idx, k2, ok = _matchname(buf, k, j, op.kind == 9 ? ENGLISH_MONTHS_ABBR : ENGLISH_MONTHS_FULL)
            ok || return (CivilParts(), RC_INVALID)
            mo = idx
            k = k2
        elseif op.kind == 13 || op.kind == 14
            _, k2, ok = _matchname(buf, k, j, op.kind == 13 ? ENGLISH_DAYS_ABBR : ENGLISH_DAYS_FULL)
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
            v, k2, ok = _readnum(buf, k, j, 9, false)
            ok || return (CivilParts(), RC_INVALID)
            nd = k2 - k
            ns = v * Int(10)^(9 - nd)
            k = k2
        else
            v, k2, ok = _readnum(buf, k, j, op.width, op.fixed)
            ok || return (CivilParts(), RC_INVALID)
            if op.kind == 1
                y = v
            elseif op.kind == 2
                mo = v
            elseif op.kind == 3
                dy = v
            elseif op.kind == 4 || op.kind == 11
                h = v
            elseif op.kind == 5
                mi = v
            else
                s = v
            end
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
