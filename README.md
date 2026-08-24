# Parsers.jl

[![CI](https://github.com/JuliaData/Parsers.jl/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/JuliaData/Parsers.jl/actions/workflows/ci.yml)
[![Codecov](https://codecov.io/gh/JuliaData/Parsers.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaData/Parsers.jl)
[![PkgEval](https://juliahub.com/docs/Parsers/pkgeval.svg)](https://juliahub.com/ui/Packages/Parsers/833b9)
[![Version](https://juliahub.com/docs/Parsers/version.svg)](https://juliahub.com/ui/Packages/Parsers/833b9)

Parsers.jl provides fast, exact parsers for Julia scalar types. Its public API
has two levels:

- `Parsers.parse`, `Parsers.tryparse`, and `Parsers.parsenext` provide the
  checked user-facing interface.
- Span-exact kernels provide low-level `(value, code)` results for readers and
  tokenizers that already control their input bounds.

Parsers 3 is a rewrite. It keeps whole-value parsing and removes the
delimited-field machinery from Parsers 2. The reader now owns quoting,
delimiters, escaping, and missing-value rules.

Parsers 3 requires Julia 1.10 or later. The package exports no names. Use its
API through the `Parsers` namespace.

## Installation

```julia
import Pkg
Pkg.add("Parsers")
```

## Whole-value parsing

```julia
import Parsers

Parsers.parse(Int, "101")                         # 101
Parsers.parse(Float64, "101.101")                # 101.101
Parsers.parse(Float64, "101,101"; decimal=',')   # 101.101
Parsers.parse(Int, "1,000,000"; groupmark=',')   # 1000000
Parsers.parse(Int, "0x1f")                       # 31
Parsers.parse(Int, "z"; base=36)                 # 35
Parsers.parse(Float32, "0.1")                    # 0.1f0
Parsers.parse(Float64, "0x1.8p1")                # 3.0
Parsers.parse(Bool, "true")                      # true
Parsers.parse(Bool, "yes"; trues=["yes"], falses=["no"])
Parsers.parse(BigInt, "123456789012345678901234567890")
Parsers.parse(BigFloat, "0.1")
Parsers.parse(Base.UUID, "123e4567-e89b-12d3-a456-426614174000")
```

`Parsers.tryparse` has the same target and keyword support. It returns
`nothing` for malformed or out-of-range input. Configuration errors, such as
an invalid base or incompatible numeric marks, still throw:

```julia
Parsers.tryparse(Int, "abc")  # nothing
```

Supported whole-value targets and their keywords are:

| Target | Keywords |
|---|---|
| `Int8` through `Int128`, `UInt8` through `UInt128`, and `BigInt` | `base`, `groupmark` |
| `Float16`, `Float32`, and `Float64` | `decimal`, `groupmark` |
| `BigFloat` | `decimal`, `groupmark`, `rounding` |
| `Bool` | `trues`, `falses` |
| `Dates.Date`, `Dates.DateTime`, and `Dates.Time` | `dateformat` |
| `Base.UUID` | none |

Short default decimals and in-range values with a supported rounding mode and
a custom `decimal` or `groupmark` use Parsers' package-owned numeric
conversion. Longer default values go directly to MPFR's native BigFloat string
parser. That parser also handles hexadecimal values, NaN payloads, and MPFR's
full exponent range. Configured syntax is always validated by Parsers; a valid
configured value outside the bounded kernel's range is normalized before MPFR
converts it.

Numbers and `Bool` accept surrounding ASCII whitespace. Dates and UUIDs must
fill the input exactly. Custom `trues` and `falses` lists replace the default
`true`, `false`, `1`, and `0` spellings; they do not extend them. Custom
spellings cannot be empty.

### Dates and times

```julia
using Dates

Parsers.parse(Date, "2018-01-01")
Parsers.parse(Date, "01/20/2018"; dateformat="mm/dd/yyyy")
Parsers.parse(DateTime, "2024-01-02T03:04:05.125")
Parsers.parse(Time, "1:05 PM"; dateformat="I:MM p")
```

`dateformat` accepts a format string, a `Dates.DateFormat`, or a compiled
`Parsers.DatePattern`. Compile a repeated custom format once:

```julia
format = Dates.DateFormat("mm/dd/yyyy")
pattern = Parsers.compilepattern(format)
Parsers.parse(Date, "01/20/2018"; dateformat=pattern)
```

A `Dates.DateFormat` keeps its escaped literals and locale tables. A format
string uses the default English tables. Format strings and dynamic or
noncanonical `Dates.DateFormat` values use bounded caches. Canonical English
DateFormats compile lazily into their specialized adapters. `compilepattern`
lets a caller compile eagerly and keep the resulting plan.
Fractional-second fields accept up to nine digits. `Time` preserves
nanoseconds, while `DateTime` truncates to its millisecond resolution.

## Byte spans and tokenizing

The checked span forms use an inclusive `first:last` byte range:

```julia
buf = Vector{UInt8}("12,3.5e2,true")

Parsers.parse(Int, buf, 1, 2)          # 12
Parsers.parse(Float64, buf, 4, 8)      # 350.0
Parsers.tryparse(Bool, buf, 10, 13)    # true
```

`String`, `SubString{String}`, their `codeunits` views, and one-based
`AbstractVector{UInt8}` inputs use their existing byte storage. Other
`AbstractString` inputs can require a copy. Byte vectors with offset axes are
rejected because public span indices are one-based.

Use `parsenext` when the token end is not known. It finds and parses the
longest supported token at `pos` and does not skip whitespace. Recognition and
conversion advance together; it does not scan a boundary and then call a
whole-value parser on the same span:

```julia
value, nextpos, code = Parsers.parsenext(Float64, buf, 4, length(buf))
# (350.0, 9, Parsers.RC_OK)
```

`nextpos` is the first byte that was not consumed. It equals `pos` when no
valid token starts there. A range error consumes the complete token, returns
the rounded or range value, and sets `RC_OVERFLOW` or `RC_UNDERFLOW`. An
invalid token returns the zero value for the target and sets `RC_INVALID`.

Byte bounds are checked. A nonempty range must satisfy
`1 <= pos <= last <= length(bytes)`. When `length(bytes) + 1` is representable,
the one valid empty range is `pos == length(bytes) + 1` and
`last == length(bytes)`; it returns `RC_INVALID`. Other invalid ranges throw
`BoundsError`. If a token consumes byte `typemax(Int)`, its one-past
`nextpos` is not representable and `parsenext` throws `OverflowError`.

`parsenext` supports fixed-width integers and floats, `BigInt`, `BigFloat`,
and `Bool`. It supports radix prefixes, digit-group marks, C99 hexadecimal
floats, and custom Boolean spellings. The longest matching custom Boolean
spelling wins. `parsenext` does not scan dates or UUIDs, and it is not a
quoted-field or delimiter scanner.

`parsenext(BigFloat, ...)` uses the bounded low-level kernel. It returns a
range code outside that kernel's decimal prove-out range. Whole-value
`BigFloat` parsing instead uses MPFR's full range and can accept additional
MPFR-only spellings.

## Low-level kernels

The kernels consume exactly `buf[i:j]`. Their bounds are a caller contract;
hot paths can use unchecked loads. Use the checked public span forms for
untrusted indices. Kernels accept `AbstractVector{UInt8}` buffers; use
`codeunits(s)` for a string. A kernel `decimal` argument is a `UInt8` byte.

| Call | Result |
|---|---|
| `Parsers.parseint(T, buf, i, j)` | `(value, code)` for a decimal integer |
| `Parsers.parseint(T, buf, i, j, base)` | `(value, code, badpos)` for base 2 through 62 |
| `Parsers.parsefloat(T, buf, i, j, decimal)` | `(value, code)` for `Float16`, `Float32`, or `Float64` |
| `Parsers.parsebool(buf, i, j)` | `(value, code)` for `true` or `false` |
| `Parsers.parsebigint(buf, i, j)` | `(value, code)` for a decimal `BigInt` |
| `Parsers.parsebigint(buf, i, j, base)` | `(value, code, badpos)` for an arbitrary-base `BigInt` |
| `Parsers.parsebigfloat(buf, i, j, decimal; prec, rounding)` | `(value, code)` for a `BigFloat` |
| `Parsers.parseuuid(buf, i, j)` | `(UInt128, code)` |
| `Parsers.parsecivil(buf, i, j, pattern)` | `(CivilParts, code)` |

Compare return codes by name: `Parsers.RC_OK`, `Parsers.RC_INVALID`,
`Parsers.RC_OVERFLOW`, or `Parsers.RC_UNDERFLOW`. Their numeric values are an
implementation detail. The explicit-base `parseint` and `parsebigint`
overloads also return `badpos`, which identifies an invalid digit.

Given a valid span and configuration, fixed-width numeric kernels report parse
failures through a code that the caller must check. `Parsers.compilepattern`
compiles a temporal format for `parsecivil`; it is not a parsing kernel and can
throw for an invalid format.

The low-level `parsebigfloat` decimal kernel has a deliberate prove-out bound
near `10^±65536`. It reports `RC_OVERFLOW` outside that bound. Repeated calls
can reuse a `Parsers.BigWork` workspace with
`Parsers.parsebigfloat(buf, i, j, decimal, workspace; prec, rounding)`.
A `BigWork` workspace owns mutable scratch state. Do not share one workspace
between concurrent calls.
Fixed-width numeric kernels use round-to-nearest, ties-to-even.

## Compatibility with Base

Parsers aims to match `Base.parse` and `Base.tryparse` for its documented
whole-value grammar. The test suite compares results and errors against Base.
Fixed-width float range handling is platform-independent. A nonzero numeric
spelling that rounds to signed zero or infinity is a range error for checked
whole-value parsing. Low-level kernels return the rounded value with
`RC_UNDERFLOW` or `RC_OVERFLOW`. Parsers does not delegate fixed-width decimal
conversion to Base or Julia's private C parser.

Known deliberate differences are:

- Whitespace tolerance is limited to ASCII whitespace.
- Base parses `Float16` through `Float32`, which can double-round at a Float16
  boundary. Parsers resolves such boundaries against the original decimal.
  Base also accepts some `Float16` conversions that round to signed zero or
  infinity, and Windows accepts some such `Float32` values. Parsers reports
  range errors consistently on every platform.
- Temporal patterns require every field of the pattern to be present and the
  whole input to be consumed (Dates allows trailing fields to be omitted).
  The one intentional omission is a final delimiter plus fractional-second
  field: for example, `HH:MM:SS.s` also accepts `HH:MM:SS`.
  Numeric field widths follow `Dates.DateFormat`: a field is fixed-width only
  when another field follows it directly, otherwise it is greedy. Year fields
  take an optional sign.
  String formats use the default English names; a `Dates.DateFormat` keeps its
  locale tables.
- Fractional-second fields accept up to nine digits. `Time` preserves
  nanoseconds; `DateTime` truncates to its millisecond resolution. The Dates
  stdlib parser accepts at most three fractional digits.
- Temporal errors use Parsers-specific message text.
- `Parsers.parse(BigInt, "")` reports an invalid BigInt rather than Base's
  unrelated base error.

## Performance

Instantiate the package environment once, then run the included benchmark:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate()'
julia --project=. benchmarks/values.jl
```

The script needs no benchmark framework. It prints the Julia version, package
version, commit, CPU, corpus size, seed, and timing statistic. Treat the output
as a local microbenchmark. Record the complete header when publishing
comparisons.

## Development

Run the complete test suite from a clean checkout:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

Parsing code is platform-sensitive. Test changes on Julia 1.10 and the latest
stable Julia. Also test 32-bit Julia when changing integer widths, GMP or MPFR
calls, pointer arithmetic, or C integer types. Keep randomized tests
deterministic, and add a small pinned regression for each bug.

## Migrating from Parsers 2

Parsers 3 requires Julia 1.10 or later. Parsers 2 supported Julia 1.6. Update a
dependent package before raising its Parsers compatibility entry to `3`.

The common whole-value calls remain:

```julia
Parsers.parse(T, input)
Parsers.tryparse(T, input)
```

Parsers 3 has the explicit target set shown above. Parsers 2 also parsed
`AbstractString`, `Symbol`, `Char`, `Number`, and custom targets through a
generic `Base.tryparse` fallback. Parsers 3 does not provide those target
parsers. It also does not accept `IO`; the owning I/O layer must read the bytes
and pass the value span to Parsers.

### Replace `Options`

Value-level options are now keywords:

| Parsers 2 | Parsers 3 |
|---|---|
| `Parsers.parse(T, s, Parsers.Options(decimal=','))` | `Parsers.parse(T, s; decimal=',')` |
| `Options(groupmark=',')` | `groupmark=','` for numbers |
| `Options(rounding=mode)` | `rounding=mode` for `BigFloat` |
| `Options(trues=[...], falses=[...])` | `trues=[...], falses=[...]` for `Bool` |
| `Options(dateformat=...)` | `dateformat=...` for temporal types |

Custom Boolean lists replace the default spellings. Include the standard
`"true"`, `"false"`, `"1"`, and `"0"` spellings in custom lists if the
application must keep them.

Reader-specific options were removed. The reader must handle delimiters,
quotes, escapes, sentinels, missing values, comments, empty lines, and field
whitespace before it calls Parsers on a value span.

### Replace `xparse`

For a span whose end is known, convert the old `pos` plus byte `len` to
inclusive indices:

```julia
# Parsers 2
result = Parsers.xparse(T, buf, pos, len, options)

# Parsers 3
last = pos + len - 1
value = Parsers.tryparse(T, buf, pos, last; value_keywords...)
```

Use `Parsers.parsenext` for a numeric or Boolean token whose end is not known.
It does not replace a general field scanner.

### Replace results and extension hooks

`Parsers.Result`, `Parsers.ReturnCode`, `Parsers.ok`, `Parsers.invalid`, and
the other Parsers 2 bit predicates were removed. Use `tryparse` and test for
`nothing` in checked code, or use a kernel and compare its code with the four
named constants.

`PosLen` and `getstring` were removed. The reader now controls string storage
and unescaping. The `typeparser`/`supportedtype` extension seam and its
`AbstractConf`, `conf`, `result`, and `xparse2` hooks were also removed. Keep
application-specific target parsing in the dependent package.

`Parsers.Format` was removed. Pass a format string or `Dates.DateFormat`
through `dateformat`. Compile a repeated format once with
`Parsers.compilepattern`.

Before enabling Parsers 3 in a dependent package:

1. Search for every removed type, function, and configuration object named
   above.
2. Convert each old `pos, len` call to inclusive `first, last` indices.
3. Move field structure and whitespace policy into the reader.
4. Test empty input, byte-span boundaries, invalid tokens, overflow, and
   underflow.
5. Run the full dependent-package suite with the Parsers 3 source developed in
   its environment.

## Maintenance

Parsers is maintained collectively by the JuliaData collaborators. Report
ordinary package problems through the repository issue tracker. Do not post an
unpatched vulnerability publicly; contact a JuliaData maintainer privately.
