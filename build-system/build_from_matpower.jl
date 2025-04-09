using PowerSystems

include("parse-matpower.jl");
system = System("MATPOWER/CaliforniaTestSystem.m");
include("replace_gens.jl");
include("define_time_series.jl");

display(system)