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

# `Dates.DateFormat` → the kernel's pattern string: each DatePart{c} of width n
# is the letter repeated, each Delim its literal text. Round-tripping through
# `compilepattern` gives Dates' own token semantics (only token letters are
# special; 'T' is a plain separator).
function _patternstring(df::Dates.DateFormat)
    io = IOBuffer()
    for t in df.tokens
        if t isa Dates.DatePart
            c = typeof(t).parameters[1]::Char   # the token letter
            for _ in 1:max(t.width, 1)
                print(io, c)
            end
        elseif t isa Dates.Delim
            print(io, t.d)
        else
            throw(ArgumentError("unsupported DateFormat token $(typeof(t))"))
        end
    end
    return String(take!(io))
end
