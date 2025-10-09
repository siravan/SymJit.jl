using Mmap

const PAGESIZE = 4096

# MachineCode is defined as mutable to allow for passing to finalizer
mutable struct MachineCode
    mem::Array{UInt8}
    func::Ptr{Cvoid}
end

@static if Sys.isunix()

const PROT_READ = 1
const PROT_WRITE = 2
const PROT_EXEC = 4

function create_executable_memory(code::Vector{UInt8})::MachineCode
    size = ceil(Int, length(code) / PAGESIZE) * PAGESIZE
    mem = Mmap.mmap(Mmap.Anonymous(), Vector{UInt8}, (size,), 0)
    mem[1:length(code)] .= code

    ret = ccall(:mprotect, Cint, (Ptr{Cvoid}, Csize_t, Cint), mem, size, PROT_READ | PROT_EXEC)
    if ret != 0
        error("cannot change memory to executable")
    end

    func = Base.unsafe_convert(Ptr{Cvoid}, mem)

    return MachineCode(mem, func)
end

elseif Sys.iswindows()

const MEM_COMMIT = 0x00001000
const MEM_RESERVE = 0x00002000
const PAGE_EXECUTE_READWRITE = 0x00000040
const MEM_RELEASE = 0x00008000

function create_executable_memory(code::Vector{UInt8})::MachineCode
    size = ceil(Int, length(code) / PAGESIZE) * PAGESIZE

    func = ccall(:VirtualAlloc,
        Ptr{Cuchar},
        (Ptr{Cvoid}, Csize_t, Cuint, Cuint),
        C_NULL,
        size,
        MEM_COMMIT | MEM_RESERVE,
        PAGE_EXECUTE_READWRITE
    )

    mem = unsafe_wrap(Array{UInt8}, func, (size,))
    mem[1:length(code)] .= code

    mc = MachineCode(mem, func)

    finalizer(mc) do x
        ccall(:VirtualFree,
            Cuchar,
            (Ptr{Cvoid}, Csize_t, Cuint),
            x.func,
            0,
            MEM_RELEASE
        )
    end

    return mc
end

else    # not unix and not windows
    error("unsupported OS")
end

function call(machine::MachineCode, x::Float64, y::Float64)
    f = machine.func
    return @ccall $f(x::Float64, y::Float64)::Cdouble
end

function call(machine::MachineCode, mem::Vector{Float64}, params::Vector{Float64})
    f = machine.func
    p = Base.unsafe_convert(Ptr{Cdouble}, mem)
    q = Base.unsafe_convert(Ptr{Cdouble}, params)
    @ccall $f(p::Ptr{Cdouble}, C_NULL::Ptr{Cdouble}, 0::Clong, q::Ptr{Cdouble})::Cint
end
