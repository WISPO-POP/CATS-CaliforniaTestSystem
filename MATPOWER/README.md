# MATPOWER: CATS network in MATPOWER case format

This folder holds the current California Test System network as a MATPOWER version 2 case file. The file defines one function, `CaliforniaTestSystem`, which returns the case struct `mpc`. It is the file that `run_opf.jl` and `Script/test_eval.jl` load. **Author (git history):** Sofia Taylor, 2022 to 2024; the first version of the file was added by Aditya Rangarajan in 2022.

## Files

| File | What it contains |
|---|---|
| `CaliforniaTestSystem.m` | Bus, generator, branch and generator cost tables of the current CATS model (updated 2023-11-11; function renamed to `CaliforniaTestSystem` on 2024-02-28) |

## Case summary

Counted from the file:

| Item | Value |
|---|---|
| System base | 100 MVA |
| Buses | 8,870 (8,085 PQ, 784 PV, 1 reference) |
| Bus voltage levels | 500 kV (92 buses), 230 kV (1,028), 115 kV (2,016), 66 kV (5,734) |
| Generators | 3,892, all in service |
| Branches | 10,823, all in service; 661 have a non-zero tap ratio (transformers) |
| Generator costs | Polynomial (model 2) with three coefficients for every generator: 1,229 have a non-zero quadratic term, 28 are linear only, and 2,635 have zero cost |
| Total bus real power demand | About 44,009 MW |

## Link to the GIS files

- `GIS/CATS_buses.csv` has one row per bus, in the same order as `mpc.bus`, with the same bus numbers and kV, plus latitude and longitude.
- `GIS/CATS_gens.csv` has one row per generator, in the same order as `mpc.gen` (row *i* is generator *i*; bus and Pmax match), plus plant code, generator ID, fuel type, latitude and longitude.
- `GIS/CATS_lines.json` has one GeoJSON feature per branch (10,823). Each feature carries `f_bus` and `t_bus` in MATPOWER bus numbers, and the features cover the same from/to bus pairs as `mpc.branch`. The first 10,162 features are in the same order as `mpc.branch`; the last 661 (all transformers) are in a different order.

## Setup

Use either MATPOWER in MATLAB or GNU Octave, or Julia with PowerModels.jl. See Setup in the [root README](../README.md#setup).

## Running

In MATLAB or Octave, from the repository root:

```matlab
addpath('MATPOWER');
mpc = loadcase('CaliforniaTestSystem');
results = rundcopf(mpc);
```

In Julia, from the repository root (this is what `run_opf.jl` does):

```julia
using PowerModels, Ipopt
data = PowerModels.parse_file("MATPOWER/CaliforniaTestSystem.m")
result = solve_opf(data, DCPPowerModel, Ipopt.Optimizer)
```

## Inputs and outputs

- `CaliforniaTestSystem.m` is an input only. MATPOWER and PowerModels.jl read it directly; nothing in the repository writes it.
- The previous version of the case is `Archive/CaliforniaTestSystem.m`.
