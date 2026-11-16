# RPM-MGA demo with ESAurban-SpineOpt model instance

## Environment setup

- Use the root directory of this repository as the working directory in the following commands.
- **Note**: ideally, ensure the "path" doesn't contain any spaces.

```bash
cd path/to/ESAurban-RPM-MGA-demo
```

### 1. Python environment (via `conda`)

- default compatible version: python 3.14 

```bash
conda env create -f conda-py-env.yml
conda activate spine-tools-demo
```

### 2. Julia environment (Julia 1.13 via `juliaup`)

- default compatible version: Julia 1.13.4 (recommend using Juliaup: `juliaup add 1.13.4`)
- the conda environment `spine-tools-demo` **must be activated** before running the following commands:
```bash
(spine-tools-demo) > julia --project=@. -i "jl-env-config.jl"
```

### 3. Solver: Gurobi licence required

- The simulation scripts in `simulation_RPM-MGA/` solve the model with [Gurobi](https://www.gurobi.com) through `Gurobi.jl`, so a **valid Gurobi licence** is required to run them. The environment setup above works without a licence; the licence is only needed when the solver is called.
- `Gurobi.jl` downloads the Gurobi binaries automatically, so no separate Gurobi installation is needed. Only the licence file has to be set up.
- Academic users can get a free licence from the [Gurobi Academic Program](https://www.gurobi.com/academia/academic-program-and-licenses/).
- Place the licence file `gurobi.lic` in its default location (your home directory), or point the environment variable `GRB_LICENSE_FILE` to it.
- Check the licence: if it is found, the following command prints your licence details, e.g. `Academic license - for non-commercial use only`.
```bash
julia --project=@. -e "using Gurobi; Gurobi.Env()"
```
