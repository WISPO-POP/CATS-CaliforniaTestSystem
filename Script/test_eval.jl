using PowerModels
using JuMP
using CSV, JSON
using DataFrames
using Gurobi, Ipopt

#println(Threads.nthreads())
# User input
save_to_JSON = true
save_summary = false
N = 8760
# run for N hours (scenarios)

# Specify solver
#const GUROBI_ENV = Gurobi.Env()
# solver = JuMP.optimizer_with_attributes(() -> Gurobi.Optimizer(GUROBI_ENV), "OutputFlag" => 1)

# const IPOPT_ENV = Ipopt.Env()
solver = Ipopt.Optimizer #JuMP.optimizer_with_attributes(() -> Ipopt.Optimizer(), "print_level" => 1)

include("test_eval_functions.jl")
load_scenarios = CSV.read("../data/Load_Agg_Post_Assignment_v3_latest.csv",header = false, DataFrame)
load_scenarios = load_scenarios[:,1:N]

NetworkData = PowerModels.parse_file("../MATPOWER/CaliforniaTestSystem.m")

gen_data = CSV.read("../GIS/CATS_gens.csv",DataFrame)

PMaxOG = [NetworkData["gen"][string(i)]["pmax"] for i in 1:size(gen_data)[1]]
println(sum(PMaxOG))

SolarGenIndex = [g for g in 1:size(gen_data)[1] if occursin("solar", lowercase(gen_data.FuelType[g]))]
WindGenIndex= [g for g in 1:size(gen_data)[1] if occursin("wind", lowercase(gen_data.FuelType[g]))]

SolarCap = sum(g["pmax"] for (i,g) in NetworkData["gen"] if g["index"] in SolarGenIndex)
WindCap = sum(g["pmax"] for (i,g) in NetworkData["gen"] if g["index"] in WindGenIndex)

load_mapping = map_buses_to_loads(NetworkData)

HourlyData2019 = CSV.read("../data/HourlyProduction2019.csv",DataFrame)
SolarGeneration = HourlyData2019[1:N,"Solar"]
WindGeneration = HourlyData2019[1:N,"Wind"]

# Create dataframe to store results
results = []

@time begin
    #Threads.@threads
    for k = 8649:N
        #println("k = $k on thread $(Threads.threadid())")
        println(k)
        # Change renewable generators' pg for the current scenario
        update_rgen!(k,NetworkData,gen_data,SolarGeneration,WindGeneration,PMaxOG,SolarCap,WindCap)
        #println(sum(NetworkData["gen"][string(i)]["pmax"] for i in 1:size(gen_data)[1]))

        # Change load buses' Pd and Qd for the current scenario
        update_loads!(k, load_scenarios, NetworkData)

        # Run power flow
        solution = PowerModels.solve_opf(NetworkData, ACPPowerModel, solver)
        #push!(results, (renewable_scenarios[!,1][k], solution["termination_status"]))

        #Save solution dictionary to JSON
        if save_to_JSON == true
           export_JSON(solution, k, "solutions")
        end
        push!(results,  solution["termination_status"])
    end
end

if save_summary == true
    CSV.write(results, "eval_results.csv")
end

j=0
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
