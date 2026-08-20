# Parsers.jl

[![CI](https://github.com/JuliaData/Parsers.jl/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/JuliaData/Parsers.jl/actions/workflows/ci.yml)
[![Documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaData.github.io/Parsers.jl/stable/)
[![Documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaData.github.io/Parsers.jl/dev/)
[![Codecov](https://codecov.io/gh/JuliaData/Parsers.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaData/Parsers.jl)
[![PkgEval](https://juliahub.com/docs/Parsers/pkgeval.svg)](https://juliahub.com/ui/Packages/Parsers/833b9)
[![Version](https://juliahub.com/docs/Parsers/version.svg)](https://juliahub.com/ui/Packages/Parsers/833b9)

Parsers.jl provides fast, exact parsers for Julia scalar types. Its public API
has two levels:

- `Parsers.parse`, `Parsers.tryparse`, and `Parsers.parsenext` provide the
  checked user-facing interface.
- Span-exact kernels provide low-level `(value, code)` results for readers and
  tokenizers that already control their input bounds.

Parsers 3 is a rewrite. It keeps the common whole-value calls and removes the
delimited-field machinery from Parsers 2. That machinery belongs in the reader
that owns quoting, delimiters, escaping, and missing-value rules.

Parsers 3 requires Julia 1.10 or later. The package exports no names. Use its
API through the `Parsers` namespace.

## Installation

```julia
import Pkg
Pkg.add("Parsers")
```

## Basic use

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

Temporal parsing uses `Dates` types:

```julia
using Dates

Parsers.parse(Date, "2018-01-01")
Parsers.parse(Date, "01/20/2018"; dateformat="mm/dd/yyyy")
Parsers.parse(DateTime, "2024-01-02T03:04:05.125")
Parsers.parse(Time, "1:05 PM"; dateformat="I:MM p")
```

For repeated custom temporal parsing, compile the format once with
`Parsers.compilepattern` and pass the returned pattern through `dateformat`.

`parse` throws for malformed or out-of-range input. `tryparse` returns
`nothing`:

```julia
Parsers.tryparse(Int, "abc")  # nothing
```

Numbers and `Bool` accept surrounding ASCII whitespace. Dates and UUIDs must
fill the input exactly. Custom `trues` and `falses` lists replace the default
Boolean spellings; they do not extend them. Custom spellings cannot be empty.

## Byte spans and tokenizing

The span forms use an inclusive `first:last` byte range:

```julia
buf = Vector{UInt8}("12,3.5e2,true")

Parsers.parse(Int, buf, 1, 2)          # 12
Parsers.parse(Float64, buf, 4, 8)      # 350.0
Parsers.tryparse(Bool, buf, 10, 13)    # true
```

`String`, `SubString{String}`, their `codeunits` views, and one-based
`AbstractVector{UInt8}` inputs use their existing byte storage. Other
`AbstractString` inputs can require a copy. Byte vectors with offset axes are
rejected because the public span indices are one-based.

`parsenext` finds and parses the longest supported token at a byte position. It
does not skip whitespace:

```julia
value, nextpos, code = Parsers.parsenext(Float64, buf, 4, length(buf))
# (350.0, 9, Parsers.RC_OK)
```

For integers, floats, `BigInt`, `BigFloat`, and `Bool`, the tokenizer uses the
same value grammar and applicable keywords as whole-input parsing. This
includes integer radix prefixes, digit-group marks, C99 hexadecimal floats,
and custom Boolean spellings. `parsenext(BigFloat, ...)` uses the bounded
low-level kernel and returns a range code outside that kernel's documented
decimal prove-out range; whole-input parsing uses MPFR's full range. The
tokenizer does not scan dates or UUIDs. See the
[API reference](https://JuliaData.github.io/Parsers.jl/dev/api/) for the exact
return-code and bounds contract.

## Supported whole-value types

- `Int8` through `Int128` and `UInt8` through `UInt128`
- `Float16`, `Float32`, and `Float64`
- `BigInt` and `BigFloat`
- `Bool` and `Base.UUID`
- `Dates.Date`, `Dates.DateTime`, and `Dates.Time`

Keyword support is type-specific. Fixed-width integers and `BigInt` accept
`base` and `groupmark`. Fixed-width floats accept `decimal` and `groupmark`.
`BigFloat` accepts `decimal`, `groupmark`, and `rounding`. `Bool` accepts
`trues` and `falses`. Temporal types accept `dateformat`.

## Low-level kernels

The low-level kernels consume exactly `buf[i:j]`. Their bounds are a caller
contract; use the checked public span forms for untrusted indices.

| Call | Result |
|---|---|
| `Parsers.parseint(T, buf, i, j)` | `(value, code)` for a decimal integer |
| `Parsers.parseint(T, buf, i, j, base)` | `(value, code, badpos)` for base 2 through 62 |
| `Parsers.parsefloat(T, buf, i, j, decimal)` | `(value, code)` for `Float32` or `Float64` |
| `Parsers.parsebool(buf, i, j)` | `(value, code)` for `true` or `false` |
| `Parsers.parsebigint(buf, i, j)` | `(value, code)` for a decimal `BigInt` |
| `Parsers.parsebigint(buf, i, j, base)` | `(value, code, badpos)` for an arbitrary-base `BigInt` |
| `Parsers.parsebigfloat(buf, i, j, decimal; prec, rounding)` | `(value, code)` for a `BigFloat` |
| `Parsers.parseuuid(buf, i, j)` | `(UInt128, code)` |
| `Parsers.parsecivil(buf, i, j, pattern)` | `(CivilParts, code)` |

Codes are `Parsers.RC_OK`, `Parsers.RC_INVALID`, `Parsers.RC_OVERFLOW`, and
`Parsers.RC_UNDERFLOW`. Given a valid span and configuration, fixed-width
numeric kernels report parse failures through a code that the caller must
check. `Parsers.compilepattern` compiles a temporal format for `parsecivil`; it
is not a parsing kernel and can throw for an invalid format.

The low-level `parsebigfloat` decimal kernel has a deliberate prove-out bound
near `10^±65536`. It reports `RC_OVERFLOW` outside that bound. The public
`Parsers.parse` and `Parsers.tryparse` methods for `BigFloat` use MPFR and match
Base across MPFR's full exponent range.

## Compatibility notes

Parsers aims to match `Base.parse` and `Base.tryparse` for the documented
whole-value grammar. The test suite compares results and errors against Base.
Known deliberate differences are:

- Whitespace tolerance is limited to ASCII whitespace.
- Temporal patterns are field-exact, with an optional sign on year fields.
  String formats use the default English names; a `Dates.DateFormat`
  preserves its locale tables.
- Fractional-second fields accept up to nine digits. `Time` preserves
  nanoseconds; `DateTime` truncates to its millisecond resolution. The Dates
  stdlib parser accepts at most three fractional digits.
- Temporal errors use Parsers-specific message text.
- `Parsers.parse(BigInt, "")` reports an invalid BigInt rather than Base's
  unrelated base error.

## Performance

Run the dependency-free benchmark from a clean checkout:

```sh
julia --project=. benchmarks/values.jl
```

The script prints the Julia version, package version, commit, CPU, corpus size,
seed, and timing statistic with its results. Treat the output as a local
microbenchmark. Record the complete header when publishing comparisons.

## Migrating from Parsers 2

Read the [Parsers 2 to 3 migration guide](docs/src/migration.md) before raising
compatibility to Parsers 3. The largest changes are the removal of `Options`,
`xparse`, `Result`, `PosLen`, IO input, string-like target parsing, and the old
custom-type extension seam. Span endpoints are now inclusive indices, not a
`pos` plus a byte length.

## Maintenance and contributing

Parsers is maintained collectively by the
[JuliaData collaborators](https://github.com/orgs/JuliaData/people). See
[CONTRIBUTING.md](CONTRIBUTING.md) for development commands and
[SECURITY.md](SECURITY.md) for private vulnerability reports. User-visible
changes are recorded in [CHANGELOG.md](CHANGELOG.md).
