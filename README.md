Parsers.jl
=============

[![codecov](https://codecov.io/gh/JuliaData/Parsers.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/JuliaData/Parsers.jl)
[![Travis Build Status](https://travis-ci.org/JuliaData/Parsers.jl.svg?branch=master)](https://travis-ci.org/JuliaData/Parsers.jl)

A collection of type parsers and utilities for Julia.

**Installation**: at the Julia REPL, `import Pkg; Pkg.add("Parsers")`

**Maintenance**: Parsers is maintained collectively by the [JuliaData collaborators](https://github.com/orgs/JuliaData/people).
Responsiveness to pull requests and issues can vary, depending on the availability of key collaborators.


### Basic Usage
```julia
using Parsers

# basic int/float parsing
x = Parsers.parse(Int, "101")
y = Parsers.parse(Float64, "101.101")

# use comma as decimal
y2 = Parsers.parse(Float64, "101,101", Parsers.Options(decimal=','))

# Bool parsing
z = Parsers.parse(Bool, "true")

# Date/DateTime parsing
using Dates
a = Parsers.parse(Date, "2018-01-01")

# custom dateformat
b = Parsers.parse(Date, "01/20/2018", Parsers.Options(dateformat="mm/dd/yyyy"))

# will throw on invalid values
Parsers.parse(Int, "abc")

# tryparse will return `nothing` on invalid values
y = Parsers.tryparse(Int, "abc")
```

### Additional usage
Read through the docs of the following types/functions for more information on using advanced Parsers machinery:
  * `?Parsers.Options`
  * `?Parsers.xparse`
  * `?Parsers.ReturnCode`
