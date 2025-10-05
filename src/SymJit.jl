module SymJit

using SymbolicUtils
using Symbolics
using ModelingToolkit

include("memory.jl")
include("jsonify.jl")
include("engine.jl")

#************************************************************

# using DifferentialEquations

function test_func()
    @variables x y
    f = compile_func([x, y], [x+y, x*y, sin(y-x)])
    print(f([2.0, 3.0]))
end

function test_ode()
    ml = CellModel("/home/shahriar/af/Julia/CellMLToolkit.jl/models/beeler_reuter_1977.cellml.xml")
    model = JSON.json(dictify(sys))
    f = compile(ml.sys)
    u0 = get_u0(ml)
    p = get_p(ml)
    tspan = (0, 5000.0)
    prob = ODEProblem(f, u0, tspan, p)
    sol = solve(prob, dtmax=0.1)
    return sol
end

end # module
