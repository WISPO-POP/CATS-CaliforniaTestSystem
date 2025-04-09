using PowerSystems
using CSV
using DataFrames
gen_data = SystemDataTable("MATPOWER/CaliforniaTestSystem.m", "generator")
gen_csv = CSV.read("GIS/CATS_gens.csv", DataFrame)

thermal_gens_old = collect(get_components(ThermalStandard, system))
sort!(thermal_gens_old, by = n -> parse(Int64, n.name[5:end]))

# Creating arrays sorting fuel types by function
renew_types = ["Batteries", "Onshore Wind Turbine", "Solar Photovoltaic", "Solar Thermal without Energy Storage"]
hydro_types = ["Conventional Hydroelectric", "Hydroelectric Pumped Storage"]
nat_gas_types = ["Natural Gas Fired Combustion Turbine", "Natural Gas Internal Combustion Engine",
                             "Natural Gas Fired Combined Cycle", "Natural Gas Steam Turbine", "Other Natural Gas"]
other_types = ["Synchronous Condenser", "IMPORT", "All Other"]

fuels = Dict(
    (gas_type => ThermalFuels.NATURAL_GAS for gas_type in nat_gas_types)...,
    (other_type => ThermalFuels.OTHER for other_type in other_types)...,
    "Municipal Solid Waste" => ThermalFuels.MUNICIPAL_WASTE,
    "Other Waste Biomass" => ThermalFuels.MUNICIPAL_WASTE,
    "Petroleum Liquids" => ThermalFuels.RESIDUAL_FUEL_OIL,
    "Geothermal" => ThermalFuels.GEOTHERMAL,
    "Nuclear" => ThermalFuels.NUCLEAR,
    "Wood/Wood Waste Biomass" => ThermalFuels.WOOD_WASTE,
    "Conventional Steam Coal" => ThermalFuels.COAL,
    "Petroleum Coke" => ThermalFuels.PETROLEUM_COKE,
    "Landfill Gas" => ThermalFuels.MUNICIPAL_WASTE,
    "Other Gases" => ThermalFuels.OTHER_GAS
)

prime_movers = Dict(
    "Municipal Solid Waste" => PrimeMovers.ST,
    "Other Waste Biomass" => PrimeMovers.ST,
    "Petroleum Liquids" => PrimeMovers.IC,
    "Geothermal" => PrimeMovers.OT,
    "Nuclear" => PrimeMovers.OT,
    "Wood/Wood Waste Biomass" => PrimeMovers.ST,
    "Conventional Steam Coal" => PrimeMovers.ST,
    "Petroleum Coke" => PrimeMovers.ST,
    "Natural Gas Fired Combustion Turbine" => PrimeMovers.GT,
    "Natural Gas Internal Combustion Engine" => PrimeMovers.IC,
    "Natural Gas Fired Combined Cycle" => PrimeMovers.CT,
    "Natural Gas Steam Turbine" => PrimeMovers.ST,
    "Other Natural Gas" => PrimeMovers.OT,
    "Synchronous Condenser" => PrimeMovers.OT,
    "IMPORT" => PrimeMovers.OT,
    "All Other" => PrimeMovers.OT,
    "Landfill Gas" => PrimeMovers.OT,
    "Other Gases" => PrimeMovers.OT
)

ramp_limits = Dict(
    (PrimeMovers.ST, ThermalFuels.COAL) => (up = 0.00264, down = 0.00264),
    # ("ST", "SUB") => (up = 0.00264, down = 0.00264),
    (PrimeMovers.CA, ThermalFuels.NATURAL_GAS) => (up = 0.0042, down = 0.0042),
    (PrimeMovers.CT, ThermalFuels.NATURAL_GAS) => (up = 0.14, down = 0.14),
    # Average of the GT
    (PrimeMovers.GT, ThermalFuels.NATURAL_GAS) => (up = 0.2475, down = 0.2475),
    (PrimeMovers.ST, ThermalFuels.NATURAL_GAS) => (up = 0.0054, down = 0.0054),
)

key_remaps = Dict(
    (PrimeMovers.ST, ThermalFuels.COAL) => ["CLLIG"],
    # (PrimeMovers.ST, "SUB") => ["CLLIG"],
    (PrimeMovers.CA, ThermalFuels.NATURAL_GAS) => ["CCLE90", "CCGT90"],
    (PrimeMovers.CT, ThermalFuels.NATURAL_GAS) => ["SCLE90", "SCGT90"],
    # Average of the GT
    (PrimeMovers.GT, ThermalFuels.NATURAL_GAS) => ["SCLE90", "SCGT90"],
    (PrimeMovers.ST, ThermalFuels.NATURAL_GAS) => ["GSREH"],
)

duration_lims = Dict(
    ("CLLIG", "SMALL") => (up = 12.0, down = 6.0), # Coal and Lignite -> WECC (1) Small coal
    ("CLLIG", "LARGE") => (up = 12.0, down = 8.0), # WECC (2) Large coal
    ("CLLIG", "SUPER") => (up = 24.0, down = 8.0), # WECC (3) Super-critical coal
    "CCGT90" => (up = 2.0, down = 6.0),    # Combined cycle greater than 90 MW -> WECC (7) Typical CC
    "CCLE90" => (up = 2.0, down = 4.0), # Combined cycle less than 90 MW -> WECC (7) Typical CC, modified
    "GSNONR" => (up = 2.0, down = 4.0), # Gas steam non-reheat -> WECC (4) Gas-fired steam (sub- and super-critical)
    "GSREH" => (up = 2.0, down = 4.0), # Gas steam reheat boiler -> WECC (4) Gas-fired steam (sub- and super-critical)
    "GSSUP" => (up = 2.0, down = 4.0), # Gas-steam supercritical -> WECC (4) Gas-fired steam (sub- and super-critical)
    "SCGT90" => (up = 1.0, down = 1.0), # Simple-cycle greater than 90 MW -> WECC (5) Large-frame Gas CT
    "SCLE90" => (up = 1.0, down = 0.0), # Simple-cycle less than 90 MW -> WECC (6) Aero derivative CT
)

for i in 1:length(gen_csv[:, 1])
	set_base_power!(thermal_gens_old[i], 100.0)
    local num = lpad(i, 4, '0')
    local pmtype
# Replacing ThermalStandard with HydroDispatch at appropriate nodes
    if gen_csv[i, 4] in hydro_types
        commonKeys = intersect(fieldnames(HydroDispatch), fieldnames(ThermalStandard))
        local old_data = Dict(key=>getfield(thermal_gens_old[i], key) for key ∈ fieldnames(HydroDispatch))
        delete!.((old_data,), (:operation_cost, :internal, :prime_mover_type));
        remove_component!(system, thermal_gens_old[i])
        #local pmtype
        if gen_csv[i, 4] == "Conventional Hydroelectric"
            pmtype = PrimeMovers.HA
        elseif gen_csv[i, 4] == "Hydroelectric Pumped Storage"
            pmtype = PrimeMovers.HY
        end
        local hydro = HydroDispatch(;
          # name = "hydro$num",
          prime_mover_type = pmtype,
          operation_cost = HydroGenerationCost(nothing),
          old_data...
        )
        add_component!(system, hydro)
# Replacing ThermalStandard with RenewableDispatch at appropriate nodes
    elseif gen_csv[i, 4] in renew_types
        commonKeys = intersect(fieldnames(RenewableDispatch), fieldnames(ThermalStandard))
        local old_data = Dict(key=>getfield(thermal_gens_old[i], key) for key ∈ commonKeys)
        delete!.((old_data,), (:operation_cost, :internal, :prime_mover_type))
        old_power = get_active_power(thermal_gens_old[i])+ im * get_reactive_power(thermal_gens_old[i])
        remove_component!(system, thermal_gens_old[i])
        #local pmtype
        if gen_csv[i, 4] == "Batteries"
            pmtype = PrimeMovers.BA
        elseif gen_csv[i, 4] == "Onshore Wind Turbine"
            pmtype = PrimeMovers.WT
        elseif gen_csv[i, 4] == "Solar Photovoltaic" || gen_csv[i, 4] == "Solar Thermal without Energy Storage"
            pmtype = PrimeMovers.PVe
        end
        power_factor = 0.95
        if old_power != zero(ComplexF64)
            power_factor = abs(old_power)/real(old_power)
        end
        local rgen = RenewableDispatch(;
          # name = "renew$num",
          prime_mover_type = pmtype,
          operation_cost = RenewableGenerationCost(nothing),
          power_factor = power_factor, # assumption.
          old_data...
        )
        add_component!(system, rgen)
# Setting correct fuel and prime mover types for ThermalStandards
    else
        set_fuel!(thermal_gens_old[i], fuels[gen_csv[i, 4]])
        set_prime_mover_type!(thermal_gens_old[i], prime_movers[gen_csv[i, 4]])
        set_active_power!(thermal_gens_old[i], gen_data[i, "Pg"]) #MW
        set_reactive_power!(thermal_gens_old[i], gen_data[i, "Qg"]) #MVAR
        set_active_power_limits!(thermal_gens_old[i], (min = convert(Float64, gen_data[i, "Pmin"]), max = gen_data[i, "Pmax"]))
        set_reactive_power_limits!(thermal_gens_old[i], (min = gen_data[i, "Qmin"], max = gen_data[i, "Qmax"]))
        moverFuelTp = (get_prime_mover_type(thermal_gens_old[i]), get_fuel(thermal_gens_old[i]))
        maxPower = get_max_active_power(thermal_gens_old[i])
        local coalSize
        if maxPower < 300
            coalSize = "SMALL"
        elseif maxPower < 900
            coalSize = "LARGE"
        else
            coalSize = "SUPER"
        end
        if moverFuelTp in keys(key_remaps)
            preSizeType = key_remaps[moverFuelTp]
            local remappedType
            if length(preSizeType) == 2
                remappedType = preSizeType[1+(maxPower >= 90)] # 1st item if < 90, 2nd if >= 90
            elseif moverFuelTp[2] == ThermalFuels.COAL
                remappedType = (preSizeType[1], coalSize)
            else
                remappedType = preSizeType[1]
            end
            # ramp_limits has the same keys as key_remaps.
            set_ramp_limits!(thermal_gens_old[i], ramp_limits[moverFuelTp])
            set_time_limits!(thermal_gens_old[i], duration_lims[remappedType])
        elseif moverFuelTp[1] == PrimeMovers.ST
            # the other steam turbine movers use the same scheme as coal
            set_ramp_limits!(thermal_gens_old[i], ramp_limits[(PrimeMovers.ST, ThermalFuels.COAL)])
            set_time_limits!(thermal_gens_old[i], duration_lims[("CLLIG", coalSize)])
        elseif moverFuelTp == (PrimeMovers.OT, ThermalFuels.GEOTHERMAL)
            # set manually.
            set_ramp_limits!(thermal_gens_old[i], (up = 0.01, down = 0.01))
            set_time_limits!(thermal_gens_old[i], (up = 1000, down = 300))
        elseif moverFuelTp == (PrimeMovers.OT, ThermalFuels.NUCLEAR)
            # set manually.
            set_ramp_limits!(thermal_gens_old[i], (up = 0.0001, down = 0.0001))
            set_time_limits!(thermal_gens_old[i], (up = 8000, down = 8000))
        end
    end
end

# set buses with generators as PV buses
all_generators = get_components(Generator, system)
for g in all_generators
    b = get_bus(g)
    if get_bustype(b) == ACBusTypes.PQ
        set_bustype!(b, ACBusTypes.PV)
    end
end