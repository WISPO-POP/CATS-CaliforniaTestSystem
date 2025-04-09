using CSV
using DataFrames
# csv from the big run that Jose did on the cluster.
TIMESERIES_PATH = "data/condenserReactiveFlows.csv"
reactiveFlows = CSV.read(TIMESERIES_PATH, DataFrame)
difficultTimesteps = [row["timestep"] for row in eachrow(reactiveFlows)
                        if count(!=(0.0), row) > 0.8*length(row)]
println(sort(difficultTimesteps))