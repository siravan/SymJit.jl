using SymbolicUtils
using SymbolicUtils.Rewriters
using Symbolics
using Symbolics: value

# is_number(x) returns true if x is a concrete numerical type
is_number(x::T) where {T <: Integer} = true
is_number(x::T) where {T <: Float32} = true
is_number(x::T) where {T <: Float64} = true
is_number(x::T) where {T <: Complex} = true
is_number(x::T) where {T <: Rational} = true
is_number(x) = false

is_proper(x) = is_number(x) && !isnan(x) && !isinf(x)
is_integer(x) = is_number(x) && round(x) == x

################### Split Nary Operations ####################

@syms plus(x, y) times(x, y) minus(x, y) divide(x, y) power(x, y) rem(x, y)
@syms lt(x, y) leq(x, y) gt(x, y) geq(x, y) eq(x, y) neq(x, y)

rules_split_nary = [
    @rule +(~~xs) => foldl(plus, ~~xs)
    @rule *(~~xs) => foldl(times, ~~xs)
    @rule ~x - ~y => minus(~x, ~y)
    @rule ~x / ~y => divide(~x, ~y)
    @rule ^(~x, ~y) => power(~x, ~y)
    @rule %(~x, ~y) => rem(~x, ~y)
    @rule ~x > ~y => gt(~x, ~y)
    @rule ~x >= ~y => geq(~x, ~y)
    @rule ~x < ~y => lt(~x, ~y)
    @rule ~x <= ~y => leq(~x, ~y)
    @rule ~x == ~y => eq(~x, ~y)
    @rule ~x != ~y => neq(~x, ~y)
]

apply_split_nary(eq) = Postwalk(PassThrough(Chain(rules_split_nary)))(value(eq))

################### Substitute New Ops #######################

@syms neg(x) square(x) cube(x) sqrt(x) cbrt(x) powi(x, p::Int)

rules_subs_ops = [
    @rule times(~x, -1.0) => neg(~x)
    @rule times(-1.0, ~x) => neg(~x)
    @rule plus(neg(~x), neg(~y)) => neg(plus(~x, ~y))
    @rule plus(~x, neg(~y)) => minus(~x, ~y)
    @rule plus(neg(~x), ~y) => minus(~y, ~x)
    @rule power(~x, 2) => square(~x)
    @rule power(~x, 3) => cube(~x)
    @rule power(~x, 4) => square(square(~x))
    @rule power(~x, -1) => divide(1.0, ~x)
    @rule power(~x, -2) => divide(1.0, square(~x))
    @rule power(~x, -3) => divide(1.0, cube(~x))
    @rule power(~x, 0.5) => sqrt(~x)
    @rule power(~x, 1/3) => cbrt(~x)
    @rule power(~x, -0.5) => divide(1.0, sqrt(~x))
    @rule power(~x, ~p::is_integer) => powi(~x, ~p)
]


apply_subs_ops(eq) = Postwalk(PassThrough(Chain(rules_subs_ops)))(value(eq))

############# High-level Intermediate Representation #########

@syms uniop(op::Symbol, x, e) binop(op::Symbol, x, y, e) call(op::Symbol, x) bincall(op::Symbol, x, y) ternary(cond, x, y, e)

rules_ershov = [
    @rule uniop(~op, ~x, ~e) => ~e
    @rule binop(~op, ~x, ~y, ~e) => ~e
]

function ershov(x)
   x = value(x)

   if iscall(x) && (operation(x) == uniop || operation(x) == binop)
       return arguments(x)[end]
   else
       return 1
   end
end

function calc_ershov(x1, x2)
    e1 = ershov(x1)
    e2 = ershov(x2)
    return e1 == e2 ? e1 + 1 : max(e1, e2)
end

calc_ershov(x1, x2, x3) = calc_ershov(calc_ershov(x1, x2), x3)

rules_codify = [
    @rule plus(~x, ~y) => binop(:plus, ~x, ~y, calc_ershov(~x, ~y))
    @rule times(~x, ~y) => binop(:times, ~x, ~y, calc_ershov(~x, ~y))
    @rule minus(~x, ~y) => binop(:minus, ~x, ~y, calc_ershov(~x, ~y))
    @rule divide(~x, ~y) => binop(:divide, ~x, ~y, calc_ershov(~x, ~y))
    @rule lt(~x, ~y) => binop(:lt, ~x, ~y, calc_ershov(~x, ~y))
    @rule leq(~x, ~y) => binop(:leq, ~x, ~y, calc_ershov(~x, ~y))
    @rule gt(~x, ~y) => binop(:gt, ~x, ~y, calc_ershov(~x, ~y))
    @rule geq(~x, ~y) => binop(:geq, ~x, ~y, calc_ershov(~x, ~y))
    @rule eq(~x, ~y) => binop(:eq, ~x, ~y, calc_ershov(~x, ~y))
    @rule neq(~x, ~y) => binop(:neq, ~x, ~y, calc_ershov(~x, ~y))
    @rule power(~x, ~y) => bincall(:power, ~x, ~y)
    @rule powi(~x, ~p) => binop(:powi, ~x, ~p, ershov(~x))
    @rule neg(~x) => uniop(:neg, ~x, ershov(~x))
    @rule square(~x) => uniop(:square, ~x, ershov(~x))
    @rule cube(~x) => uniop(:cube, ~x, ershov(~x))
    @rule sqrt(~x) => uniop(:sqrt, ~x, ershov(~x))
    @rule cbrt(~x) => uniop(:cbrt, ~x, ershov(~x))
    @rule ifelse(~cond, ~x, ~y) => ternary(~cond, ~x, ~y, calc_ershov(~cond, ~x, ~y))
    @rule (~f)(~x) => call(Symbol(~f), ~x)
]

function apply_codify(eq)
    return Postwalk(PassThrough(Chain(rules_codify)))(value(eq))
end

@syms mem(x::Int) stack(x::Int) param(x::Int) reg(r::Int)
@syms load(r, loc) save(r, loc) load_const(r, val) mov(r, s)

mutable struct Builder
    eqs::Array{Any}
    vars::Dict{Any, Any}
    count_states::Int
    count_obs::Int
    count_params::Int
    # count_diffs
    count_temps::Int
    count_regs::Int

    Builder() = new(Any[], Dict{Any,Any}(), 0, 0, 0, 0, 2)
end

function build(states, eqs, params=[])
    builder = Builder()

    for v in states
        builder.vars[v] = mem(builder.count_states)
        builder.count_states += 1
    end

    sym = Symbol("Ψ_")
    v = (@variables $sym)[1]
    builder.vars[v] = mem(builder.count_states)

    obs = []

    for i = 0:(length(eqs)-1)
        sym = Symbol("Ψ$i")
        v = (@variables $sym)[1]
        push!(obs, v)
    end

    for v in obs
        builder.vars[v] = mem(builder.count_states + 1 + builder.count_obs)
        builder.count_obs += 1
    end

    for v in params
        builder.vars[v] = param(builder.count_params)
        builder.count_params += 1
    end

    for (lhs, eq) in zip(obs, eqs)
        rhs = apply_codify(apply_subs_ops(apply_split_nary(eq)))
        propagate(builder, lhs, rhs)
    end

    return builder
end

function new_temp(builder::Builder)
    n = builder.count_temps
    sym = Symbol("θ$n")
    v = (@variables $sym)[1]
    builder.vars[v] = stack(n)
    builder.count_temps += 1
    return v
end

function propagate(builder::Builder, lhs, rhs)
    push!(builder.eqs, lhs ~ propagate(builder, rhs))
end

const COUNT_SCRATCH = 14

function propagate(builder::Builder, eq)
    eq = value(eq)

    if iscall(eq)
        head = operation(eq)

        if head == uniop
            return propagate_uniop(builder, eq)
        elseif head == binop
            return propagate_binop(builder, eq)
        elseif head == ternary
            return propagate_ternary(builder, eq)
        elseif head == call
            return propagate_call(builder, eq)
        elseif head == bincall
            return propagate_bincall(builder, eq)
        end
    else
        return eq
    end
end


function propagate_uniop(builder::Builder, eq)
    op, x, _ = arguments(eq)
    xx = propagate(builder, x)
    e = ershov(xx)
    return uniop(op, xx, e)
end

function propagate_binop(builder::Builder, eq)
    op, x, y, _ = arguments(eq)
    xx = propagate(builder, x)
    yy = propagate(builder, y)
    e = calc_ershov(xx, yy)
    u = binop(op, xx, yy, e)

    if e < COUNT_SCRATCH
        return u
    else
        t = new_temp(builder)
        push!(builder.eqs, t ~ u)
        return t
    end
end

function propagate_ternary(builder::Builder, eq)
    cond, x, y, _ = arguments(eq)
    cond = propagate(builder, cond)
    xx = propagate(builder, x)
    yy = propagate(builder, y)
    e = calc_ershov(cond, xx, yy)
    u = ternary(cond, xx, yy, e)

    if e < COUNT_SCRATCH
        return u
    else
        t = new_temp(builder)
        push!(builder.eqs, t ~ u)
        return t
    end
end

function propagate_call(builder::Builder, eq)
    op, x = arguments(eq)
    xx = propagate(builder, x)
    t = new_temp(builder)
    push!(builder.eqs, t ~ call(op, xx))
    return t
end

function propagate_bincall(builder::Builder, eq)
    op, x, y = arguments(eq)
    xx = propagate(builder, x)
    yy = propagate(builder, y)
    t = new_temp(builder)
    push!(builder.eqs, t ~ bincall(op, xx, yy))
    return t
end

function new_reg(builder::Builder)
    r = builder.count_regs
    builder.count_regs += 1
    return reg(r)
end

function compile(builder::Builder)
    mir = []
    for eq in builder.eqs
        r = compile(builder, mir, eq.rhs)
        push!(mir, save(eq.lhs, r))
    end
    return mir
end

const COUNT_SCRATCH = 14

function compile(builder::Builder, mir, eq)
    eq = value(eq)

    if iscall(eq)
        head = operation(eq)

        if head == uniop
            return compile_uniop(builder, mir, eq)
        elseif head == binop
            return compile_binop(builder, mir, eq)
        elseif head == ternary
            return compile_ternary(builder, mir, eq)
        elseif head == call
            return compile_call(builder, mir, eq)
        elseif head == bincall
            return compile_bincall(builder, mir, eq)
        end
    else
        r = new_reg(builder)
        if is_number(eq)
            push!(mir, load_const(r, eq))
        else
            push!(mir, load(r, eq))
        end
        return r
    end
end


function compile_uniop(builder::Builder, mir, eq)
    op, x, _ = arguments(eq)
    s = compile(builder, mir, x)
    r = new_reg(builder)
    push!(mir, uniop(op, s, r))
    return r
end

function compile_binop(builder::Builder, mir, eq)
    op, x, y, _ = arguments(eq)

    if ershov(x) >= ershov(y)
        s1 = compile(builder, mir, x)
        s2 = compile(builder, mir, y)
    else
        s2 = compile(builder, mir, y)
        s1 = compile(builder, mir, x)
    end

    r = new_reg(builder)
    push!(mir, binop(op, s1, s2, r))
    return r
end

function compile_ternary(builder::Builder, mir, eq)
    cond, x, y, _ = arguments(eq)
    cond = compile(builder, cond)

    e1 = ershov(cond)
    e2 = ershov(x)
    e3 = ershov(y)

    if e1 >= e2 && e2 >= e3
        s1 = compile(builder, mir, cond)
        s2 = compile(builder, mir, x)
        s3 = compile(builder, mir, y)
    elseif e1 >= e3 && e3 >= e2
        s1 = compile(builder, mir, cond)
        s3 = compile(builder, mir, y)
        s2 = compile(builder, mir, x)
    elseif e2 >= e1 && e1 >= e3
        s2 = compile(builder, mir, x)
        s1 = compile(builder, mir, cond)
        s3 = compile(builder, mir, y)
    elseif e2 >= e3 && e3 >= e1
        s2 = compile(builder, mir, x)
        s3 = compile(builder, mir, y)
        s1 = compile(builder, mir, cond)
    elseif e3 >= e1 && e1 >= e2
        s3 = compile(builder, mir, y)
        s1 = compile(builder, mir, cond)
        s2 = compile(builder, mir, x)
    else
        s3 = compile(builder, mir, y)
        s2 = compile(builder, mir, x)
        s1 = compile(builder, mir, cond)
    end

    r = new_reg(builder)
    push!(mir, r ~ ternary(cond, xx, yy, r))
    return r
end

function compile_call(builder::Builder, mir, eq)
    op, x = arguments(eq)
    push!(mir, mov(reg(0), compile(builder, mir, x)))
    push!(mir, call(op, 1))
    r = new_reg(builder)
    push!(mir, mov(r, reg(0)))
    return r
end

function propagate_bincall(builder::Builder, mir, eq)
    op, x, y = arguments(eq)
    push!(mir, mov(reg(0), compile(builder, mir, x)))
    push!(mir, mov(reg(1), compile(builder, mir, y)))
    push!(mir, call(op, 2))
    r = new_reg(builder)
    push!(mir, mov(r, reg(0)))
    return r
end
