using Parsers, Test, Dates

import Parsers: INVALID, OK, SENTINEL, QUOTED, DELIMITED, NEWLINE, EOF, INVALID_QUOTED_FIELD, INVALID_DELIMITER, OVERFLOW, ESCAPED_STRING

struct CustomType
    x::String
end

Base.tryparse(::Type{CustomType}, x::String) = CustomType(x)

@testset "Parsers" begin

@testset "Core Parsers.xparse" begin

sentinels = ["NANA", "NAN", "NA"]

testcases = [
    (str="", kwargs=(), x=0, code=(INVALID | EOF), vpos=1, vlen=0, tlen=0),
    (str="", kwargs=(sentinel=missing,), x=0, code=(SENTINEL | EOF), vpos=1, vlen=0, tlen=0),
    (str=" ", kwargs=(), x=0, code=(INVALID | EOF), vpos=1, vlen=1, tlen=1),
    (str=" ", kwargs=(sentinel=missing,), x=0, code=(INVALID | EOF), vpos=1, vlen=1, tlen=1),
    (str=" -", kwargs=(sentinel=missing,), x=0, code=(INVALID | EOF), vpos=1, vlen=2, tlen=2),
    (str=" +", kwargs=(sentinel=missing,), x=0, code=(INVALID | EOF), vpos=1, vlen=2, tlen=2),
    (str="-", kwargs=(sentinel=missing,), x=0, code=(INVALID | EOF), vpos=1, vlen=1, tlen=1),
    (str=" {-", kwargs=(sentinel=missing,), x=0, code=(QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=3, vlen=1, tlen=3),
    (str="{+", kwargs=(sentinel=missing,), x=0, code=(QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=2, vlen=1, tlen=2),
    (str=" {+,", kwargs=(sentinel=missing,), x=0, code=(QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=3, vlen=1, tlen=4),
    (str="{-,", kwargs=(sentinel=missing,), x=0, code=(QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=2, vlen=1, tlen=3),
    (str="+,", kwargs=(sentinel=missing,), x=0, code=(INVALID | DELIMITED), vpos=1, vlen=1, tlen=2),
    (str="-,", kwargs=(sentinel=missing,), x=0, code=(INVALID | DELIMITED), vpos=1, vlen=1, tlen=2),
    (str=" {-},", kwargs=(sentinel=missing,), x=0, code=(INVALID | QUOTED | DELIMITED), vpos=3, vlen=1, tlen=5),
    (str="{+} ,", kwargs=(sentinel=missing,), x=0, code=(INVALID | QUOTED | DELIMITED), vpos=2, vlen=1, tlen=5),
    (str="{", kwargs=(), x=0, code=(QUOTED | INVALID_QUOTED_FIELD), vpos=2, vlen=-1, tlen=1),
    (str="{}", kwargs=(), x=0, code=(INVALID | QUOTED | EOF), vpos=2, vlen=0, tlen=2),
    (str=" {", kwargs=(), x=0, code=(QUOTED | INVALID_QUOTED_FIELD), vpos=3, vlen=-2, tlen=2),
    (str=" {\\\\", kwargs=(), x=0, code=(QUOTED | INVALID_QUOTED_FIELD | ESCAPED_STRING | EOF), vpos=3, vlen=0, tlen=4),
    (str=" {\\}} ", kwargs=(), x=0, code=(QUOTED | INVALID | ESCAPED_STRING | EOF), vpos=3, vlen=2, tlen=6),
    (str=" {\\\\}", kwargs=(), x=0, code=(INVALID | QUOTED | ESCAPED_STRING | EOF), vpos=3, vlen=2, tlen=5),
    
    (str=" {}", kwargs=(), x=0, code=(INVALID | QUOTED | EOF), vpos=3, vlen=0, tlen=3),
    (str=" { }", kwargs=(), x=0, code=(INVALID | QUOTED | EOF), vpos=3, vlen=1, tlen=4),
    (str=" {,} ", kwargs=(), x=0, code=(INVALID | QUOTED | EOF), vpos=3, vlen=1, tlen=5),
    (str=" { } ", kwargs=(), x=0, code=(INVALID | QUOTED | EOF), vpos=3, vlen=1, tlen=5),
    (str=" {\t", kwargs=(), x=0, code=(INVALID_QUOTED_FIELD | QUOTED | EOF), vpos=3, vlen=-2, tlen=3),

    (str="NA", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | EOF), vpos=1, vlen=2, tlen=2),
    (str="£", kwargs=(sentinel=["£"],), x=0, code=(SENTINEL | EOF), vpos=1, vlen=2, tlen=2),
    (str="NA2", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | EOF | INVALID_DELIMITER), vpos=1, vlen=3, tlen=3),
    (str="NAN", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | EOF), vpos=1, vlen=3, tlen=3),
    (str="NANA", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | EOF), vpos=1, vlen=4, tlen=4),
    (str=" NA", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | EOF), vpos=1, vlen=3, tlen=3),
    (str="{NAN", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | EOF | QUOTED | INVALID_QUOTED_FIELD), vpos=2, vlen=3, tlen=4),
    (str="{NANA}", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | QUOTED | EOF), vpos=2, vlen=4, tlen=6),
    (str=" {NA", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=3, vlen=2, tlen=4),
    (str=" {NANA}", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | QUOTED | EOF), vpos=3, vlen=4, tlen=7),
    (str=" { NAN}", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | QUOTED | EOF), vpos=3, vlen=4, tlen=7),
    (str=" {NAN }", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | QUOTED | EOF), vpos=3, vlen=4, tlen=7),
    (str=" {NA} ", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | QUOTED | EOF), vpos=3, vlen=2, tlen=6),
    (str=" { NANA} ", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | QUOTED | EOF), vpos=3, vlen=5, tlen=9),
    (str=" {\tNA", kwargs=(sentinel=sentinels,), x=0, code=(SENTINEL | EOF | QUOTED | INVALID_QUOTED_FIELD), vpos=3, vlen=3, tlen=5),

    (str="-", kwargs=(sentinel=["-"],), x=0, code=(SENTINEL | EOF), vpos=1, vlen=1, tlen=1),
    (str=" +", kwargs=(sentinel=["+"],), x=0, code=(SENTINEL | EOF), vpos=1, vlen=2, tlen=2),
    (str="+1 ", kwargs=(sentinel=["+1"],), x=1, code=(SENTINEL | EOF), vpos=1, vlen=3, tlen=3),
    (str=" -1 ", kwargs=(sentinel=["-1"],), x=-1, code=(SENTINEL | EOF), vpos=1, vlen=4, tlen=4),
    (str="{1", kwargs=(sentinel=["1"],), x=1, code=(SENTINEL | EOF | QUOTED | INVALID_QUOTED_FIELD), vpos=2, vlen=1, tlen=2),
    (str="{1 ", kwargs=(sentinel=["1"],), x=1, code=(SENTINEL | EOF | QUOTED | INVALID_QUOTED_FIELD), vpos=2, vlen=2, tlen=3),
    (str="{-1}", kwargs=(sentinel=["-1"],), x=-1, code=(SENTINEL | QUOTED | EOF), vpos=2, vlen=2, tlen=4),
    (str=" {+1", kwargs=(sentinel=["+1"],), x=1, code=(SENTINEL | EOF | QUOTED | INVALID_QUOTED_FIELD), vpos=3, vlen=2, tlen=4),
    (str=" {-}", kwargs=(sentinel=["-"],), x=0, code=(SENTINEL | QUOTED | EOF), vpos=3, vlen=1, tlen=4),
    (str=" { +}", kwargs=(sentinel=["+"],), x=0, code=(SENTINEL | QUOTED | EOF), vpos=3, vlen=2, tlen=5),
    (str=" {-1 }", kwargs=(sentinel=["-1"],), x=-1, code=(SENTINEL | QUOTED | EOF), vpos=3, vlen=3, tlen=6),
    (str=" {+1} ", kwargs=(sentinel=["+1"],), x=1, code=(SENTINEL | QUOTED | EOF), vpos=3, vlen=2, tlen=6),
    (str=" { 1} ", kwargs=(sentinel=["1"],), x=1, code=(SENTINEL | QUOTED | EOF), vpos=3, vlen=2, tlen=6),
    (str=" {\t-", kwargs=(sentinel=["-"],), x=0, code=(SENTINEL | EOF | QUOTED | INVALID_QUOTED_FIELD), vpos=3, vlen=2, tlen=4),

    (str="+a ", kwargs=(sentinel=["+1"],), x=0, code=(INVALID | EOF | INVALID_DELIMITER), vpos=1, vlen=3, tlen=3),
    (str=" -a ", kwargs=(sentinel=["-1"],), x=0, code=(INVALID | EOF | INVALID_DELIMITER), vpos=1, vlen=4, tlen=4),
    (str="{a", kwargs=(sentinel=["1"],), x=0, code=(INVALID | EOF | QUOTED | INVALID_QUOTED_FIELD), vpos=2, vlen=0, tlen=2),
    (str="{-a}", kwargs=(sentinel=["-1"],), x=0, code=(INVALID | EOF | QUOTED), vpos=2, vlen=2, tlen=4),
    (str=" {+1a", kwargs=(sentinel=["+1"],), x=1, code=(SENTINEL | QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=3, vlen=2, tlen=5),
    (str=" {-1a }", kwargs=(sentinel=["-1"],), x=-1, code=(SENTINEL | QUOTED | INVALID | EOF), vpos=3, vlen=4, tlen=7),
    (str=" {+a} ", kwargs=(sentinel=["+1"],), x=0, code=(INVALID | QUOTED | EOF), vpos=3, vlen=2, tlen=6),
    (str=" { a} ", kwargs=(sentinel=["1"],), x=0, code=(INVALID | QUOTED | EOF), vpos=3, vlen=2, tlen=6),

    (str="-", kwargs=(), x=0, code=(INVALID | EOF), vpos=1, vlen=1, tlen=1),
    (str="0", kwargs=(), x=0, code=(OK | EOF), vpos=1, vlen=1, tlen=1),
    (str=" +", kwargs=(), x=0, code=(INVALID | EOF), vpos=1, vlen=2, tlen=2),
    (str=" +1", kwargs=(), x=1, code=(OK | EOF), vpos=1, vlen=3, tlen=3),
    (str="-1 ", kwargs=(), x=-1, code=(OK | EOF), vpos=1, vlen=3, tlen=3),
    (str=" +1 ", kwargs=(), x=1, code=(OK | EOF), vpos=1, vlen=4, tlen=4),
    (str="{1", kwargs=(), x=1, code=(OK | QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=2, vlen=1, tlen=2),
    (str="{1 ", kwargs=(), x=1, code=(OK | QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=2, vlen=2, tlen=3),
    (str="{-1}", kwargs=(), x=-1, code=(OK | QUOTED | EOF), vpos=2, vlen=2, tlen=4),
    (str=" {+1", kwargs=(), x=1, code=(OK | QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=3, vlen=2, tlen=4),
    (str=" {-}", kwargs=(), x=0, code=(INVALID | QUOTED | EOF), vpos=3, vlen=1, tlen=4),
    (str=" { +}", kwargs=(), x=0, code=(INVALID | QUOTED | EOF), vpos=3, vlen=2, tlen=5),
    (str=" {-1 }", kwargs=(), x=-1, code=(OK | QUOTED | EOF), vpos=3, vlen=3, tlen=6),
    (str=" {+1} ", kwargs=(), x=1, code=(OK | QUOTED | EOF), vpos=3, vlen=2, tlen=6),
    (str=" { 1} ", kwargs=(), x=1, code=(OK | QUOTED | EOF), vpos=3, vlen=2, tlen=6),
    (str=" {\t-", kwargs=(), x=0, code=(QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=3, vlen=2, tlen=4),
    (str="{1ab\\\\c}", kwargs=(), x=1, code=(OK | QUOTED | ESCAPED_STRING | EOF | INVALID), vpos=2, vlen=6, tlen=8),
    (str="{1\\\\abc,", kwargs=(), x=1, code=(OK | QUOTED | ESCAPED_STRING | EOF | INVALID_QUOTED_FIELD), vpos=2, vlen=6, tlen=8),
    (str="{1abc},", kwargs=(sentinel=["1abc"],), x=1, code=(SENTINEL | QUOTED | DELIMITED), vpos=2, vlen=4, tlen=7),
    (str="{1abc", kwargs=(sentinel=["1abc"],), x=1, code=(SENTINEL | QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=2, vlen=4, tlen=5),

    (str="922337203,", kwargs=(sentinel=["92233"],), x=922337203, code=(OK | DELIMITED), vpos=1, vlen=9, tlen=10),
    (str="92233,", kwargs=(sentinel=["92233"],), x=92233, code=(SENTINEL | DELIMITED), vpos=1, vlen=5, tlen=6),
    (str="92233  ", kwargs=(sentinel=["92233"],), x=92233, code=(SENTINEL | EOF), vpos=1, vlen=7, tlen=7),
    (str="{92233  ,", kwargs=(sentinel=["92233"],), x=92233, code=(SENTINEL | QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=2, vlen=7, tlen=9),
    (str="{92233} ,", kwargs=(sentinel=["92233"],), x=92233, code=(SENTINEL | QUOTED | DELIMITED), vpos=2, vlen=5, tlen=9),
    (str=" { 92233 },", kwargs=(sentinel=["92233"],), x=92233, code=(SENTINEL | QUOTED | DELIMITED), vpos=3, vlen=7, tlen=11),
    (str="922337203685477580", kwargs=(), x=922337203685477580, code=(OK | EOF), vpos=1, vlen=18, tlen=18),
    (str="9223372036854775808", kwargs=(), x=-9223372036854775808, code=(OVERFLOW | EOF), vpos=1, vlen=19, tlen=19),
    (str="9223372036854775808a", kwargs=(sentinel=["9223372036854775808a"],), x=-9223372036854775808, code=(SENTINEL | EOF), vpos=1, vlen=20, tlen=20),
    (str="{9223372036854775808a", kwargs=(sentinel=["9223372036854775808a"],), x=-9223372036854775808, code=(SENTINEL | QUOTED | EOF | INVALID_QUOTED_FIELD), vpos=2, vlen=20, tlen=21),

    (str="{9223372036854775808", kwargs=(), x=-9223372036854775808, code=(OVERFLOW | EOF | QUOTED | INVALID_QUOTED_FIELD), vpos=2, vlen=19, tlen=20),
    (str="{9223372036854775807", kwargs=(), x=9223372036854775807, code=(OK | EOF | QUOTED | INVALID_QUOTED_FIELD), vpos=2, vlen=19, tlen=20),
    (str="{9223372036854775807a", kwargs=(), x=9223372036854775807, code=(OK | EOF | QUOTED | INVALID_QUOTED_FIELD), vpos=2, vlen=19, tlen=21),
    (str="9223372036854775807a", kwargs=(), x=9223372036854775807, code=(OK | EOF | INVALID_DELIMITER), vpos=1, vlen=20, tlen=20),
    (str="9223372036854775807,", kwargs=(), x=9223372036854775807, code=(OK | DELIMITED), vpos=1, vlen=19, tlen=20),
    (str="9223372036854775807", kwargs=(sentinel=["9223372036854775807"],), x=9223372036854775807, code=(SENTINEL | EOF), vpos=1, vlen=19, tlen=19),
    (str="{9223372036854775807a", kwargs=(sentinel=["9223372036854775807a"],), x=9223372036854775807, code=(SENTINEL | EOF | QUOTED | INVALID_QUOTED_FIELD), vpos=2, vlen=20, tlen=21),

    (str="9223372036854775808", kwargs=(sentinel=["92233"],), x=-9223372036854775808, code=(OVERFLOW | EOF), vpos=1, vlen=19, tlen=19),
    (str="922337203685477580", kwargs=(sentinel=["92233"],), x=922337203685477580, code=(OK | EOF), vpos=1, vlen=18, tlen=18),
    (str="922337203685477580,", kwargs=(), x=922337203685477580, code=(OK | DELIMITED), vpos=1, vlen=18, tlen=19),
    (str="922337203685477580,", kwargs=(sentinel=["92233"],), x=922337203685477580, code=(OK | DELIMITED), vpos=1, vlen=18, tlen=19),
    (str="9223372036854775800000,", kwargs=(sentinel=["92233"],), x=-80, code=(DELIMITED | INVALID_DELIMITER | OVERFLOW), vpos=1, vlen=22, tlen=23),

    (str="1;", kwargs=(), x=1, code=(OK | EOF | INVALID_DELIMITER), vpos=1, vlen=2, tlen=2),
    (str="1;", kwargs=(delim=UInt8(';'),), x=1, code=(OK | DELIMITED), vpos=1, vlen=1, tlen=2),
    (str="1abc;", kwargs=(delim=UInt8(';'),), x=1, code=(OK | DELIMITED | INVALID_DELIMITER), vpos=1, vlen=4, tlen=5),
    (str="1\n", kwargs=(), x=1, code=(OK | NEWLINE | EOF), vpos=1, vlen=1, tlen=2),
    (str="1\r", kwargs=(), x=1, code=(OK | NEWLINE | EOF), vpos=1, vlen=1, tlen=2),
    (str="1\r\n", kwargs=(), x=1, code=(OK | NEWLINE | EOF), vpos=1, vlen=1, tlen=3),
    (str="1\n2", kwargs=(), x=1, code=(OK | NEWLINE), vpos=1, vlen=1, tlen=2),
    (str="1\r2", kwargs=(), x=1, code=(OK | NEWLINE), vpos=1, vlen=1, tlen=2),
    (str="1\r\n2", kwargs=(), x=1, code=(OK | NEWLINE), vpos=1, vlen=1, tlen=3),
    (str="1a\n", kwargs=(), x=1, code=(OK | NEWLINE | EOF | INVALID_DELIMITER), vpos=1, vlen=2, tlen=3),
    (str="1a\r", kwargs=(), x=1, code=(OK | NEWLINE | EOF | INVALID_DELIMITER), vpos=1, vlen=2, tlen=3),
    (str="1a\r\n", kwargs=(), x=1, code=(OK | NEWLINE | EOF | INVALID_DELIMITER), vpos=1, vlen=2, tlen=4),
    (str="1a\n2", kwargs=(), x=1, code=(OK | NEWLINE | INVALID_DELIMITER), vpos=1, vlen=2, tlen=3),
    (str="1a\r2", kwargs=(), x=1, code=(OK | NEWLINE | INVALID_DELIMITER), vpos=1, vlen=2, tlen=3),
    (str="1a\r\n2", kwargs=(), x=1, code=(OK | NEWLINE | INVALID_DELIMITER), vpos=1, vlen=2, tlen=4),

    (str="1,,,2,null,4", kwargs=(), x=1, code=(OK | DELIMITED), vpos=1, vlen=1, tlen=2),
    (str="1,,,2,null,4", kwargs=(ignorerepeated=true,), x=1, code=(OK | DELIMITED), vpos=1, vlen=1, tlen=4),
    (str="1,", kwargs=(ignorerepeated=true,), x=1, code=(OK | DELIMITED), vpos=1, vlen=1, tlen=2),
    (str="1,,", kwargs=(ignorerepeated=true,), x=1, code=(OK | DELIMITED), vpos=1, vlen=1, tlen=3),
    (str="1,,,", kwargs=(ignorerepeated=true,), x=1, code=(OK | DELIMITED), vpos=1, vlen=1, tlen=4),
    (str="1::2", kwargs=(delim="::",), x=1, code=(OK | DELIMITED), vpos=1, vlen=1, tlen=3),
    (str="1::::2", kwargs=(ignorerepeated=true, delim="::"), x=1, code=(OK | DELIMITED), vpos=1, vlen=1, tlen=5),
    (str="1a::::2", kwargs=(ignorerepeated=true, delim="::"), x=1, code=(OK | DELIMITED | INVALID_DELIMITER), vpos=1, vlen=2, tlen=6),
    (str="1[][]", kwargs=(delim="[]", ignorerepeated = true), x = 1, code=(OK | DELIMITED), vpos=1, vlen=1, tlen=5),
    (str="1a[][]", kwargs=(delim="[]", ignorerepeated = true), x = 1, code=(OK | DELIMITED | INVALID_DELIMITER), vpos=1, vlen=2, tlen=6),
    (str="1a[][]", kwargs=(delim="[]",), x = 1, code=(OK | DELIMITED | INVALID_DELIMITER), vpos=1, vlen=2, tlen=4),
    # ignorerepeated
    (str="1a,,", kwargs=(ignorerepeated=true,), x=1, code=(OK | DELIMITED | INVALID_DELIMITER), vpos=1, vlen=2, tlen=4),
    (str="1a,,2", kwargs=(ignorerepeated=true,), x=1, code=(OK | DELIMITED | INVALID_DELIMITER), vpos=1, vlen=2, tlen=4),
    (str="1,\n", kwargs=(ignorerepeated=true, delim=UInt8(',')), x=1, code=(OK | DELIMITED | NEWLINE | EOF), vpos=1, vlen=1, tlen=3),
    (str="1,\n,", kwargs=(ignorerepeated=true, delim=UInt8(',')), x=1, code=(OK | DELIMITED | NEWLINE), vpos=1, vlen=1, tlen=4),
    (str="1,\n,\n", kwargs=(ignorerepeated=true, delim=UInt8(',')), x=1, code=(OK | DELIMITED | NEWLINE), vpos=1, vlen=1, tlen=4),
    (str="1::\n::", kwargs=(ignorerepeated=true, delim="::"), x=1, code=(OK | DELIMITED | NEWLINE), vpos=1, vlen=1, tlen=6),
    (str="1::\n::\n", kwargs=(ignorerepeated=true, delim="::"), x=1, code=(OK | DELIMITED | NEWLINE), vpos=1, vlen=1, tlen=6),
    (str="1,\r\n,", kwargs=(ignorerepeated=true, delim=UInt8(',')), x=1, code=(OK | DELIMITED | NEWLINE), vpos=1, vlen=1, tlen=5),
    (str="1,\r\n,\r\n", kwargs=(ignorerepeated=true, delim=UInt8(',')), x=1, code=(OK | DELIMITED | NEWLINE), vpos=1, vlen=1, tlen=5),
    (str="1::\r\n::", kwargs=(ignorerepeated=true, delim="::"), x=1, code=(OK | DELIMITED | NEWLINE), vpos=1, vlen=1, tlen=7),
    (str="1::\r\n::\r\n", kwargs=(ignorerepeated=true, delim="::"), x=1, code=(OK | DELIMITED | NEWLINE), vpos=1, vlen=1, tlen=7),
    # invalid
    (str="1a,\n,", kwargs=(ignorerepeated=true, delim=UInt8(',')), x=1, code=(OK | INVALID_DELIMITER | DELIMITED | NEWLINE), vpos=1, vlen=2, tlen=5),
    (str="1a,\n,\n", kwargs=(ignorerepeated=true, delim=UInt8(',')), x=1, code=(OK | INVALID_DELIMITER | DELIMITED | NEWLINE), vpos=1, vlen=2, tlen=5),
    (str="1a::\n::", kwargs=(ignorerepeated=true, delim="::"), x=1, code=(OK | INVALID_DELIMITER | DELIMITED | NEWLINE), vpos=1, vlen=2, tlen=7),
    (str="1a::\n::\n", kwargs=(ignorerepeated=true, delim="::"), x=1, code=(OK | INVALID_DELIMITER | DELIMITED | NEWLINE), vpos=1, vlen=2, tlen=7),
    (str="1a,\r\n,", kwargs=(ignorerepeated=true, delim=UInt8(',')), x=1, code=(OK | INVALID_DELIMITER | DELIMITED | NEWLINE), vpos=1, vlen=2, tlen=6),
    (str="1a,\r\n,\r\n", kwargs=(ignorerepeated=true, delim=UInt8(',')), x=1, code=(OK | INVALID_DELIMITER | DELIMITED | NEWLINE), vpos=1, vlen=2, tlen=6),
    (str="1a::\r\n::", kwargs=(ignorerepeated=true, delim="::"), x=1, code=(OK | INVALID_DELIMITER | DELIMITED | NEWLINE), vpos=1, vlen=2, tlen=8),
    (str="1a::\r\n::\r\n", kwargs=(ignorerepeated=true, delim="::"), x=1, code=(OK | INVALID_DELIMITER | DELIMITED | NEWLINE), vpos=1, vlen=2, tlen=8),
    # ignoreemptylines
    (str="1\n\n", kwargs=(ignoreemptylines=true,), x=1, code=(OK | NEWLINE | EOF), vpos=1, vlen=1, tlen=3),
    (str="1\n\n\n", kwargs=(ignoreemptylines=true,), x=1, code=(OK | NEWLINE | EOF), vpos=1, vlen=1, tlen=4),
    (str="1,\n\n\n,", kwargs=(ignorerepeated=true, ignoreemptylines=true, delim=UInt8(',')), x=1, code=(OK | NEWLINE | DELIMITED), vpos=1, vlen=1, tlen=6),
    (str="1::\n\n\n::", kwargs=(ignorerepeated=true, ignoreemptylines=true, delim="::"), x=1, code=(OK | NEWLINE | DELIMITED), vpos=1, vlen=1, tlen=8),
    (str="1\r\n\r\n", kwargs=(ignoreemptylines=true,), x=1, code=(OK | NEWLINE | EOF), vpos=1, vlen=1, tlen=5),
    (str="1\r\n\r\n\r\n", kwargs=(ignoreemptylines=true,), x=1, code=(OK | NEWLINE | EOF), vpos=1, vlen=1, tlen=7),
    (str="1,\r\n\r\n\r\n,", kwargs=(ignorerepeated=true, ignoreemptylines=true, delim=UInt8(',')), x=1, code=(OK | NEWLINE | DELIMITED), vpos=1, vlen=1, tlen=9),
    (str="1::\r\n\r\n\r\n::", kwargs=(ignorerepeated=true, ignoreemptylines=true, delim="::"), x=1, code=(OK | NEWLINE | DELIMITED), vpos=1, vlen=1, tlen=11),
    # comments
    (str="1\n#\n", kwargs=(comment="#",), x=1, code=(OK | NEWLINE | EOF), vpos=1, vlen=1, tlen=4),
    (str="1\n#   \n", kwargs=(comment="#",), x=1, code=(OK | NEWLINE | EOF), vpos=1, vlen=1, tlen=7),
    (str="1,\n#  \n\n,", kwargs=(ignorerepeated=true, ignoreemptylines=true, comment="#", delim=UInt8(',')), x=1, code=(OK | NEWLINE | DELIMITED), vpos=1, vlen=1, tlen=9),
    (str="1::\n#  \n\n::", kwargs=(ignorerepeated=true, ignoreemptylines=true, comment="#", delim="::"), x=1, code=(OK | NEWLINE | DELIMITED), vpos=1, vlen=1, tlen=11),
    (str="1\r\n#  \r\n", kwargs=(ignoreemptylines=true, comment="#",), x=1, code=(OK | NEWLINE | EOF), vpos=1, vlen=1, tlen=8),
    (str="1\r\n#  \r\n\r\n", kwargs=(ignoreemptylines=true, comment="#",), x=1, code=(OK | NEWLINE | EOF), vpos=1, vlen=1, tlen=10),
    (str="1,\r\n#  \r\n\r\n,", kwargs=(ignorerepeated=true, ignoreemptylines=true, comment="#", delim=UInt8(',')), x=1, code=(OK | NEWLINE | DELIMITED), vpos=1, vlen=1, tlen=12),
    (str="1::\r\n#  \r\n\r\n::", kwargs=(ignorerepeated=true, ignoreemptylines=true, comment="#", delim="::"), x=1, code=(OK | NEWLINE | DELIMITED), vpos=1, vlen=1, tlen=14),
    # stripquoted
    (str=" 1", kwargs=(stripquoted=true,), x=1, code=(OK | EOF), vpos=2, vlen=1, tlen=2),
    (str="{ 1}", kwargs=(stripquoted=true,), x=1, code=(OK | QUOTED | EOF), vpos=3, vlen=1, tlen=4),
    (str="{1 }", kwargs=(stripquoted=true,), x=1, code=(OK | QUOTED | EOF), vpos=2, vlen=1, tlen=4),
    (str="1 ", kwargs=(stripquoted=true,), x=1, code=(OK | EOF), vpos=1, vlen=1, tlen=2),
    (str="1 ,", kwargs=(stripquoted=true,delim=UInt8(',')), x=1, code=(OK | DELIMITED), vpos=1, vlen=1, tlen=3),
    (str="{1 } ,", kwargs=(stripquoted=true,delim=UInt8(',')), x=1, code=(OK | DELIMITED | QUOTED), vpos=2, vlen=1, tlen=6),
];

for useio in (false, true)
    for (oq, cq, e) in ((UInt8('"'), UInt8('"'), UInt8('"')), (UInt8('"'), UInt8('"'), UInt8('\\')), (UInt8('{'), UInt8('}'), UInt8('\\')))
        for (i, case) in enumerate(testcases)
            str = replace(replace(replace(case.str, '{'=>Char(oq)), '}'=>Char(cq)), '\\'=>Char(e))
            source = useio ? IOBuffer(str) : str
            res = Parsers.xparse(Int64, source; openquotechar=oq, closequotechar=cq, escapechar=e, case.kwargs...)
            x, code, tlen = res.val, res.code, res.tlen
            # println("testing int case i = $i, case = $case")
            if !Parsers.invalid(code) && !Parsers.sentinel(code)
                @test x == case.x
            end
            @test code == case.code
            @test tlen == case.tlen
        end
    end
end

# strings
oq = UInt8('{')
cq = UInt8('}')
e = UInt8('\\')
for (i, case) in enumerate(testcases)
    str = replace(replace(replace(case.str, '{'=>Char(oq)), '}'=>Char(cq)), '\\'=>Char(e))
    res = Parsers.xparse(String, case.str; openquotechar=oq, closequotechar=cq, escapechar=e, case.kwargs...)
    x, code, tlen = res.val, res.code, res.tlen
    # println("testing string case i = $i, case = $case")
    if !Parsers.invalidquotedfield(code)
        @test x.pos == case.vpos
        @test x.len == case.vlen
        @test tlen == case.tlen
    end
end

# stripwhitespace
res = Parsers.xparse(String, "{hey there}"; openquotechar='{', closequotechar='}', stripwhitespace=true)
@test res.val.pos == 2 && res.val.len == 9
res = Parsers.xparse(String, "{hey there }"; openquotechar='{', closequotechar='}', stripwhitespace=true)
@test res.val.pos == 2 && res.val.len == 10
res = Parsers.xparse(String, "{hey there },"; openquotechar='{', closequotechar='}', delim=',', stripwhitespace=true)
@test res.val.pos == 2 && res.val.len == 10
res = Parsers.xparse(String, "{hey there } ,"; openquotechar='{', closequotechar='}', delim=',', stripwhitespace=true)
@test res.val.pos == 2 && res.val.len == 10
res = Parsers.xparse(String, "{hey there } a,"; openquotechar='{', closequotechar='}', delim=',', stripwhitespace=true)
@test res.val.pos == 2 && res.val.len == 10 && Parsers.invaliddelimiter(res.code)
res = Parsers.xparse(String, "{hey there } a "; openquotechar='{', closequotechar='}', delim=nothing, stripwhitespace=true)
@test res.val.pos == 2 && res.val.len == 10 && res.tlen == 13
res = Parsers.xparse(String, "hey there ,"; delim=',', stripwhitespace=true)
@test res.val.pos == 1 && res.val.len == 9
res = Parsers.xparse(String, " hey there "; stripwhitespace=true)
@test res.val.pos == 2 && res.val.len == 9
res = Parsers.xparse(String, " hey there "; delim=nothing, stripwhitespace=true)
@test res.val.pos == 2 && res.val.len == 9

res = Parsers.xparse(String, "{hey there}"; openquotechar='{', closequotechar='}', stripquoted=true)
@test res.val.pos == 2 && res.val.len == 9
res = Parsers.xparse(String, "{hey there }"; openquotechar='{', closequotechar='}', stripquoted=true)
@test res.val.pos == 2 && res.val.len == 9
res = Parsers.xparse(String, "{hey there },"; openquotechar='{', closequotechar='}', delim=',', stripquoted=true)
@test res.val.pos == 2 && res.val.len == 9
res = Parsers.xparse(String, "{hey there } ,"; openquotechar='{', closequotechar='}', delim=',', stripquoted=true)
@test res.val.pos == 2 && res.val.len == 9
res = Parsers.xparse(String, "{hey there } a,"; openquotechar='{', closequotechar='}', delim=',', stripquoted=true)
@test res.val.pos == 2 && res.val.len == 9 && Parsers.invaliddelimiter(res.code)
res = Parsers.xparse(String, "{hey there } a "; openquotechar='{', closequotechar='}', delim=nothing, stripquoted=true)
@test res.val.pos == 2 && res.val.len == 9 && res.tlen == 13
res = Parsers.xparse(String, "hey there ,"; delim=',', stripquoted=true)
@test res.val.pos == 1 && res.val.len == 9
res = Parsers.xparse(String, " hey there "; stripquoted=true)
@test res.val.pos == 2 && res.val.len == 9
res = Parsers.xparse(String, " hey there "; delim=nothing, stripquoted=true)
@test res.val.pos == 2 && res.val.len == 9
# `stripquoted=true` should always override `stripwhitespace` to `true`
res = Parsers.xparse(String, " hey there "; delim=nothing, stripquoted=true, stripwhitespace=false)
@test res.val.pos == 2 && res.val.len == 9

# https://github.com/JuliaData/Parsers.jl/issues/115
res = Parsers.xparse(String, "{hey there } "; openquotechar='{', closequotechar='}', stripquoted=true, delim=' ', wh1=0x00)
@test res.val.pos == 2 && res.val.len == 9

end # @testset "Core Parsers.xparse"

@testset "ints" begin

# test lots of ints
@time for i in typemin(Int64):100_000_000_000_000:typemax(Int64)
    str = string(i)
    res = Parsers.xparse(Int64, str)
    x, code, tlen = res.val, res.code, res.tlen
    @test string(x) == str
    @test code == OK | EOF
    @test tlen == length(str)
end

# test some critical ints Issue #44
for i in [typemin(Int64):typemin(Int64)+20; typemax(Int)-20:typemax(Int)]
    str = string(i)
    res = Parsers.xparse(Int64, str)
    x, code, tlen = res.val, res.code, res.tlen
    @test string(x) == str
    @test code == OK | EOF
    @test tlen == length(str)
end

end # @testset "ints"

@testset "bools" begin

trues1 = ["T"]
falses1 = ["F"]
trues2 = ["truthy"]
falses2 = ["falsy"]

testcases = [
    (str="", kwargs=(), x=false, code=(INVALID | EOF), tlen=0),
    (str="t", kwargs=(), x=false, code=(INVALID | EOF), tlen=1),
    (str="tr", kwargs=(), x=false, code=(INVALID | EOF), tlen=2),
    (str="tru", kwargs=(), x=false, code=(INVALID | EOF), tlen=3),
    (str="true", kwargs=(), x=true, code=(OK | EOF), tlen=4),

    (str="f", kwargs=(), x=false, code=(INVALID | EOF), tlen=1),
    (str="fa", kwargs=(), x=false, code=(INVALID | EOF), tlen=2),
    (str="fal", kwargs=(), x=false, code=(INVALID | EOF), tlen=3),
    (str="fals", kwargs=(), x=false, code=(INVALID | EOF), tlen=4),
    (str="false", kwargs=(), x=false, code=(OK | EOF), tlen=5),

    (str="t,", kwargs=(), x=false, code=(INVALID | DELIMITED), tlen=2),
    (str="tr,", kwargs=(), x=false, code=(INVALID | DELIMITED), tlen=3),
    (str="tru,", kwargs=(), x=false, code=(INVALID | DELIMITED), tlen=4),
    (str="true,", kwargs=(), x=true, code=(OK | DELIMITED), tlen=5),

    (str="f,", kwargs=(), x=false, code=(INVALID | DELIMITED), tlen=2),
    (str="fa,", kwargs=(), x=false, code=(INVALID | DELIMITED), tlen=3),
    (str="fal,", kwargs=(), x=false, code=(INVALID | DELIMITED), tlen=4),
    (str="fals,", kwargs=(), x=false, code=(INVALID | DELIMITED), tlen=5),
    (str="false,", kwargs=(), x=false, code=(OK | DELIMITED), tlen=6),

    (str="0", kwargs=(), x=false, code=(OK | EOF), tlen=1),
    (str="1", kwargs=(), x=true, code=(OK | EOF), tlen=1),
    (str="001", kwargs=(), x=true, code=(OK | EOF), tlen=3),
    (str="2", kwargs=(), x=false, code=(INVALID | EOF | INVALID_DELIMITER), tlen=1),

    (str="t", kwargs=(trues=trues1, falses=falses1,), x=false, code=(INVALID | EOF | INVALID_DELIMITER), tlen=1),
    (str="T", kwargs=(trues=trues1, falses=falses1,), x=true, code=(OK | EOF), tlen=1),
    (str="T,", kwargs=(trues=trues1, falses=falses1,), x=true, code=(OK | DELIMITED), tlen=2),
    (str="Tr", kwargs=(trues=trues1, falses=falses1,), x=true, code=(OK | EOF | INVALID_DELIMITER), tlen=2),
    (str="F", kwargs=(trues=trues1, falses=falses1,), x=false, code=(OK | EOF), tlen=1),
    (str="truthy", kwargs=(trues=trues2, falses=falses2,), x=true, code=(OK | EOF), tlen=6),
    (str="truthyfalsy", kwargs=(trues=trues2, falses=falses2,), x=true, code=(OK | EOF | INVALID_DELIMITER), tlen=11),
    (str="falsytruthy", kwargs=(trues=trues2, falses=falses2,), x=false, code=(OK | EOF | INVALID_DELIMITER), tlen=11),
];

for useio in (false, true)
    for (i, case) in enumerate(testcases)
        res = Parsers.xparse(Bool, useio ? IOBuffer(case.str) : case.str; case.kwargs...)
        x, code, tlen = res.val, res.code, res.tlen
        if !Parsers.invalid(code) && !Parsers.sentinel(code)
            @test x == case.x
        end
        # println("testing bool case i = $i, case = $case")
        @test code == case.code
        @test tlen == case.tlen
    end
end

end # @testset "bools"

@testset "misc" begin

# additional tests for full xparse branch coverage
oq = UInt8('{')
cq = UInt8('}')
e = UInt8('\\')
str=" {\\"
res = Parsers.xparse(Int64, str; openquotechar=oq, closequotechar=cq, escapechar=e)
x, code, tlen = res.val, res.code, res.tlen
@test code == QUOTED | EOF | INVALID_QUOTED_FIELD
@test tlen == 3

@test Parsers.parse(Int, "101") === 101
@test Parsers.parse(Float64, "101,101", Parsers.Options(decimal=',')) === 101.101
@test Parsers.parse(Bool, IOBuffer("true")) === true
@test_throws Parsers.Error Parsers.parse(Int, "abc")

@test Parsers.tryparse(Int, "abc") === nothing
@test Parsers.tryparse(Float32, IOBuffer("101,101"), Parsers.Options(decimal=',')) === Float32(101.101)
@test Parsers.parse(Date, "01/20/2018", Parsers.Options(dateformat="mm/dd/yyyy")) === Date(2018, 1, 20)

# https://github.com/JuliaData/CSV.jl/issues/345
res = Parsers.xparse(String, "\"DALLAS BLACK DANCE THEATRE\",")
x, code, tlen = res.val, res.code, res.tlen
@test x.pos == 2
@test x.len == 26
@test tlen == 29
@test code == OK | QUOTED | DELIMITED | EOF

# https://github.com/JuliaData/CSV.jl/issues/344
str = "1,2,null,4"
pos = 1
res = Parsers.xparse(Int, str; pos=pos, sentinel=["null"])
x, code, tlen = res.val, res.code, res.tlen
pos += tlen
@test x === 1
@test code === OK | DELIMITED
@test pos == 3
res = Parsers.xparse(Int, str; pos=pos, sentinel=["null"])
x, code, tlen = res.val, res.code, res.tlen
pos += tlen
@test x === 2
@test code === OK | DELIMITED
@test pos == 5
res = Parsers.xparse(Int, str; pos=pos, sentinel=["null"])
x, code, tlen = res.val, res.code, res.tlen
pos += tlen
@test code === SENTINEL | DELIMITED
@test pos == 10
res = Parsers.xparse(Int, str; pos=pos, sentinel=["null"])
x, code, tlen = res.val, res.code, res.tlen
pos += tlen
@test x === 4
@test code === OK | EOF
@test pos == 11

@test Parsers.parse(Int, SubString("101")) === 101
@test Parsers.parse(Float64, SubString("101,101"), Parsers.Options(decimal=',')) === 101.101

@test Parsers.asciival(' ')

@test_throws ArgumentError Parsers.Options(sentinel=[" "])
@test_throws ArgumentError Parsers.Options(sentinel=["\""])
@test_throws ArgumentError Parsers.Options(sentinel=[","], delim=',')
@test_throws ArgumentError Parsers.Options(sentinel=[","], delim=",")

@test Parsers.checkdelim!(UInt8[], 1, 0, Parsers.OPTIONS) == 1
@test Parsers.checkdelim!(codeunits(","), 1, 1, Parsers.XOPTIONS) == 2
@test Parsers.checkdelim!(codeunits("::"), 1, 2, Parsers.Options(delim="::")) == 3
@test Parsers.checkdelim!(codeunits(",,"), 1, 2, Parsers.Options(ignorerepeated=true, delim=',')) == 3
@test Parsers.checkdelim!(codeunits("::::"), 1, 4, Parsers.Options(delim="::", ignorerepeated=true)) == 5

e = Parsers.Error(Vector{UInt8}("hey"), Int64, INVALID | EOF, 1, 3)
io = IOBuffer()
showerror(io, e)
@test String(take!(io)) == "Parsers.Error (INVALID: EOF ):\ninitial value parsing failed, reached EOF\nattempted to parse Int64 from: \"hey\"\n"
e2 = Parsers.Error(IOBuffer("hey"), Int64, INVALID | EOF, 1, 3)
showerror(io, e2)
@test String(take!(io)) == "Parsers.Error (INVALID: EOF ):\ninitial value parsing failed, reached EOF\nattempted to parse Int64 from: \"hey\"\n"

@test Parsers.invalid(INVALID_DELIMITER)
@test Parsers.sentinel(SENTINEL)
@test !Parsers.sentinel(OK)
@test Parsers.quoted(QUOTED)
@test !Parsers.quoted(INVALID_DELIMITER)
@test Parsers.delimited(DELIMITED)
@test !Parsers.delimited(OK)
@test Parsers.newline(NEWLINE)
@test !Parsers.newline(DELIMITED)
@test Parsers.escapedstring(ESCAPED_STRING)
@test !Parsers.escapedstring(OK)
@test Parsers.invalidquotedfield(INVALID_QUOTED_FIELD)
@test !Parsers.invalidquotedfield(INVALID_DELIMITER)
@test Parsers.invaliddelimiter(INVALID_DELIMITER)
@test !Parsers.invaliddelimiter(INVALID_QUOTED_FIELD)
@test Parsers.overflow(OVERFLOW)
@test !Parsers.overflow(OK)
@test Parsers.quotednotescaped(QUOTED)
@test !Parsers.quotednotescaped(QUOTED | ESCAPED_STRING)

# https://github.com/JuliaData/CSV.jl/issues/454
res = Parsers.xparse(Float64, "\"\"", 1, 2)
x, code, tlen = res.val, res.code, res.tlen
@test Parsers.sentinel(code)

res = Parsers.xparse(String, "\"\"", 1, 2)
x, code, tlen = res.val, res.code, res.tlen
@test Parsers.sentinel(code)

@test_throws ArgumentError Parsers.Options(delim=' ')

# #38
@test Parsers.parse(Date, "25JUL1985", Parsers.Options(dateformat="dduuuyyyy")) == Date(1985, 7, 25)

# https://github.com/JuliaIO/JSON.jl/issues/296
@test Parsers.parse(Float64, "99233885.0302231276962159466369304902338091026") === 9.923388503022313e7

# Int8 -1 parsed as UInt8 0xff
@test Parsers.parse(Int8, "-1") === Int8(-1)

# parsing am/pm issue for > Julia 1.3
@static if VERSION >= v"1.3-DEV"
@test Parsers.parse(DateTime, "7/22/1998 4:37:01.500 PM", Parsers.Options(dateformat="m/d/yyyy I:M:S.s p")) == DateTime(1998, 7, 22, 16, 37, 1, 500)
end

# #55
# Parsers.parse must consume entire string
@test_throws Parsers.Error Parsers.parse(Int, "10a")
# but with IO will just consume until non digit
@test Parsers.parse(Int, IOBuffer("10a")) == 10

# #65
@test Parsers.parse(Char, "a") === 'a'
@test Parsers.parse(Char, "漢") === '漢'
@test Parsers.parse(Symbol, "a") === :a
@test Parsers.parse(Symbol, "漢") === :漢

res = Parsers.xparse(Char, codeunits("a"), 1, 1, Parsers.XOPTIONS)
@test res.code == (Parsers.EOF | Parsers.OK)
@test res.val == 'a'
res = Parsers.xparse(Symbol, codeunits("a"), 1, 1, Parsers.XOPTIONS)
@test res.code == (Parsers.EOF | Parsers.OK)
@test res.val == :a
res = Parsers.xparse(CustomType, codeunits("a"), 1, 1, Parsers.XOPTIONS)
@test res.code == (Parsers.EOF | Parsers.OK)
@test res.val == CustomType("a")

# 67
@test Parsers.parse(CustomType, "hey there", Parsers.XOPTIONS) == CustomType("hey there")

# https://github.com/JuliaData/CSV.jl/issues/780
missings = ["na"]
opts = Parsers.Options(sentinel=missings, trues=["true"])
@test missings == ["na"]

# reported from Slack via CSV.jl
@test Parsers.xparse(String, ""; sentinel=["NULL"]) == Parsers.Result{PosLen}(Int16(33), 0, Base.bitcast(PosLen, 0x0000000000100000))

# Parsers.getstring
@test Parsers.getstring(b"hey there", Parsers.PosLen(5, 5), 0x00) == "there"
@test Parsers.getstring(IOBuffer("hey there"), Parsers.PosLen(5, 5), 0x00) == "there"
@test Parsers.getstring("hey there", Parsers.PosLen(5, 5), 0x00) == "there"
@test Parsers.getstring("hey \"\" there", Parsers.PosLen(1, 12, false, true), UInt8('"')) == "hey \" there"
@test Parsers.getstring(IOBuffer("hey \"\" there"), Parsers.PosLen(1, 12, false, true), UInt8('"')) == "hey \" there"

# PosLen
@test_throws ArgumentError Parsers.PosLen(Parsers.MAX_POS + 1, 0)
@test_throws ArgumentError Parsers.PosLen(1, Parsers.MAX_LEN + 1)
@test_throws ArgumentError Parsers.PosLen(1, 1).invalidproperty

# test invalid fallback parsing
@test_throws Parsers.Error Parsers.parse(Complex{Float64}, "NaN+NaN*im")
@test Parsers.tryparse(Complex{Float64}, "NaN+NaN*im") === nothing

# test we parse and return the correct value up to an invalid delimiter
# https://github.com/JuliaData/Parsers.jl/issues/93
for (T, str, val) in (
    (Float64, "1.0 /", 1.0),
    (Float64, "1.0 /[ 2.0 ]/", 1.0),
    (Int, "2 _", 2),
    (Date, "2021-10-20 *", Date("2021-10-20")),
    (Bool, "false^", false),
)
    res = Parsers.xparse(T, str)
    @test Parsers.invaliddelimiter(res.code)
    @test res.val === val
end

end # @testset "misc"

include("floats.jl")
include("dates.jl")
include("ryu.jl")

end # @testset "Parsers"
