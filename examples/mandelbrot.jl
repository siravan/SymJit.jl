using SymJit

using Symbolics
using Plots

# this is not the fastest or best method to create a Manderbrot graph, but
# it generates very large symbolic expressions that test both the Symbolic
# engine and the compiler.

const N = 500

@variables a b

function manderbrot(a, b)
    x = a
    y = b

    for i = 1:15
        x, y = (x^2 - y^2 + a, 2 * x * y + b)
    end

    return [x, y]
end

f = SymJit.compile_func([a, b], manderbrot(a, b))

m = zeros(N, N)

for i = 1:N
    for j = 1:N
        m[j, i] = hypot(f([i/N*3.0-2.0, j/N*3.0-1.5])...)
    end
end

heatmap(m .< 4.0; aspect_ratio = :equal)
