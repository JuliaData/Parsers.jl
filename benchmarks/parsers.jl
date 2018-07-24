using BenchmarkTools, Parsers

# fast
run(@benchmarkable Parsers.xparse(io, Int) setup=(io = IOBuffer("0")))
@btime Parsers.xparse(Parsers.defaultparser, IOBuffer("0"), Int)
io = IOBuffer("0")
@time Parsers.xparse(Parsers.defaultparser, io, Int)

# slow
run(@benchmarkable Parsers.xparse(io, Int) setup=(io = Parsers.Sentinel(IOBuffer("0"), ["NA"])))
run(@benchmarkable Main.Parsers.xparse(io, Int) setup=(io = Main.Parsers.Sentinel(IOBuffer("NA"), ["NA"])))
@code_warntype Parsers.xparse(Parsers.defaultparser, Parsers.Sentinel(IOBuffer("0"), ["NA"]), Int)
@code_llvm Parsers.xparse(Parsers.defaultparser, Parsers.Sentinel(IOBuffer("0"), ["NA"]), Int)
@btime Parsers.xparse(Parsers.defaultparser, Parsers.Sentinel(IOBuffer("0"), ["NA"]), Int)

io = IOBuffer("0")
@time Parsers.xparse(Parsers.defaultparser, io, Int)

io = Parsers.Sentinel(IOBuffer("0"), ["NA"])
@time Parsers.xparse(Parsers.defaultparser, io, Int)

io = Parsers.Strip(Parsers.Sentinel(IOBuffer("0"), ["NA"]))
@time Parsers.xparse(Parsers.defaultparser, io, Int)

io = Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("0"), ["NA"])))
@time Parsers.xparse(Parsers.defaultparser, io, Int)

io = Parsers.Delimited(Parsers.Sentinel(IOBuffer("0"), ["NA"]))
@time Parsers.xparse(Parsers.defaultparser, io, Int)

io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("0"), ["NA"]))))
@time Parsers.xparse(Parsers.defaultparser, io, Int)

io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("0.0"), ["NA"]))))
@time Parsers.xparse(Parsers.defaultparser, io, Float64)

io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("0.0"), ["NA"]))))
@time Parsers.xparse(Parsers.defaultparser, io, String)

io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("2018-01-01"), ["NA"]))))
@time Parsers.xparse(Parsers.defaultparser, io, Date)


run(@benchmarkable Parsers.xparse(io, Int) setup=(io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("NA"), ["NA"]))))))
io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("NA"), ["NA"]))))
@time Parsers.xparse(Parsers.defaultparser, io, Int)

@btime Parsers.xparse(Parsers.defaultparser, Parsers.Sentinel(IOBuffer("NA"), ["NA"]), Int)

function test(n)
    io = Parsers.Sentinel(IOBuffer("NA"), ["NA"])
    io2 = Parsers.getio(io)
    for i = 1:n
        Parsers.xparse(Parsers.defaultparser, io, Int)
        Parsers.fastseek!(io2, 1)
    end
end

function test(n)
    io = Parsers.Delimited(Parsers.Sentinel(IOBuffer("NA"), ["NA"]))
    io2 = Parsers.getio(io)
    for i = 1:n
        Parsers.xparse(Parsers.defaultparser, io, Int)
        Parsers.fastseek!(io2, 1)
    end
end