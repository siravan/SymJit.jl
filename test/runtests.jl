using Test

using Symbolics
using SymJit
using DifferentialEquations

@variables x y t

@testset "compile_func" begin

    f = SymJit.compile_func([x, y], [x+y, x*y])
    @test f([2, 3]) == [5.0, 6.0]

end

@testset "compile_ode" begin

    f = SymJit.compile_ode(t, [x, y], [y, -x])
    prob = ODEProblem(f, [0.0, 1.0], (0.0, 2*pi), Float64[])
    sol = solve(prob)
    @test all(abs.(sol[1, :] .- sin.(sol.t)) .< 0.0001)  # sol[1,:] should be sin(sol.t)

end
