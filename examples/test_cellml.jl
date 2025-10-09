using SymJit

using CellMLToolkit
using DifferentialEquations
using Plots

get_p(ml::CellModel) = [last(v) for v in list_params(ml)]
get_u0(ml::CellModel) = [last(v) for v in list_states(ml)]

function test_ode()
    ml = CellModel(joinpath(@__DIR__, "..", "models/beeler_reuter_1977.cellml.xml"))
    f = SymJit.compile_ode(ml.sys)
    u0 = get_u0(ml)
    p = get_p(ml)
    tspan = (0, 5000.0)
    prob = ODEProblem(f, u0, tspan, p)
    sol = solve(prob, dtmax=0.1)
    plot(sol; idxs=2)
end
