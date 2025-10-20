# is_number(x) returns true if x is a concrete numerical type
is_number(x::T) where {T <: Integer} = true
is_number(x::T) where {T <: Float32} = true
is_number(x::T) where {T <: Float64} = true
is_number(x::T) where {T <: Complex} = true
is_number(x::T) where {T <: Rational} = true
is_number(x) = false

is_proper(x) = is_number(x) && !isnan(x) && !isinf(x)
is_integer(x) = is_number(x) && round(x) == x

###################### Rename Operators #######################

@syms plus(x, y) times(x, y) minus(x, y) divide(x, y) power(x, y) rem(x, y)
@syms lt(x, y) leq(x, y) gt(x, y) geq(x, y) eq(x, y) neq(x, y)

rules_rename = [
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

apply_rename(eq) = Postwalk(PassThrough(Chain(rules_rename)))(value(eq))

################### Rewrite Operators #######################

@syms neg(x) square(x) cube(x) sqrt(x) cbrt(x) powi(x, p::Int)

rules_rewrite = [
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


apply_rewrite(eq) = Postwalk(PassThrough(Chain(rules_rewrite)))(value(eq))

############# High-level Intermediate Representation #########

# the meaning of e in uniop and binop depends on the compilation pass.
# In the early stages, it is the ershov numner
# When IR is emitted, it is the destination
@syms uniop(e, op::Symbol, x) binop(e, op::Symbol, x, y) ternary(e, cond, x, y)
@syms unicall(op::Symbol, x) bincall(op::Symbol, x, y)

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
    @rule plus(~x, ~y) => binop(0, :plus, ~x, ~y)
    @rule times(~x, ~y) => binop(0, :times, ~x, ~y)
    @rule minus(~x, ~y) => binop(0, :minus, ~x, ~y)
    @rule divide(~x, ~y) => binop(0, :divide, ~x, ~y)
    @rule lt(~x, ~y) => binop(0, :lt, ~x, ~y)
    @rule leq(~x, ~y) => binop(0,:leq, ~x, ~y)
    @rule gt(~x, ~y) => binop(0, :gt, ~x, ~y)
    @rule geq(~x, ~y) => binop(0, :geq, ~x, ~y)
    @rule eq(~x, ~y) => binop(0, :eq, ~x, ~y)
    @rule neq(~x, ~y) => binop(0, :neq, ~x, ~y)
    @rule power(~x, ~y) => bincall(:power, ~x, ~y)
    @rule powi(~x, ~p) => binop(0, :powi, ~x, ~p)
    @rule neg(~x) => uniop(0, :neg, ~x)
    @rule square(~x) => uniop(0, :square, ~x)
    @rule cube(~x) => uniop(0, :cube, ~x)
    @rule sqrt(~x) => uniop(0, :sqrt, ~x)
    @rule cbrt(~x) => uniop(0, :cbrt, ~x)
    @rule ifelse(~cond, ~x, ~y) => ternary(0, ~cond, ~x, ~y)
    @rule (~f)(~x) => unicall(Symbol(~f), ~x)
]

function apply_codify(eq)
    return Postwalk(PassThrough(Chain(rules_codify)))(value(eq))
end

############################ Builder #############################

@syms mem(x::Int) stack(x::Int) param(x::Int) reg(r::Int)
@syms load(r, loc) save(loc, r) load_const(r, val::Float64, idx::Int)
@syms mov(r, s) call_func(op::Symbol, idx::Int)


mutable struct Builder
    eqs::Array{Any}
    vars::Dict{Any, Any}
    count_states::Int
    count_obs::Int
    count_params::Int
    # count_diffs
    count_temps::Int

    Builder() = new(
        Any[],
        Dict(),
        0,
        0,
        0,
        0,
    )
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
        rhs = apply_codify(apply_rewrite(apply_rename(eq)))
        propagate_equation(builder, lhs, rhs)
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

################### Propagation ##########################
#
# note that propagation is used in herbiculture sense, measing
# cutting and re-implasting tree branches

function propagate_equation(builder::Builder, lhs, rhs)
    rhs = value(rhs)

    if iscall(rhs)
        head = operation(rhs)

        if head == unicall
            propagate_unicall(builder, lhs, rhs)
        elseif head == bincall
            propagate_bincall(builder, lhs, rhs)
        else
            push!(builder.eqs, lhs ~ propagate(builder, rhs))
        end
    else
        push!(builder.eqs, lhs ~ rhs)
    end
end

function propagate(builder::Builder, eq)
    if iscall(eq)
        head = operation(eq)

        if head == uniop
            return propagate_uniop(builder, eq)
        elseif head == binop
            return propagate_binop(builder, eq)
        elseif head == ternary
            return propagate_ternary(builder, eq)
        else
            error("call instruction should be on top of trees")
        end
    else
        return eq
    end
end

const COUNT_SCRATCH = 14

function propagate_uniop(builder::Builder, eq)
    e, op, x = arguments(eq)
    @assert e == 0
    xx = propagate(builder, x)
    e = ershov(xx)
    return uniop(e, op, xx)
end

function propagate_binop(builder::Builder, eq)
    e, op, x, y = arguments(eq)
    @assert e == 0
    xx = propagate(builder, x)
    yy = propagate(builder, y)
    e = calc_ershov(xx, yy)
    u = binop(e, op, xx, yy)

    if e < COUNT_SCRATCH
        return u
    else
        t = new_temp(builder)
        push!(builder.eqs, t ~ u)
        return t
    end
end

function propagate_ternary(builder::Builder, eq)
    e, cond, x, y = arguments(eq)
    @assert e == 0
    cond = propagate(builder, cond)
    xx = propagate(builder, x)
    yy = propagate(builder, y)
    e = calc_ershov(cond, xx, yy)
    u = ternary(e, cond, xx, yy)

    if e < COUNT_SCRATCH
        return u
    else
        t = new_temp(builder)
        push!(builder.eqs, t ~ u)
        return t
    end
end

function propagate_unicall(builder::Builder, lhs, eq)
    op, x = arguments(eq)
    xx = propagate(builder, x)
    push!(builder.eqs, lhs ~ unicall(op, xx))
end

function propagate_bincall(builder::Builder, lhs, eq)
    op, x, y = arguments(eq)
    xx = propagate(builder, x)
    yy = propagate(builder, y)
    push!(builder.eqs, lhs ~ bincall(op, xx, yy))
end
