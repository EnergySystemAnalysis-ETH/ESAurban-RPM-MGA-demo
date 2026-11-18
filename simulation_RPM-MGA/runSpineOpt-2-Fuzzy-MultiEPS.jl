import Pkg
let proj = Base.current_project(@__DIR__) === nothing ? 
    Base.current_project(pwd()) : 
    Base.current_project(@__DIR__)
    isnothing(proj) && begin
        @error "No Project.toml found above \'$(@__DIR__)\' or\n
                the currect working directory \'$(pwd())\'."
        @info "Please ensure that a Julia project environment contains either\n
                (1) this script $(@__FILE__) or\n(2) the working directory  (esp. if you run this script from REPL)."
        exit(1)
    end
    Pkg.activate(dirname(proj); io=devnull)
end

# ---- run definitions ----
input_db_core = "MGA"
method = "Fuzzy"
iteration = 20
scenarios = ["MGA-$(method)-Base", "MGA-$(method)-DstrGridsInv-BF"]
array_runs = [(slack, iteration) for slack in [0.1, 0.3, 0.6, 0.9]]

run_ids = eachindex(array_runs)

using SpineOpt, SpineInterface
using JuMP, Gurobi

include("./simulation_mga_config.jl")

@info "Julia threads: ", Threads.nthreads()

for i in run_ids
    mga_slack, mga_iteration = array_runs[i]
    update_mga_config(input_db_core, mga_slack, mga_iteration; alternative="MGA-invest")  
    for scenario in scenarios
        simulation_run_mga(input_db_core, method, mga_slack, scenario)
    end
end
