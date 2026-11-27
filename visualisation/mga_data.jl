# Data loading and preprocessing for the MGA result plots.
#
# This file is `include`d by `plot_mga_results.jl`; it is not meant to be run on its own.
#
#   * one output DB per (MGA method, slack), each holding all cases as alternatives
#     `MGA-<method>-<case>`, e.g. `MGA-HSJ-DstrGridsInv-BF` and `MGA-HSJ-Base`;
#   * one input DB (`simulation_RPM-MGA/Input_MGA.sqlite`) whose scenarios carry the same names; the
#     technology capacities used to scale the investment variables are resolved per scenario.
#
# Only packages from the root Julia project are used. SQLite / DataFrames / StatsPlots are reached
# through PlotMGA (they are dependencies of PlotMGA, not direct dependencies of the root project).

using PlotMGA
using PlotMGA.SQLite      # also brings `DBInterface`
using PlotMGA.DataFrames
using Serialization       # stdlib, used for the result cache

# ------------------------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------------------------

const REPO_ROOT   = normpath(joinpath(@__DIR__, ".."))
const OUTPUT_DIR  = joinpath(REPO_ROOT, "OutputDBs")
const INPUT_DB    = joinpath(REPO_ROOT, "simulation_RPM-MGA", "Input_MGA.sqlite")
const CACHE_DIR   = joinpath(@__DIR__, ".cache")
const CACHE_VERSION = 1   # bump when the cached content changes

"MGA methods as named in the output DB files / alternatives / input scenarios."
const METHODS = ["HSJ", "Fuzzy"]
"MGA slack values (the `eps=` part of the output DB file names)."
const SLACKS  = ["0.1", "0.3", "0.6", "0.9"]

"Label of each method in the plots (alternative names, file names, legends)."
const METHOD_LABELS = Dict("HSJ" => "HSJ", "Fuzzy" => "RPM")

"""
Cases plotted by default, as `case => output folder name`. A case is the part of the output-DB
alternative / input-DB scenario name after `MGA-<method>-`. Other cases or folder names can also be given
on the command line (`--case=<case>:<folder>`, see `plot_mga_results.jl`).
"""
const DEFAULT_CASES = [
    "DstrGridsInv-BF" => "investable-grid",      # investable district grids
    "Base"            => "power-only-grid",
]
case_scenario(method, case) = "MGA-$(method)-$(case)"

"""
How several capacity entries of the same unit/connection *within one energy domain* are combined, e.g.
`connection__from_node` and `connection__to_node` of the same connection (same value): `maximum` counts
each connection once (`sum` would count it twice).
"""
const CAPACITY_REDUCER = maximum

"""
Energy domain of a node, derived from its name (`Electricity_…`, `Space_Heating_…`, `Hydrogen_…`).
Capacities are kept per domain: a unit with capacities in several domains (e.g. the electricity and heat
outputs of `Wood Pellet CHP (25 MW)`) gets one entry per domain, labelled `<technology> [<domain>]`, so that
it is compared with other technologies using the capacity of the matching energy vector.
"""
const DOMAINS = [
    r"^Electricity"   => "Electricity",
    r"^Space_Heating" => "Heat",
    r"^Hydrogen"      => "Hydrogen",
]
function node_domain(node)
    for (pattern, domain) in DOMAINS
        contains(node, pattern) && return domain
    end
    "Other"
end

"Output-DB parameters to load, with the columns to keep."
const OUTPUT_PARAMS = [
    :total_costs          => [:mga_iteration, :alternative, :total_value],
    :storages_invested    => [:mga_iteration, :alternative, :technology, :installation, :total_value, :technology_tag],
    :units_invested       => [:mga_iteration, :alternative, :technology, :installation, :total_value, :technology_tag],
    :unit_flow            => [:mga_iteration, :alternative, :technology, :installation, :destination, :total_value, :technology_tag],
    :node_state           => [:mga_iteration, :alternative, :technology, :total_value, :technology_tag],
    :connections_invested => [:mga_iteration, :alternative, :technology, :installation, :total_value, :technology_tag],
]

output_db_path(method, slack) = joinpath(OUTPUT_DIR, "Output_$(method)_eps=$(slack).sqlite")
alternative_label(method, slack) = "$(METHOD_LABELS[method])_eps=$(slack)"

# ------------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------------

"Replace SubString columns by String columns (smaller cache, no references to parent strings)."
function materialize_strings!(df::DataFrame)
    for col in names(df)
        eltype(df[!, col]) <: AbstractString && (df[!, col] = String.(df[!, col]))
    end
    df
end

"Technology name without the district/building suffix."
remove_district(technology) = String(first(split(technology, "_")))

"""
Merge numbered wind turbine units into one technology, e.g. `Wind Turbine 1 (onshore-2MW)` and
`Wind Turbine 2 (onshore-2MW)` -> `Wind Turbine (onshore-2MW)`.
"""
merge_numbered_units(technology) = replace(technology, r"^Wind Turbine \d+ \(" => "Wind Turbine (")

# ------------------------------------------------------------------------------------------------
# Output DBs (with cache)
# ------------------------------------------------------------------------------------------------

"""
    load_output_db(path) -> Dict{Symbol,DataFrame}

Read all `OUTPUT_PARAMS` from one output DB with PlotMGA's `get_spine_parameter` (all alternatives).
"""
function load_output_db(path)
    isfile(path) || error("Output DB not found: $path")
    db = SQLite.DB(path)
    try
        data = Dict{Symbol,DataFrame}()
        for (param, cols) in OUTPUT_PARAMS
            data[param] = materialize_strings!(get_spine_parameter(db, param, cols))
            GC.gc()  # the raw time series of `unit_flow` take several GB
        end
        return data
    finally
        SQLite.close(db)
    end
end

cache_path(path) = joinpath(CACHE_DIR, splitext(basename(path))[1] * ".jls")
cache_key(path) = (CACHE_VERSION, filesize(path), mtime(path))

"""
    load_output_db_cached(path; refresh=false)

Like `load_output_db`, but keeps the (small) processed tables in `.cache/` next to this file, so that
later runs do not re-read the multi-GB databases. The cache is invalidated when the DB file
changes (size / modification time) or when `refresh=true`.
"""
function load_output_db_cached(path; refresh::Bool=false)
    cpath = cache_path(path)
    if !refresh && isfile(cpath)
        cached = try
            deserialize(cpath)
        catch err
            @warn "Ignoring unreadable cache $cpath" exception = err
            nothing
        end
        if cached isa NamedTuple && get(cached, :key, nothing) == cache_key(path)
            @info "Using cached data for $(basename(path))"
            return cached.data
        end
    end
    @info "Reading $(basename(path)) (this takes a while) ..."
    data = load_output_db(path)
    mkpath(CACHE_DIR)
    serialize(cpath, (key=cache_key(path), data=data))
    data
end

"""
    load_all_outputs(; refresh=false) -> Dict{Symbol,DataFrame}

Load every output DB and stack the tables. Adds the columns
- `method`: method name as in the DBs (`HSJ`, `Fuzzy`),
- `case`: the output alternative without the `MGA-<method>-` prefix (e.g. `DstrGridsInv-BF`, `Base`),
and relabels `alternative` to `<method label>_eps=<slack>` (e.g. `HSJ_eps=0.1`, `RPM_eps=0.3`).
Alternatives that do not start with `MGA-<method>-` (e.g. `Base`) are dropped.
"""
function load_all_outputs(; refresh::Bool=false)
    stacked = Dict(param => DataFrame() for (param, _) in OUTPUT_PARAMS)
    for method in METHODS, slack in SLACKS
        path = output_db_path(method, slack)
        data = load_output_db_cached(path; refresh=refresh)
        prefix = case_scenario(method, "")
        for (param, _) in OUTPUT_PARAMS
            df = filter(:alternative => startswith(prefix), data[param])
            df.case = [String(chopprefix(a, prefix)) for a in df.alternative]
            df.method .= method
            df.alternative .= alternative_label(method, slack)
            stacked[param] = vcat(stacked[param], df; cols=:union)
        end
    end
    stacked
end

"Cases (output-DB alternatives without the `MGA-<method>-` prefix) found in the loaded results."
available_cases(all_data) = sort(unique(all_data[:total_costs].case))

# ------------------------------------------------------------------------------------------------
# Input DB: capacities per scenario
# ------------------------------------------------------------------------------------------------

"Alternative ranks of a scenario in the input DB (a higher rank overrides a lower one)."
function scenario_ranks(db, scenario)
    df = DBInterface.execute(db, """
        SELECT alternative.name AS alternative, scenario_alternative.rank AS rank
        FROM scenario_alternative
        JOIN scenario ON scenario.id = scenario_alternative.scenario_id
        JOIN alternative ON alternative.id = scenario_alternative.alternative_id
        WHERE scenario.name = ?;
    """, [scenario]) |> DataFrame
    nrow(df) > 0 || error("Scenario `$scenario` not found in $(INPUT_DB)")
    Dict(String(a) => r for (a, r) in zip(df.alternative, df.rank))
end

"""
    entity_elements(db) -> Dict(entity_id => element names)

Element names of every multi-dimensional entity, in order. They are read from `entity_element` rather than
parsed from the stored entity name: Spine does not update the stored name of e.g. a `unit__to_node` entity
when one of its elements is renamed, so the stored name may still show an old unit name.
"""
function entity_elements(db)
    df = DBInterface.execute(db, """
        SELECT entity_element.entity_id AS entity_id, entity_element.position AS position, element.name AS name
        FROM entity_element JOIN entity AS element ON element.id = entity_element.element_id;
    """) |> DataFrame
    sort!(df, [:entity_id, :position])
    Dict(key.entity_id => String.(sdf.name) for (key, sdf) in pairs(groupby(df, :entity_id)))
end

"Scalar value of a SpineDB parameter value blob (floats are stored as their text representation)."
function parse_scalar(blob, what)
    value = tryparse(Float64, String(copy(blob)))
    isnothing(value) && error("Non-scalar value for $what")
    value
end

"""
    scenario_parameter(db, param_name, scenario) -> DataFrame(technology_tag, node, value)

Values of `param_name` as seen by `scenario`: for every entity the value of the highest-ranked alternative
of the scenario. `technology_tag` is the first element (unit/connection/node name) and `node` the second
element (the first one for a 0-dimensional entity such as a node).
"""
function scenario_parameter(db, param_name, scenario)
    ranks = scenario_ranks(db, scenario)
    elements = entity_elements(db)
    df = DBInterface.execute(db, """
        SELECT parameter_value.entity_id AS entity_id, entity.name AS entity_name,
               alternative.name AS alternative, parameter_value.value AS value
        FROM parameter_value
        JOIN entity ON entity.id = parameter_value.entity_id
        JOIN alternative ON alternative.id = parameter_value.alternative_id
        WHERE parameter_value.parameter_definition_id IN
            (SELECT id FROM parameter_definition WHERE name = ?);
    """, [param_name]) |> DataFrame
    filter!(:alternative => in(keys(ranks)), df)
    df.rank = [ranks[a] for a in df.alternative]
    df = combine(groupby(df, :entity_id), sdf -> sdf[argmax(sdf.rank), [:entity_name, :value]])
    names_of(id, name) = get(elements, id, [String(name)])
    els = names_of.(df.entity_id, df.entity_name)
    DataFrame(
        technology_tag = first.(els),
        node = [length(e) >= 2 ? e[2] : e[1] for e in els],
        value = [parse_scalar(v, "`$param_name` of $(join(e, "__"))") for (v, e) in zip(df.value, els)],
    )
end

"""
    load_capacities(scenario) -> NamedTuple(units, nodes, connections)

Capacities used to scale the investment variables:
`unit_capacity` (units), `node_state_cap` (storage nodes), `connection_capacity` (connections).

Capacities are kept per energy domain of the node they refer to (`node_domain`): several entries of the
same unit/connection in the same domain are combined with `CAPACITY_REDUCER`; entries in different domains
stay separate rows. Columns: `technology_tag`, `domain`, `capacity`, `n_domains`.
"""
function load_capacities(scenario)
    db = SQLite.DB(INPUT_DB)
    try
        return map((units="unit_capacity", nodes="node_state_cap", connections="connection_capacity")) do p
            df = scenario_parameter(db, p, scenario)
            df.domain = node_domain.(df.node)
            caps = combine(groupby(df, [:technology_tag, :domain]), :value => CAPACITY_REDUCER => :capacity)
            transform!(groupby(caps, :technology_tag), nrow => :n_domains)
        end
    finally
        SQLite.close(db)
    end
end

"""
Multiply the (relative) investment variable by the capacity of its technology (one row per capacity
domain). Errors if a technology has no capacity in the input DB.
"""
function scale_by_capacity(df, capacities, what)
    out = leftjoin(df, capacities, on=:technology_tag)
    missing_tags = unique(out.technology_tag[ismissing.(out.capacity)])
    isempty(missing_tags) ||
        error("No capacity found in $(basename(INPUT_DB)) for $what: $(missing_tags)")
    out.total_value = out.total_value .* disallowmissing(out.capacity)
    out.domain = disallowmissing(out.domain)
    out.n_domains = disallowmissing(out.n_domains)
    select!(out, Not(:capacity))
end

"""
Label technologies that have capacities in several energy domains with the domain, e.g.
`Wood Pellet CHP (25 MW) [Electricity]`, and drop the helper columns.
"""
function label_capacity_domains!(df)
    multi = df.n_domains .> 1
    df.technology[multi] .= string.(df.technology[multi], " [", df.domain[multi], "]")
    select!(df, Not([:domain, :n_domains]))
end

# ------------------------------------------------------------------------------------------------
# Preprocessing per case
# ------------------------------------------------------------------------------------------------

"""
    prepare_case(all_data, case) -> NamedTuple

Select the results of one case (e.g. `DstrGridsInv-BF`) and process them:
- scale `units_invested` with `unit_capacity` (non-storage units) / `node_state_cap` (storages) and
  `connections_invested` with `connection_capacity`, taken from the matching input-DB scenario;
- strip district/building suffixes from technology names and merge numbered wind turbines;
- keep only technologies that are invested in at least once (investments, storages, node states);
- keep only unit flows into electricity, space heating and hydrogen nodes, and replace the flows of
  storages by their charged energy (increments of `node_state`).

Returns `(; total_costs, units_invested, storages_invested, unit_flows, connections_invested, storages)`.
"""
function prepare_case(all_data, case)
    sel(param) = filter(:case => ==(case), all_data[param])
    total_costs = sel(:total_costs)
    units_invested = sel(:units_invested)
    storages_invested = sel(:storages_invested)
    unit_flows = sel(:unit_flow)
    node_states = sel(:node_state)
    connections_invested = sel(:connections_invested)
    nrow(total_costs) > 0 ||
        error("No results for case `$case` in the output DBs; available cases: $(available_cases(all_data))")
    for method in METHODS, slack in SLACKS
        any(==(alternative_label(method, slack)), total_costs.alternative) ||
            @warn "No results for case `$case` in $(basename(output_db_path(method, slack)))"
    end

    # --- scale investments by capacities of the case's input scenario (per method) ----------------
    scaled_units = DataFrame()
    scaled_connections = DataFrame()
    for method in METHODS
        caps = load_capacities(case_scenario(method, case))
        storage_tags = caps.nodes.technology_tag
        unit_caps = filter(:technology_tag => !in(storage_tags), caps.units)
        all_caps = vcat(unit_caps, caps.nodes)
        scaled_units = vcat(scaled_units,
            scale_by_capacity(filter(:method => ==(method), units_invested), all_caps, "units ($case, $method)"))
        scaled_connections = vcat(scaled_connections,
            scale_by_capacity(filter(:method => ==(method), connections_invested), caps.connections,
                              "connections ($case, $method)"))
    end
    units_invested = scaled_units
    connections_invested = scaled_connections

    # --- technology names -------------------------------------------------------------------------
    for df in (units_invested, storages_invested, unit_flows)
        df.technology = merge_numbered_units.(remove_district.(df.technology))
    end
    label_capacity_domains!(units_invested)
    label_capacity_domains!(connections_invested)

    # All storage technologies (also those never invested in), so that their flows are never shown as
    # "Production".
    storages = unique(storages_invested.technology)

    # --- keep technologies that are used --------------------------------------------------------
    tech_total = combine(groupby(units_invested, :technology), :total_value => sum => :total_value)
    used_tech = tech_total.technology[tech_total.total_value .> 0]
    filter!(:technology => in(used_tech), storages_invested)
    filter!(:technology => in(used_tech), units_invested)
    filter!(:destination => contains(r"(Electricity|Space_Heating|Hydrogen)"), unit_flows)

    # --- storage "flows" = charged energy from node_state increments -------------------------
    storage_state = select(node_states, :mga_iteration, :alternative, :technology_tag,
                           :total_value => :storage_value)
    unit_flows = leftjoin(unit_flows, storage_state, on=[:mga_iteration, :alternative, :technology_tag])
    is_storage = in.(unit_flows.technology, Ref(storages))
    no_state = is_storage .& ismissing.(unit_flows.storage_value)
    any(no_state) && error("No node_state for storage units: $(unique(unit_flows.technology_tag[no_state]))")
    unit_flows.total_value = ifelse.(is_storage, coalesce.(unit_flows.storage_value, 0.0), unit_flows.total_value)
    select!(unit_flows, Not(:storage_value))
    sort!(unit_flows, :alternative)

    (; total_costs, units_invested, storages_invested, unit_flows, connections_invested, storages)
end
