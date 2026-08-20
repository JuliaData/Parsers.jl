```@meta
CurrentModule = Parsers
```

# Public API

## Whole-input parsing

[`Parsers.parse`](@ref) and [`Parsers.tryparse`](@ref) accept an
`AbstractString` or `AbstractVector{UInt8}`. Their byte-span forms accept an
inclusive `first:last` range and check that range before parsing. Byte-vector
inputs must use one-based axes; offset-axis vectors are rejected.

Numbers and `Bool` accept surrounding ASCII whitespace. Dates and UUIDs must
consume the complete input. Custom `trues` and `falses` lists replace the
default Boolean spellings. Each custom spelling must contain at least one byte.

Supported target types are:

- fixed-width signed and unsigned integers;
- `Float16`, `Float32`, and `Float64`;
- `BigInt` and `BigFloat`;
- `Bool` and `Base.UUID`; and
- `Dates.Date`, `Dates.DateTime`, and `Dates.Time`.

Keyword support is target-specific:

| Target | Keywords |
|---|---|
| fixed-width integers and `BigInt` | `base`, `groupmark` |
| fixed-width floats | `decimal`, `groupmark` |
| `BigFloat` | `decimal`, `groupmark`, `rounding` |
| `Bool` | `trues`, `falses` |
| temporal types | `dateformat` |

Public `BigFloat` conversion uses MPFR's default string grammar. Its decimal,
binary, hexadecimal, special-value, and exponent spellings match Base across
MPFR's full exponent range, including values beyond the bounded range of the
low-level `parsebigfloat` kernel. Custom `decimal` and `groupmark` syntax is
validated before it is normalized for MPFR.

`dateformat` accepts a format string, a `Dates.DateFormat`, or a compiled
`Parsers.DatePattern`. A `Dates.DateFormat` keeps its escaped literals and
month/day locale tables. String formats use the default English tables. Year
fields accept an optional leading `+` or `-` sign.

Compile a repeated custom format once, then reuse its pattern:

```julia
format = Dates.DateFormat("mm/dd/yyyy")
pattern = Parsers.compilepattern(format)
value = Parsers.parse(Dates.Date, "01/20/2018"; dateformat=pattern)
```

Passing a format string or `Dates.DateFormat` directly compiles it for each
call. A reused `DatePattern` avoids that parse-time configuration allocation.
Fractional-second fields accept up to nine digits. `Time` preserves
nanoseconds, while `DateTime` truncates to its millisecond resolution. This is
broader than the Dates stdlib parser, which accepts at most three fractional
digits.

```@docs
Parsers.parse
Parsers.tryparse
```

## Prefix tokenizing

`parsenext` supports fixed-width integers, `Float16`, `Float32`, `Float64`,
`BigInt`, `BigFloat`, and `Bool`. For those targets, it uses the whole-input
value grammar and applicable keywords. Integer parsing supports `base`, radix
prefixes, and `groupmark`. Floating-point parsing supports `decimal`,
`groupmark`, special values, and C99 hexadecimal floats. `BigFloat` also
supports low-level `RoundingMode` values. Boolean parsing supports `trues` and
`falses`; custom lists replace the defaults, and the longest matching spelling
wins.

`parsenext(BigFloat, ...)` uses the bounded low-level `parsebigfloat` kernel.
Values outside that kernel's documented decimal prove-out range return a range
code. Whole-input public parsing instead uses its MPFR fallback across MPFR's
full exponent range.

The call returns `(value, nextpos, code)`. `nextpos` is the first byte that was
not consumed. It equals `pos` when no token starts there. Range errors consume
the complete token, return the kernel's rounded or range value, and set
`RC_OVERFLOW` or `RC_UNDERFLOW`. Other successful tokens return `RC_OK`.
Invalid tokens return the zero value for the target, keep `nextpos == pos`, and
set `RC_INVALID`.

`parsenext` does not skip whitespace. It does not support dates or UUIDs, and
it is not a quoted-field or delimiter scanner.

Byte bounds are checked. A nonempty range must satisfy
`1 <= pos <= last <= length(bytes)`. The one valid empty range is
`pos == length(bytes) + 1` and `last == length(bytes)`; it returns
`RC_INVALID`. All other ranges throw `BoundsError`.

```@docs
Parsers.parsenext
```

## Return codes

Low-level callers must compare codes by name. The numeric values are an
implementation detail.

```@docs
Parsers.RC_OK
Parsers.RC_INVALID
Parsers.RC_OVERFLOW
Parsers.RC_UNDERFLOW
```
