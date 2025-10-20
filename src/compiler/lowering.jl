mutable struct IntRep
    ir::Vector{Any}
    vt::Vector{Any}
    constants::Vector{Float64}
    count_regs::Int

    IntRep() = new([], [], [0.0, -0.0, 1.0, -1.0], 2)
end

function Base.push!(mir::IntRep, t)
    push!(mir.ir, t)
end

function push_new_reg!(mir::IntRep, f)
    r = new_reg(mir)
    push!(mir.ir, f(r))
    return r
end

@syms σ0 σ1 ω

function new_reg(mir::IntRep)
    r = mir.count_regs
    mir.count_regs += 1
    sym = Symbol("σ$r")
    v = (@variables $sym)[1]
    return v
end

#
# lower functions convert a propagated Builder object into
# an intermediate representation

function lower(builder::Builder)
    mir = IntRep()

    for eq in builder.eqs
        r = lower(builder, mir, eq.rhs)
        push!(mir, save(eq.lhs, r))
    end

    return mir
end

function lower(builder::Builder, mir::IntRep, eq)
    eq = value(eq)

    if iscall(eq)
        head = operation(eq)

        if head == uniop
            return lower_uniop(builder, mir, eq)
        elseif head == binop
            return lower_binop(builder, mir, eq)
        elseif head == ternary
            return lower_ternary(builder, mir, eq)
        elseif head == unicall
            return lower_unicall(builder, mir, eq)
        elseif head == bincall
            return lower_bincall(builder, mir, eq)
        end
    else
        return lower_terminal(builder, mir, eq)
    end
end

function lower_terminal(builder::Builder, mir::IntRep, eq)
    if is_number(eq)
        val = Float64(eq)
        idx = findfirst(x -> x == val, mir.constants)

        if idx == nothing
            idx = length(mir.constants)
            push!(mir.constants, val)
        end

        return push_new_reg!(mir, r -> load_const(r, val, idx))
    else
        return push_new_reg!(mir, r -> load(r, eq))
    end
end

function lower_uniop(builder::Builder, mir::IntRep, eq)
    _, op, x = arguments(eq)
    s = lower(builder, mir, x)
    return push_new_reg!(mir, r -> uniop(r, op, s))
end

function lower_binop(builder::Builder, mir::IntRep, eq)
    _, op, x, y = arguments(eq)

    if ershov(x) >= ershov(y)
        s1 = lower(builder, mir, x)
        s2 = lower(builder, mir, y)
    else
        s2 = lower(builder, mir, y)
        s1 = lower(builder, mir, x)
    end

    return push_new_reg!(mir, r -> binop(r, op, s1, s2))
end

function lower_ternary(builder::Builder, mir::IntRep, eq)
    _, cond, x, y = arguments(eq)

    e1 = ershov(cond)
    e2 = ershov(x)
    e3 = ershov(y)

    if e1 >= e2 && e2 >= e3
        s1 = lower(builder, mir, cond)
        s2 = lower(builder, mir, x)
        s3 = lower(builder, mir, y)
    elseif e1 >= e3 && e3 >= e2
        s1 = lower(builder, mir, cond)
        s3 = lower(builder, mir, y)
        s2 = lower(builder, mir, x)
    elseif e2 >= e1 && e1 >= e3
        s2 = lower(builder, mir, x)
        s1 = lower(builder, mir, cond)
        s3 = lower(builder, mir, y)
    elseif e2 >= e3 && e3 >= e1
        s2 = lower(builder, mir, x)
        s3 = lower(builder, mir, y)
        s1 = lower(builder, mir, cond)
    elseif e3 >= e1 && e1 >= e2
        s3 = lower(builder, mir, y)
        s1 = lower(builder, mir, cond)
        s2 = lower(builder, mir, x)
    else
        s3 = lower(builder, mir, y)
        s2 = lower(builder, mir, x)
        s1 = lower(builder, mir, cond)
    end

    return push_new_reg!(mir, r -> ternary(r, s1, s2, s3))
end

function lower_unicall(builder::Builder, mir::IntRep, eq)
    op, x = arguments(eq)
    push!(mir, mov(σ0, lower(builder, mir, x)))
    push!(mir, call_func(op, find_func_idx(mir, op)))
    return push_new_reg!(mir, r -> mov(r, σ0))
end

function lower_bincall(builder::Builder, mir::IntRep, eq)
    op, x, y = arguments(eq)

    if ershov(x) >= ershov(y)
        push!(mir, mov(σ0, lower(builder, mir, x)))
        push!(mir, mov(σ1, lower(builder, mir, y)))
    else
        push!(mir, mov(σ1, lower(builder, mir, y)))
        push!(mir, mov(σ0, lower(builder, mir, x)))
    end

    push!(mir, call_func(op, find_func_idx(mir, op)))
    return push!(mir, r -> mov(r, σ0))
end

function find_func_idx(mir::IntRep, op)
    idx = findfirst(x -> first(x) == op, mir.vt)

    if idx == nothing
        f = func_ptr[op]
        idx = length(mir.vt)
        push!(mir.vt, (op, f))
    end

    return idx
end

###################### Register Allocator ####################

rules_extract = [
    @rule load(~dst, ~x) => (~dst, ω, ω, ω)
    @rule load_const(~dst, ~x, ~idx) => (~dst, ω, ω, ω)
    @rule save(~x, ~r1) => (ω, ~r1, ω, ω)
    @rule uniop(~dst, ~op, ~r1) => (~dst, ~r1, ω, ω)
    @rule binop(~dst, ~op, ~r1, ~r2) => (~dst, ~r1, ~r2, ω)
    @rule ternary(~dst, ~r1, ~r2, ~r3) => (~dst, ~r1, ~r2, ~r3)
    @rule call_func(~op, ~idx) => (σ0, ω, ω, ω)
    @rule mov(~dst, ~r1) => (~dst, ~r1, ω, ω)
]

apply_extract(eq) = Chain(rules_extract)(value(eq))


function allocate(mir::IntRep)
    pool = (1 << COUNT_SCRATCH - 1) << 2

    regs = Dict{Any, Int}()
    regs[σ0] = 0
    regs[σ1] = 1
    S = Set([σ0, σ1, ω])

    for t in mir.ir
        dst, r1, r2, r3 = apply_extract(t)

        if !(r1 in S)
            pool |= 1 << regs[r1]
        end

        if !(r2 in S)
            pool |= 1 << regs[r2]
        end

        if !(r3 in S)
            pool |= 1 << regs[r3]
        end

        if dst in S
            continue
        end

        if haskey(regs, dst)
            error("double allocation!")
        end

        if pool == 0
            error("no available free register")
        end

        d = trailing_zeros(pool)
        regs[dst] = d
        pool &= ~(1 << d)
    end

    return regs
end
