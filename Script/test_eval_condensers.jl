# using Pkg
# Pkg.develop(path = "/home/jlara/HSL_jll.jl-2023.11.7")
# using HSL_jll

using PowerModels
using JuMP
using CSV, JSON
using DataFrames
using Ipopt #, Gurobi
# change these
DATA_DIR = "data"
save_to_JSON = false
# run for N hours (scenarios)
N = 8760
CUTOFF = 75

solver = Ipopt.Optimizer #JuMP.optimizer_with_attributes(() -> Ipopt.Optimizer(), "print_level" => 1)

# copy-pasted from output of difficult-timesteps.
difficultTimesteps = [71, 95, 322, 359, 597, 666, 742, 824, 1031, 2107, 2181, 2374, 2539, 2635, 2827, 2830, 2875, 3238, 3899, 4169, 4384, 4698, 4717, 4947, 5024, 5184, 5238, 5436, 5450, 5677, 5786, 6040, 6303, 6335, 6352, 6442, 6741, 6927, 7103, 7303, 7362, 7463, 7472, 7625, 7653, 7654, 7727, 7913, 8425, 8711]

include("test_eval_functions.jl")
load_scenarios = CSV.read("$DATA_DIR/Load_Agg_Post_Assignment_v3_latest.csv",header = false, DataFrame)
load_scenarios = load_scenarios[:,1:N]

# NetworkData = PowerModels.parse_file("$CATS_DIR/MATPOWER/CaliforniaTestSystem.m")
NetworkData = PowerModels.parse_file("MATPOWER/system_condensers_removed_cutoff$CUTOFF.m")

# gen_data = CSV.read("$CATS_DIR/GIS/CATS_gens.csv",DataFrame)
gen_data = CSV.read("GIS/CATS_gens_condensers_removed_cutoff$CUTOFF.csv",DataFrame)
NUM_GENS = size(gen_data)[1]

PMaxOG = [NetworkData["gen"][string(i)]["pmax"] for i in 1:NUM_GENS]
println(sum(PMaxOG))

SolarGenIndex = [g for g in 1:NUM_GENS if occursin("solar", lowercase(gen_data.FuelType[g]))]
WindGenIndex= [g for g in 1:NUM_GENS if occursin("wind", lowercase(gen_data.FuelType[g]))]
condenserIndices = [g for g in 1:size(gen_data)[1] if occursin("condenser", lowercase(gen_data.FuelType[g]))]
# condenserReactiveFlows = DataFrame("timestep" => Int[],
#                        ("gen $x" => Float64[] for x in condenserIndices)...)

# condenserReactiveFlows = DataFrame("timestep" => Int[],
# ("gen $x" => Float64[] for x in condenserIndices)...)
# CSV.write("$DATA_DIR/condenserReactiveFlows.csv", condenserReactiveFlows; append=true)

SolarCap = sum(g["pmax"] for (i,g) in NetworkData["gen"] if g["index"] in SolarGenIndex)
WindCap = sum(g["pmax"] for (i,g) in NetworkData["gen"] if g["index"] in WindGenIndex)

load_mapping = map_buses_to_loads(NetworkData)

# I can't add HourlyProduction2019.csv to the git repo: it's too large.
HourlyData2019 = CSV.read("$DATA_DIR/HourlyProduction2019.csv",DataFrame)
SolarGeneration = HourlyData2019[1:N,"Solar"]
WindGeneration = HourlyData2019[1:N,"Wind"]


# Create dataframe to store results
results = []


@time begin
    # Threads.@threads
    for k = 1:N # change to small number for testing.
        if !(k in difficultTimesteps)
            continue
        end
        #println("k = $k on thread $(Threads.threadid())")
        println(k)
        # Change renewable generators' pg for the current scenario
        update_rgen!(k,NetworkData,gen_data,SolarGeneration,WindGeneration,PMaxOG,SolarCap,WindCap)
        #println(sum(NetworkData["gen"][string(i)]["pmax"] for i in 1:size(gen_data)[1]))

        # Change load buses' Pd and Qd for the current scenario
        update_loads!(k, load_scenarios, load_mapping, NetworkData)

        # Run power flow
        solution = PowerModels.solve_opf(NetworkData, ACPPowerModel, solver)
        #push!(results, (renewable_scenarios[!,1][k], solution["termination_status"]))
        #Save solution dictionary to JSON
        if save_to_JSON == true
           export_JSON(solution, k, "solutions")
        end
        push!(results,  solution["termination_status"])
        #nextRow = solution["solution"]["gen"][FIRST_CONDENSER:NUM_GENS]
        #push!(condenserReactiveFlows, (k, (solution["solution"]["gen"]["$x"]["qg"] for x in condenserIndices)...))
        #CSV.write("condenserReactiveFlows.csv", condenserReactiveFlows)

        # I got stack overflow with these lines. Plus for now we're mostly interested in if a solution exists.
        #tmp_condenserReactiveFlows = Tables.table([k, [solution["solution"]["gen"]["$x"]["qg"] for x in condenserIndices...]])
        # CSV.write("condenserReactiveFlows.csv", tmp_condenserReactiveFlows; append=true)
    end
end
using MathOptInterface
for status in [MathOptInterface.LOCALLY_INFEASIBLE, MathOptInterface.LOCALLY_SOLVED, MathOptInterface.ALMOST_LOCALLY_SOLVED]
    n = count(==(status), results)
    println("$status: $n")
end
#=
open("termination_status_ACOPF_corrected_cc.txt", "w") do file
    for i in 1:length(results)
        if results[i] == LOCALLY_SOLVED
            write(file, "Locally Solved\n")
        elseif results[i] == LOCALLY_INFEASIBLE
            write(file,"Locally Infeasible\n")
        elseif results[i] == ALMOST_LOCALLY_SOLVED
            write(file, " Solved to an acceptable level\n")
        else
            println(i)
        end
    end
end
=#
