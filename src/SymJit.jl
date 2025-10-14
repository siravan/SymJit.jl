module SymJit

using SymbolicUtils
using Symbolics

export compile_func, compile_ode, compile_jac

include("artifacts.jl")
include("memory.jl")
include("jsonify.jl")
include("inspector.jl")
include("matrix.jl")
include("engine.jl")

#************************************************************

function test_func()
    @variables x y
    f = compile_func([x, y], [x+y, x*y, sin(y-x)])
    print(f([2.0, 3.0]))
end

end # module
