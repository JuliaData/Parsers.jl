Parsers.jl
=============

[![Coverage Status](https://coveralls.io/repos/JuliaData/Parsers.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/JuliaData/Parsers.jl?branch=master)
[![Travis Build Status](https://travis-ci.org/JuliaData/Parsers.jl.svg?branch=master)](https://travis-ci.org/JuliaData/Parsers.jl)
[![AppVeyor Build status](https://ci.appveyor.com/api/projects/status/85h1i9lll64jpg3y/branch/master?svg=true)](https://ci.appveyor.com/project/quinnj/dataframes-jl/branch/master)

A collection of type parsers and utilities for Julia.

**Installation**: at the Julia REPL, `Pkg.add("Parsers")`

**Maintenance**: Parsers is maintained collectively by the [JuliaData collaborators](https://github.com/orgs/JuliaData/people).
Responsiveness to pull requests and issues can vary, depending on the availability of key collaborators.


### Basic Usage
```julia
using Parsers

# basic int/float parsing
x = Parsers.parse("101", Int)
y = Parsers.parse("101.101", Float64)

# use comma as decimal
y2 = Parsers.parse("101,101", Float64, Parsers.Options(decimal=','))

# Bool parsing
z = Parsers.parse("true", Bool)

# Date/DateTime parsing
using Dates
a = Parsers.parse("2018-01-01", Date)

# custom dateformat
b = Parsers.parse("01/20/2018", Date, Parsers.Options(dateformat="mm/dd/yyyy"))

# will throw on invalid values
Parsers.parse("abc", Int)

# tryparse will return `nothing` on invalid values
y = Parsers.tryparse("abc", Int)
```

### Additional usage
Read through the docs of the following types/functions for more information on using advanced Parsers machinery:
  * `?Parsers.Options`
  * `?Parsers.xparse`
  * `?Parsers.ReturnCode`
