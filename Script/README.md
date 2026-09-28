# Script: hourly AC optimal power flow of CATS

`test_eval.jl` loads the CATS MATPOWER case and, for each hour in its loop, sets the load at each bus that has a load in the case and the maximum output of every solar and wind generator from time-series files. It then solves an AC optimal power flow with PowerModels.jl (`ACPPowerModel`) and Ipopt and records the solver's termination status. `test_eval_functions.jl` holds the helper functions. **Author (git history):** Aditya Rangarajan and Dinah Shi, 2024.

## Files

| File | What it does |
|---|---|
| `test_eval.jl` | Main script. Settings at the top: `save_to_JSON = true`, `save_summary = false`, `N = 8760`. Loads the case, `GIS/CATS_gens.csv` and the two time-series files, then loops `for k = 8649:N` and calls `solve_opf(NetworkData, ACPPowerModel, Ipopt.Optimizer)` for each hour `k`. |
| `test_eval_functions.jl` | `map_buses_to_loads` (bus number to load index), `update_loads!` (sets `pd` and `qd` of each load for hour `k`), `update_rgen!` (sets `pmax` of the solar and wind generators for hour `k`), `export_JSON` (writes one solution file). |

## How the hourly data are applied

- Loads: the script reads the load file with no header row (`header = false`) and treats row *i* as the load at bus *i* and column *k* as hour *k*. It expects each cell to be a complex power string `P+Qi` (MW and MVAr), splits it at `+`, divides by the case base (100 MVA) and sets `pd` and `qd` of the load at that bus. Rows for buses with zero `Pd` and `Qd` in the case file are skipped, because PowerModels creates a load only for buses with non-zero demand (2,472 of the 8,870 buses).
- Solar and wind: a generator is treated as solar or wind when its `FuelType` in `GIS/CATS_gens.csv` contains "solar" or "wind" (any case). For hour *k*, each such generator gets `pmax` = (the `Solar` or `Wind` value of `HourlyProduction2019.csv` for hour *k*) × (its Pmax in the case) / (total Pmax of all generators of that type in the case). `pmin` is not changed.
- All other generator limits and the network stay as in the case file.

## Known issues

- As committed, the loop runs hours 8649 to 8760 only (the last 112 hours of the year). Change `for k = 8649:N` to `for k = 1:N` for the full year.
- `using Gurobi, Ipopt` loads Gurobi.jl although the active solver is Ipopt (the Gurobi solver lines are commented out). The script stops at that line if Gurobi.jl is not installed; install it or remove `Gurobi, ` from the line.
- `export_JSON` writes `solutions/solution_<k>.json` relative to the current folder, and Julia's `open` does not create folders. With the default `save_to_JSON = true`, create `Script/solutions/` before running.
- `save_summary = true` would fail: `CSV.write(results, "eval_results.csv")` has its arguments in the reverse order of `CSV.write(file, table)`, and `results` is a plain vector, not a table.
- The two input files in `data/` are not in the repository (`data/` is listed in `.gitignore`).
- `termination_status_ACOPF_corrected_cc.txt` gets a line only for `LOCALLY_SOLVED`, `LOCALLY_INFEASIBLE` and `ALMOST_LOCALLY_SOLVED`. Any other status is printed to the console by its position in the run and gets no line in the file, so file lines can fall out of step with hours.

## Setup

1. Install Julia and the packages listed in the [root README](../README.md#setup), plus `Gurobi` (or remove it from the `using` line, see Known issues).
2. Put `Load_Agg_Post_Assignment_v3_latest.csv` and `HourlyProduction2019.csv` in a `data/` folder at the repository root (one level above this folder).
3. Create an empty `solutions/` folder inside `Script/`.
4. Edit the loop range in `test_eval.jl` if you want hours other than 8649 to 8760.

## Running

All paths in the script are relative to this folder (`include("test_eval_functions.jl")`, `../data/`, `../MATPOWER/`, `../GIS/`), so run it from here:

```
cd Script
mkdir solutions
julia test_eval.jl
```

There are no absolute paths to edit.

## Inputs and outputs

Inputs:

- `../MATPOWER/CaliforniaTestSystem.m`: the network.
- `../GIS/CATS_gens.csv`: `FuelType` of each generator, in the same order as the case's generators.
- `../data/Load_Agg_Post_Assignment_v3_latest.csv`: hourly load per bus; the first `N` columns are used.
- `../data/HourlyProduction2019.csv`: columns `Solar` and `Wind`; the first `N` rows are used.

Outputs (written in `Script/`):

- `solutions/solution_<k>.json`: the full PowerModels result for hour `k` (when `save_to_JSON = true`).
- `termination_status_ACOPF_corrected_cc.txt`: the solver status of each hour (see Known issues).
- Console: the total generator Pmax of the case (per unit) at the start, each hour number as it is solved, the Ipopt log, and the elapsed time at the end (`@time`).
