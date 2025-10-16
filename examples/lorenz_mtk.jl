using SymJit
using Symbolics
using ModelingToolkit
using DifferentialEquations
using Plots

@independent_variables t
@variables x(t) y(t) z(t)
@parameters σ ρ β

D = Differential(t)

eqs = [D(x) ~ σ * (y - x), D(y) ~ x * (ρ - z) - y, D(z) ~ x * y - β * z]

@mtkcompile sys = System(eqs, t)

f = compile_ode(sys)
prob = ODEProblem(f, [1.0, 1.0, 1.0], (0.0, 100.0), [28.0, 8 / 3, 10.0])
sol = solve(prob)
plot(sol; idxs = (3, 1))
