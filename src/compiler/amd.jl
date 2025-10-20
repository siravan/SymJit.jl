mutable struct Amd
    a::Assembler

    Amd() = new(Assembler(-4, 0))
end

const RAX = 0
const RCX = 1
const RDX = 2
const RBX = 3
const RSP = 4
const RBP = 5
const RSI = 6
const RDI = 7
const R8 = 8
const R9 = 9
const R10 = 10
const R11 = 11
const R12 = 12
const R13 = 13
const R14 = 14
const R15 = 15

function bytes(amd::Amd)
    return bytes(amd.a)
end

function append_byte(amd::Amd, b)
    append_byte(amd.a, b)
end

function append_bytes(amd::Amd, bs)
    append_bytes(amd.a, bs)
end

function append_word(amd::Amd, u)
    append_word(amd.a, u)
end

function append_quad(amd::Amd, u)
    append_quad(amd.a, u)
end

function modrm_reg(amd::Amd, reg::UInt8, rm::UInt8)
    append_byte(amd, 0xc0 + ((reg & 7) << 3) + (rm & 7))
end

function modrm_sib(amd::Amd, reg::UInt8, base::UInt8, index::UInt8, scale::UInt8)
    append_byte(amd, 0x04 + ((reg & 7) << 3)) # R/M = 0b100, MOD = 0b00
    scale = trailing_zeros(scale) << 6
    append_byte((amd, scale | (index & 7) << 3) | (base & 7))
end

function rex(amd::Amd, reg::UInt8, rm::UInt8)
    b = 0x48 + ((rm & 8) >> 3) + ((reg & 8) >> 1)
    append_byte(amd, b)
end

function rex_index(amd::Amd, reg::UInt8, rm::UInt8, index::UInt8)
    b = 0x48 + ((rm & 8) >> 3) + ((index & 8) >> 2) + ((reg & 8) >> 1)
    append_byte(amd, b)
end

function modrm_mem(amd::Amd, reg::UInt8, rm::UInt8, offset)
    small = -128 <= offset < 128

    if small
        append_byte(amd, 0x40 + ((reg & 7) << 3) + (rm & 7))
    else
        append_byte(amd, 0x80 + ((reg & 7) << 3) + (rm & 7))
    end

    if rm == RSP
        append_byte(amd, 0x24) # SIB byte for RSP
    end

    if small
        append_byte(amd, offset)
    else
        append_word(amd, offset)
    end
end

function vex2pd(amd::Amd, reg::UInt8, vreg::UInt8)
    # This is the two-byte VEX prefix (VEX2) for packed-double (pd)
    # and 256-bit ymm registers
    r = (~reg & 8) << 4
    vvvv = (~vreg & 0x0f) << 3
    append_byte(amd, 0xc5)
    append_byte(amd, r | vvvv | 5)
end

function vex2sd(amd::Amd, reg::UInt8, vreg::UInt8)
    # This is the two-byte VEX prefix (VEX2) for scalar-double (sd)
    # and 256-bit ymm registers
    r = (~reg & 8) << 4
    vvvv = (~vreg & 0x0f) << 3

    append_byte(amd, 0xc5)
    append_byte(amd, r | vvvv | 3)
end

function vex3pd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8, index::UInt8, encoding::UInt8)
    # This is the three-byte VEX prefix (VEX3) for packed-double (pd)
    # and 256-bit ymm registers
    # fnault encoding is 1
    r = (~reg & 8) << 4
    x = (~index & 8) << 3
    b = (~rm & 8) << 2
    vvvv = (~vreg & 0x0f) << 3

    append_byte(amd, 0xc4)
    append_byte(amd, r | x | b | encoding)
    append_byte(amd, vvvv | 5)
end

function vex3sd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8, index::UInt8, encoding::UInt8)
    # This is the three-byte VEX prefix (VEX3) for scalar-double (sd)
    # and 256-bit ymm registers
    # default encoding is 1
    r = (~reg & 8) << 4
    x = (~index & 8) << 3
    b = (~rm & 8) << 2
    vvvv = (~vreg & 0x0f) << 3

    append_byte(amd, 0xc4)
    append_byte(amd, r | x | b | encoding)
    append_byte(amd, vvvv | 3)
end

function vex_sd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8, index::UInt8)
    if rm < 8 && index < 8
        vex2sd(amd, reg, vreg)
    else
        vex3sd(amd, reg, vreg, rm, index, 1)
    end
end

function vex_pd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8, index::UInt8)
    if rm < 8 && index < 8
        vex2pd(amd, reg, vreg)
    else
        vex3pd(amd, reg, vreg, rm, index, 1)
    end
end

function sse_sd(amd::Amd, reg::UInt8, rm::UInt8)
    append_byte(amd, 0xf2) # sd
    rex(amd, reg, rm)
    append_byte(amd, 0x0f)
end

function sse_sd_index(amd::Amd, reg::UInt8, rm::UInt8, index::UInt8)
    append_byte(amd, 0xf2) # sd
    rex_index(amd, reg, rm, index)
    append_byte(amd, 0x0f)
end

function sse_pd(amd::Amd, reg::UInt8, rm::UInt8)
    append_byte(amd, 0x66) # pd
    rex(amd, reg, rm)
    append_byte(amd, 0x0f)
end

# AVX rules!
function vmovapd(amd::Amd, reg::UInt8, rm::UInt8)
    vex_pd(amd, reg, 0, rm, 0)
    append_byte(amd, 0x28)
    modrm_reg(amd, reg, rm)
end

#******************* scalar double ******************#
function vmovsd_xmm_mem(amd::Amd, reg::UInt8, rm::UInt8, offset)
    vex_sd(amd, reg, 0, rm, 0)
    append_byte(amd, 0x10)
    modrm_mem(amd, reg, rm, offset)
end

function vmovsd_xmm_indexed(amd::Amd, reg::UInt8, base::UInt8, index::UInt8, scale::UInt8)
    vex_sd(amd, reg, 0, base, index)
    append_byte(amd, 0x10)
    modrm_sib(amd, reg, base, index, scale)
end

function vmovsd_xmm_label(amd::Amd, reg::UInt8, label)
    vex_sd(amd, reg, 0, 0, 0)
    append_byte(amd, 0x10)
    # modr/m byte with MOD=00 and R/M=101 (RIP-relative address)
    append_byte(amd, 5 | ((reg & 7) << 3))
    jump(amd.a, label, 0)
end

function vmovsd_mem_xmm(amd::Amd, rm::UInt8, offset, reg::UInt8)
    vex_sd(amd, reg, 0, rm, 0)
    append_byte(amd, 0x11)
    modrm_mem(amd, reg, rm, offset)
end

function vmovsd_indexed_xmm(amd::Amd, base::UInt8, index::UInt8, scale::UInt8, reg::UInt8)
    vex_sd(amd, reg, 0, base, index)
    append_byte(amd, 0x11)
    modrm_sib(amd, reg, base, index, scale)
end

function vaddsd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x58)
    modrm_reg(amd, reg, rm)
end

function vsubsd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x5c)
    modrm_reg(amd, reg, rm)
end

function vmulsd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x59)
    modrm_reg(amd, reg, rm)
end

function vdivsd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x5e)
    modrm_reg(amd, reg, rm)
end

function vsqrtsd(amd::Amd, reg::UInt8, rm::UInt8)
    vex_sd(amd, reg, 0, rm, 0)
    append_byte(amd, 0x51)
    modrm_reg(amd, reg, rm)
end

function vroundsd(amd::Amd, reg::UInt8, rm::UInt8, mode)
    vex3pd(amd, reg, reg, rm, 0, 3)
    append_byte(amd, 0x0b)
    modrm_reg(amd, reg, rm)

    if mode == :round
        append_byte(amd, 0)
    elseif mode == :floor
        append_byte(amd, 1)
    elseif mode == :ceiling
        append_byte(amd, 2)
    elseif mode == :trunc
        append_byte(amd, 3)
    end
end

function vcmpeqsd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 0)
end

function vcmpltsd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 1)
end

function vcmplesd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 2)
end

function vcmpunordsd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 3)
end

function vcmpneqsd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 4)
end

function vcmpnltsd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 5)
end

function vcmpnlesd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 6)
end

function vcmpordsd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_sd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xC2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 7)
end

function vucomisd(amd::Amd, reg::UInt8, rm::UInt8)
    vex_pd(amd, reg, 0, rm, 0)
    append_byte(amd, 0x2e)
    modrm_reg(amd, reg, rm)
end

#******************* packed double ******************#
function vbroadcastsd(amd::Amd, reg::UInt8, rm::UInt8, offset)
    vex3pd(amd, reg, 0, rm, 0, 2)
    append_byte(amd, 0x19)
    modrm_mem(amd, reg, rm, offset)
end

function vbroadcastsd_label(amd::Amd, reg::UInt8, label)
    vex3pd(amd, reg, 0, 0, 0, 2)
    append_byte(amd, 0x19)
    # modr/m byte with MOD=00 and R/M=101 (RIP-relative address)
    append_byte(amd, 5 | ((reg & 7) << 3))
    jump(amd.a, label, 0)
end

function vmovpd_ymm_mem(amd::Amd, reg::UInt8, rm::UInt8, offset)
    vex_pd(amd, reg, 0, rm, 0)
    append_byte(amd, 0x10)
    modrm_mem(amd, reg, rm, offset)
end

function vmovpd_ymm_indexed(amd::Amd, reg::UInt8, base::UInt8, index::UInt8, scale::UInt8)
    vex_pd(amd, reg, 0, base, index)
    append_byte(amd, 0x10)
    modrm_sib(amd, reg, base, index, scale)
end

function vmovpd_ymm_label(amd::Amd, reg::UInt8, label)
    vex_pd(amd, reg, 0, 0, 0)
    append_byte(amd, 0x10)
    # modr/m byte with MOD=00 and R/M=101 (RIP-relative address)
    append_byte(amd, 5 | ((reg & 7) << 3))
    jump(amd.a, label, 0)
end

function vmovpd_mem_ymm(amd::Amd, rm::UInt8, offset, reg::UInt8)
    vex_pd(amd, reg, 0, rm, 0)
    append_byte(amd, 0x11)
    modrm_mem(amd, reg, rm, offset)
end

function vmovpd_indexed_ymm(amd::Amd, base::UInt8, index::UInt8, scale::UInt8, reg::UInt8)
    vex_pd(amd, reg, 0, base, index)
    append_byte(amd, 0x11)
    modrm_sib(amd, reg, base, index, scale)
end

function vaddpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x58)
    modrm_reg(amd, reg, rm)
end

function vsubpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x5c)
    modrm_reg(amd, reg, rm)
end

function vmulpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x59)
    modrm_reg(amd, reg, rm)
end

function vdivpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x5e)
    modrm_reg(amd, reg, rm)
end

function vsqrtpd(amd::Amd, reg::UInt8, rm::UInt8)
    vex_pd(amd, reg, 0, rm, 0)
    append_byte(amd, 0x51)
    modrm_reg(amd, reg, rm)
end

function vroundpd(amd::Amd, reg::UInt8, rm::UInt8, mode)
    vex3pd(amd, reg, 0, rm, 0, 3)
    append_byte(amd, 0x09)
    modrm_reg(amd, reg, rm)

    if mode == :round
        append_byte(amd, 0)
    elseif mode == :floor
        append_byte(amd, 1)
    elseif mode == :ceiling
        append_byte(amd, 2)
    elseif mode == :trunc
        append_byte(amd, 3)
    end
end

function vandpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x54)
    modrm_reg(amd, reg, rm)
end

function vandnpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x55)
    modrm_reg(amd, reg, rm)
end

function vorpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x56)
    modrm_reg(amd, reg, rm)
end

function vxorpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0x57)
    modrm_reg(amd, reg, rm)
end

function vcmpeqpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 0)
end

function vcmpltpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 1)
end

function vcmplepd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 2)
end

function vcmpunordpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 3)
end

function vcmpneqpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 4)
end

function vcmpnltpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 5)
end

function vcmpnlepd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 6)
end

function vcmpordpd(amd::Amd, reg::UInt8, vreg::UInt8, rm::UInt8)
    vex_pd(amd, reg, vreg, rm, 0)
    append_byte(amd, 0xC2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 7)
end

#******************* SSE scalar double ******************#
function movapd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_pd(amd, reg, rm)
    append_byte(amd, 0x28)
    modrm_reg(amd, reg, rm)
end

function movsd_xmm_mem(amd::Amd, reg::UInt8, rm::UInt8, offset)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0x10)
    modrm_mem(amd, reg, rm, offset)
end

function movsd_xmm_indexed(amd::Amd, reg::UInt8, base::UInt8, index::UInt8, scale::UInt8)
    sse_sd_index(amd, reg, base, index)
    append_byte(amd, 0x10)
    modrm_sib(amd, reg, base, index, scale)
end

function movsd_xmm_label(amd::Amd, reg::UInt8, label)
    sse_sd(amd, reg, 0)
    append_byte(amd, 0x10)
    # modr/m byte with MOD=00 and R/M=101 (RIP-relative address)
    append_byte(amd, 5 | ((reg & 7) << 3))
    jump(amd.a, label, 0)
end

function movsd_mem_xmm(amd::Amd, rm::UInt8, offset, reg::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0x11)
    modrm_mem(amd, reg, rm, offset)
end

function movsd_indexed_xmm(amd::Amd, base::UInt8, index::UInt8, scale::UInt8, reg::UInt8)
    self.sse_sd_index(reg, base, index)
    append_byte(amd, 0x11)
    modrm_sib(amd, reg, base, index, scale)
end

function addsd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0x58)
    modrm_reg(amd, reg, rm)
end

function subsd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0x5c)
    modrm_reg(amd, reg, rm)
end

function mulsd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0x59)
    modrm_reg(amd, reg, rm)
end

function divsd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0x5e)
    modrm_reg(amd, reg, rm)
end

function sqrtsd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0x51)
    modrm_reg(amd, reg, rm)
end

function roundsd(amd::Amd, reg::UInt8, rm::UInt8, mode)
    sse_pd(amd, reg, rm)
    append_bytes(amd, [0x3a, 0x0b])
    modrm_reg(amd, reg, rm)

    if mode == :round
        append_byte(amd, 0)
    elseif mode == :floor
        append_byte(amd, 1)
    elseif mode == :ceiling
        append_byte(amd, 2)
    elseif mode == :trunc
        append_byte(amd, 3)
    end
end

function cmpeqsd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 0)
end

function cmpltsd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 1)
end

function cmplesd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 2)
end

function cmpunordsd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 3)
end

function cmpneqsd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 4)
end

function cmpnltsd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 5)
end

function cmpnlesd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0xc2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 6)
end

function cmpordsd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_sd(amd, reg, rm)
    append_byte(amd, 0xC2)
    modrm_reg(amd, reg, rm)
    append_byte(amd, 7)
end

function ucomisd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_pd(amd, reg, rm)
    append_byte(amd, 0x2e)
    modrm_reg(amd, reg, rm)
end

function andpd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_pd(amd, reg, rm)
    append_byte(amd, 0x54)
    modrm_reg(amd, reg, rm)
end

function andnpd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_pd(amd, reg, rm)
    append_byte(amd, 0x55)
    modrm_reg(amd, reg, rm)
end

function orpd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_pd(amd, reg, rm)
    append_byte(amd, 0x56)
    modrm_reg(amd, reg, rm)
end

function xorpd(amd::Amd, reg::UInt8, rm::UInt8)
    sse_pd(amd, reg, rm)
    append_byte(amd, 0x57)
    modrm_reg(amd, reg, rm)
end

#*******************************************#
function vzeroupper(amd::Amd)
    append_bytes(amd, [0xC5, 0xF8, 0x77])
end

# general registers
function mov_reg_reg(amd::Amd, reg::UInt8, rm::UInt8)
    rex(amd, reg, rm)
    append_byte(amd, 0x8b)
    modrm_reg(amd, reg, rm)
end

function mov_reg_mem(amd::Amd, reg::UInt8, rm::UInt8, offset)
    rex(amd, reg, rm)
    append_byte(amd, 0x8b)
    modrm_mem(amd, reg, rm, offset)
end

function mov_reg_label(amd::Amd, reg::UInt8, label)
    rex(amd, reg, 0)
    append_byte(amd, 0x8b)
    # modr/m byte with MOD=00 and R/M=101 (RIP-relative address)
    append_byte(amd, 5 | ((reg & 7) << 3))
    jump(amd.a, label, 0)
end

function mov_mem_reg(amd::Amd, rm::UInt8, offset, reg::UInt8)
    rex(amd, reg, rm)
    append_byte(amd, 0x89)
    modrm_mem(amd, reg, rm, offset)
end

function movabs(amd::Amd, rm::UInt8, imm64)
    rex(amd, 0, rm)
    append_byte(amd, 0xb8 + (rm & 7))
    append_word(amd, imm64)
    append_word(amd, imm64 >> 32)
end

function call(amd::Amd, reg::UInt8)
    if reg < 8
        append_bytes(amd, [0xff, 0xd0 | reg])
    else
        append_bytes(amd, [0x41, 0xff, 0xd0 | (reg & 7)])
    end
end

function call_indirect(amd::Amd, label)
    append_bytes(amd, [0xff, 0x15])
    jump(amd.a, label, 0)
end

function push(amd::Amd, reg::UInt8)
    if reg < 8
        append_byte(amd, 0x50 | reg)
    else
        append_bytes(amd, [0x41, 0x50 | (reg & 7)])
    end
end

function pop(amd::Amd, reg::UInt8)
    if reg < 8
        append_byte(amd, 0x58 | reg)
    else
        append_bytes(amd, [0x41, 0x58 | (reg & 7)])
    end
end

function ret(amd::Amd)
    append_byte(amd, 0xc3)
end

function add_rsp(amd::Amd, imm)
    append_bytes(amd, [0x48, 0x81, 0xc4])
    append_word(amd, imm)
end

function sub_rsp(amd::Amd, imm)
    append_bytes(amd, [0x48, 0x81, 0xec])
    append_word(amd, imm)
end

function or(amd::Amd, reg::UInt8, rm::UInt8)
    rex(amd, reg, rm)
    append_byte(amd, 0x0b)
    modrm_reg(amd, reg, rm)
end

function xor(amd::Amd, reg::UInt8, rm::UInt8)
    rex(amd, reg, rm)
    append_byte(amd, 0x33)
    modrm_reg(amd, reg, rm)
end

function add(amd::Amd, reg::UInt8, rm::UInt8)
    rex(amd, reg, rm)
    append_byte(amd, 0x03)
    modrm_reg(amd, reg, rm)
end

function add_imm(amd::Amd, rm::UInt8, imm)
    rex(amd, 0, rm)
    append_byte(amd, 0x81)
    modrm_reg(amd, 0, rm)
    append_word(amd, imm)
end

function inc(amd::Amd, rm::UInt8)
    rex(amd, 0, rm)
    append_byte(amd, 0xff)
    modrm_reg(amd, 0, rm)
end

function dec(amd::Amd, rm::UInt8)
    rex(amd, 0, rm)
    append_byte(amd, 0xff)
    modrm_reg(amd, 1, rm)
end

function jmp(amd::Amd, label)
    append_byte(amd, 0xe9)
    jump(amd.a, label, 0)
end

function jz(amd::Amd, label)
    append_bytes(amd, [0x0f, 0x84])
    jump(amd.a, label, 0)
end

function jnz(amd::Amd, label)
    append_bytes(amd, [0x0f, 0x85])
    jump(amd.a, label, 0)
end

function jpe(amd::Amd, label)
    # jump if parity even is true if vucomisd returns
    # an unordered result
    append_bytes(amd, [0x0f, 0x8a])
    jump(amd.a, label, 0)
end

function nop(amd::Amd)
    append_byte(amd, 0x90)
end
