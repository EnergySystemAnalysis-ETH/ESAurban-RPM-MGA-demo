# Plot the MGA results of the output DBs in `OutputDBs/` using PlotMGA.jl 
# (with technology capacities from the input DB `simulation_RPM-MGA/Input_MGA.sqlite`). 
#
# Usage (the root Julia project of the repository is activated automatically):
#     julia plot_mga_results.jl [options]
#
# Options:
#     --case=<case>[:<folder>]  plot this case into <outdir>/<folder> (can be repeated). <case> is the
#                               output-DB alternative / input-DB scenario name without `MGA-<method>-`,
#                               e.g. `--case=DstrGridsInv-BF:investable-grid`. Without `:<folder>` the folder of
#                               DEFAULT_CASES (mga_data.jl) is used, or else the case name.
#                               Default: all DEFAULT_CASES.
#     --outdir=PATH             output folder (default: plots/ next to this script)
#     --refresh                 re-read the output DBs instead of using the cache (.cache/)
#     --interactions            also plot technology interaction figures (one per technology pair)
#
# Output (per case folder):
#     mga_profile_for_<Commodity> <Production|Storage>_<alternative>.png
#     technology_effects_on_cost_<technology>.png
#     technology_interactions_<technology1>_<technology2>.png
#     connections_investment_<Heat|H2> _<alternative>.png      (cases with connection investments)

import Pkg
let proj = Base.current_project(@__DIR__)
    isnothing(proj) && error("No Project.toml found above $(@__DIR__)")
    Pkg.activate(dirname(proj); io=devnull)
end

ENV["GKSwstype"] = "100"  # headless GR: no plot windows

include(joinpath(@__DIR__, "mga_data.jl"))
using PlotMGA.StatsPlots
gr()

# ------------------------------------------------------------------------------------------------
# Plot definitions
# ------------------------------------------------------------------------------------------------

"Markers of the alternatives in the scatter plots."
function alternative_markers()
    method_markers = Dict(
        "HSJ"   => fill(:x, length(SLACKS)),
        "Fuzzy" => [:utriangle, :rect, :pentagon, :hexagon],
    )
    markers = Dict{String,Symbol}("Optimal" => :circle)
    for method in METHODS, (i, slack) in enumerate(SLACKS)
        markers[alternative_label(method, slack)] = method_markers[method][i]
    end
    markers
end

const COMMODITY_TYPES = [
    ProfileType("Electricity", :destination => ByRow(contains("Electricity"))),
    ProfileType("Heat", :destination => ByRow(contains("Space_Heating"))),
    ProfileType("Hydrogen", :destination => ByRow(contains("Hydrogen"))),
]

production_types(storages) = [
    ProfileType("Production", :technology => ByRow(!in(storages))),
    ProfileType("Storage", :technology => ByRow(in(storages))),
]

const CONNECTION_TYPES = [
    ProfileType("Heat", :technology => ByRow(contains("Heating"))),
    ProfileType("H2", :technology => ByRow(contains("H2"))),
]
# A second, always-true group: gives file names `connections_investment_Heat _<alternative>.png`
const ALL_ITERATIONS = [ProfileType("", :mga_iteration => ByRow(x -> true))]

# ------------------------------------------------------------------------------------------------
# Plotting
# ------------------------------------------------------------------------------------------------

"File name prefixes of the figures written by this script."
const FIGURE_PREFIXES = ("mga_profile_for_", "technology_effects_on_cost_", "technology_interactions_",
                         "connections_investment_")

"Remove figures of a previous run (only PNGs with this script's prefixes), so no stale files remain."
function remove_old_figures(folder)
    for f in readdir(folder)
        endswith(f, ".png") && any(p -> startswith(f, p), FIGURE_PREFIXES) && rm(joinpath(folder, f))
    end
end

function plot_case(all_data, case, folder; interactions::Bool=false)
    @info "Plotting case `$case` into $folder ..."
    d = prepare_case(all_data, case)
    mkpath(folder)
    remove_old_figures(folder)
    prefix(name) = joinpath(folder, name)
    markers = alternative_markers()

    # Production and storage profiles over the MGA iterations [GWh]
    plot_all_mga_profiles(
        d.unit_flows, PlotMGA.GWh, COMMODITY_TYPES, production_types(d.storages);
        fig_prefix=prefix("mga_profile_for_"), display_plot=false,
    )

    # Invested capacity of every technology vs. total system costs
    plot_technology_effects(
        d.units_invested, d.total_costs, markers;
        fig_prefix=prefix("technology_effects_on_cost_"), display_plot=false,
    )

    if interactions
        plot_technology_interactions(
            d.units_invested, d.total_costs, markers;
            fig_prefix=prefix("technology_interactions_"), display_plot=false,
        )
    end

    # Investments in district heating / hydrogen connections [MW] (only if the case invests in any)
    if any(>(0), d.connections_invested.total_value)
        plot_all_mga_profiles(
            d.connections_invested, PlotMGA.MWh, CONNECTION_TYPES, ALL_ITERATIONS;
            fig_prefix=prefix("connections_investment_"), display_plot=false,
        )
    end

    n = count(endswith(".png"), readdir(folder))
    @info "Case `$case`: $n figures in $folder"
end

"""
    parse_args(args) -> (; cases, outdir, refresh, interactions)

`cases` is a vector of `case => folder name` pairs (see the header of this file).
"""
function parse_args(args)
    defaults = Dict(DEFAULT_CASES)
    cases = Pair{String,String}[]
    outdir = joinpath(@__DIR__, "plots")
    refresh = interactions = false
    for arg in args
        if startswith(arg, "--case=")
            spec = chopprefix(arg, "--case=")
            case, folder = contains(spec, ":") ? split(spec, ":", limit=2) : (spec, get(defaults, spec, spec))
            (isempty(case) || isempty(folder)) && error("Invalid option `$arg`; expected --case=<case>[:<folder>]")
            push!(cases, String(case) => String(folder))
        elseif startswith(arg, "--outdir=")
            outdir = abspath(chopprefix(arg, "--outdir="))
        elseif arg == "--refresh"
            refresh = true
        elseif arg == "--interactions"
            interactions = true
        else
            error("Unknown argument `$arg` (see the header of $(basename(@__FILE__)))")
        end
    end
    isempty(cases) && append!(cases, DEFAULT_CASES)
    folders = last.(cases)
    allunique(folders) || error("Several cases would be plotted into the same folder: $cases")
    (; cases, outdir, refresh, interactions)
end

function main(args=ARGS)
    opts = parse_args(args)
    all_data = load_all_outputs(; refresh=opts.refresh)
    for (case, folder) in opts.cases
        plot_case(all_data, case, joinpath(opts.outdir, folder); interactions=opts.interactions)
    end
end

abspath(PROGRAM_FILE) == (@__FILE__) && main()
