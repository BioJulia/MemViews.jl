module MemViews

export MemView, ImmutableMemView, MutableMemView, MemKind, IsMemory, NotMemory, inner

"""
    Unsafe

Trait object used to dispatch to unsafe methods.
The `MemViews.unsafe` instance is the singleton instance of this type.
"""
struct Unsafe end

"Singleton instance of the trait type `Unsafe`"
const unsafe = Unsafe()

"""
Trait struct, only used in the mutability parameter of `MemView`
"""
struct Mutable end

"""
Trait struct, only used in the mutability parameter of `MemView`
"""
struct Immutable end

"""
    MemView{T, M} <: DenseVector{T}

View into a `Memory{T}`.
Construct from memory-backed values `x` with `MemView(x)`.

`MemView`s are guaranteed to point to contiguous, valid CPU memory,
except where they have size zero.

The parameter `M` controls the mutability of the memory view,
and may be `Mutable` or `Immutable`, corresponding to the
the aliases `MutableMemView{T}` and `ImmutableMemView{T}`.

See also: `MemKind`

# Examples
```jldoctest
julia> v = view([1, 2, 3, 4], 2:3);

julia> mem = MemView(v)
2-element MutableMemView{Int64}:
 2
 3

julia> MemView(codeunits("abc")) isa ImmutableMemView{UInt8}
true
```

# Extended help
New types `T` which are backed by dense memory should implement:
* `MemView(x::T)` to construct a memory view from `x`. This should
   always return a `MutableMemView` when the memory of `x` is mutable.
* `MemKind(x::T)`, if `T` is semantically equal to its own memory view.
  Examples of this include `Vector`, `Memory`, and
  `Base.CodeUnits{UInt8, String}`. If so, `x == MemView(x)` should hold.

If `MemView(x)` is implemented, then `ImmutableMemView(x)` will
automatically work, even if `MemView(x)` returns a mutable view.

It is not possible to mutate memory though an `ImmutableMemView`, but the existence
of the view does not protect the same memory from being mutated though another
variable.

The precise memory layout of the data in a `MemView` follows that of `Memory`.
This includes the fact that some elements in the array, such as  `String`s,
may be stored as pointers, and [isbits Union optimisations]
(https://docs.julialang.org/en/v1/devdocs/isbitsunionarrays/).

"""
struct MemView{T, M <: Union{Mutable, Immutable}} <: DenseVector{T}
    # If the memview is empty, there is no guarantees where the ref points to
    ref::MemoryRef{T}
    len::Int

    function MemView{T, M}(::Unsafe, ref::MemoryRef{T}, len::Int) where {T, M}
        M == Union{} && error("Parameter M must be Mutable or Immutable")
        new{T, M}(ref, len)
    end
end

const MutableMemView{T} = MemView{T, Mutable}
const ImmutableMemView{T} = MemView{T, Immutable}

# Mutable mem views can turn into immutable ones, but not vice versa
ImmutableMemView(x) = ImmutableMemView(MemView(x)::MemView)
ImmutableMemView(x::MutableMemView{T}) where {T} = ImmutableMemView{T}(unsafe, x.ref, x.len)
ImmutableMemView(x::ImmutableMemView) = x

"""
    MutableMemView(::Unsafe, x::MemView)

Convert a memory view into a mutable memory view.
Note that it may cause undefined behaviour, if supposedly immutable data
is observed to be mutated.
"""
MutableMemView(::Unsafe, x::MemView{T}) where {T} = MutableMemView{T}(unsafe, x.ref, x.len)

"""
    MemKind

Trait object used to signal if values of a type is semantically equal to their own `MemView`.
If so, `MemKind(T)` should return an instance of `IsMemory`,
else `NotMemory()`. The default implementation `MemKind(::Type)` returns `NotMemory()`.

If `MemKind(T) isa IsMemory{M}`, the following must hold:
1. `M` is a concrete subtype of `MemView`. To obtain `M` from an `m::IsMemory{M}`,
    use `inner(m)`.
2. `MemView(T)` is a valid instance of `M`.
3. `MemView(x) == x` for all instances `x::T`

Some objects can be turned into `MemView` without being `IsMemory`.
For example, `MemView(::String)` returns a valid `MemView` even though
`MemKind(String) === NotMemory()`.
This is because strings have different semantics than memory views - the latter
is a dense `AbstractArray` while strings are not, and so the fourth requirement
`MemView(x::String) == x` does not hold.

See also: [`MemView`](@ref)
"""
abstract type MemKind end

"""
    NotMemory <: MemKind

See: [`MemKind`](@ref)
"""
struct NotMemory <: MemKind end

"""
    IsMemory{T <: MemView} <: MemKind

See: [`MemKind`](@ref)
"""
struct IsMemory{T <: MemView} <: MemKind
    function IsMemory{T}() where {T}
        isconcretetype(T) || error("In IsMemory{T}, T must be concrete")
        new{T}()
    end
end
IsMemory(T::Type{<:MemView}) = IsMemory{T}()

"""
    inner(::IsMemory{T})

Return `T` from an `IsMemory{T}`.

See: [`MemKind`](@ref)
"""
inner(::IsMemory{T}) where {T} = T

MemKind(::Type) = NotMemory()
MemKind(::Type{Union{}}) = NotMemory()

include("construction.jl")
include("basic.jl")

end # module