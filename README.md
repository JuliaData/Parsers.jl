Parsers.jl
==========

[![CI](https://github.com/JuliaData/Parsers.jl/workflows/CI/badge.svg)](https://github.com/JuliaData/Parsers.jl/actions?query=workflow%3ACI)
[![codecov](https://codecov.io/gh/JuliaData/Parsers.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/JuliaData/Parsers.jl)
[![deps](https://juliahub.com/docs/Parsers/deps.svg)](https://juliahub.com/ui/Packages/Parsers/833b9?t=2)
[![version](https://juliahub.com/docs/Parsers/version.svg)](https://juliahub.com/ui/Packages/Parsers/833b9)

Fast, exact, self-contained parsers for Julia's scalar types — and a thin
layer that reproduces `Base.parse` / `Base.tryparse` on top of them.

**Installation**: `import Pkg; Pkg.add("Parsers")`

**Maintenance**: Parsers is maintained collectively by the
[JuliaData collaborators](https://github.com/orgs/JuliaData/people).

> **3.0 is a rewrite.** Version 3 keeps the two calls almost everyone uses —
> `Parsers.parse(T, str)` and `Parsers.tryparse(T, str)` — makes them faster
> and Base-identical, adds byte-span and tokenizer forms, and **removes the
> delimited-field machinery** (`Parsers.Options` with `delim`/`quoted`/
> `sentinel`/`escapechar`, `Parsers.xparse`, `Result`/return codes, `PosLen`,
> `getstring`, `typeparser` extension). That machinery now lives where it is
> used, in CSV.jl. See [Migrating from 2.x](#migrating-from-2x).

## Usage

```julia
using Parsers

Parsers.parse(Int, "101")             # 101
Parsers.parse(Float64, "101.101")     # 101.101
Parsers.parse(Float64, "101,101"; decimal=',')
Parsers.parse(Int, "1,000,000"; groupmark=',')
Parsers.parse(Int, "0x1f")            # 31   (0x / 0o / 0b prefixes, like Base)
Parsers.parse(Int, "z"; base=36)      # 35   (2 ≤ base ≤ 62)
Parsers.parse(Float32, "0.1")         # 0.1f0 — parsed natively, never via Float64
Parsers.parse(Float64, "0x1.8p1")     # 3.0  (C99 hexadecimal floats, like Base)
Parsers.parse(Bool, "true")           # true (also "1"/"0", like Base)
Parsers.parse(Bool, "yes"; trues=["yes"], falses=["no"])
Parsers.parse(BigInt, "123456789012345678901234567890")
Parsers.parse(BigFloat, "0.1")        # correctly rounded at precision(BigFloat)
Parsers.parse(Base.UUID, "123e4567-e89b-12d3-a456-426614174000")

using Dates
Parsers.parse(Date, "2018-01-01")
Parsers.parse(Date, "01/20/2018"; dateformat="mm/dd/yyyy")   # a String or a DateFormat
Parsers.parse(DateTime, "2024-01-02T03:04:05.125")
Parsers.parse(Time, "1:05 PM"; dateformat="I:MM p")

Parsers.parse(Int, "abc")             # ArgumentError, the message Base gives
Parsers.parse(Int8, "200")            # OverflowError
Parsers.tryparse(Int, "abc")          # nothing
```

Numbers and `Bool` tolerate surrounding ASCII whitespace; dates and UUIDs
must fill the input exactly — the same rules `Base.parse` follows.

### Byte spans and tokenizing

The whole-input forms are conveniences over span parsing: `s` may be any
`AbstractString` or byte vector, and the span forms take an explicit range —
no substring, no copy.

```julia
buf = Vector{UInt8}("12,3.5e2,true")
Parsers.parse(Int, buf, 1, 2)          # 12
Parsers.parse(Float64, buf, 4, 8)      # 350.0
Parsers.tryparse(Bool, buf, 10, 13)    # true

# a tokenizer wants "the value that starts HERE, and where it ended":
value, nextpos, code = Parsers.parsenext(Float64, buf, 4, length(buf))   # (350.0, 9, RC_OK)
```

`parsenext` recognizes the value's own grammar (`[+-]digits[.digits][e±digits]`,
`inf`/`nan`, `true`/`false`) — the caller does not have to know where the
number ends. This is the primitive JSON- and SQL-wire-format parsers need.

### Supported types

`Int8`…`Int128`, `UInt8`…`UInt128`, `Bool`, `Float16`, `Float32`, `Float64`,
`BigInt`, `BigFloat`, `Base.UUID`, and `Date`/`DateTime`/`Time` (with
`dateformat=` for custom formats; the token set is Dates', including
`I`/`p` for 12-hour clocks and `e`/`E` for day names).

Keywords: `base` (integers), `decimal` and `groupmark` (numbers),
`trues`/`falses` (extra Bool spellings), `dateformat` (temporals).

## The kernels

Underneath the Base-compatible layer sits a family of **span-exact kernels**:

| kernel | what it does |
|---|---|
| `Parsers.parseint(T, buf, i, j[, base])` | any integer width; SWAR eight-digits-at-a-time |
| `Parsers.parsefloat(T, buf, i, j, decimal)` | `Float64` / `Float32`: Clinger → Eisel–Lemire → exact decimal fallback |
| `Parsers.parsebool`, `parsebigint`, `parsebigfloat`, `parseuuid` | |
| `Parsers.parsecivil(buf, i, j, pattern)` | a `CivilParts` record from a compiled format program — no `Dates` dependency |
| `Parsers.compilepattern("yyyy-mm-dd")` | Dates' format tokens → a plain-data pattern |

Each returns `(value, code)` with `code` one of `RC_OK`, `RC_INVALID`,
`RC_OVERFLOW`, `RC_UNDERFLOW`. They never throw, never allocate on the
fixed-width paths, and never fall back to C, `Base.parse`, or GMP/MPFR string
routines: 768-digit halfway floats, subnormals, `Int128`, arbitrary bases,
and hexadecimal floats are handled by self-contained code. That is what makes
them candidates for Base itself, and what CSV.jl builds its columnar loops on.
The float range codes carry the value they rounded to (`±Inf` / `±0`), so a
caller that wants strtod semantics simply treats them as success — while
`Parsers.parse` rejects them exactly as `Base.parse` does.

Two design commitments worth knowing:

* **Strict spellings.** `parsebool` accepts exactly `true`/`false` (the
  Base-parity layer adds `1`/`0`; custom lists replace the defaults);
  temporal patterns are field-exact — `yyyy` is four digits, a bare date is
  not a `DateTime`, and the whole input must be consumed. This is stricter than
  the Dates stdlib (which parses `"24-01-01"` with `yyyy-mm-dd` as year 24 and
  lets trailing fields default), and deliberately so: parse-set ≡ detect-set is
  what lets a type-inferring reader stay sample-independent.
* **`Dates` independence.** Date/time parsing produces integers (`CivilParts`,
  Rata Die days via the same formula `Dates.totaldays` uses); the adapters in
  `src/dates.jl` are the only code that touches the stdlib.

## Performance

`benchmarks/values.jl` reports ns/value for the kernels against `Base.parse`
across shapes. On an M-series laptop: ints 4–5 ns (Base 37–55), short floats
9–12 ns (Base 37), 17-digit floats 27 ns (Base 54), ISO dates 3 ns (Base 55),
UUIDs 6 ns (Base 117), 256-bit `BigFloat` 209 ns (MPFR's own `strtofr` 357).
Against `fast_float`, the C++ reference: parity or better on nine of sixteen
float shapes, within 1.2–1.9× on the rest.

## Migrating from 2.x

| 2.x | 3.0 |
|---|---|
| `Parsers.parse(T, str)`, `Parsers.tryparse(T, str)` | unchanged (faster; errors/whitespace now identical to `Base.parse`) |
| `Parsers.parse(T, str, Parsers.Options(decimal=','))` | `Parsers.parse(T, str; decimal=',')` — likewise `groupmark`, `dateformat`, `trues`/`falses` |
| `Parsers.xparse(T, buf, pos, len, opts)` on a *value* span | `Parsers.parse`/`tryparse(T, buf, first, last)` |
| `Parsers.xparse` to find where a number *ends* (JSON, MySQL) | `Parsers.parsenext(T, buf, pos, last)` |
| `Parsers.Result`, `Parsers.ok/invalid/eof/…` return codes | `tryparse` → `nothing`; kernels return `(value, RC_*)` |
| `Options(delim=, quoted=, sentinel=, escapechar=, ignorerepeated=, stripwhitespace=)` — field-level parsing | removed: quote/delimiter/sentinel handling is the reader's job (CSV.jl 1.0 does it on its structural index) |
| `Parsers.PosLen`, `Parsers.getstring` | removed |
| `Parsers.typeparser` / `Parsers.supportedtype` extension seam | removed; unsupported types get a clear `ArgumentError` — open an issue for a type that belongs in the core set |
| `Parsers.Format` | `dateformat=` accepts a String or `Dates.DateFormat` |

Deliberate deltas from Base, all pinned by tests: `Parsers.parse(BigInt, "")`
says "invalid BigInt" (Base reports an odd base error); whitespace tolerance is
ASCII whitespace; date formats are strict as described above and date errors
carry Parsers' own message text.
