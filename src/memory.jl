using Mmap

const PAGESIZE = 4096

struct MachineCode
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

else

const MEM_COMMIT = 0x00001000
const MEM_RESERVE = 0x00002000
const PAGE_EXECUTE_READWRITE = 0x00000040
const MEM_RELEASE = 0x00008000

function create_executable_memory(code::Vector{UInt8})::MachineCode
    size = ceil(Int, length(code) / PAGESIZE) * PAGESIZE

    func = ccall(:VirtualAlloc,
        Ptr{Cvoid},
        (Ptr{Cvoid}, Csize_t, Cuint, Cuint),
        C_NULL,
        size,
        MEM_COMMIT | MEM_RESERVE,
        PAGE_EXECUTE_READWRITE
    )

    mem = unsafe_wrap(Array{UInt8}, func, (size,))
    mem[1:length(func)] .= code

    mc = MachineCode(mem, func)

    finalizer(mc) do x
        ccall(:VirtualFree,
            Cuchar,
            (Ptr{CVoid}, Csize_t, Cuint),
            x.func,
            0,
            MEM_RELEASE
        )
    end

    return mc
end

end

function call(machine::MachineCode, x::Float64, y::Float64)
    f = machine.func
    return @ccall $f(x::Float64, y::Float64)::Cdouble
end

function call(machine::MachineCode, mem::Vector{Float64}, params::Vector{Float64})
    f = machine.func
    p = Base.unsafe_convert(Ptr{Cdouble}, mem)
    q = Base.unsafe_convert(Ptr{Cdouble}, params)
    @ccall $f(p::Ptr{Cdouble}, C_NULL::Ptr{Cdouble}, 0::Clong, q::Ptr{Cdouble})::Cdouble
end

##################################################################

@static if Sys.ARCH == :x86_64
# f = compile_func([x, y], x*y)
code =  "55534881ec88000000488becf2480f114500f2480f114d08c5fb105" *
        "d00c5fb105508c5e359dac5fb115d18c5f877f2480f104424184881" *
        "c4880000005b5dc3900000000000000080000000000000f03ffffff" *
        "fffffffffff"

elseif Sys.ARCH == :aarch64
code =  ""
else
    @error "unsupported CPU architecture"
end

function bytes(s)
    return parse.(UInt8, [s[i:i+1] for i=1:2:length(s)], base=16)
end

function test()
    func = create_executable_memory(bytes(code))
    println(call(func, 2.0, 3.0))
end
