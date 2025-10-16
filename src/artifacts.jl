using Pkg.Artifacts

ensure_artifact_installed(
    "symjit",
    joinpath(@__DIR__, "..", "Artifacts.toml");
    io = devnull,
)
libpath = readdir(artifact"symjit"; join = true)[1]

@static if Sys.iswindows()
    # long story...see https://github.com/JuliaLang/julia/issues/52272
    chmod(libpath, 0o755)
end
