# Migrate from Parsers 2

Parsers 3 is a breaking rewrite. It keeps value parsing and removes the
field-reader layer. A dependent package must update its code before it raises
its Parsers compat entry to `3`.

## Environment change

Parsers 3 requires Julia 1.10 or later. Parsers 2 supported Julia 1.6.

## Common value calls

The common whole-value shape remains:

```julia
Parsers.parse(T, input)
Parsers.tryparse(T, input)
```

The supported target set is now explicit. It contains fixed-width integers and
floats, `BigInt`, `BigFloat`, `Bool`, `Base.UUID`, `Dates.Date`,
`Dates.DateTime`, and `Dates.Time`.

Parsers 2 also parsed `AbstractString`, `Symbol`, `Char`, `Number`, and custom
targets through a generic `Base.tryparse` fallback. Parsers 3 does not provide
those target parsers.

Parsers 2 accepted an `IO` input. Parsers 3 accepts an `AbstractString` or byte
vector. Read the required bytes in the owning I/O layer, then pass the value
span to Parsers.

## Replace `Options`

Value-level options become keywords:

| Parsers 2 | Parsers 3 |
|---|---|
| `Parsers.parse(T, s, Parsers.Options(decimal=','))` | `Parsers.parse(T, s; decimal=',')` |
| `Options(groupmark=',')` | `groupmark=','` for numbers |
| `Options(rounding=mode)` | `rounding=mode` for `BigFloat` |
| `Options(trues=[...], falses=[...])` | `trues=[...], falses=[...]` for `Bool` |
| `Options(dateformat=...)` | `dateformat=...` for temporal types |

Custom Boolean lists replace the default spellings. Include `"true"`,
`"false"`, `"1"`, or `"0"` in the lists if the application must keep them.

Fixed-width numeric kernels use round-to-nearest, ties-to-even. `BigFloat`
keeps an explicit `rounding` keyword. Public `BigFloat` parsing uses MPFR and
matches Base across MPFR's full exponent range. The low-level self-contained
`parsebigfloat` kernel keeps a decimal prove-out bound near `10^±65536` and
reports a range code outside it. A `Dates.DateFormat` preserves escaped
literals and its month/day locale tables; a plain format string uses the
default English tables.

## Move field structure to the reader

The following Parsers 2 concerns are removed:

- delimiters and repeated delimiters;
- open and close quotes;
- escape characters;
- sentinels and missing values;
- comments and empty-line rules;
- leading and trailing whitespace policy; and
- field debug flags.

The reader that owns row and field structure must handle these concerns before
it calls Parsers on the value span.

## Replace `xparse`

For a span whose end is known, replace a `pos` plus byte `len` with inclusive
indices:

```julia
# Parsers 2
result = Parsers.xparse(T, buf, pos, len, options)

# Parsers 3
last = pos + len - 1
value = Parsers.tryparse(T, buf, pos, last; value_keywords...)
```

For a numeric or Boolean token whose end is not known, use
`Parsers.parsenext`. It supports the whole-input value grammar and applicable
keywords for fixed-width integers, floating-point types, `BigInt`, `BigFloat`,
and `Bool`. It returns the first unconsumed byte and one of the four return
codes. `parsenext(BigFloat, ...)` uses the bounded low-level kernel and returns
a range code outside that kernel's decimal prove-out range; whole-input public
parsing uses MPFR's full range. `parsenext` checks its byte range and does not
skip whitespace. It does not
replace a general quoted-field or delimiter scanner, and it does not scan dates
or UUIDs.

## Replace results and return-code predicates

`Parsers.Result`, `Parsers.ReturnCode`, `Parsers.ok`, `Parsers.invalid`, and
the other Parsers 2 bit predicates are removed.

- Use `tryparse` and test for `nothing` in checked application code.
- Use a low-level kernel and compare against `Parsers.RC_OK`,
  `Parsers.RC_INVALID`, `Parsers.RC_OVERFLOW`, or `Parsers.RC_UNDERFLOW` in a
  controlled column loop.

Kernel return shapes are not uniform. In particular, the explicit-base
`parseint` and `parsebigint` overloads also return `badpos`. See the
[kernel reference](kernels.md).

## Removed string spans and extension hooks

`PosLen` and `getstring` are removed. The owning reader now controls string
storage and unescaping.

The `typeparser`/`supportedtype` seam and the related `AbstractConf`, `conf`,
`result`, and `xparse2` hooks are removed. Keep application-specific parsing in
the dependent package. Open an issue if a scalar type belongs in the small
Parsers core.

`Parsers.Format` is removed. Pass a format string or `Dates.DateFormat` through
the `dateformat` keyword. For a repeated custom format, call
`Parsers.compilepattern(format)` once and pass the returned `DatePattern` to
avoid compiling the format for every value.

## Downstream checklist

Before changing a package's compat entry to include Parsers 3:

1. Search for `Options`, `xparse`, `xparse2`, `Result`, `ReturnCode`, `PosLen`,
   `getstring`, `typeparser`, `supportedtype`, and `AbstractConf`.
2. Confirm every old `pos, len` call becomes an inclusive `first, last` call.
3. Move quoting, delimiters, missing values, and whitespace rules to the reader.
4. Add tests for empty input, span boundaries, overflow, underflow, and invalid
   UTF-8 or bytes where applicable.
5. Run the dependent package's full test suite with Parsers developed from the
   version 3 branch before widening compat.
