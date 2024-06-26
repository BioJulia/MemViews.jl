using Test
using MemoryViews

MUT_BACKINGS = Any[
    # Arrays
    UInt8[1, 2],
    [4, 7],
    Float32[2, 9],
    Vector{AbstractDict{Int, String}}(undef, 3),

    # Memory
    Memory{String}(undef, 3),

    # Views
    view([1, 2, 3, 4, 5, 6], 1:5),
    view(Memory{UInt8}(), 1:0),
]

@testset "Mutability" begin
    for mut in MUT_BACKINGS
        @test MemoryView(mut) isa MutableMemoryView
    end

    for immut in
        Any["abc", codeunits("abcd"), view("adskd", 2:4), codeunits(view("dsaas", 1:3))]
        @test MemoryView(immut) isa ImmutableMemoryView
    end

    for nonmem in [nothing, missing, 5, (1, 3, 5), view([1, 2, 3, 4], 1:2:3)]
        @test_throws Exception MemoryView(nonmem)
    end

    @testset "Unsafe mutability" begin
        v = [1.0, 2.0, 3.0]
        m = ImmutableMemoryView(v)
        m2 = MutableMemoryView(MemoryViews.unsafe, m)
        m2[2] = 5.0
        @test v == [1.0, 5.0, 3.0]
    end
end

@testset "More construction" begin
    mem = MemoryView([1, 2, 3])
    @test MemoryView(mem) === mem

    mem = MemoryView(view("abc", 2:3))
    @test mem isa ImmutableMemoryView{UInt8}
    @test mem == [0x62, 0x63]
end

@testset "Immutable views are immutable" begin
    mem = MemoryView("abc")
    @test mem isa ImmutableMemoryView{UInt8}
    @test ImmutableMemoryView(mem) === mem
    mutmem = MemoryView(collect(codeunits("def")))

    @test_throws Exception mem[1] = 2
    @test_throws Exception reverse!(mem)
    @test_throws Exception copy!(mem, mutmem)
    @test_throws Exception unsafe_copyto!(mem, 1, mutmem, 1, 2)
end

# Span of views
@testset "Span of views" begin
    mem = MemoryView("abc")
    @test length(mem) == 3
    @test first(mem) == UInt8('a')
    @test last(mem) == UInt8('c')

    memory = Memory{Float32}(undef, 6)
    mem = MemoryView(memory)
    @test all(i == j for (i, j) in zip(mem, memory))
    @test length(mem) == length(memory)
    @test mem == memory

    v = view(view(rand(UInt16, 19), 2:11), 3:9)
    mem = MemoryView(v)
    @test mem == v

    s = SubString(Test.GenericString("dslkjad"), 2:5)
    # This is not implemented
    @test_throws Exception MemoryView(s)
end

memlen(x) = length(MemoryView(x))
@testset "Zero allocation" begin
    for v in MUT_BACKINGS
        memlen(v) # compile
        @test @allocated(memlen(v)) == 0
    end
end

@testset "Indexing" begin
    @testset "Scalar indexing" begin
        s = "abcdefghijklmn"
        cu = codeunits(s)
        mem = MemoryView(s)

        @test mem[3] == cu[3]
        for i in [-100, -4, -1, 0, length(cu) + 1, length(cu) + 100]
            @test_throws BoundsError mem[i]
        end
    end

    @testset "AbstractUnitRange indexing" begin
        s = "abcdefghijklmn"
        cu = codeunits(s)
        mem = MemoryView(s)

        for i in Any[
            2:6,
            Int32(4):Int32(9),
            0x05:0x0a,
            Base.OneTo(11),
            :,
            5:4,
            100:99,
            -500:-501,
        ]
            @test mem[i] == cu[i]
        end

        mem = MemoryView([9, 4, 2, 1, 8])
        mem2 = mem[3:end]
        @test typeof(mem) == typeof(mem2)
        mem[3] = 10
        # No copying
        @test mem2 == [10, 1, 8]
    end

    @testset "Views of memviews" begin
        mem = MemoryView(rand(3, 4))
        mem2 = view(mem, 4:7)
        @test mem2 === mem[4:7]
        mem2 .= [1.0, 2.0, 3.0, 4.0]
        @test mem[4:7] == [1.0, 2.0, 3.0, 4.0]
    end

    @testset "setindex!" begin
        v = Int16[32, 924, 231, 0, -145]
        mem = MemoryView(v)
        mem[1] = -500
        @test v == mem == [-500, 924, 231, 0, -145]
        mem[end] = 2
        @test v == mem == [-500, 924, 231, 0, 2]
        mem[2:(end - 2)] = 5:6
        @test v == mem == [-500, 5, 6, 0, 2]
        mem .= 99
        @test v == mem == [99, 99, 99, 99, 99]
        mem[:] .= 0
        @test mem == v == fill(0, 5)
    end
end

@testset "Iteration" begin
    mem = MemoryView(UInt16[])
    @test iterate(mem) === nothing

    mem = MemoryView("xp")
    (a, s) = iterate(mem)
    (b, s) = iterate(mem, s)
    @test iterate(mem, s) === nothing
    @test (a, b) == (UInt8('x'), UInt8('p'))

    for mut in MUT_BACKINGS
        if all(i -> isassigned(mut, i), eachindex(mut))
            @test collect(mut) == collect(MemoryView(mut))
        end
    end
end

@testset "Pointers" begin
    memory = Memory{UInt16}(undef, 10)
    mem = MemoryView(memory)[3:7]
    @test pointer(mem) == pointer(memory) + 4
    @test pointer(mem, 3) == pointer(memory) + 8

    v = view(rand(UInt32, 100), 19:55)
    mem = MemoryView(v)
    @test pointer(mem) == pointer(v)
    @test pointer(mem, 4) == pointer(v, 4)

    v = ["kls", "dsddaefe", "", "adsad"]
    mem = MemoryView(v)[2:end]
    @test pointer(v) + 8 == pointer(mem)
    @test pointer(v, 2) == pointer(mem)
    @test pointer(v, 3) == pointer(mem, 2)
end

@testset "Misc functions" begin
    @testset "Copying" begin
        # Immutable
        mem = MemoryView("abcdef")
        @test copy(mem) == mem

        # Mutable
        v = [1, 2, 3, 4, 5]
        mem = MemoryView(v)[2:4]
        mem2 = copy(mem)
        mem[1] = 9
        mem2[2] = 10
        @test v == [1, 9, 3, 4, 5]
        @test mem == [9, 3, 4]
        @test mem2 == [2, 10, 4]
        # Only makes a copy of the needed data
        @test length(mem2.ref.mem) == length(mem2)
    end

    @testset "Parentindices" begin
        mem = MemoryView(view(codeunits("lkdjfldfe"), 3:8))[2:6]
        @test parentindices(mem) == 4:8

        mem = MemoryView(UInt32[2, 5, 2, 1, 6, 8])[4:end]
        @test parentindices(mem) == 4:6

        mem = MemoryView(view(Vector{String}(undef, 10), 5:7))
        @test parentindices(mem) == 5:7
    end

    @testset "Similar and empty" begin
        mem = MemoryView(Int16[6, 4, 3])
        @test typeof(empty(mem)) == typeof(mem)
        @test isempty(empty(mem))

        mem2 = empty(mem, Int8)
        @test isempty(mem2)
        @test typeof(mem2) == MutableMemoryView{Int8}

        mem = MemoryView("abc")
        mem2 = similar(mem)
        @test length(mem2) == length(mem)
        @test typeof(mem2) == typeof(mem)

        mem = MemoryView(String["", "", ""])
        mem2 = similar(mem, Int, 4)
        @test length(mem2) == 4
        @test eltype(mem2) == Int

        mem = empty(ImmutableMemoryView{Tuple{Int, UInt8}})
        @test isempty(mem)
        @test mem isa ImmutableMemoryView{Tuple{Int, UInt8}}
        mem = empty(MutableMemoryView{Float16})
        @test isempty(mem)
        @test mem isa MutableMemoryView{Float16}
    end

    @testset "Sizeof" begin
        @test sizeof(MemoryView("abc")) == 3
        @test sizeof(MemoryView([1, 2, 3])) == 3 * sizeof(Int)
        @test sizeof(MemoryView(String["", "", "", ""])) == 4 * sizeof(Int)
    end

    @testset "Copyto" begin
        # Copy!
        v1 = [5, 2, 1, 9, 8]
        v2 = [0, 2, 6, 3, 9]
        mem1 = MemoryView(v1)
        mem2 = MemoryView(v2)
        copy!(mem1, mem2)
        @test v1 == v2
        @test mem1 == mem2

        @test_throws BoundsError copy!(MemoryView([1]), MemoryView([1, 2]))
        @test_throws BoundsError copy!(MemoryView([1, 2]), MemoryView([1]))

        # Copyto!
        v1 = [4, 2, 6, 7, 9]
        v2 = [1, 5, 2, 3]
        copyto!(MemoryView(v1), MemoryView(v2))
        @test v1 == [1, 5, 2, 3, 9]
        @test_throws BoundsError copyto!(MemoryView(v2), MemoryView(v1))

        # unsafe_copyto!
        v1 = [3, 6, 2, 1]
        v2 = [0, 9, 5]
        unsafe_copyto!(MemoryView(v1), MemoryView(v2))
        @test v1 == [0, 9, 5, 1]
        v2 = rand(Int, 4)
        unsafe_copyto!(MemoryView(v1), MemoryView(v2))
        @test v2 == v1
    end

    @testset "Find" begin
        mem = MemoryView([4, 3, 2])
        @test findfirst(==(2), mem) == 3

        mem = MemoryView(Int8[6, 2, 7, 0, 2])
        @test findfirst(iszero, mem) == 4
        @test findfirst(==(Int8(0)), mem) == 4

        mem = MemoryView(UInt8[1, 4, 2, 5, 6])
        @test findnext(==(0x04), mem, 1) == 2
        @test findnext(==(0x04), mem, 3) === nothing
    end
end

@testset "MemoryKind" begin
    @test MemoryKind(Vector{Int16}) == IsMemory(MutableMemoryView{Int16})
    @test MemoryKind(typeof(codeunits(view("abc", 2:3)))) == IsMemory(ImmutableMemoryView{UInt8})
    @test MemoryKind(typeof(view(Memory{String}(undef, 3), Base.OneTo(2)))) ==
          IsMemory(MutableMemoryView{String})
    @test MemoryKind(Matrix{Nothing}) == IsMemory(MutableMemoryView{Nothing})
    @test MemoryKind(Memory{Int32}) == IsMemory(MutableMemoryView{Int32})
    @test MemoryKind(typeof(view([1], 1:1))) == IsMemory(MutableMemoryView{Int})

    @test inner(IsMemory(MutableMemoryView{Int32})) == MutableMemoryView{Int32}
    @test inner(IsMemory(ImmutableMemoryView{Tuple{String, Int}})) ==
          ImmutableMemoryView{Tuple{String, Int}}

    @test MemoryKind(SubString{String}) == NotMemory()
    @test MemoryKind(String) == NotMemory()
    @test MemoryKind(Int) == NotMemory()
    @test MemoryKind(Nothing) == NotMemory()
    @test MemoryKind(Union{}) == NotMemory()
    @test_throws Exception inner(NotMemory())
end
