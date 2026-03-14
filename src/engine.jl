 abstract type FuncType end
abstract type Lambdify <: FuncType end
abstract type FastFunc <: FuncType end
abstract type OdeFunc <: FuncType end
abstract type JacFunc <: FuncType end


mutable struct Func{T}
    handle::Ptr{Cvoid}
    code::MachineCode
    mem::Vector
    params::Vector
    count_states::Int
    count_params::Int
    count_obs::Int
    count_diffs::Int
end

const USE_SIMD = 0x01
const USE_THREADS = 0x02
const CSE = 0x04
const FASTMATH = 0x08
const COMPLEX = 0x20
const OPT_LEVEL_MASK = 0x0f00
const OPT_LEVEL_SHIFT = 8

function compile_model(
    T,
    model;
    ty = "native",
    use_simd = true,
    use_threads = true,
    cse = true,
    fastmath = false,
    opt_level = 2,
    dtype = :real,
)
    @assert dtype in [:real, :complex]
    is_complex = dtype == :complex

    opt = (
        (use_simd ? USE_SIMD : 0) | (use_threads ? USE_THREADS : 0) | (cse ? CSE : 0) |
        (fastmath ? FASTMATH : 0) | (is_complex ? COMPLEX : 0) |
        ((opt_level << OPT_LEVEL_SHIFT) & OPT_LEVEL_MASK)
    )

    df = @ccall libpath.create_defuns()::Ptr{Cvoid}
    handle = @ccall libpath.compile(model::Cstring, ty::Cstring, opt::Cint, df::Ptr{Cvoid})::Ptr{Cvoid}
    status = unsafe_string(@ccall libpath.check_status(handle::Ptr{Cvoid})::Ptr{Cchar})

    if status != "Success"
        error("compilation error: $status")
    end

    k = is_complex ? 2 : 1

    count_states = (@ccall libpath.count_states(handle::Ptr{Cvoid})::Cint) ÷ k
    count_params = (@ccall libpath.count_params(handle::Ptr{Cvoid})::Cint) ÷ k
    count_obs = (@ccall libpath.count_obs(handle::Ptr{Cvoid})::Cint) ÷ k
    count_diffs = (@ccall libpath.count_diffs(handle::Ptr{Cvoid})::Cint) ÷ k

    code = create_executable_memory(dumps(handle))

    if is_complex
        mem = zeros(ComplexF64, count_states + count_obs + count_diffs + 1)
        params = zeros(ComplexF64, count_params)

        func = Func{T}(
            handle,
            code,
            mem,
            params,
            count_states,
            count_params,
            count_obs,
            count_diffs,
        )
    else
        mem = zeros(count_states + count_obs + count_diffs + 1)
        params = zeros(count_params)

        func = Func{T}(
            handle,
            code,
            mem,
            params,
            count_states,
            count_params,
            count_obs,
            count_diffs,
        )
    end

    finalizer(func) do f
        @ccall libpath.finalize(f.handle::Ptr{Cvoid})::Cvoid
    end

    return func
end

function dumps(handle)
    @ccall libpath.dump(handle::Ptr{Cvoid}, "_dump.bin"::Cstring, "scalar"::Cstring)::Cvoid
    bin = read("_dump.bin")
    rm("_dump.bin")
    return bin
end

function version(f::Func{T}) where T
    msg = unsafe_string(@ccall libpath.info(f.handle::Ptr{Cvoid})::Ptr{Cchar})
    return msg
end

###################### compile_* functions ###############################

function compile_ode(sys::ODESystem; kw...)
    model = JSON.json(dictify_ode(sys))
    return compile_model(OdeFunc, model; kw...)
end

function compile_ode(sys::System; kw...)
    model = JSON.json(dictify_ode(sys))
    return compile_model(OdeFunc, model; kw...)
end

function compile_ode(t, states, eqs; params = [], kw...)
    model = JSON.json(dictify_ode(states, eqs, t; params))
    return compile_model(OdeFunc, model; kw...)
end

function symbolize_ode_func(f::Function, t)
    u = Inspector("u")
    du = Inspector("du")
    p = Inspector("p")

    f(du, u, p, t)

    states, _ = linearize(u)
    _, eqs = linearize(du)
    @assert length(states) == length(eqs)
    params, _ = linearize(p)

    return states, eqs, params
end

function compile_ode(f::Function; kw...)
    @variables t
    states, eqs, params = symbolize_ode_func(f, t)
    return compile_ode(t, states, eqs; params, kw...)
end

function compile_jac(t, states, eqs; params = [], kw...)
    n = length(states)
    @assert n == length(eqs)

    J = Num[]
    for eq in eqs
        for x in states
            deq_x = expand_derivatives(Differential(x)(eq))
            push!(J, deq_x)
        end
    end

    model = JSON.json(dictify(states, J, t; params))
    return compile_model(JacFunc, model; kw...)
end

function compile_jac(f::Function; kw...)
    @variables t
    states, eqs, params = symbolize_ode_func(f, t)
    return compile_jac(t, states, eqs; params, kw...)
end

function compile_func(f::Function; kw...)
    F = methods(f)[1]
    v = Inspector("v")
    states = [v[i] for i = 1:(F.nargs-1)]
    obs = f(states...)
    model = JSON.json(dictify(states, [obs]))
    return compile_model(FastFunc, model; kw...)
end

function compile_func(states, model; params = [], kw...)
    model = JSON.json(dictify(states, model; params))
    return compile_model(Lambdify, model; kw...)
end

######################### Calls #############################

function (func::Func{Lambdify})(u::Vector{T}) where {T<:Number}
    func.mem[1:func.count_states] .= u
    call(func.code, func.mem, func.params)
    return func.mem[(func.count_states+1):(func.count_states+func.count_obs)]
end

function (func::Func{Lambdify})(u::Vector{T}, p) where {T<:Number}
    func.params .= p
    func.mem[1:func.count_states] .= u
    call(func.code, func.mem, func.params)
    return func.mem[(func.count_states+1):(func.count_states+func.count_obs)]
end

function (func::Func{Lambdify})(
    u::Matrix{T},
    p = nothing;
    copy_matrix = true,
) where {T<:Number}
    if p != nothing
        func.params .= p
    end

    if copy_matrix
        states = zeros(size(u, 1), func.count_states)
        states .= u
        states_mat = create_matrix(states)
    else
        states_mat = create_matrix(u)
    end

    obs = zeros(size(u, 1), func.count_obs)
    obs_mat = create_matrix(obs)

    @ccall libpath.execute_matrix(
        func.handle::Ptr{Cvoid},
        states_mat.handle::Ptr{Cvoid},
        obs_mat.handle::Ptr{Cvoid},
    )::Cvoid

    return obs
end

function (func::Func{FastFunc})(args...)
    @assert func.count_obs == 1
    func.mem[1:func.count_states] .= args
    call(func.code, func.mem, func.params)
    return func.mem[func.count_states+1]
end

function (f::Func{OdeFunc})(du, u, p, t)
    f.mem[1] = t
    f.mem[2:f.count_states+1] .= u
    f.params .= p
    call(f.code, f.mem, f.params)
    du .= f.mem[(f.count_states+f.count_obs+2):(f.count_states+f.count_obs+f.count_diffs+1)]
end

function (f::Func{JacFunc})(J, u, p, t)
    n = f.count_states
    f.mem[f.count_states] = t
    f.mem[2:n+1] .= u
    f.params .= p

    call(f.code, f.mem, f.params)
    J .= reshape(f.mem[(n+2):(n+1+n*n)], (n, n))
end
