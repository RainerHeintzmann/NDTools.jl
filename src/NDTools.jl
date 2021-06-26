module NDTools
using Base.Iterators, PaddedViews, LinearAlgebra, IndexFunArrays
export collect_dim, selectdim, select_sizes, expand_add, expand_size, expand_dims, 
       apply_tuple_list, reorient, select_region, single_dim_size
export get_complex_datatype, center_position, center_value, pack
export soft_theta, exp_decay, multi_exp_decay, soft_delta, radial_mean, linear_index, Δ_phase

const IterType = Union{NTuple{N,Tuple} where N, Vector, Matrix, Base.Iterators.Repeated}

# Functions from ROIViews:

"""
    expand_add(t1,t2)  # adds t1 to t2 as a tuple and returns t2[n] for n > length(t1)
adds the elements of the tuple t1 to t2 for components in t1 which exist for the rest just t2 is used.
```jldoctest
julia> expand_add((1,2,3),(4,5,6,7,8,9))
(5, 7, 9, 7, 8, 9)
```
"""
function expand_add(t1,t2)  # adds t1 to t2 as a tuple and returns t2[n] for n > length(t1)
    ((t+w for (t,w) in zip(t1,t2))..., (w for w in t2[length(t1)+1:end])...)
    # ((t+w for (t,w) in zip(t1,t2))...,t2[length(t1)+1:end]...)
end

"""
    expand_size(sz,sz2)
    expands a size tuple sz with the sizes as given in the tuple sz2 for positions which do not exist in sz. Typically one wants to
    obtain a tuple, which is achieved by a wrapping cast: `Tuple(expand_size(sz,sz2))`
```jldoctest
julia> sz = expand_size((1,2,3),(4,5,6,7,8,9))
Base.Generator{UnitRange{Int64}, var"#7#8"{Tuple{Int64, Int64, Int64}, NTuple{6, Int64}, Int64}}(var"#7#8"{Tuple{Int64, Int64, Int64}, NTuple{6, Int64}, Int64}((1, 2, 3), (4, 5, 6, 7, 8, 9), 3), 1:6)

julia> Tuple(sz)
(1, 2, 3, 7, 8, 9)
```
"""
function expand_size(sz,sz2)
    dims1 = length(sz)
    dims2 = length(sz2)
    ((d<=dims1) ? sz[d] : sz2[d] for d in 1:dims2)
end

# Functions from IndexFunArrays:

"""
    optional_posZ(x, offset)
returns a z position `posZ = x[3]-offset[3]` if the tuple is long enough and `posZ=1` otherwise.
This is useful for 3d routines, which should also work for 2d data.
```jldoctest
julia> optional_posZ((5,5),(2,3))
1

julia> optional_posZ((5,5,5),(3,2,1))
4
```
"""
optional_posZ(x::NTuple{1,T}, offset::NTuple{1,T}) where {T,N} = 1
optional_posZ(x::NTuple{2,T}, offset::NTuple{2,T}) where {T,N} = 1
optional_posZ(x::NTuple{N,T}, offset::NTuple{N,T}) where {T,N} = x[3]-offset[3]

"""
    curry(f, x) = (xs...) -> f(x, xs...)   # just a shorthand to remove x
allows to remove the fix the first argument x in a function f with any number of arguments
```jldoctest
julia> g = curry(+,10.0)
#9 (generic function with 1 method)

julia> g(3)
13.0
```
"""
curry(f, x) = (xs...) -> f(x, xs...)   # just a shorthand to remove x

## These functions ensure that also numbers can be iterated and zipped
"""
    cast_iter(vals::Matrix)
    a conveniance function used to make number itarable via repeated. This is used when dealing with multiple arguments where one can be optionally an iterable.
    A Tuple is also interpreted as repeating this tuple over and over.
"""
function cast_iter(vals::Matrix)
    Tuple(Tuple(vals[:,n]) for n in 1:size(vals,2))
    # Tuple(vals[:,axes(vals, 2)])
end

function cast_iter(vals::Vector{<:Number})
    Tuple(vals)   # makes the matrix iterable, interpreting it as a series of vectors
end

function cast_iter(vals::IterType)
    vals
end

function cast_iter(vals)
    repeated(vals) # during the zip operation this type always yields the same value
end

"""
    cast_number_iter(vals::Matrix)
    a conveniance function used to make number itarable via repeated. This is used when dealing with multiple arguments where one can be optionally an iterable.
    The behavious is slightly different to cast_iter when it comes to Tuples
    A Tuple is here iterated as a list of numbers.
"""
function cast_number_iter(vals::Vector{<:Number})
    Tuple(vals)   # makes the matrix iterable, interpreting it as a series of vectors
end

function cast_number_iter(vals::NTuple{N,<:Number} where N)
    vals
end

function cast_number_iter(vals::Number)
    repeated(vals) # during the zip operation this type always yields the same value
end

"""
    optional_mat_to_iter(vals)  # only for matrices
    casts a matrix via cast_iter, all other types are unaffected
"""
function optional_mat_to_iter(vals)  # only for matrices
    vals
end

function optional_mat_to_iter(vals::Matrix)
    cast_iter(vals)
end

"""
    mat_to_tvec(v) 
    converts a 2d matrix to a Vector of Tuples
#Example:
```jldoctest
julia> NDTools.mat_to_tvec([1 3 5; 2 4 6])
3-element Vector{Tuple{Int64, Int64}}:
 (1, 2)
 (3, 4)
 (5, 6)
```
"""
mat_to_tvec(v) = [Tuple(v[:,n]) for n in 1:size(v,2)] # converts a 2d matrix to a Vector of Tuples

"""
    apply_dims(scale, dims, N)
    replaces scale entries not in dims with zeros. Can also be applied to an Iterable of Tuples
#Arguments:
+ scale: Vector to pass its valid entries through 
+ dims: Tuple of valid dimensions
+ N: total length of the resulting  `NTuple`
#Exmample:
```jldoctest
julia> NDTools.apply_dims((1,2,3),(1,2), 4)
(1, 2, 0, 0)
```
"""
function apply_dims(scale, dims, N)  # replaces scale entries not in dims with zeros
    ntuple(i -> i ∈ dims ? scale[i] : zero(eltype(scale)), N)
end

function apply_dims(scales::IterType, dims, N)  # replaces scale entries not in dims with zeros
    Tuple(ntuple(i -> i ∈ dims ? scale[i] : zero(eltype(scale)), N)  for scale in  scales)
end

# Functions for IndexFunArrays.utils

"""
    single_dim_size(dim::Int,dim_size::Int, tdim=dim)

Returns a tuple (length `tdim`, which by default is dim) of singleton sizes except at the final position `dim`, which contains `dim_size`
#Arguments:
+ dim: non-zero position
+ dim_size: the value this non-zero position is given in the returned NTuple
+ tdim: total length of the returned NTuple

# Example
```jldoctest
julia> single_dim_size(4, 3)
(1, 1, 1, 3)

julia> single_dim_size(4, 5)
(1, 1, 1, 5)

julia> single_dim_size(2, 5)
(1, 5)
```
"""
function single_dim_size(dim::Int,dim_size::Int,tdim=dim)
    Base.setindex(Tuple(ones(Int, tdim)),dim_size,dim)
end

"""
    reorient(vec, dim)
reorients a 1D vector `vec` along dimension `dim`.
"""
function reorient(vec, dim::Int)
    reshape(vec, single_dim_size(dim, length(vec)))
end

"""
    collect_dim(col, dim::Int)
 collects a collection `col` and reorients it into direction `dim`.
 #Example:
 ```jldoctest
julia> collect_dim(1:5,2)
1×5 Matrix{Int64}:
 1  2  3  4  5
```
"""
function collect_dim(col, dim::Int)
    reorient(collect(col), dim)
end

"""
    linear_index(pos, sz)
    converts a tuble (pos) to a linear index using the size (sz).

# Example:
```doctest
julia> a = rand(10,10,10);

julia> linear_index((3,4,5), (10,10,10))
433

julia> a[3,4,5]  == a[433]
true
```
"""
function linear_index(pos, sz)
    factors = (1, cumprod(sz[1:end-1])...)
    sum((pos.-1) .* factors)+1
end

# These are the type promotion rules, taken from float.jl but written in terms of types
# see also 
promote_type()
default_type(::Type{Bool}, def_T)    = def_T
default_type(::Type{Int8}, def_T)    = def_T
default_type(::Type{Int16}, def_T)   = def_T
default_type(::Type{Int32}, def_T)   = def_T
default_type(::Type{Int64}, def_T)   = def_T # LOSSY
default_type(::Type{Int128}, def_T)  = def_T # LOSSY
default_type(::Type{UInt8}, def_T)   = def_T
default_type(::Type{UInt16}, def_T)  = def_T
default_type(::Type{UInt32}, def_T)  = def_T
default_type(::Type{UInt64}, def_T)  = def_T # LOSSY
default_type(::Type{UInt128}, def_T) = def_T # LOSSY
default_type(::Type{T}, def_T) where{T} = T # all other types remain to be the same

# Functions from scaling_offset_types in IndexFunArrays

"""
    apply_tuple_list(f, t1,t2)
    applies a two-argument function to tubles and iterables of tuples, if either of the arguments `t1` or `t2` is an Iterable
"""
function apply_tuple_list(f, t1, t2)  # applies a two-argument function to tubles and iterables of tuples
    return f(t1,t2)
end

function apply_tuple_list(f, t1, t2::IterType)
    return Tuple([f(t1,a2) for a2 in t2])
end

function apply_tuple_list(f, t1::IterType, t2)
    res= Tuple([f(a1,t2) for a1 in t1])
    return res
end

function apply_tuple_list(f, t1::IterType, t2::IterType)
    return Tuple([f(a[1],a[2]) for a in zip(t1,t2)])
end


## Functions from FourierTools utils:

"""
    select_sizes(x::AbstractArray, dim; keep_dims=true)

Additional size method to access the size at several dimensions
in one call.
`keep_dims` allows to return the other dimensions as singletons.

# Examples
```jldoctest
julia> x = ones((2,4,6,8, 10));

julia> select_sizes(x, (2,3))
(1, 4, 6, 1, 1)

julia> select_sizes(x, 5)
(1, 1, 1, 1, 10)

julia> select_sizes(x, (5,))
(1, 1, 1, 1, 10)

julia> select_sizes(x, (2,3,4), keep_dims=false)
(4, 6, 8)

julia> select_sizes(x, (4,3,2), keep_dims=false)
(8, 6, 4)
```

"""
function select_sizes(x::AbstractArray{T},dim::NTuple{N,Int};
                    keep_dims=true) where{T,N}
    if ~keep_dims
        return map(n->size(x,n),dim)
    end
    sz = ones(Int, ndims(x))
    for n in dim
        sz[n] = size(x,n) 
    end
    return Tuple(sz)
end 

function select_sizes(x::AbstractArray, dim::Integer; keep_dims=true)
    select_sizes(x, Tuple(dim), keep_dims=keep_dims)
end


"""
    slice(arr, dim, index)
Return a `N` dimensional slice (where one dimensions has size 1) of the N-dimensional `arr` at the index position
`index` in the `dim` dimension of the array.
It holds `size(out)[dim] == 1`.
# Examples
```jldoctest
julia> x = [1 2 3; 4 5 6; 7 8 9]
3×3 Matrix{Int64}:
 1  2  3
 4  5  6
 7  8  9

julia> FourierTools.slice(x, 1, 1)
1×3 view(::Matrix{Int64}, 1:1, 1:3) with eltype Int64:
 1  2  3
```
"""
function slice(arr::AbstractArray{T, N}, dim::Integer, index::Integer) where {T, N}
    inds = slice_indices(axes(arr), dim, index)
    return @view arr[inds...]
end

"""
    slice_indices(a, dim, index)

`a` should be the axes obtained by `axes(arr)` of an array.
`dim` is the dimension to be selected and `index` the index of it.

# Examples
```jldoctest
julia> FourierTools.slice_indices((1:10, 1:20, 1:12, 1:33), 1, 3)
(3:3, 1:20, 1:12, 1:33)
```
"""
function slice_indices(a::NTuple{N, T}, dim::Integer, index::Integer) where {T, N}
    inds = ntuple(i -> i == dim ? (a[i][index]:a[i][index])
                                : (first(a[i]):last(a[i])), 
                  Val(N))
    return inds
end

"""
    expand_dims(x, ::Val{N})
    expand_dims(x, N::Number)

expands the dimensions of an array to a given number of dimensions.

Try to prefer the `Val` version because this is type-stable.
`Val(N)` encapsulates the number in a type from which the compiler
can then infer the return type.

# Examples
The result is a 5D array with singleton dimensions at the end
```jldoctest
julia> expand_dims(ones((1,2,3)), Val(5))
1×2×3×1×1 Array{Float64, 5}:
[:, :, 1, 1, 1] =
 1.0  1.0

[:, :, 2, 1, 1] =
 1.0  1.0

[:, :, 3, 1, 1] =
 1.0  1.0

julia> expand_dims(ones((1,2,3)), 5)
1×2×3×1×1 Array{Float64, 5}:
[:, :, 1, 1, 1] =
 1.0  1.0

[:, :, 2, 1, 1] =
 1.0  1.0

[:, :, 3, 1, 1] =
 1.0  1.0
```
"""
function expand_dims(x, N::Number)
    return reshape(x, (size(x)..., ntuple(x -> 1, (N - ndims(x)))...))
end

function expand_dims(x, ::Val{N}) where N
    return reshape(x, (size(x)..., ntuple(x -> 1, (N - ndims(x)))...))
end

"""
    center_position(field)
    position of the center of the `field` according to the Fourier-space nomenclature (pixel right of center for even-sized arrays).
    returns a tuple of ints which can be used for indexing.
"""
function center_position(field)
    (size(field) .÷ 2).+1
end

"""
    center_value(field)
    value of the `field` at the position of the center of the `field` according to the Fourier-space nomenclature (pixel right of center for even-sized arrays).
"""
function center_value(field)
    field[center_position(field)...]
end

"""
    ft_center_diff(s [, dims])

Calculates how much each dimension must be shifted that the
center frequency is at the Fourier center.
This if for a normal `fft`
"""
function ft_center_diff(s::NTuple{N, T}, dims=ntuple(identity, Val(N))) where {N, T}
    ntuple(i -> i ∈ dims ?  s[i] ÷ 2 : 0 , N)
end


"""
    select_region(mat;new_size=size(mat), center=ft_center_diff(size(mat)).+1, pad_value=zero(eltype(mat)))

    selects (extracts) a region of interest (ROI), defined by `new_size` and centered at `center` in the source image. Note that
    the number of dimensions can be smaller in `new_size` and `center`, in which case the default values will be insterted
    into the missing dimensions. `new_size` does not need to fit into the source array and missing values will be replaced with `pad_value`.

+ `new_size`. The size of the array view after the operation finished. By default the original size is assumed

+ `center`. Specifies the center of the new view in coordinates of the old view. By default an alignment of the Fourier-centers is assumed.

+ `pad_value`. Specifies the value which is inserted in case the ROI extends to outside the source area.

The returned results is a mutable view, which allows this method to also be used for writing into a ROI

# Examples
```jldoctest
julia> using NDTools

julia> select_region(ones(3,3),new_size=(7,7),center=(1,3))
7×7 PaddedView(0.0, OffsetArray(::Matrix{Float64}, 4:6, 2:4), (Base.OneTo(7), Base.OneTo(7))) with eltype Float64:
 0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  1.0  1.0  1.0  0.0  0.0  0.0
 0.0  1.0  1.0  1.0  0.0  0.0  0.0
 0.0  1.0  1.0  1.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0
```
"""
function select_region(mat; new_size=size(mat), center=ft_center_diff(size(mat)).+1, pad_value=zero(eltype(mat)))
    new_size = Tuple(expand_size(new_size, size(mat)))
    center = Tuple(expand_size(center, ft_center_diff(size(mat)).+1))
    oldcenter = ft_center_diff(new_size).+1
    MutablePaddedView(PaddedView(pad_value, mat,new_size, oldcenter .- center.+1));
end

struct MutablePaddedView{T,N,I,A} <: AbstractArray{T,N}
    data::PaddedView{T,N,I,A}
end

Base.size(A::MutablePaddedView) = size(A.data)
# Base.ndims(A::MutablePaddedView) = ndims(A.data)

# The change below makes select_region into a writable region
Base.@propagate_inbounds function Base.setindex!(A::MutablePaddedView{T,N}, v, pos::Vararg{Int,N}) where {T,N}
    @boundscheck checkbounds(A.data, pos...)
    if Base.checkbounds(Bool, A.data.data, pos...)
        return setindex!(A.data.data, v, pos... )
    else
        return A.data.fillvalue
    end
end

Base.@propagate_inbounds function Base.getindex(A::MutablePaddedView{T,N}, pos::Vararg{Int,N}) where {T,N}
    getindex(A.data, pos...)
end

"""
    get_complex_datatype(x)
    returns the complex-valued datatyp which encompasses the eltype
Examples:
```jdoctest
julia> get_complex_datatype([1f0,2f0,3f0])
ComplexF32 (alias for Complex{Float32})

julia> get_complex_datatype(22.2)
ComplexF64 (alias for Complex{Float64})
```
"""
get_complex_datatype(x :: Number) = Complex{typeof(x)}
get_complex_datatype(x :: Complex ) = typeof(x)
get_complex_datatype(x :: AbstractArray) = get_complex_datatype(eltype(x)(0))


"""
    pack(myTuple::Tuple, do_fit)
    this packs a tuple of values into a vector which is normalized per direction and returns an unpack function which reverts this.
    This tool is useful for fit routines.

returns the packed tuples (with a position being true in do_fit) as a vector and the unpack algorithm as a closure.
"""
function pack(myTuple::Tuple, do_fit; rel_scale=nothing, dtype=Float64)
    scales = []
    vec = dtype[]
    lengths = Int[]
    for (t,f) in zip(myTuple,do_fit)
        if !isnothing(rel_scale)
            scale = sum(t)/length(t) .* rel_scale
        else
            scale = 1.0
        end
        if f
            push!(scales, scale)
            vec = cat(vec, t ./ scale, dims=1)
            push!(lengths, length(t))
        else # save the constant
            push!(scales, t)
            push!(lengths, length(t))
        end
    end

    function unpack(vec)
        res = ()
        pos = 1
        for (l,s,f) in zip(lengths,scales, do_fit)
            if f
                vals = vec[pos:pos+l-1] .* s
                pos += l
            else
                vals = s
            end
            res = (res..., vals)
        end
        return res
    end
    
    return Vector{Float64}(vec), unpack # Vector{Int}(lengths), Vector{Float64}(scales) 
end

"""
    soft_theta(val, eps=0.1) = (val .> eps) ? 1.0 : ((val .< -eps) ? 0.0 : (1.0 .- cos((val .+ eps).*(pi/(2*eps))))./2) # to make the threshold differentiable
    this is a version of the theta function that uses a soft transition and is differentialble.
val: value to compare with zero
eps: hardness of the step function (spanning from -eps to eps)
"""
soft_theta(val, eps=0.01) = (val .> eps) ? 1.0 : ((val .< -eps) ? 0.0 : (1.0 .- cos.((val .+ eps).*(pi/(2*eps))))./2.0) # to make the threshold differentiable

"""
    soft_delta(val, eps=0.1) = (val .> eps) ? 1.0 : ((val .< -eps) ? 0.0 : (1.0 .- cos((val .+ eps).*(pi/(2*eps))))./2) # to make the threshold differentiable
    this is a smooth version of the theta function that uses a soft peak and is differentialble.
    The sum is not normalized but the value at val is one.
val: value to compare with zero
eps: hardness of the step function (spanning from -eps to eps)
"""
soft_delta(val, eps=0.01) = (abs2.(val) .> abs2.(eps)) ? 0.0 : (1.0 .+ cos.(val.*(pi/eps)))./2.0 # to make the threshold differentiable

"""
    exp_decay(t,τ, eps=0.1) 
    an exponential decay starting at zero and using a soft threshold.
    Note that this function can be applied to multiple decay times τ simulataneously, yielding multiple decays stacked along the second dimension
"""
exp_decay(t,τ, eps=0.01) = soft_theta.(t,eps) .* exp.( - (t ./ transpose(τ)))


"""
    multi_exp_decay(t,amps, τs, eps=0.1) 
    a sum of exponential decays starting at t==zero and using a soft threshold.
t: time series to apply this to
amps: individual amplitudes as a vector
τs : individual lifetimes as a vector
eps: width of the soft edge
"""
multi_exp_decay(t, amps, τs, eps=0.01) = sum(transpose(amps).*exp_decay(t, τs, eps), dims=2)[:,1] 

"""
    radial_mean(data; maxbin=nothing, bin_step=nothing, pixelsize=nothing)
calculates the radial mean of a dataset `data`.
returns a tuple of the radial_mean and the bin_centers.
Arguments:
data: data to radially average
maxbin: a maximum bin value
bin_step: 
"""
function radial_mean(data; nbins=nothing, bin_step=nothing, offset=CtrFT, scale=nothing)
    if isnothing(scale)
        scale=Tuple(ones(Int,ndims(data)))
    end
    if isnothing(bin_step)
        bin_step=maximum(scale)
    end
    
    idx = round.(Int, rr(size(data), offset=offset, scale=scale./bin_step)) .+ 1
    if isnothing(nbins)
        nbins = maximum(idx)
    else
        idx[idx.>nbins] .= nbins
    end

    bincenters = bin_step .* collect(0.5:nbins-0.5)

    myevents = zeros(Float64, nbins)
    mysum = zeros(Float64, nbins)
    idxlist = idx[:]
    v = @view mysum[idxlist]
    v .+= data[:]
    v = @view myevents[idxlist]
    v .+= 1
    myevents[myevents .== 0] .= 1
    return mysum ./ myevents, bincenters
end

"""
    Δ_phase(arr, dim)
    calculates the relative phase slope along dimension `dim` of a non-zero array `arr` without wrap-around problems.
#Argument:
#Example:
+ arr: array of which to evaluate the phase slope
+ dim: dimension along which to evaluate the slope
#Example:
```jdoctest

```
"""
function Δ_phase(arr, dim)
    no_shift = ((n==dim) ? (1:size(arr,dim)-1) : (:) for n in 1:ndims(arr))
    shift = ((n==dim) ? (2:size(arr,dim)) : (:) for n in 1:ndims(arr))
    return angle.(arr[no_shift...] ./ arr[shift...]) # this is a complex-valued division to obtain the relative phase angle!
end

end # module
