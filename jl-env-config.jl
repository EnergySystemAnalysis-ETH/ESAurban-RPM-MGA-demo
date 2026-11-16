using Pkg
Pkg.activate(Base.current_project(@__DIR__))
Pkg.instantiate()

# Point `PyCall.jl` at the python of the activated conda python (layout differs by OS)
conda_prefix = ENV["CONDA_PREFIX"]
ENV["PYTHON"] = Sys.iswindows() ? joinpath(conda_prefix, "python.exe") :
                                  joinpath(conda_prefix, "bin", "python")
Pkg.build("PyCall")

using PyCall
py_prefix = pyimport("sys").prefix
println("PyCall.python = ", PyCall.python)
println("sys.prefix    = ", py_prefix)
realpath(py_prefix) == realpath(conda_prefix) ||
    error("PyCall uses $(py_prefix), \nexpected the activated conda env $(conda_prefix).")

using SpineInterface, SpineOpt
println("All setup completed successfully!")
