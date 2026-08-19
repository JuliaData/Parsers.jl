```@meta
CurrentModule = Parsers
```

# Parsers.jl

Parsers.jl parses Julia scalar values from strings and byte spans. Version 3
separates value parsing from reader-specific structure such as delimiters,
quotes, escapes, and missing-value rules.

Parsers 3 requires Julia 1.10 or later. The package exports no names. Use its
API through the `Parsers` namespace.

## Install

```julia
import Pkg
Pkg.add("Parsers")
```

## Parse a whole value

```jldoctest
julia> import Parsers

julia> Parsers.parse(Int, "42")
42

julia> Parsers.parse(Float64, "1,25"; decimal=',')
1.25

julia> Parsers.tryparse(Int, "not an integer") === nothing
true
```

The checked byte-span forms use an inclusive `first:last` range:

```jldoctest
julia> import Parsers

julia> bytes = Vector{UInt8}("id=1234;");

julia> Parsers.parse(Int, bytes, 4, 7)
1234
```

Use [`Parsers.parsenext`](@ref) when the token end is not known. Use the
[low-level kernels](kernels.md) only when the caller already validates bounds
and handles return codes.

## Version 3 migration

Parsers 3 removes the Parsers 2 field-reader API. Read the
[migration guide](migration.md) before changing a dependent package's compat
entry. The top-level
[changelog](https://github.com/JuliaData/Parsers.jl/blob/main/CHANGELOG.md)
tracks user-visible changes.
