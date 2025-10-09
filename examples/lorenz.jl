using DifferentialEquations
using SymJit
using Plots

function lorenz(du, u, p, t)
    x, y, z = u
    σ, ρ, β = p

    du[1] = σ * (y - x)
    du[2] = x * (ρ - z) - y
    du[3] = x * y - β * z
end

f = compile_ode(lorenz)

prob1 = ODEProblem(f, [1.0, 1.0, 1.0], (0.0, 100.0), (10.0, 28.0, 8 / 3))
sol1 = solve(prob1)

prob2 = ODEProblem(lorenz, [1.0, 1.0, 1.0], (0.0, 100.0), (10.0, 28.0, 8 / 3))
sol2 = solve(prob2)

p1 = plot(sol1; idxs=(1,3), lw=2)
p2 = plot(sol2; idxs=(1,3), lw=2)

plot(p1, p2, layout=(1, 2), legend=false, size=(600, 300))
