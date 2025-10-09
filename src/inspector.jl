using Symbolics

mutable struct Inspector
    prefix::String
    vars::Dict
    eqs::Dict
    idx::Int

    Inspector(prefix::AbstractString) = new(prefix, Dict(), Dict(), 0)
end

function Base.getindex(p::Inspector, key...)
    if haskey(p.vars, key)
        return p.vars[key]
    else
        p.idx += 1
        sym = Symbol("$(p.prefix)$(p.idx)")
        v = (@variables $sym)[1]
        p.vars[key] = v
        return v
    end
end

function Base.setindex!(p::Inspector, eq, key...)
    if haskey(p.vars, key)
        p.eqs[p.vars[key]] = eq
    else
        p.idx += 1
        sym = Symbol("$(p.prefix)$(p.idx)")
        v = (@variables $sym)[1]
        p.vars[key] = v
        p.eqs[v] = eq
    end
end

function linearize(p::Inspector)
    ks = sort([k[1] for k in keys(p.vars)])

    vars = Array{Num}(undef, length(ks))
    eqs = Array{Num}(undef, length(ks))

    for i = 1:length(ks)
        v = p.vars[(ks[i],)]
        vars[i] = v
        if haskey(p.eqs, v)
            eqs[i] = p.eqs[v]
        end
    end

    return vars, eqs
end

function Base.iterate(p::Inspector)
    p.idx += 1
    sym = Symbol("$(p.prefix)$(p.idx)")
    v = (@variables $sym)[1]
    p.vars[(p.idx,)] = v
    return (v, p)
end

function Base.iterate(p::Inspector, state)
    p.idx += 1
    sym = Symbol("$(p.prefix)$(p.idx)")
    v = (@variables $sym)[1]
    p.vars[(p.idx,)] = v
    return (v, p)
end
