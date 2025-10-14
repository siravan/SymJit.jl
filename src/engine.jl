abstract type FuncType end
abstract type Lambdify <: FuncType end
abstract type FastFunc <: FuncType end
abstract type OdeFunc <: FuncType end
abstract type JacFunc <: FuncType end


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
    handle = @ccall libpath.compile(model::Cstring, ty::Cstring)::Ptr{Cvoid}
    status = unsafe_string(
        @ccall libpath.check_status(handle::Ptr{Cvoid})::Ptr{Cchar}
    )

    if status != "Success"
        error("compilation error: $status")
    end
    
    count_states = @ccall libpath.count_states(handle::Ptr{Cvoid})::Cint
    count_params = @ccall libpath.count_params(handle::Ptr{Cvoid})::Cint
    count_obs = @ccall libpath.count_obs(handle::Ptr{Cvoid})::Cint
    count_diffs = @ccall libpath.count_diffs(handle::Ptr{Cvoid})::Cint

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

###################### compile_* functions ###############################

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

function compile_jac(t, states, eqs; params=[], ty="native")
    n = length(states)
    @assert n == length(eqs)

    J = Num[]
    for eq in eqs
        for x in states
            deq_x = expand_derivatives(Differential(x)(eq))
            push!(J, deq_x)
        end
    end

    model = JSON.json(dictify(states, J; params))
    return compile_model(JacFunc, model; ty)
end

function compile_func(f::Function; ty="native")
    F = methods(f)[1]
    v = Inspector("v")
    states = [v[i] for i in 1:F.nargs-1]
    obs = f(states...)
    model = JSON.json(dictify(states, [obs]))
    return compile_model(FastFunc, model; ty)       
end

function compile_func(states, model; params=[], ty="native")
    model = JSON.json(dictify(states, model; params))
    return compile_model(Lambdify, model; ty)
end

######################### Calls #############################

function (func::Func{Lambdify})(u::Vector{T}) where T <: Number
    func.mem[1:func.count_states] .= u    
    call(func.code, func.mem, func.params)
    return func.mem[func.count_states+2:func.count_states+func.count_obs+1]    
end

function (func::Func{Lambdify})(u::Vector{T}, p) where T <: Number
    func.params .= p
    func.mem[1:func.count_states] .= u    
    call(func.code, func.mem, func.params)
    return func.mem[func.count_states+2:func.count_states+func.count_obs+1]    
end

function (func::Func{Lambdify})(u::Matrix{T}, p=nothing; copy_matrix=true) where T <: Number
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
        obs_mat.handle::Ptr{Cvoid}
    )::Cvoid

    return obs    
end

function (func::Func{FastFunc})(args...)
    @assert func.count_obs == 1
    func.mem[1:func.count_states] .= args  
    call(func.code, func.mem, func.params)
    return func.mem[func.count_states+2]    
end

function (f::Func{OdeFunc})(du, u, p, t)
    f.mem[1:f.count_states] .= u
    f.params .= p
    f.mem[f.count_states+1] = t
    call(f.code, f.mem, f.params)
    du .= f.mem[f.count_states+f.count_obs+2:f.count_states+f.count_obs+f.count_diffs+1]
end

function (f::Func{JacFunc})(J, u, p, t)
    f.mem[1:f.count_states] .= u
    f.params .= p
    f.mem[f.count_states+1] = t
    call(f.code, f.mem, f.params)
    n = f.count_states
    J .= reshape(f.mem[n+2:n+1+n*n], (n,n))
end
