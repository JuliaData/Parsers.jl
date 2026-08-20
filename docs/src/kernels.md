```@meta
CurrentModule = Parsers
```

# Low-level kernels

The kernels parse exactly `buf[i:j]`. They are designed for readers and
tokenizers that already own a byte buffer and its validated bounds.

!!! warning "Bounds are a caller contract"
    Kernel hot paths can use unchecked loads. Do not pass untrusted indices.
    Use the checked `Parsers.parse(T, buf, first, last)` or
    `Parsers.tryparse(T, buf, first, last)` forms when bounds are not already
    proven.

## Integers and floats

The decimal `parseint` overload returns `(value, code)`. The explicit-base
overload returns `(value, code, badpos)`. `badpos` identifies an invalid digit;
it is not part of the decimal overload. `parsebigint` uses the same two return
shapes for its decimal and explicit-base overloads.

```@docs
Parsers.parseint
Parsers.parsefloat
Parsers.parsebigint
Parsers.parsebigfloat
Parsers.BigWork
```

The self-contained `parsebigfloat` decimal parser has a deliberate prove-out bound
near `10^±65536`. It returns `RC_OVERFLOW` outside that bound. Its hexadecimal
path returns `RC_OVERFLOW` or `RC_UNDERFLOW` for extreme binary exponents. The
public `Parsers.parse` and `Parsers.tryparse` methods for `BigFloat` use MPFR
and match Base across MPFR's full exponent range.

## Boolean and UUID

```@docs
Parsers.parsebool
Parsers.parseuuid
```

## Civil date and time parsing

`compilepattern` performs configuration work and can throw for an invalid
format. `parsecivil` then parses a byte span into integer-only `CivilParts`.
The adapters used by the public API convert those fields to `Dates` types.

```@docs
Parsers.CivilParts
Parsers.DatePattern
Parsers.compilepattern
Parsers.parsecivil
```
