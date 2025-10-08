# using Pkg.Artifacts
# ensure_artifact_installed("symjit", joinpath(@__DIR__, "..", "Artifacts.toml"))
# libpath = readdir(artifact"symjit"; join=true)[1]

using Tar, CodecZlib

function extract_lib(tarball, libname)
    libdir = joinpath(@__DIR__, "lib")
    libpath = joinpath(libdir, libname)

    if !isfile(libpath)
        open(GzipDecompressorStream, joinpath(joinpath(@__DIR__, "artifacts", tarball))) do io
            Tar.extract(io, libdir)
        end
    end

    if !isfile(libpath)
        error("SymJit.jl: dynamic library not found")
    end

    return libpath
end

@static if Sys.isapple() && Sys.ARCH == :x86_64
    libpath = extract_lib("symjit_osx-64.tar.gz", "_lib.cpython-314-darwin.so")
elseif Sys.isapple() && Sys.ARCH == :aarch64
    libpath = extract_lib("symjit_osx-arm64.tar.gz", "_lib.cpython-314-darwin.so")
elseif Sys.iswindows() && Sys.ARCH == :x86_64
    libpath = extract_lib("symjit_win-64.tar.gz", "_lib.cp314-win_amd64.pyd")
elseif Sys.isunix() && Sys.ARCH == :x86_64
    libpath = extract_lib("symjit_linux-64.tar.gz", "_lib.cpython-314-x86_64-linux-gnu.so")
else
    error("SymJit.jl: unsupported platform")
end
