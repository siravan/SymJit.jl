abstract type FuncType end
abstract type Lambdify <: FuncType end
abstract type OdeFunc <: FuncType end

mutable struct Func{T}
    handle::Ptr{Cvoid}
    code::MachineCode
    mem::Vector{Float64}
    params::Vector{Float64}
    count_states::Int
    count_params::Int
    count_obs::Int
    count_diffs::Int
end

function compile_model(T, model; ty="native")  # ty is 'native', 'bytecode', or 'wasm'
    handle = ccall((:compile, libpath), Ptr{Cvoid}, (Cstring, Cstring), model, ty)
    status = unsafe_string(
        ccall((:check_status, libpath), Ptr{Cchar}, (Ptr{Cvoid},), handle)
    )

    if status != "Success"
        error("compilation error: $status")
    end

    count_states = ccall((:count_states, libpath), Cint, (Ptr{Cvoid},), handle)
    count_params = ccall((:count_params, libpath), Cint, (Ptr{Cvoid},), handle)
    count_obs = ccall((:count_obs, libpath), Cint, (Ptr{Cvoid},), handle)
    count_diffs = ccall((:count_diffs, libpath), Cint, (Ptr{Cvoid},), handle)

    mem = zeros(count_states + count_obs + count_diffs + 1)
    params = zeros(count_params)

    code = create_executable_memory(dumps(handle))
    
    func = Func{T}(
        handle, 
        code,
        mem,
        params,
        count_states,
        count_params,
        count_obs,
        count_diffs
    )

    finalizer(func) do f
        ccall((:finalize, libpath), Cvoid, (Ptr{Cvoid},), f.handle)
    end

    return func
end

function dumps(handle)
    ccall((:dump, libpath), Cuchar, (Ptr{Cvoid}, Cstring, Cstring), handle, "_dump.bin", "scalar")
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

function compile_ode(f::Function; ty="native")
    u = Inspector("u")
    du = Inspector("du")
    p = Inspector("p")
    @variables t

    f(du, u, p, t)

    states, _ = linearize(u)
    _, eqs = linearize(du)
    @assert length(states) == length(eqs)
    params, _ = linearize(p)

    println(states)
    println(eqs)
    println(params)

    return compile_ode(t, states, eqs; params, ty)
end

function compile_func(states, model; params=[], ty="native")
    model = JSON.json(dictify(states, model; params))
    return compile_model(Lambdify, model; ty)
end

function (func::Func{Lambdify})(u, p=nothing; copy_matrix=true)
    if p != nothing
        func.params .= p
    end

    if ndims(u) == 1
        func.mem[1:func.count_states] .= u    
        call(func.code, func.mem, func.params)
        return func.mem[func.count_states+2:func.count_states+func.count_obs+1]
    elseif ndims(u) == 2
        if copy_matrix
            states = zeros(size(u, 1), func.count_states)
            states .= u        
            states_mat = create_matrix(states)
        else
            states_mat = create_matrix(u)
        end

        obs = zeros(size(u, 1), func.count_obs)
        obs_mat = create_matrix(obs)

        ccall((:execute_matrix, libpath), 
            Cvoid, 
            (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}), 
            func.handle, 
            states_mat.handle, 
            obs_mat.handle
        )

        return obs
    else
        error("dimension should be 1 or 2")
    end
end

function (f::Func{OdeFunc})(du, u, p, t)
    f.mem[1:f.count_states] .= u
    f.params .= p
    f.mem[f.count_states+1] = t
    call(f.code, f.mem, f.params)
    du .= f.mem[f.count_states+f.count_obs+2:f.count_states+f.count_obs+f.count_diffs+1]
end
