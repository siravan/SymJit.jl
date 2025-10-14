
mutable struct Mat
    handle::Ptr{Cvoid}
    vecs::Array{Ptr{Cdouble}}       
end

function Mat()
    # handle = ccall((:create_matrix, libpath), Ptr{Cvoid}, ())
    handle = @ccall libpath.create_matrix()::Ptr{Cvoid}
    mat = Mat(handle, Array{Ptr{Cdouble}}[])

    finalizer(mat) do x
        ccall((:finalize_matrix, libpath), Cvoid, (Ptr{Cvoid},), mat.handle)
    end

    return mat
end

function create_matrix(X)
    nrows, ncols = size(X)
    mat = Mat()

    for col = 1:ncols
        ptr = pointer(X, 1 + (col-1)*nrows)
        # ccall((:add_row, libpath), Cvoid, (Ptr{Cvoid}, Ptr{Cdouble}, Cint), mat.handle, ptr, nrows)
        @ccall libpath.add_row(mat.handle::Ptr{Cvoid}, ptr::Ptr{Cdouble}, nrows::Cint)::Cvoid
    end

    return mat
end
