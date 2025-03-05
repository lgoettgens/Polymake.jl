function Base.promote_rule(::Type{<:OscarNumber},
    ::Type{<:Union{Integer, Rational, Base.Integer, Base.Rational{<:Base.Integer}}})
    return OscarNumber
end

(::Type{<:OscarNumber})(a::Union{Base.Integer, Base.Rational{<:Base.Integer}}) = OscarNumber(Rational(a))
# this needs to be separate to avoid ambiguities
OscarNumber(a::Union{Base.Integer, Base.Rational{<:Base.Integer}}) = OscarNumber(Rational(a))
(::Type{<:OscarNumber})(a::Integer) = OscarNumber(Rational(a))
OscarNumber(a::Integer) = OscarNumber(Rational(a))
(::Type{<:OscarNumber})(a::Rational) = OscarNumber(CxxWrap.ConstCxxRef(a))
OscarNumber(a::Rational) = OscarNumber(CxxWrap.ConstCxxRef(a))

Base.zero(::Type{<:OscarNumber}) = OscarNumber(0)
Base.zero(::OscarNumber) = OscarNumber(0)
Base.one(::Type{<:OscarNumber}) = OscarNumber(1)
Base.one(::OscarNumber) = OscarNumber(1)
Base.sign(e::OscarNumber) = OscarNumber(_sign(e))

import Base: <, //, <=

Base.:<=(x::OscarNumber, y::OscarNumber) = x < y || x == y
Base.:/(x::OscarNumber, y::OscarNumber) = x // y

# no-copy convert
convert(::Type{<:OscarNumber}, on::OscarNumber) = on

function unwrap(on::OscarNumber)
   if isinf(on)
      error("cannot unwrap OscarNumber containing infinity")
   elseif _uses_rational(on)
      return _get_rational(on)
   else
      return GC.@preserve on begin
         ptr = _unsafe_get_ptr(on)
         jn = unsafe_pointer_to_objref(ptr)
         return deepcopy(jn)
      end
   end
end

# this struct must match the struct in OscarNumber.cc
mutable struct oscar_number_dispatch_helper
    index::Clong
    init::Ptr{Cvoid}
    init_from_mpz::Ptr{Cvoid}
    copy::Ptr{Cvoid}
    gc_protect::Ptr{Cvoid}
    gc_free::Ptr{Cvoid}
    add::Ptr{Cvoid}
    sub::Ptr{Cvoid}
    mul::Ptr{Cvoid}
    div::Ptr{Cvoid}
    pow::Ptr{Cvoid}
    negate::Ptr{Cvoid}
    cmp::Ptr{Cvoid}
    to_string::Ptr{Cvoid}
    from_string::Ptr{Cvoid}
    is_zero::Ptr{Cvoid}
    is_one::Ptr{Cvoid}
    is_inf::Ptr{Cvoid}
    sign::Ptr{Cvoid}
    abs::Ptr{Cvoid}
    hash::Ptr{Cvoid}
    to_rational::Ptr{Cvoid}
    to_float::Ptr{Cvoid}
    is_rational::Ptr{Cvoid}
    to_ceil::Ptr{Cvoid}
    to_floor::Ptr{Cvoid}
end
oscar_number_dispatch_helper() = oscar_number_dispatch_helper(-1, repeat([C_NULL], 25)...)

const _on_gc_refs = IdDict()

field_count = 0

# mapping parent -> (id, element, dispatch)
const _on_dispatch_helper = Dict{Any, Tuple{Clong, oscar_number_dispatch_helper}}()
const _on_parent_by_id = Dict{Clong, Any}()

@generated _on_gen_add(::Type{ArgT}) where ArgT =
   quote
      @cfunction(Base.:+, Ref{ArgT}, (Ref{ArgT}, Ref{ArgT}))
   end
@generated _on_gen_sub(::Type{ArgT}) where ArgT =
   quote
      @cfunction(Base.:-, Ref{ArgT}, (Ref{ArgT}, Ref{ArgT}))
   end
@generated _on_gen_mul(::Type{ArgT}) where ArgT =
   quote
      @cfunction(Base.:*, Ref{ArgT}, (Ref{ArgT}, Ref{ArgT}))
   end
@generated _on_gen_div(::Type{ArgT}) where ArgT =
   quote
      @cfunction(Base.://, Ref{ArgT}, (Ref{ArgT}, Ref{ArgT}))
   end

@generated _on_gen_pow(::Type{ArgT}) where ArgT =
   quote
      @cfunction(Base.:^, Ref{ArgT}, (Ref{ArgT}, Clong))
   end
@generated _on_gen_negate(::Type{ArgT}) where ArgT =
   quote
      @cfunction(Base.:-, Ref{ArgT}, (Ref{ArgT},))
   end

@generated function _on_gen_abs(::Type{ArgT}) where ArgT
   return quote
      @cfunction(Base.abs, Ref{ArgT}, (Ref{ArgT},))
   end
end

_on_cmp_int(e1::T, e2::T) where T = Clong(Base.cmp(e1, e2))
@generated _on_gen_cmp(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_cmp_int, Clong, (Ref{ArgT}, Ref{ArgT}))
   end

@generated _on_gen_is_zero(::Type{ArgT}) where ArgT =
   quote
      @cfunction(Base.iszero, Bool, (Ref{ArgT},))
   end
@generated _on_gen_is_one(::Type{ArgT}) where ArgT =
   quote
      @cfunction(Base.isone, Bool, (Ref{ArgT},))
   end

_on_sign_int(e::T) where T = Clong(Base.cmp(e,0))
@generated _on_gen_sign_int(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_sign_int, Clong, (Ref{ArgT},))
   end

function _fieldelem_to_float(e::T) where T
   return Float64(e)
end

function _on_to_float(e::ArgT)::Float64 where ArgT
   return _fieldelem_to_float(e)
end

@generated _on_gen_to_float(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_to_float, Float64, (Ref{ArgT},))
   end

function _fieldelem_to_ceil(e::T) where T
   return BigInt(ceil(e))
end

function _fieldelem_to_floor(e::T) where T
   return BigInt(floor(e))
end

function _fieldelem_to_rational(e::T) where T
   Polymake._fieldelem_is_rational(e) || error("not a rational number")
   return Base.Rational{BigInt}(e)
end

function _on_to_rational(e::ArgT)::Ptr{Base.GMP.MPQ.mpq_t} where ArgT
   r = try
      _fieldelem_to_rational(e)
   catch e
      return C_NULL
   end
   q = Base.GMP.MPQ._MPQ(r)
   return pointer_from_objref(q)
end

@generated _on_gen_to_rational(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_to_rational, Ptr{Base.GMP.MPQ.mpq_t}, (Ref{ArgT},))
   end

function _fieldelem_is_rational(e::T) where T
   error("OscarNumber: cannot check is_rational, please define 'Polymake._fieldelem_is_rational(e::$T)::Bool'")
end

@generated _on_gen_is_rational(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_fieldelem_is_rational, Bool, (Ref{ArgT},))
   end

function _on_to_ceil(e::ArgT)::Ptr{BigInt} where ArgT
   i = try
      _fieldelem_to_ceil(e)
   catch e
      return C_NULL
   end
   return pointer_from_objref(i)
end

@generated _on_gen_to_ceil(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_to_ceil, Ptr{BigInt}, (Ref{ArgT},))
   end

function _on_to_floor(e::ArgT)::Ptr{BigInt} where ArgT
   i = try
      _fieldelem_to_floor(e)
   catch e
      return C_NULL
   end
   return pointer_from_objref(i)
end

@generated _on_gen_to_floor(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_to_floor, Ptr{BigInt}, (Ref{ArgT},))
   end

function _on_hash(e::T) where T
   if !_fieldelem_is_rational(e)
      return hash(e)
   end
   r = _fieldelem_to_rational(e)
   return GC.@preserve r begin
      Polymake._hash_mpz(numerator(r)) - Polymake._hash_mpz(denominator(r))
   end
end


@generated _on_gen_hash(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_hash, Csize_t, (Ref{ArgT},))
   end

# the Ptr arg in the following functions allows us to fix the return type
# from the @cfunction call
function _on_init(id::Clong, ::Ptr{ArgT}, i::Clong)::ArgT where ArgT
   return _on_parent_by_id[id](i)
end
@generated _on_gen_init(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_init, Ref{ArgT}, (Clong, Ptr{ArgT}, Clong))
   end

function _fieldelem_from_rational(f::Any, r::Base.Rational{BigInt})
   return f(r)
end

function _on_init_frac(id::Clong, ::Ptr{ArgT}, np::Ptr{BigInt}, dp::Ptr{BigInt})::ArgT where ArgT
   n = unsafe_load(np)::BigInt
   d = unsafe_load(dp)::BigInt
   return _fieldelem_from_rational(_on_parent_by_id[id], Base.Rational{BigInt}(n, d))::ArgT
end
@generated _on_gen_init_frac(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_init_frac, Ref{ArgT}, (Clong, Ptr{ArgT}, Ptr{BigInt}, Ptr{BigInt}))
   end

function _on_copy(e::T)::T where T
   return deepcopy(e)
end
@generated _on_gen_copy(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_copy, Ref{ArgT}, (Ref{ArgT},))
   end


function _on_gc_protect(x::T) where T
   if haskey(Polymake._on_gc_refs, x)
      error("gc_protect: duplicate on $x : $(objectid(x))")
   end
   Polymake._on_gc_refs[x] = x
   return nothing
end
@generated _on_gen_gc_protect(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_gc_protect, Cvoid, (Ref{ArgT},))
   end

function _on_gc_free(x::T) where T
   if !haskey(Polymake._on_gc_refs, x)
      error("gc_free: invalid on $x : $(objectid(x))")
   end
   delete!(Polymake._on_gc_refs, x)
   return nothing
end
@generated _on_gen_gc_free(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_gc_free, Cvoid, (Ref{ArgT},))
   end


function _on_to_string(e::T) where T
   str = "$e"
   return GC.@preserve str begin
      Base.unsafe_convert(Cstring, str)
   end
end
@generated _on_gen_to_string(::Type{ArgT}) where ArgT =
   quote
      @cfunction(_on_to_string, Cstring, (Ref{ArgT},))
   end

function OscarNumber(e)
   id = register_julia_element(e, parent(e), typeof(e))
   return GC.@preserve e begin
      on = OscarNumber(pointer_from_objref(e), id)
   end
   return on
end

function register_julia_element(e, p, t::Type)
   if haskey(_on_dispatch_helper, p)
      return _on_dispatch_helper[p][1]
   end
   newid = field_count+1

   if isimmutable(e)
      error("OscarNumber: immutable julia types not supported")
   end

   hasmethod(p, (Int64,)) || error("OscarNumber: no constructor ($p)(Int64)")

   dispatch = oscar_number_dispatch_helper()
   dispatch.index = newid
   dispatch.init = _on_gen_init(t)
   dispatch.init_from_mpz = _on_gen_init_frac(t)
   dispatch.copy = _on_gen_copy(t)

   dispatch.gc_protect = _on_gen_gc_protect(t)
   dispatch.gc_free = _on_gen_gc_free(t)

   dispatch.add = _on_gen_add(t)
   dispatch.sub = _on_gen_sub(t)
   dispatch.mul = _on_gen_mul(t)
   dispatch.div = _on_gen_div(t)
   dispatch.pow = _on_gen_pow(t)

   dispatch.negate = _on_gen_negate(t)
   dispatch.abs    = _on_gen_abs(t)

   dispatch.is_zero = _on_gen_is_zero(t)
   dispatch.is_one  = _on_gen_is_one(t)
   dispatch.sign    = _on_gen_sign_int(t)
   dispatch.hash    = _on_gen_hash(t)

   dispatch.to_rational = _on_gen_to_rational(t)
   dispatch.to_float = _on_gen_to_float(t)

   dispatch.cmp = _on_gen_cmp(t)

   dispatch.to_string = _on_gen_to_string(t)

   dispatch.is_rational = _on_gen_is_rational(t)

   dispatch.to_ceil = _on_gen_to_ceil(t)
   dispatch.to_floor = _on_gen_to_floor(t)
   # later:
   # from_string::Ptr{Cvoid}

   # currently not really needed
   #dispatch.is_inf  = _on_gen_is_inf(t)

   _register_oscar_number(pointer_from_objref(dispatch), newid)
   _on_dispatch_helper[p] = (newid, dispatch)
   _on_parent_by_id[newid] = p

   global field_count=newid
   return field_count
end

(::Type{T})(on::OscarNumber) where T<:Number = convert(T, unwrap(on))
(::Type{<:Integer})(on::OscarNumber) = convert(Integer, unwrap(on))
(::Type{<:Rational})(on::OscarNumber) = convert(Rational, unwrap(on))
Integer(on::OscarNumber) = convert(Integer, unwrap(on))
Rational(on::OscarNumber) = convert(Rational, unwrap(on))
Base.hash(on::OscarNumber, h::UInt) = hash(unwrap(on), h)

# we don't support conversion for concrete types inside the OscarNumber here
(::Type{<:QuadraticExtension{<:Rational}})(on::OscarNumber) = QuadraticExtension{Rational}(Rational(on))
QuadraticExtension{<:Rational}(on::OscarNumber) = QuadraticExtension{Rational}(Rational(on))
QuadraticExtension{Rational}(on::OscarNumber) = QuadraticExtension{Rational}(Rational(on))
(::Type{<:OscarNumber})(qe::QuadraticExtension) = OscarNumber(Rational(qe))
OscarNumber(qe::QuadraticExtension) = OscarNumber(Rational(qe))

