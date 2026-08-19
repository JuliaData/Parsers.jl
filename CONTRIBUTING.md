# Contributing to Parsers.jl

Thank you for improving Parsers.jl. Bug reports, focused fixes, documentation,
and new differential tests are welcome. Participation is governed by the
[code of conduct](CODE_OF_CONDUCT.md).

## Report a bug

Use the GitHub bug-report form. Include:

- the exact input or byte sequence;
- the target type and all keywords;
- the observed value, exception, or return code;
- the expected result and the oracle used;
- Julia and Parsers versions; and
- the operating system and word size.

Report security-sensitive input privately as described in
[SECURITY.md](SECURITY.md).

## Set up the package

From a clean checkout, instantiate the project and run the complete test suite:

```sh
julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.test()'
```

Run tests on Julia 1.10 and on the latest stable Julia before opening a pull
request. Parsing code is platform-sensitive. Test 32-bit Julia when changing
integer widths, GMP or MPFR calls, pointer arithmetic, or C integer types.

## Tests

Keep random tests deterministic. Use an explicit local random-number generator
and a fixed seed. Add a small pinned regression before adding a large fuzz or
differential corpus.

Prefer an independent oracle:

- compare public behavior with `Base.parse` or `Base.tryparse` where parity is
  the contract;
- compare float bit patterns, including signed zero and NaN behavior;
- test the minimum and maximum value of each integer width; and
- test every byte-span boundary directly.

Do not weaken a test because it fails on one architecture. Find the width,
bounds, ABI, or semantics error that caused the failure.

## Documentation

The docs use a standalone environment. Build them with:

```sh
julia --project=docs -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

The build is strict. Update the API reference, migration guide, README, and
changelog when a public contract changes.

## Benchmarks

Run the dependency-free value benchmark with:

```sh
julia --project=. benchmarks/values.jl
```

Include its complete environment header with reported results. Compare the same
commit, Julia version, CPU state, corpus, seed, sample count, and statistic.
Correctness tests must pass before performance results are considered.

## Pull requests

Keep each change focused. State the contract that changed, the root cause, and
the validation performed. Do not add new exports without a clear user-facing
need. Parsers users should normally call supported names through the package
namespace.
