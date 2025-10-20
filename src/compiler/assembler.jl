mutable struct Assembler
    buf::Vector{UInt8}
    labels::Dict{String, Int}
    jumps::Vector{Any}
    delta::Int
    shift::Int

    Assembler(delta, shift) = new(Vector{UInt8}[], Dict{String, Int}(), Vector{Any}(), delta, shift)
end

function bytes(asm::Assembler)
    return buf
end

function append_byte(asm::Assembler, b)
    push!(asm.buf, b)
end

function append_bytes(asm::Assembler, bs)
    for b in bs
        append_byte(asm, b)
    end
end

function append_word(asm::Assembler, u)
    # appends u (uint32) as little-endian
    for i in 1:4
        append_byte(asm, u & 0xff)
        u >>= 8
    end
end

function append_quad(asm::Assembler, u)
    # appends u (uint32) as little-endian
    for i in 1:8
        append_byte(asm, u & 0xff)
        u >>= 8
    end
end

function ip(asm::Assembler)
    return length(asm.buf)
end

function set_label(asm::Assembler, label)
    @assert !haskey(asm.labels, label)
    asm.labels[label] = ip(asm)
end

function jump(asm::Assembler, label, code)
    push!(asm.jumps, (label, ip(asm), code))
    append_word(asm, code)
end

function apply_jumps(asm::Assembler)
    for (label, k, code) in asm.jumps
        target = asm.labels[label]
        offset = target - k + asm.delta

        # TODO: we need a better place for this check
        # assembler is supposed to be arch agnostic
        #[cfg(target_arch = "aarch64")]
        #    assert!(
        #        offset >= 0 && offset < (1 << 20),
        #        "the code segment is too large!"
        #    )

        x = (offset << asm.shift) | code

        asm.buf[k] |= (x & 0xff)
        asm.buf[k + 1] |= (x >> 8) & 0xff
        asm.buf[k + 2] |= (x >> 16) & 0xff
        asm.buf[k + 3] |= (x >> 24) & 0xff
    end
end
