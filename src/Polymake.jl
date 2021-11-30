"""
`Polymake.jl` is the Julia interface to `polymake`, an open source software for research in polyhedral geometry.

For more information see:
 > https://polymake.org/doku.php
 >
 > https://github.com/oscar-system/Polymake.jl
"""
module Polymake

export @pm, @convert_to, visual

# We need to import all functions which will be extended on the Cxx side
import Base: ==, <, <=, *, -, +, //, ^, div, rem, one, zero,
    append!, deepcopy_internal, delete!, numerator, denominator,
    empty!, Float64, getindex, in, intersect, intersect!, isempty,
    length, numerator, push!, resize!,
    setdiff, setdiff!, setindex!, symdiff, symdiff!,
    union, union!

import Pkg

using SparseArrays
import SparseArrays: AbstractSparseMatrix, findnz
import SparseArrays

import Random

using CxxWrap

using BinaryWrappers

using Scratch

# FLINT_jll now initializes the flint malloc functions
# to the corresponding julia functions.
# See also https://github.com/Nemocas/Nemo.jl/issues/788
using FLINT_jll

import Perl_jll
import Ninja_jll
import polymake_jll
import lib4ti2_jll
import TOPCOM_jll
using libpolymake_julia_jll


const jlpolymake_version_range = (v"0.6.0",  v"0.7")

struct PolymakeError <: Exception
    msg
end

function Base.showerror(io::IO, ex::PolymakeError)
    print(io, "Exception occured at Polymake side:\n$(ex.msg)")
end

###########################
# Load Cxx stuff and init
##########################

Sys.iswindows() && error("System is not supported!")

libcxxwrap_build_version() = VersionNumber(unsafe_string(ccall((:jlpolymake_libcxxwrap_build_version,libpolymake_julia), Cstring, ())))

jlpolymake_version() = VersionNumber(unsafe_string(ccall((:jlpolymake_version,libpolymake_julia), Cstring, ())))

function checkversion()
  jlpolymakeversion = jlpolymake_version()
  if !(jlpolymake_version_range[1] <= jlpolymakeversion < jlpolymake_version_range[2])
    error("This version of Polymake.jl requires libpolymake-julia in the range $(jlpolymake_version_range), but version $jlpolymakeversion was found")
  end
end

# Must also be called during precompile
checkversion()

const version_key = "$(VERSION.major).$(VERSION.minor)"
# unique per precompilation to ensure deps tree is updated
const rand_key = Random.randstring(10)

include("repl.jl")
include("ijulia.jl")

@wrapmodule(joinpath(libpolymake_julia), :define_module_polymake)

include(polymake_jll.generate_deps_tree)

include(type_translator)

function __init__()

    binpaths = [
                 @generate_wrappers(lib4ti2_jll),
                 @generate_wrappers(TOPCOM_jll),
                 @generate_wrappers(Ninja_jll),
                 @generate_wrappers(Perl_jll),
               ]
    polymake_deps_tree = @get_scratch!("polymake_deps_$(version_key)_$(rand_key)")
    if (!isdir(joinpath(polymake_deps_tree,"deps")))
        prepare_deps_tree(polymake_deps_tree)
    end

    polymake_user_dir = @get_scratch!("polymake_user_$(version_key)_$(rand_key)")

    checkversion()

    @initcxx

    # prepare environment variables
    ENV["PATH"] = join([binpaths...,ENV["PATH"]], ":")
    ENV["POLYMAKE_USER_DIR"] = polymake_user_dir
    ENV["POLYMAKE_DEPS_TREE"] = polymake_deps_tree

    try
        show_banner = isinteractive() &&
                       !any(x->x.name in ["Oscar"], keys(Base.package_locks))

        initialize_polymake(show_banner)
        if !show_banner
            shell_execute(raw"$Verbose::credits=\"0\";")
        end
    catch ex # initialize_polymake may throw jl_error
        ex isa ErrorException && throw(PolymakeError(ex.msg))
        rethrow(ex)
    end

    application("common")
    shell_execute("include(\"$(joinpath(@__DIR__, "polymake", "julia.rules"))\");")

    # work around issue with lp2poly and looking up perl modules from different applications
    application("polytope")
    Polymake.shell_execute("require LPparser;")

    # make sure 4ti2 is configured
    application("matroid")
    Polymake.shell_execute(raw"""
       application("polytope")->configured->{"_4ti2.rules"} > 0 or reconfigure("polytope::_4ti2.rules");
       application("matroid")->configured->{"_4ti2.rules"} > 0 or reconfigure("_4ti2.rules");
    """)

    for app in call_function(:common, :startup_applications)
        application(app)
    end
    application("common")

    # We need to set the Julia types as c types for polymake
    for (name, c_type) in C_TYPES
        current_type = Ptr{Cvoid}(pointer_from_objref(c_type))
        set_julia_type(name, current_type)
    end

    if isdefined(Base, :active_repl)
        run_polymake_repl()
    end

    if isdefined(Main, :IJulia) && Main.IJulia.inited
        prepare_jupyter_kernel_for_visualization()
    end

end

include("setup_apps.jl")
include("setup_types.jl")
include("util.jl")
include("call_function.jl")

include("perlobj.jl")
include("visual.jl")
include("convert.jl")

include("integers.jl")
include("rationals.jl")
include("sets.jl")
include("std/lists.jl")
include("std/pairs.jl")
include("vectors.jl")
include("matrices.jl")
include("sparsematrix.jl")
include("sparsevector.jl")
include("broadcast.jl")
include("arrays.jl")
include("incidencematrix.jl")
include("tropicalnumber.jl")
include("polynomial.jl")
include("map.jl")

include("polymake_direct_calls.jl")

include("generate_applications.jl")

include("get_attachment.jl")

include("polydb.jl")
end # of module Polymake
