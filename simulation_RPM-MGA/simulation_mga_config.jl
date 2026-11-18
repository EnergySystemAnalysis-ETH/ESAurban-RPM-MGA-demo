using JuMP, SpineInterface, SpineOpt

function update_mga_config(
    db_name::String, mga_slack::Real, iteration::Real;
    alternative::Union{Symbol, String}="Basic"
)
    Y = Bind()  # dummy Module created using SpineInterface
    db_url = "sqlite:///$(@__DIR__)/Input_$(db_name).sqlite"
    
    using_spinedb(db_url, Y)
    max_mga_slack = map(
        m -> [m.class_name, m.name, :max_mga_slack, mga_slack, alternative], 
        indices(Y.max_mga_slack)
    )
    max_mga_iterations = map(
        m -> [m.class_name, m.name, :max_mga_iterations, iteration, alternative], 
        indices(Y.max_mga_iterations)
    )
    mga_config = Dict(
        :object_parameter_values => vcat(max_mga_slack, max_mga_iterations)
    )
    SpineInterface.import_data(db_url, mga_config, "Update mga configuration"; upgrade=true)
    
    using_spinedb(db_url, Y)
    map(m -> println(
        "MGA config for model `$(m)`: slack=$(Y.max_mga_slack(model=m)), iteration=$(Y.max_mga_iterations(model=m))"
    ), Y.model())
end

function simulation_run_mga(mga_input_db::String, mga_method::String, mga_slack::Real, model_scenario::String)
    db_report_term = "$(mga_method)_eps=$(mga_slack)"
    
    input_db_url = "sqlite:///$(@__DIR__)/Input_$(mga_input_db).sqlite"
    output_db_url = "sqlite:///$(@__DIR__)/Output_$(db_report_term).sqlite"

    @info "Running simulation with $(mga_method) MGA method (slack=$(mga_slack)) on scenario '$(model_scenario)' ... "
    
    log_dir = joinpath(@__DIR__, "log-julia"); mkpath(log_dir)  # no-op if it already exists
    solver_threads = Threads.nthreads()
    m = run_spineopt(
        input_db_url, output_db_url; upgrade=true, 
        lp_solver=optimizer_with_attributes(Gurobi.Optimizer, 
            "Threads" => solver_threads, "Method" => 2, 
        ),
        mip_solver=optimizer_with_attributes(Gurobi.Optimizer, 
            "Threads" => solver_threads, "Method" => 2, "NodeMethod" => 2, "MIPFocus" => 0, 
        ),
        log_file_path=joinpath(
            log_dir, 
            "runSpineOpt-$(get(ENV, "SLURM_ARRAY_TASK_ID", "local"))-$(db_report_term)-$(model_scenario).txt"
        ),
        filters=Dict("scenario" => model_scenario),
        alternative=model_scenario
    )
    @info "Simulation with $(mga_method) MGA method (slack=$(mga_slack)) on scenario '$(model_scenario)' completed."
    return m
end