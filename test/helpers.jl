# Shared test helpers. Keep these definitions in one file so each included
# kernel suite does not overwrite the same methods in Main.
b(s) = Vector{UInt8}(codeunits(s))
pint(s) = Parsers.parseint64(b(s), 1, ncodeunits(s))
pint128(s) = Parsers.parseint128(b(s), 1, ncodeunits(s))
pflt(s) = Parsers.parsefloat64(b(s), 1, ncodeunits(s))
pbool(s) = Parsers.parsebool(b(s), 1, ncodeunits(s))

const todate = Parsers.todate
const todatetime = Parsers.todatetime
const totime = Parsers.totime
