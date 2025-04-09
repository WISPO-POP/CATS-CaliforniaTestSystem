# Goal: remove the condensers connected to PQ buses where at most timesteps
# the reactive power generation is 0.0 (and when not 0.0, it's very small)

include("../build-system/build_from_matpower.jl")
using CSV
using DataFrames

pqSyncGens, pvSyncGens = [], []
for g in get_components(Generator, system)
    if get_max_active_power(g) == 0.0 && get_bustype(get_bus(g)) == ACBusTypes.PQ
        push!(pqSyncGens, parse(Int, get_name(g)[5:end]))
    elseif get_max_active_power(g) == 0.0 && get_bustype(get_bus(g)) == ACBusTypes.PV
        push!(pvSyncGens, parse(Int, get_name(g)[5:end]))
    end
end

# return true if should remove, based on reactive power values timesteps
# being "mostly exactly zero, with the remainder being small" 
function mostlyZero(col)
    return (maximum(abs.(col)) < 0.01) && (count(==(zero(eltype(col))), col)/length(col) > 0.8)
end

TIMESERIES_PATH = "data/condenserReactiveFlows.csv"
reactiveFlows = CSV.read(TIMESERIES_PATH, DataFrame)
toRemovePQ = [genNum for genNum in pqSyncGens if mostlyZero(reactiveFlows[!, "gen $genNum"])]
toRemovePV = [g for g in pvSyncGens if all(abs.(reactiveFlows[!, "gen $g"]) .< 0.01)]
# toRemovePV = [g for g in pvSyncGens if mostlyZero(reactiveFlows[!, "gen $g"])]

# parse matpower into data tables.
dataTables = Dict()
MATPOWER_FILE = "MATPOWER/CaliforniaTestSystem.m"
for s in ["bus", "gen", "branch"]
    searchKey = s
    if s == "gen"
        searchKey = "generator"
    end
    dataTables[s] = SystemDataTable(MATPOWER_FILE, searchKey)
end
COST_KEYS = ["model", "startup", "shutdown", "n", "c0", "c1", "c2"]
dataTables["real power cost"] = SystemDataTable(MATPOWER_FILE, "cost", COST_KEYS)

# Take not-pv condensers with all values non-negative.
# Put the largest in the column as the Bs at the bus, and remove the condenser.
MAX_REPLACE = 75
replaceWithShunt = Vector{Tuple{Int, Int, Float64}}()
for colName in names(reactiveFlows)[2:end]
    ind = parse(Int, colName[5:end])
    @assert colName == "gen $ind"
    @assert get_max_active_power(get_components_by_name(Generator, system, "gen-$ind")[1]) == 0.0
    #isPV = (ind in pvSyncGens)
    isRemoved = (ind in toRemovePQ) || (ind in toRemovePV)
    if (ind in pqSyncGens) && !isRemoved && all(reactiveFlows[:, colName] .>= 0.0)
        g = get_components_by_name(Generator, system, "gen-$ind")[1]
        push!(replaceWithShunt, (ind, get_number(get_bus(g)), maximum(reactiveFlows[:, colName])))
    end
end
sort!(replaceWithShunt, by = (y->y[3]))
for (_, busInd, shuntVal) in replaceWithShunt[1:min(MAX_REPLACE,end)]
    dataTables["bus"][busInd, "Bs"] = shuntVal
end

toRemove = vcat(toRemovePQ, toRemovePV, first.(replaceWithShunt[1:min(MAX_REPLACE,end)]))
sort!(toRemove)
# verify that we're only removing synchronous condensers.
removedGens = [get_components_by_name(Generator, system, "gen-$n")[1] for n in toRemove]
@assert all(get_max_active_power.(removedGens) .== 0.0)

println("$(length(toRemovePQ)) condensers at PQ buses removed due to being mostly 0.0")
println("$(length(toRemovePV)) condensers at PV buses removed due to being mostly 0.0")
println("$(length(replaceWithShunt[1:min(MAX_REPLACE,end)])) condensers at"*
                             " PQ buses removed and replaced with shunts")
println("$(size(reactiveFlows)[2]-1-length(toRemove)) condensers remaining")

# work out which buses will have generators post-removal
busesWithGenerators = Set{Int64}()
for g in get_components(Generator, system)
    ind = parse(Int, get_name(g)[5:end])
    if !(ind in toRemove)
        push!(busesWithGenerators, ind)
    end
end
# PV buses that won't have generators post-removal should be PQ.
PQ_TYPE, PV_TYPE = 1, 2
converted = 0
for (i, row) in enumerate(eachrow(dataTables["bus"]))
    if !(i in busesWithGenerators) && row["type"] == PV_TYPE
        row["type"] = PQ_TYPE
        global converted += 1
    end
end
println("Converted $converted buses from PV to PQ.")

# correct datatables for removing those synchronous condensers
for key in ["gen", "real power cost"]
    delete!(dataTables[key], toRemove)
end

# write matpower from corrected data tables.
writeMatpower("MATPOWER/system_condensers_removed_cutoff$MAX_REPLACE.m", dataTables)

# also re-write CATS_gens.csv
catsGens = CSV.read("GIS/CATS_gens.csv", DataFrame)
delete!(catsGens, toRemove)
CSV.write("GIS/CATS_gens_condensers_removed_cutoff$MAX_REPLACE.csv", catsGens)

catsCheck = CSV.read("GIS/CATS_gens_condensers_removed_cutoff$MAX_REPLACE.csv", DataFrame)
numCondensersLeft = count(x->(occursin("condenser", lowercase(x))), catsCheck.FuelType) 
@assert size(reactiveFlows)[2]-1-length(toRemove) == numCondensersLeft