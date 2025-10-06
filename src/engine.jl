using Pkg.Artifacts

ensure_artifact_installed("symjit", joinpath(@__DIR__, "..", "Artifacts.toml"))
libpath = readdir(artifact"symjit"; join=true)[1]

abstract type FuncType end
abstract type Lambdify <: FuncType end
abstract type OdeFunc <: FuncType end

mutable struct Func{T}
    code::MachineCode
    mem::Vector{Float64}
    params::Vector{Float64}
    count_states::Int
    count_params::Int
    count_obs::Int
    count_diffs::Int
end

function compile_model(T, model; ty="native")  # ty is 'native', 'bytecode', or 'wasm'
    ref = ccall((:compile, libpath), Ptr{Cvoid}, (Cstring, Cstring), model, ty)
    status = unsafe_string(
        ccall((:check_status, libpath), Ptr{Cchar}, (Ptr{Cvoid},), ref)
    )

    if status != "Success"
        error("compilation error: $status")
    end

    count_states = ccall((:count_states, libpath), Cint, (Ptr{Cvoid},), ref)
    count_params = ccall((:count_params, libpath), Cint, (Ptr{Cvoid},), ref)
    count_obs = ccall((:count_obs, libpath), Cint, (Ptr{Cvoid},), ref)
    count_diffs = ccall((:count_diffs, libpath), Cint, (Ptr{Cvoid},), ref)

    mem = zeros(count_states + count_obs + count_diffs + 1)
    params = zeros(count_params)

    code = create_executable_memory(dumps(ref))

    ccall((:finalize, libpath), Cvoid, (Ptr{Cvoid},), ref)

    func = Func{T}(
        code,
        mem,
        params,
        count_states,
        count_params,
        count_obs,
        count_diffs
    )

    return func
end

function dumps(ref)
    ccall((:dump, libpath), Cuchar, (Ptr{Cvoid}, Cstring, Cstring), ref, "_dump.bin", "scalar")
    bin = read("_dump.bin")
    rm("_dump.bin")
    return bin
end

function compile_ode(sys::ODESystem; ty="native")
    model = JSON.json(dictify(sys))
    return compile_model(OdeFunc, model; ty)
end

function compile_ode(t, states, eqs; params=[], ty="native")
    model = JSON.json(dictify(t, states, eqs; params))
    return compile_model(OdeFunc, model; ty)
end

function compile_func(states, model; params=[], ty="native")
    model = JSON.json(dictify(states, model; params))
    return compile_model(Lambdify, model; ty)
end

function (func::Func{Lambdify})(u)
    func.mem[1:func.count_states] .= u
    call(func.code, func.mem, func.params)
    return func.mem[func.count_states+2:func.count_states+func.count_obs+1]
end

function (func::Func{Lambdify})(u, p)
    func.mem[1:func.count_states] .= u
    func.params .= p
    call(func.code, func.mem, func.params)
    return func.mem[func.count_states+2:func.count_states+func.count_obs+1]
end

function (f::Func{OdeFunc})(du, u, p, t)
    f.mem[1:f.count_states] .= u
    f.params .= p
    f.mem[f.count_states+1] = t
    call(f.code, f.mem, f.params)
    du .= f.mem[f.count_states+f.count_obs+2:f.count_states+f.count_obs+f.count_diffs+1]
end

# get_p(ml::CellModel) = [last(v) for v in list_params(ml)]
# get_u0(ml::CellModel) = [last(v) for v in list_states(ml)]
