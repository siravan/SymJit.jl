
mutable struct Matrix
    handle::Ptr{Cvoid}
    vecs::Array{Ptr{Cdouble}}       
end

function Matrix()
    handle = ccall((:create_matrix, libpath), Ptr{Cvoid}, ())
    return Matrix(handle, Array{Ptr{Cdouble}}[])
end

function create_matrix(X)
    nrows, ncols = size(X)
    mat = Matrix()

    for col = 1:ncols
        ptr = pointer(X, 1 + (col-1)*nrows)
        ccall((:add_row, libpath), Cvoid, (Ptr{Cvoid}, Ptr{Cdouble}, Cint), mat.handle, ptr, nrows)
    end

    return mat
end
