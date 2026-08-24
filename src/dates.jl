# =============================================================================
# Dates adapters. The civil kernels produce a `CivilParts` record through pure
# integer arithmetic. This file owns conversion to Dates values and translates
# a `DateFormat` into a kernel pattern. The public API dispatches on Dates
# types, but civil.jl remains independent of the Dates stdlib.
# =============================================================================

@inline todate(c::CivilParts) = Dates.Date(Dates.UTD(daysfromcivil(c.year, c.month, c.day)))

@inline function todatetime(c::CivilParts)
    days = daysfromcivil(c.year, c.month, c.day)
    ms = Int64(c.nanosecond) ÷ 1_000_000
    return Dates.DateTime(Dates.UTM(((days * 24 + c.hour) * 60 + c.minute) * 60_000 +
                                    Int64(c.second) * 1000 + ms))
end

@inline totime(c::CivilParts) =
    Dates.Time(Dates.Nanosecond(((Int64(c.hour) * 60 + c.minute) * 60 + c.second) *
                                1_000_000_000 + c.nanosecond))

# Translate `Dates.DateFormat` tokens directly. Reconstructing a format string
# is lossy: an escaped token such as `\m` has already become `Dates.Delim('m')`,
# and the DateFormat also carries the locale used for textual month/day names.
# The adapter owns DateFormat translation and caching. Civil plan construction,
# execution selection, and String-pattern caching remain in civil.jl.
function _datepartop(t::Dates.DatePart{c}) where {c}
    width = t.width
    width >= 1 || throw(ArgumentError("date format token '$c' has invalid width $width"))

    kind = _patternkind(c)
    kind != 0 || throw(ArgumentError("unsupported DateFormat token '$c'"))
    hasdate = _kindhasdate(kind)
    hastime = _kindhastime(kind)

    # DateFormat's `fixed` bit is the parsing contract. In the civil bytecode,
    # 0xff marks an unbounded non-fixed numeric field; fixed widths above 255
    # use the civil program's extended encoding. CivilParts stores at most
    # nanoseconds, so fractional seconds remain limited to nine digits.
    maxwidth = if kind == 7
        t.fixed ? width : 9
    elseif kind <= 6 || kind == 11
        t.fixed ? Int(width) : Int(typemax(UInt8))
    elseif kind in (9, 10, 13, 14)
        t.fixed ? Int(width) : 0
    else
        0
    end
    kind == 7 && width > 9 &&
        throw(ArgumentError("subsecond date format token has unsupported width $width"))
    return PatternOp(kind, maxwidth, t.fixed), hasdate, hastime
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
    Base.@nospecialize df
    ops = PatternOp[]
    natural = PatternOp[]
    hasdate = false
    hastime = false
    hasnames = false
    for t in df.tokens
        if t isa Dates.DatePart
            op, token_hasdate, token_hastime = _datepartop(t)
            push!(ops, op)
            push!(natural, _naturalop(op, t))
            hasdate |= token_hasdate
            hastime |= token_hastime
            hasnames |= op.kind in (0x09, 0x0a, 0x0d, 0x0e)
        elseif t isa Dates.Delim
            _pushdelimiter!(ops, t)
            _pushdelimiter!(natural, t)
        else
            throw(ArgumentError("unsupported DateFormat token $(typeof(t))"))
        end
    end
    locale = df.locale
    names = !hasnames || locale === Dates.ENGLISH ? _ENGLISH_CIVIL_NAMES_BOX :
            CivilNamesBox(CivilNames(CivilNameTable(locale.month_abbr_value, Val(24)),
                                     CivilNameTable(locale.month_value, Val(24)),
                                     CivilNameTable(locale.day_of_week_abbr_value, Val(14)),
                                     CivilNameTable(locale.day_of_week_value, Val(14))))
    return _makepattern(ops, natural, hasdate, hastime, names)
end

# The fixed fast path reads each numeric field at the token's own width ("mm"
# is two digits, "yyyy" four). Dates' variable-width rule still governs: every
# other shape uses the compiled executor or general interpreter, which reads
# the same values whenever the fixed attempt would have succeeded.
@inline function _naturalop(op::PatternOp, t::Dates.DatePart)
    (1 <= op.kind <= 7 && 1 <= t.width) || return op
    return PatternOp(op.kind, Int(t.width), true)
end

# A canonical English DateFormat carries its source in its type. Reconstruct
# the format once during specialization and embed its pointer-sized plan.
# Tuple identity uses Julia's value-based `===` for these immutable tokens, so
# the guard checks delimiter values, field widths, and fixed bits in one bounded
# operation. Hand-built same-type tokens that differ at runtime use the cache.
# DatePattern is an opaque pointer-sized handle, so a canonical compiled plan
# can be embedded even when its source DateFormat has many tuple-shaped tokens.
# Execution crosses a function barrier so inference does not expand the
# interpreter into each public adapter specialization.

struct _RuntimeDateFormatEntry
    locale::Dates.DateLocale
    tokens::Tuple
    pattern::DatePattern
end

struct _RuntimeDateFormatBucket
    entries::Vector{_RuntimeDateFormatEntry}
    locale_sensitive::Bool
end

mutable struct _RuntimeDateFormatCache
    @atomic table::Dict{DataType, _RuntimeDateFormatBucket}
end

const _RUNTIME_DATEFORMAT_CACHE =
    _RuntimeDateFormatCache(Dict{DataType, _RuntimeDateFormatBucket}())
const _RUNTIME_DATEFORMAT_LOCK = ReentrantLock()
const _RUNTIME_DATEFORMAT_CACHE_MAX = 256
const _RUNTIME_DATEFORMAT_BUCKET_MAX = 8

struct _CanonicalDateFormatEntry
    locale::Dates.DateLocale
    pattern::DatePattern
end

struct _CanonicalDateFormatBucket
    entries::Vector{_CanonicalDateFormatEntry}
end

mutable struct _CanonicalDateFormatCache
    @atomic table::Dict{DataType, _CanonicalDateFormatBucket}
end

const _CANONICAL_DATEFORMAT_CACHE =
    _CanonicalDateFormatCache(Dict{DataType, _CanonicalDateFormatBucket}())

@inline _sametokens(left::Tuple, right::Tuple) = left === right

@inline function _findruntimepattern(bucket::_RuntimeDateFormatBucket,
                                     locale::Dates.DateLocale, tokens::Tuple)
    @inbounds for entry in bucket.entries
        (!bucket.locale_sensitive || entry.locale === locale) &&
            _sametokens(entry.tokens, tokens) &&
            return entry.pattern
    end
    return nothing
end

function _formattypeuseslocale(tokens_type)
    tokens_type isa DataType && tokens_type <: Tuple || return true
    # An abstract tuple parameter can hold locale-sensitive DateParts even if
    # the first value cached under it contains only numeric fields. Key such a
    # bucket by locale from its first entry so later name formats cannot reuse
    # a plan compiled from another locale.
    isconcretetype(tokens_type) || return true
    for token_type in tokens_type.parameters
        token_type <: Dates.DatePart || continue
        c = token_type.parameters[1]
        c in ('u', 'U', 'e', 'E') && return true
    end
    return false
end

@inline function _findcanonicalpattern(bucket::_CanonicalDateFormatBucket,
                                       locale::Dates.DateLocale)
    @inbounds for entry in bucket.entries
        entry.locale === locale && return entry.pattern
    end
    return nothing
end

@inline function _lookupcanonicalpattern(format_type::DataType,
                                         locale::Dates.DateLocale)::Union{DatePattern, Nothing}
    table = @atomic :acquire _CANONICAL_DATEFORMAT_CACHE.table
    bucket = get(table, format_type, nothing)
    bucket === nothing && return nothing
    return _findcanonicalpattern(bucket, locale)
end

@noinline function _cachecanonicalformat!(format_type::DataType, source::Symbol,
                                          locale::Dates.DateLocale)::DatePattern
    return lock(_RUNTIME_DATEFORMAT_LOCK) do
        table = @atomic :acquire _CANONICAL_DATEFORMAT_CACHE.table
        bucket = get(table, format_type, nothing)
        if bucket !== nothing
            pattern = _findcanonicalpattern(bucket, locale)
            pattern === nothing || return pattern
        end
        df = Dates.DateFormat(String(source), locale)
        typeof(df) === format_type ||
            throw(ArgumentError("DateFormat source and token type do not agree"))
        pattern = compilepattern(df)
        entries = bucket === nothing ? _CanonicalDateFormatEntry[] :
                                       copy(bucket.entries)
        length(entries) >= _RUNTIME_DATEFORMAT_BUCKET_MAX && deleteat!(entries, 1)
        push!(entries, _CanonicalDateFormatEntry(locale, pattern))
        updated = copy(table)
        if bucket === nothing && length(updated) >= _RUNTIME_DATEFORMAT_CACHE_MAX
            delete!(updated, first(keys(updated)))
        end
        updated[format_type] = _CanonicalDateFormatBucket(entries)
        @atomic :release _CANONICAL_DATEFORMAT_CACHE.table = updated
        return pattern
    end
end

@inline function _canonicalformatplan(format_type::DataType, source::Symbol,
                                      locale::Dates.DateLocale)::DatePattern
    pattern = _lookupcanonicalpattern(format_type, locale)
    pattern === nothing || return pattern
    return _cachecanonicalformat!(format_type, source, locale)
end

Base.@constprop :none @noinline function _lookupruntimepattern(
        format_type::DataType, locale::Dates.DateLocale,
        tokens::Tuple)::Union{DatePattern, Nothing}
    table = @atomic :acquire _RUNTIME_DATEFORMAT_CACHE.table
    bucket = get(table, format_type, nothing)
    bucket === nothing && return nothing
    return _findruntimepattern(bucket, locale, tokens)
end

Base.@nospecializeinfer @noinline function _cacheruntimeformat!(
        df::Dates.DateFormat, format_type::DataType)::DatePattern
    Base.@nospecialize df
    return lock(_RUNTIME_DATEFORMAT_LOCK) do
        table = @atomic :acquire _RUNTIME_DATEFORMAT_CACHE.table
        bucket = get(table, format_type, nothing)
        if bucket !== nothing
            pattern = _findruntimepattern(bucket, df.locale, df.tokens)
            pattern === nothing || return pattern
        end
        pattern = compilepattern(df)
        locale_sensitive = bucket === nothing ?
            _formattypeuseslocale(format_type.parameters[2]) : bucket.locale_sensitive
        entries = bucket === nothing ? _RuntimeDateFormatEntry[] : copy(bucket.entries)
        length(entries) >= _RUNTIME_DATEFORMAT_BUCKET_MAX && deleteat!(entries, 1)
        storedlocale = locale_sensitive ? df.locale : Dates.ENGLISH
        push!(entries, _RuntimeDateFormatEntry(storedlocale, df.tokens, pattern))
        updated = copy(table)
        if bucket === nothing && length(updated) >= _RUNTIME_DATEFORMAT_CACHE_MAX
            delete!(updated, first(keys(updated)))
        end
        updated[format_type] = _RuntimeDateFormatBucket(entries, locale_sensitive)
        @atomic :release _RUNTIME_DATEFORMAT_CACHE.table = updated
        return pattern
    end
end

Base.@constprop :none @noinline function _runtimeformatplan(df::F)::DatePattern where
                                                        {F <: Dates.DateFormat}
    pattern = _lookupruntimepattern(F, df.locale, df.tokens)
    pattern === nothing || return pattern
    return _cacheruntimeformat!(df, F)
end

@generated function _translatedpattern(df::Dates.DateFormat{S, T}) where {S, T}
    fallback = :(_runtimeformatplan(df))
    S isa Symbol || return fallback
    reconstructed = try
        Dates.DateFormat(String(S))
    catch
        return fallback
    end
    typeof(reconstructed) === Dates.DateFormat{S, T} || return fallback
    pattern = compilepattern(reconstructed)
    expected = QuoteNode(reconstructed.tokens)
    if _formattypeuseslocale(T)
        canonical = :(df.locale === Dates.ENGLISH ? $pattern :
                      _canonicalformatplan($(Dates.DateFormat{S, T}),
                                           $(QuoteNode(S)), df.locale))
        return :(df.tokens === $expected ? $canonical : $fallback)
    end
    return :(df.tokens === $expected ? $pattern : $fallback)
end
