using DifferentialEquations
using SymJit
using Symbolics
using Plots

@variables t, x, y
@variables alpha, beta, gamma, delta

params = [alpha, beta, gamma, delta]
states = [x, y]
eqs = [alpha * x - beta * x * y, -gamma * y + delta * x * y]

f = compile_ode(t, states, eqs; params)
f_jac = compile_jac(t, states, eqs; params)

u0 = [1.0, 1.0]
p = [2.0, 1.2, 3.0, 1.0]
t_span = (0, 100.0)

ff = ODEFunction(f; jac=f_jac)
prob = ODEProblem(ff, u0, t_span, p)
sol = solve(prob)

plot(sol)
