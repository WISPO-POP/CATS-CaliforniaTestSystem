using CSV
using DataFrames
using Dates
using TimeSeries
using InfrastructureSystems
# Time Stamps: 

resolution = Dates.Hour(1);
ts_file = CSV.read("data/HourlyProduction2019.csv", DataFrame) 
tslength = length(ts_file[:, 1])
timestamps = range(DateTime("2019-01-01T00:00:00"); step = resolution, length = tslength);

loads = get_components(PowerLoad, system)
renews = get_components(RenewableDispatch, system)
renew_solar = []
renew_wind = []
renew_else = []
hydros = get_components(HydroDispatch, system)
therms = get_components(ThermalStandard, system)
therm_nuclear = []
therm_else = []

for gen in renews
	if get_prime_mover_type(gen) == PrimeMovers.PVe
		push!(renew_solar, gen)
	elseif get_prime_mover_type(gen) == PrimeMovers.WT
		push!(renew_wind, gen)
	else
		push!(renew_else, gen)
	end
end

for gen in therms
	if get_fuel(gen) == ThermalFuels.NUCLEAR
		push!(therm_nuclear, gen)
	else
		push!(therm_else, gen)
	end
end

ts_df = DataFrame(Load=ts_file[:, 4], Solar=ts_file[:, 5], Wind=ts_file[:, 6], Renews=ts_file[:, 8],
			Nuclear=ts_file[:, 9], Thermal=ts_file[:, 13], Hydros=ts_file[:, 10])
lists = [loads, renew_solar, renew_wind, renew_else, therm_nuclear, therm_else, hydros];

for i in 4:6
	for n in 1:length(ts_df[:, i])
		try
			parse(Float64, ts_df[n, i])
		catch error
			ts_df[n, i] = ts_df[n-1,i]
		end
	end
	ts_df[!, i] = parse.(Float64, ts_df[!,i])
end

for i in 1:7
	local vals = ts_df[:, i]./maximum(ts_df[:, i])
	local array = TimeArray(timestamps, vals)
	local TS = SingleTimeSeries(;
           name = "max_active_power",
           data = array,
           scaling_factor_multiplier = get_max_active_power, #assumption?
        );  
	local associations = ( 
    	InfrastructureSystems.TimeSeriesAssociation(
        	object,
        	TS,)
    	for object in lists[i]
	);
	bulk_add_time_series!(system, associations)
end
