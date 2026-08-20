# Changelog

This file records user-visible changes to Parsers.jl. The project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Breaking

- Require Julia 1.10 or later.
- Replace the Parsers 2 field-reader API with a value-only API.
- Remove `Options`, `xparse`, `xparse2`, `Result`, `ReturnCode`, `PosLen`,
  `getstring`, `Format`, and the old custom-type extension hooks.
- Remove `IO` input and string-like, `Char`, `Symbol`, `Number`, and generic
  target parsing.
- Change byte-span arguments from `pos, len` to inclusive `first, last`
  indices.
- Require one-based axes for public byte-vector inputs.
- Move delimiter, quote, escape, sentinel, missing-value, comment, and
  whitespace policy to the owning reader.

### Added

- Add checked whole-input and byte-span forms of `Parsers.parse` and
  `Parsers.tryparse` for the supported scalar types.
- Add `Parsers.parsenext` for integer, floating-point, big-number, and Boolean
  prefix tokenization with explicit return codes.
- Add span-exact integer, float, Boolean, big-number, UUID, and civil-time
  kernels with explicit return codes.
- Add a versioned Documenter site, an expanded Parsers 2 migration guide, and
  a maintainer release checklist.

### Changed

- Parse `Float32` directly instead of parsing through `Float64`.
- Use explicit, target-specific keywords for value parsing.
- Match Base's full MPFR exponent range in public `BigFloat` parsing while the
  low-level self-contained parser keeps its documented decimal prove-out bound.
- Keep the package export surface empty; supported names are called through
  the `Parsers` namespace.
- Raise CI coverage to Julia 1.10, the latest stable Julia, nightly Julia,
  32-bit Julia, Windows, and macOS.

### Fixed

- Make coverage upload failures fail CI instead of passing silently.
- Make at least one downstream integration test require and execute Parsers 3.

[Unreleased]: https://github.com/JuliaData/Parsers.jl/compare/v2.8.7...main
