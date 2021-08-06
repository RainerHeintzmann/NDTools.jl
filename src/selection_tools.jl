## selection_tools.jl
export selectdim, expand_dims, select_region_view, select_region, select_region!, flatten_trailing_dims
export assign_to!, add_to!, sub_to!, mul_to!, div_to!

"""
    slice(arr, dim, index)

Return a `N` dimensional slice (where one dimensions has size 1) of the N-dimensional `arr` at the index position
`index` in the `dim` dimension of the array.
It holds `size(out)[dim] == 1`.

Examples
```jldoctest
julia> x = [1 2 3; 4 5 6; 7 8 9]
3×3 Matrix{Int64}:
 1  2  3
 4  5  6
 7  8  9

julia> NDTools.slice(x, 1, 1)
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

Arguments:
`a` should be the axes obtained by `axes(arr)` of an array.
`dim` is the dimension to be selected and `index` the index of it.

Examples
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

Examples
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
    flatten_trailing_dims(arr, max_dim=length(arr)÷2+1)

flattens (squeezes) the trailing dims. `max_dim` denotes the last dimension to keep. The implementation
uses reshape and thus returns a modified view of the array referring to the same data. 
By default max_dim is adjusted such that a 2N array is squeezed into an N+1 array as needed for a scan.
"""
function flatten_trailing_dims(arr, max_dim)
    reshape(arr,(size(arr)[1:max_dim-1]...,prod(size(arr)[max_dim:end])))
end

"""
    select_region_view(src; new_size=size(src), center=ft_center_diff(size(src)).+1, pad_value=zero(eltype(src)))

selects (extracts) a region of interest (ROI), defined by `new_size` and centered at `center` in the source image. Note that
the number of dimensions can be smaller in `new_size` and `center`, in which case the default values will be insterted
into the missing dimensions. `new_size` does not need to fit into the source array and missing values will be replaced with `pad_value`.

Arguments:
+ `src`. The source array to select from.
+ `new_size`. The size of the array view after the operation finished. By default the original size is assumed
+ `center`. Specifies the center of the new view in coordinates of the old view. By default an alignment of the Fourier-centers is assumed.
+ `pad_value`. Specifies the value which is inserted in case the ROI extends to outside the source area.

The returned results is a mutable view, which allows this method to also be used for writing into a ROI

See also
+ select_region(src; new_size=size(src), center=ft_center_diff(size(src)).+1, pad_value=zero(eltype(src)))

Examples
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
function select_region_view(src::Array{T,N}; new_size=size(src), center=ft_center_diff(size(src)).+1, pad_value=zero(eltype(src))) where {T,N}
    new_size = Tuple(expand_size(new_size, size(src)))
    center = Tuple(expand_size(center, ft_center_diff(size(src)).+1))
    oldcenter = ft_center_diff(new_size).+1
    MutablePaddedView(PaddedView(pad_value, src,new_size, oldcenter .- center.+1)) :: MutablePaddedView{T, N, NTuple{N,Base.OneTo{Int64}}, OffsetArrays.OffsetArray{T, N, Array{T, N}}} 
end

"""
    get_src_dst_range(src_size, dst_size, new_size, center)

A helpfer function to calculate the index ranges to copy from source size `src_size` to destination size `dst_size` with the
integer center position of the destination aligning with the position in the source as specified by center.
"""
function get_src_dst_range(src_size, dst_size, new_size, src_center, dst_ctr=dst_size .÷2 .+1)
    ROI_center = (new_size.÷2 .+1)
    src_start = src_center .- ROI_center  .+1 # start of the first pixel to copy (without clipping)
    src_end = src_start .+ new_size .- 1 # the last pixel to copy
    src_start_clip = max.(1, src_start)
    src_end_clip = min.(src_end, src_size)
    if any(src_start_clip .> src_size) || any(src_end_clip .< 1)
        return (1:0), (1:0)
    end
    extra_src_start = max.(0, src_start_clip .- src_start)
    extra_src_end = max.(0, src_end .- src_end_clip)
    copy_size = new_size .- extra_src_start .- extra_src_end

    dst_start = dst_ctr .- ROI_center .+1 .+ extra_src_start
    dst_end = dst_start .+ copy_size .- 1
    dst_end_clip = min.(dst_end, dst_size)
    dst_start_clip = max.(1, dst_start)
    if any(dst_start_clip .> dst_size) || any(dst_end_clip .< 1)
        return (1:0), (1:0)  # returns an empty range for all coordinates
    end

    extra_dst_start = max.(0, dst_start_clip .- dst_start)
    extra_dst_end = max.(0, dst_end .- dst_end_clip)
    src_start_clip = src_start_clip .+ extra_dst_start
    src_end_clip = max.(0, src_end_clip .- extra_dst_end)

    range_src = Tuple((src_start_clip[d]:src_end_clip[d]) for d in 1:length(src_start))
    range_dst = Tuple((dst_start_clip[d]:dst_end_clip[d]) for d in 1:length(dst_start))
    return range_src, range_dst
end

"""
    assign_to!(a,b)
    
assignes array (or value) `b` to array `a` pointwise.
Helper function to be passed as an operator to functions such as select_region!
"""
function assign_to!(a,b)
    a .= b
end

"""
    add_to!(a,b)

adds array (or value) `b` to array `a` pointwise.
Hlper function to be passed as an operator to functions such as select_region!
"""
function add_to!(a,b)
    a  .+= b
end

"""
    sub_to!(a,b)
    
subtractss array (or value) `b` from array `a` pointwise and assigns into a.
Hlper function to be passed as an operator to functions such as select_region!
"""
function sub_to!(a,b)
    a  .-= b
end

"""
    mul_to!(a,b)

multiplies array (or value) `b` to array `a` pointwise.
Helper function to be passed as an operator to functions such as select_region!
"""
function mul_to!(a,b)
    a .*= b
end

"""
    div_to!(a,b)
    
divides array `a` by array (or value) `b` to array a pointwise.
Helper function to be passed as an operator to functions such as select_region!
"""
function div_to!(a,b)
    a ./= b
end


"""
    select_region!(src, dst=nothing, new_size=size(src), center=size(src).÷2 .+1, dst_center=nothing, pad_value=zero(eltype(mat), operator!=assign_to!))

selects (extracts, pads, shifts) a region of interest (ROI), defined by `new_size` and centered with the destination center aligned at 
the position `center` in the source image. Note that the number of dimensions in `new_size`,  `center` and `dst_center` can be smaller , 
in which case default values (see below) will be insterted into the missing dimensions. `new_size` does not need to fit into the source array 
and missing values will be replaced with `pad_value`, if no `dst` is provided.

As opposed to `select_region()`, this version returns a copy rather than a view or, alternatively, also writes into a destination array `dst` 
(`new_size` is then interpreted to refer to the maximally assigned region). 
If `nothing` is provided for `dst`, a new array of size `new_size` is created.

Arguments:
+ `src`. The source array to select from.
+ `dst`. The destination array to write into, if provided. By default `dst=nothing` a new array is created. The `dst`array (or new array) is returned. 
+ `new_size`. The size of the array view after the operation finished. By default the original size is assumed
+ `center`. Specifies the center of the new view in coordinates of the old view. By default an alignment of the Fourier-center (right center) is assumed.
+ `dst_center`. defines the center coordinate in the destination array which should align with the above source center. If nothing is provided, the right center pixel of the `dst` array or new array is used.
+ `pad_value`. specifies the value which is inserted in case the ROI extends to outside the source area. This is only used, if no `dst` array is provided.
+ `operator!`. allows to provide a user_defined array assignment function. The function my_op!(dst,src) should operator on array views and typically perform the assignment elementwise, overwriting the entries in dst.
                Five such functions are exported by NDTools: `assign_to!`, `add_to!`, `sub_to!`, `mul_to!`, `div_to!`, representing the operations `.=`, `.+=`, `.-=`, `.*=` and `./=` respectively.

The returned results is the destination (or newly created) array.
Note that this version is rather fast, since it consists of only a sinlge sub-array assigment on views, avoiding copy operations.

See also
+ select_region(src; new_size=size(src), center=ft_center_diff(size(src)).+1, pad_value=zero(eltype(src)))

Examples:
```jdoctest
julia> a = ones(5,6);

julia> dst=select_region(a,new_size=(10,10), dst_center=(1,1)) # pad a with zeros to a size of (10,10), but place original center at the corner
10×10 Matrix{Float64}:
 1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0

 julia> select_region!(2 .*a,dst, dst_center=size(dst)) # write a doubled version into the bottom right corner
10×10 Matrix{Float64}:
 1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  2.0  2.0  2.0  2.0
 0.0  0.0  0.0  0.0  0.0  0.0  2.0  2.0  2.0  2.0
 0.0  0.0  0.0  0.0  0.0  0.0  2.0  2.0  2.0  2.0
```
"""
function select_region!(src, dst; new_size=size(dst), 
                        center=size(src).÷2 .+1, dst_center=size(dst).÷ 2 .+1, operator! =assign_to!)
    new_size = Tuple(expand_size(new_size, size(dst)))    
    center = Tuple(expand_size(center, size(src).÷2 .+1))
    dst_center = Tuple(expand_size(dst_center, size(dst).÷ 2 .+1))

    range_src, range_dst = get_src_dst_range(size(src),size(dst),new_size,center, dst_center)
    if !isempty(range_dst)
        v_src = @view src[range_src...]
        v_dst = @view dst[range_dst...]
        operator!(v_dst, v_src)  # for some strange reason this is faster (and of course more flexible) than the line below.
        # dst[range_dst...] .+= src[range_src...]
    end
    return dst
end


"""
    select_region(src; new_size=size(mat), center=ft_center_diff(size(mat)).+1, pad_value=zero(eltype(mat)))

selects (extracts) a region of interest (ROI), defined by `new_size` and centered at `center` in the source image. Note that
the number of dimensions can be smaller in `new_size` and `center`, in which case the default values will be insterted
into the missing dimensions. `new_size` does not need to fit into the source array and missing values will be replaced with `pad_value`.

Arguments:
+ `src`. The array to extract the region from.
+ `new_size`. The size of the array view after the operation finished. By default the original size is assumed
+ `center`. Specifies the center of the new view in coordinates of the old view. By default an alignment of the Fourier-centers is assumed.
+ `pad_value`. Specifies the value which is inserted in case the ROI extends to outside the source area.

The returned result is a newly allocated array of the same type as the src. This is currently faster that select_region_view().

See also
+ select_region_view(src; new_size=size(src), center=ft_center_diff(size(src)).+1, pad_value=zero(eltype(src)))

Examples
```jldoctest
julia> using NDTools

julia> select_region(ones(3,3),new_size=(7,7),center=(1,3))
7×7 Matrix{Float64}:
 0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  1.0  1.0  1.0  0.0  0.0  0.0
 0.0  1.0  1.0  1.0  0.0  0.0  0.0
 0.0  1.0  1.0  1.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0

 julia> dst=select_region(a,new_size=(10,10), dst_center=(1,1)) # pad a with zeros to a size of (10,10), but place original center at the corner
10×10 Matrix{Float64}:
 1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 1.0  1.0  1.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
 0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0  0.0
```
"""
function select_region(src::AbstractArray{T,N}; new_size=size(src), center=size(src).÷2 .+1, pad_value=zero(eltype(src)), dst_center = new_size .÷ 2 .+1) where {T,N}
    new_size = Tuple(expand_size(new_size, size(src)))
    dst_center = Tuple(expand_size(dst_center, new_size .÷ 2 .+1)) # replace missing coordinates with the new center position

    pad_value = eltype(src)(pad_value)
    dst = fill(pad_value,new_size)
    select_region!(src,dst;new_size=new_size, center=center, dst_center=dst_center)
    return dst::Array{T,N}
end