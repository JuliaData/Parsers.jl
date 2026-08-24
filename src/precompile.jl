# A light precompile workload: the whole-input parse for the common types, so
# first use in a session is instant. Everything here is exercised through the
# public API only.
using PrecompileTools: @setup_workload, @compile_workload
@setup_workload begin
    ints = ("42", " -7 ", "0x1f")
    flts = ("1.5", "1e10", "-0.25", "3.141592653589793")
    @compile_workload begin
        for s in ints
            parse(Int, s); tryparse(Int, s); parse(Int64, s); tryparse(UInt64, "42")
        end
        for s in flts
            parse(Float64, s); tryparse(Float64, s); parse(Float32, s)
        end
        # "1e10" overflows Float16 (public overflow errors rather than rounding
        # to Inf16), so Float16 gets its own in-range inputs
        parse(Float16, "1.5"); tryparse(Float16, "-0.25")
        parse(Bool, "true"); tryparse(Bool, "0")
        parse(Dates.Date, "2024-01-02"); parse(Dates.DateTime, "2024-01-02T03:04:05")
        parse(Dates.Time, "03:04:05"); parse(Dates.Date, "01/02/2024"; dateformat="mm/dd/yyyy")
        parse(Base.UUID, "123e4567-e89b-12d3-a456-426614174000")
        buf = Vector{UInt8}("12,3.5,true")
        parse(Int, buf, 1, 2); parse(Float64, buf, 4, 6); parse(Bool, buf, 8, 11)
        parsenext(Float64, buf, 4, 11); parsenext(Int, buf, 1, 11)
    end
end
