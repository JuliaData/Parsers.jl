# =============================================================================
# Dates adapters — the ONLY code that touches the Dates stdlib. The kernels
# produce a `CivilParts` record through pure integer arithmetic; these turn
# it into Dates values, and translate a `DateFormat` into a kernel pattern.
# When the kernels move to Base, this file moves to Dates.
# =============================================================================

todate(c::CivilParts) = Dates.Date(Dates.UTD(daysfromcivil(c.year, c.month, c.day)))

function todatetime(c::CivilParts)
    days = daysfromcivil(c.year, c.month, c.day)
    ms = Int64(c.nanosecond) ÷ 1_000_000
    return Dates.DateTime(Dates.UTM(((days * 24 + c.hour) * 60 + c.minute) * 60_000 +
                                    Int64(c.second) * 1000 + ms))
end

totime(c::CivilParts) =
    Dates.Time(Dates.Nanosecond(((Int64(c.hour) * 60 + c.minute) * 60 + c.second) *
                                1_000_000_000 + c.nanosecond))

# Compile `Dates.DateFormat` tokens directly. Reconstructing a format string is
# lossy: an escaped token such as `\m` has already become `Dates.Delim('m')`,
# and the DateFormat also carries the locale used for textual month/day names.
# Users can compile either source form once with `compilepattern`.
function _datepartop(t::Dates.DatePart{c}) where {c}
    width = t.width
    width >= 1 || throw(ArgumentError("date format token '$c' has invalid width $width"))

    kind = _patternkind(c)
    kind != 0 || throw(ArgumentError("unsupported DateFormat token '$c'"))
    hasdate = _kindhasdate(kind)
    hastime = _kindhastime(kind)

    # DateFormat's `fixed` bit is the parsing contract. A non-fixed numeric
    # field has no width limit in Dates; 255 is enough to reach this kernel's
    # checked integer limit without truncating the token. CivilParts stores at
    # most nanoseconds, so fractional seconds remain limited to nine digits.
    maxwidth = if kind == 7
        t.fixed ? width : 9
    elseif kind <= 6 || kind == 11
        t.fixed ? width : Int(typemax(UInt8))
    else
        0
    end
    maxwidth <= typemax(UInt8) ||
        throw(ArgumentError("date format token '$c' has unsupported fixed width $width"))
    kind == 7 && maxwidth > 9 &&
        throw(ArgumentError("subsecond date format token has unsupported width $width"))
    return PatternOp(kind, UInt8(maxwidth), t.fixed), hasdate, hastime
end

function _pushdelimiter!(ops::Vector{PatternOp}, t::Dates.Delim)
    d = t.d
    if d isa AbstractChar
        # Dates.Delim{Char,N} means the same character repeated N times.
        n = Int(typeof(t).parameters[2])
        bytes = codeunits(string(d))
        for _ in 1:n, b in bytes
            push!(ops, PatternOp(8, b, true))
        end
    else
        for b in codeunits(String(d))
            push!(ops, PatternOp(8, b, true))
        end
    end
    return ops
end

"""
    compilepattern(df::Dates.DateFormat) -> DatePattern

Compile a `Dates.DateFormat` directly into the byte-oriented pattern program.
Escaped literals and the DateFormat's locale tables are preserved.
"""
function compilepattern(df::Dates.DateFormat)
    ops = PatternOp[]
    hasdate = false
    hastime = false
    for t in df.tokens
        if t isa Dates.DatePart
            op, token_hasdate, token_hastime = _datepartop(t)
            push!(ops, op)
            hasdate |= token_hasdate
            hastime |= token_hastime
        elseif t isa Dates.Delim
            _pushdelimiter!(ops, t)
        else
            throw(ArgumentError("unsupported DateFormat token $(typeof(t))"))
        end
    end
    locale = df.locale
    return DatePattern(ops, hasdate, hastime,
                       ntuple(i -> locale.months_abbr[i], 12),
                       ntuple(i -> locale.months[i], 12),
                       ntuple(i -> locale.days_of_week_abbr[i], 7),
                       ntuple(i -> locale.days_of_week[i], 7))
end
