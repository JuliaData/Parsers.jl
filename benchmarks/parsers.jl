using BenchmarkTools, Parsers
run(@benchmarkable Parsers.xparse(io, Int) setup=(io = IOBuffer("0")))
@code_warntype Parsers.xparse(Parsers.defaultparser, IOBuffer("0"), Int)
@btime Parsers.xparse(Parsers.defaultparser, IOBuffer("0"), Int)
run(@benchmarkable Parsers.xparse(io, Int) setup=(io = Parsers.Sentinel(IOBuffer("0"), ["NA"])))
run(@benchmarkable Main.Parsers.xparse(io, Int) setup=(io = Main.Parsers.Sentinel(IOBuffer("NA"), ["NA"])))
@code_warntype Parsers.xparse(Parsers.defaultparser, Parsers.Sentinel(IOBuffer("0"), ["NA"]), Int)
@btime Parsers.xparse(Parsers.defaultparser, Parsers.Sentinel(IOBuffer("0"), ["NA"]), Int)
run(@benchmarkable Parsers.xparse(io, Int) setup=(io = Parsers.Delimited(Parsers.Quoted(Parsers.Strip(Parsers.Sentinel(IOBuffer("NA"), ["NA"]))))))

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