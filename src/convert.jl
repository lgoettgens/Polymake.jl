import Base: convert
####################  Converting to polymake types  ####################

for (pm_T, jl_T) in [
        (Vector, AbstractVector),
        (Matrix, AbstractMatrix),
        (Array, AbstractVector),
        (Set, AbstractSet),
        (SparseMatrix, AbstractMatrix),
        (SparseVector, AbstractVector),
        ]
    @eval begin
        convert(::Type{$pm_T}, itr::$jl_T) = $pm_T(itr)
        convert(::Type{$pm_T{T}}, itr::$jl_T) where T = $pm_T{T}(itr)
        convert(::Type{$pm_T}, itr::$pm_T) = itr
        convert(::Type{$pm_T{T}}, itr::$pm_T{T}) where T = itr
    end
end

convert(::Type{Set{T}}, itr::AbstractArray) where T = Set{T}(itr)

convert(::Type{<:Polynomial{C,E}}, itr::Polynomial{C,E}) where {C,E} = itr
convert(::Type{<:Polynomial{C1,E1}}, itr::Polynomial{C2,E2}) where {C1,C2,E1,E2} = Polynomial{C1,E1}(itr)

convert(::Type{BasicDecoration}, p::StdPair) = BasicDecoration(first(p),last(p))
Polymake.BasicDecoration(p::Pair{<:AbstractSet{<:Base.Integer},<:Base.Integer}) = BasicDecoration(convert(PolymakeType, first(p)), convert(PolymakeType,last(p)))
Polymake.BasicDecoration(p::Tuple{<:AbstractSet{<:Base.Integer},<:Base.Integer}) = BasicDecoration(convert(PolymakeType, first(p)), convert(PolymakeType,last(p)))
Polymake.BasicDecoration(s::Base.Set{<:Base.Integer}, i::Base.Integer) = BasicDecoration(Set(s), i)


###########  Converting to objects polymake understands  ###############

struct PolymakeType end

convert(::Type{PolymakeType}, x::T) where T = convert(convert_to_pm_type(T), x)
convert(::Type{PolymakeType}, v::Visual) = v.obj
convert(::Type{PolymakeType}, ::Nothing) = call_function(PropertyValue, :common, :get_undef)
convert(::Type{OptionSet}, dict) = OptionSet(dict)

# long (>=3) uniform tuples need some extra treatment
convert(::Type{PolymakeType}, x::Tuple{T,T,T,Vararg{T}}) where T = Polymake.Array(map(convert_to_pm_type(T), collect(x)))

as_perl_array(t::SmallObject) = Polymake.call_function(PropertyValue, :common, :as_perl_array, t)
as_perl_array_of_array(t::SmallObject) = Polymake.call_function(PropertyValue, :common, :as_perl_array_of_array, t)

###############  Adjusting type parameter to CxxWrap  ##################

to_cxx_type(::Type{T}) where T = T
to_cxx_type(::Type{Bool}) = CxxWrap.CxxBool
to_cxx_type(::Type{Int64}) = CxxWrap.CxxLong
to_cxx_type(::Type{UInt64}) = CxxWrap.CxxULong
to_cxx_type(::Type{<:AbstractString}) = CxxWrap.StdString
to_cxx_type(::Type{<:AbstractVector{T}}) where T =
    Vector{to_cxx_type(T)}
to_cxx_type(::Type{<:AbstractMatrix{T}}) where T =
    Matrix{to_cxx_type(T)}
to_cxx_type(::Type{<:AbstractSet{T}}) where T =
    Set{to_cxx_type(T)}
to_cxx_type(::Type{<:Array{T}}) where T =
    Array{to_cxx_type(T)}
to_cxx_type(::Type{<:Polynomial{S,T}}) where {S,T} =
    Polynomial{to_cxx_type(S), to_cxx_type(T)}
to_cxx_type(::Type{<:Tuple{A,B}}) where {A,B} =
    StdPair{to_cxx_type(A), to_cxx_type(B)}
to_cxx_type(::Type{<:Pair{A,B}}) where {A,B} =
    StdPair{to_cxx_type(A), to_cxx_type(B)}
to_cxx_type(::Type{<:StdPair{A,B}}) where {A,B} =
    StdPair{to_cxx_type(A), to_cxx_type(B)}

to_jl_type(::Type{T}) where T = T
to_jl_type(::Type{CxxWrap.CxxBool}) = Bool
to_jl_type(::Type{CxxWrap.CxxLong}) = Int64
to_jl_type(::Type{CxxWrap.CxxULong}) = UInt64
to_jl_type(::Type{CxxWrap.StdString}) = String

if Int64 != CxxWrap.CxxLong
   CxxWrap.CxxLong(n::Integer) = CxxLong(new_int_from_integer(n))
   CxxWrap.CxxLong(r::Rational) = CxxLong(new_int_from_rational(r))
end
Int64(r::Rational) = Int64(new_int_from_rational(r))

const PmInt64 = to_cxx_type(Int64)

####################  Guessing the polymake type  ######################

# By default we throw an error:
convert_to_pm_type(T::Type) = throw(ArgumentError("Unrecognized argument type: $T.\nYou need to convert to polymake compatible type first."))

convert_to_pm_type(::Type{T}) where T <: Union{Int64, Float64} = T
convert_to_pm_type(::Type{T}) where T <: Union{BigObject, BigObjectType, PropertyValue, OptionSet} = T
convert_to_pm_type(::Type{T}) where T <: TropicalNumber = T

convert_to_pm_type(::Nothing) = Nothing
convert_to_pm_type(::Type{Int32}) = Int64
convert_to_pm_type(::Type{CxxWrap.CxxLong}) = CxxWrap.CxxLong
convert_to_pm_type(::Type{<:AbstractFloat}) = Float64
convert_to_pm_type(::Type{<:AbstractString}) = String
convert_to_pm_type(::Type{<:CxxWrap.StdString}) = CxxWrap.StdString
convert_to_pm_type(::Type{<:Union{Base.Integer, Integer}}) = Integer
convert_to_pm_type(::Type{<:Union{Base.Rational, Rational}}) = Rational
convert_to_pm_type(::Type{<:OscarNumber}) = OscarNumber
convert_to_pm_type(::Type{<:NodeMap}) = NodeMap
convert_to_pm_type(::Type{<:Union{AbstractVector, Vector}}) = Vector
convert_to_pm_type(::Type{<:Union{AbstractMatrix, Matrix}}) = Matrix
convert_to_pm_type(::Type{<:Union{AbstractSparseMatrix, SparseMatrix}}) = SparseMatrix
convert_to_pm_type(::Type{<:AbstractSparseMatrix{<:Union{Bool, CxxWrap.CxxBool}}}) = IncidenceMatrix
convert_to_pm_type(::Type{<:Union{AbstractSparseVector, SparseVector}}) = SparseVector
convert_to_pm_type(::Type{<:Array}) = Array
convert_to_pm_type(::Type{<:Union{Pair, StdPair}}) = StdPair
convert_to_pm_type(::Type{<:Pair{A,B}}) where {A,B} = StdPair{convert_to_pm_type(A),convert_to_pm_type(B)}
convert_to_pm_type(::Type{<:StdPair{A,B}}) where {A,B} = StdPair{convert_to_pm_type(A),convert_to_pm_type(B)}
convert_to_pm_type(::Type{<:Tuple{A,B}}) where {A,B} = StdPair{convert_to_pm_type(A),convert_to_pm_type(B)}
convert_to_pm_type(::Type{<:Polynomial{<:Rational, <:Union{Int64, CxxWrap.CxxLong}}}) = Polynomial{Rational, CxxWrap.CxxLong}
convert_to_pm_type(::Type{<:AbstractVector{T}}) where T<:Tuple = Polymake.Array{convert_to_pm_type(T)}
convert_to_pm_type(::Type{<:BasicDecoration}) = BasicDecoration
# only for 3 or more elements:
convert_to_pm_type(::Type{<:Tuple{A,A,A,Vararg{A}}}) where A = Polymake.Array{convert_to_pm_type(A)}

# Graph, EdgeMap, NodeMap
const DirType = Union{Directed, Undirected}
convert_to_pm_type(::Type{<:Graph{T}}) where T<:DirType = Graph{T}

convert_to_pm_type(::Type{<:EdgeMap{S,T}}) where S<:DirType where T = EdgeMap{S, convert_to_pm_type(T)}
EdgeMap{Dir, T}(g::Graph{Dir}) where Dir<:DirType where T = EdgeMap{Dir,to_cxx_type(T)}(g)

convert_to_pm_type(::Type{<:NodeMap{S,T}}) where S <: DirType where T = NodeMap{S, convert_to_pm_type(T)}
NodeMap{Dir, T}(g::Graph{Dir}) where Dir<:DirType where T = NodeMap{Dir,to_cxx_type(T)}(g)



convert_to_pm_type(::Type{HomologyGroup{T}}) where T<:Integer = HomologyGroup{T}
convert_to_pm_type(::Type{<:QuadraticExtension{T}}) where T<:Rational = QuadraticExtension{Rational}
convert_to_pm_type(::Type{<:TropicalNumber{S,T}}) where S<:Union{Max,Min} where T<:Rational = TropicalNumber{S,Rational}


for (pmT, jlT) in [(Integer, Base.Integer),
                   (Int64, Union{Int32,Int64}),
                   (CxxWrap.CxxLong, CxxWrap.CxxLong),
                   (Rational, Union{Base.Rational, Rational}),
                   (TropicalNumber{Max, Rational}, TropicalNumber{Max, Rational}),
                   (TropicalNumber{Min, Rational}, TropicalNumber{Min, Rational}),
                   (OscarNumber, OscarNumber),
                   (QuadraticExtension{Rational}, QuadraticExtension{Rational})]
    @eval begin
        convert_to_pm_type(::Type{<:AbstractMatrix{T}}) where T<:$jlT = Matrix{convert_to_pm_type($pmT)}
        convert_to_pm_type(::Type{<:AbstractVector{T}}) where T<:$jlT = Vector{convert_to_pm_type($pmT)}
        convert_to_pm_type(::Type{<:AbstractSet{T}}) where T<:$jlT = Set{convert_to_pm_type($pmT)}
    end
end

convert_to_pm_type(::Type{<:AbstractMatrix{T}}) where T<:AbstractFloat =
    Matrix{convert_to_pm_type(T)}

convert_to_pm_type(::Type{<:AbstractVector{T}}) where T<:Union{AbstractString, AbstractSet} =
    Array{convert_to_pm_type(T)}

# this catches all Arrays of Arrays we have right now:
convert_to_pm_type(::Type{<:AbstractVector{<:AbstractArray{T}}}) where T =
    Array{Array{convert_to_pm_type(T)}}

# 2-argument version: the first is the container type
promote_to_pm_type(::Type, S::Type) = convert_to_pm_type(S) #catch all

function promote_to_pm_type(
    ::Type{<:Union{Vector,Matrix,SparseMatrix,SparseVector}},
    S::Type{<:Union{Base.Integer,CxxWrap.CxxLong}},
)
    (promote_type(S, Int64) == Int64 || S isa CxxWrap.CxxLong) && return Int64
    return Integer
end

"""
    @convert_to PerlType argument

This macro can be used to quickly convert objects using the [`@pm`](@ref) macro and Polymake's `common.convert_to` method.
As the latter is rooted in Perl, the stated type also has to be understandable by Polymake's Perl

# Examples
```jldoctest
julia> @convert_to Integer true
1

julia> @convert_to Array{Set{Int}} [Set([1, 2, 4, 5, 7, 8]), Set([1]), Set([6, 9])]
pm::Array<pm::Set<long, pm::operations::cmp>>
{1 2 4 5 7 8}
{1}
{6 9}


julia> @convert_to Vector{Float} [10, 11, 12]
pm::Vector<double>
10 11 12

julia> @convert_to Matrix{Rational} [10/1 11/1 12/1]
pm::Matrix<pm::Rational>
10 11 12

```
"""
macro convert_to(args...)
    # Catch case that only one or more than two arguments are given
    if length(args) != 2
        throw(ArgumentError("@convert_to needs to be called with 2 arguments, e.g., `@convert_to Matrix{Integer} A`."))
    end
    expr1, expr2 = args
    :(
        try
            # expr2 needs to be escaped
            @pm common.convert_to{$expr1}($(esc(expr2)))
        catch ex
            # To not catch things like UndefVarError only catch ErrorException
            # since this is currently thrown if something invalid is parsed.
            if ex isa ErrorException
                # Use QuoteNodes to keep expr1 and expr2 as Expr around
                expr1 = $(QuoteNode(expr1))
                expr2 = $(QuoteNode(expr2))
                throw(ArgumentError("Can not parse the expression passed to @convert_to macro:\n$expr1 $expr2\n Only `@convert_to PerlType argument` syntax is recognized"))
            else
                rethrow(ex)
            end
        end
    )
end
