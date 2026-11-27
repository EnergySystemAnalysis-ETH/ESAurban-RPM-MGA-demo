[![DOI](https://zenodo.org/badge/github/1460335097.svg)](https://doi.org/10.5281/zenodo.24591109)

# RPM-MGA demo with ESAurban-SpineOpt model instance

This repository presents a multi-energy system optimisation model (ESAurban-SpineOpt) of the urban residential energy system of Wohlen (AG) Switzerland, formulated by the [SpineOpt.jl](https://github.com/spine-tools/SpineOpt.jl) modelling framework.

The model aims to demonstrate 2 Modeling to Generate Alternatives (MGA) algorithms, [Reference-Point-Mothod (RPM) Fuzzy MGA](https://spine-tools.github.io/SpineOpt.jl/latest/advanced_concepts/mga/#RPM-Fuzzy-MGA) vs. [Hop-Skip-Jump (HSJ) MGA](https://spine-tools.github.io/SpineOpt.jl/latest/advanced_concepts/mga/#Hop-Skip-Jump-MGA), in a single-year investment planning problem by mixed-integer linear programming (MILP).

- Start: Clone the repository
```shell
git clone https://github.com/EnergySystemAnalysis-ETH/ESAurban-RPM-MGA-demo.git
```

- To run the optimisation in `julia` (starting from the root directory of this repo).  
> Note: this requires setting up the environment first, see the next section.  
```shell
cd ./simulation_RPM-MGA
julia runSpineOpt-1-HSJ-MultiEPS.jl
julia runSpineOpt-2-Fuzzy-MultiEPS.jl
```

- Results to be stored in `OutputDBs/` as `.sqlite` databases (see examples in the release).
- To plot the comparison of the two MGA algorithms:
```shell
cd ./visualisation
julia plot_mga_results.jl
```

## Environment setup

- Use the root directory of this repository as the working directory in the following commands.
- **Note**: ideally, ensure the "path" doesn't contain any spaces.

```shell
cd path/to/ESAurban-RPM-MGA-demo
```

### 1. Python environment (via `conda`)

- default compatible version: python 3.14 

```shell
conda env create -f conda-py-env.yml
conda activate spine-tools-demo
```

### 2. Julia environment (Julia 1.13 via `juliaup`)

- default compatible version: Julia 1.13.4 (recommend using Juliaup: `juliaup add 1.13.4`)
- the conda environment `spine-tools-demo` **must be activated** before running the following commands:
```shell
(spine-tools-demo) > julia --project=@. -i "jl-env-config.jl"
```

### 3. Solver: Gurobi licence required

- The simulation scripts in `simulation_RPM-MGA/` solve the model with [Gurobi](https://www.gurobi.com) through `Gurobi.jl`, so a **valid Gurobi licence** is required to run them. The environment setup above works without a licence; the licence is only needed when the solver is called.
- `Gurobi.jl` downloads the Gurobi binaries automatically, so no separate Gurobi installation is needed. Only the licence file has to be set up.
- Academic users can get a free licence from the [Gurobi Academic Program](https://www.gurobi.com/academia/academic-program-and-licenses/).
- Place the licence file `gurobi.lic` in its default location (your home directory), or point the environment variable `GRB_LICENSE_FILE` to it.
- Check the licence: if it is found, the following command prints your licence details, e.g. `Academic license - for non-commercial use only`.
```shell
julia --project=@. -e "using Gurobi; Gurobi.Env()"
```
