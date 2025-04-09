using CSV
using DataFrames

function SystemDataTable(filepath, keyword, keys = nothing)
    # find where table starts, list of keys, and how many rows, then just use CSV.
    parseKeys = isnothing(keys)
    if parseKeys
        keys = Vector{String}()
    end
    numRows = 0
    startTableLine = -1
    headerLine = -1
    for (i, line) in enumerate(eachline(filepath))
        if startswith(line, "%% $keyword data") # found header for desired table.
            headerLine = i
        elseif parseKeys && i == headerLine + 1 # line with keys: eg "%    bus_i    type..."
            for key in split(line[2:end]," "; keepempty = false)
                push!(keys, key)
            end
        elseif headerLine !== -1 && startswith(line, '\t') # line is row in table.
            if startTableLine == -1
                startTableLine = i
            end
            numRows += 1
        end
        if headerLine !== -1 && startswith(line, "];") # end of table.
            break
        end
    end
    @assert numRows > 0 "Expected line starting with \"%% $keyword data\", none found."
    # lines start with a tab, and often have extra tabs, so throw those columns out.
    # TODO: quiet the warning? Or is there a way to tell it to not widen?
    df = DataFrame(CSV.File(filepath,
                        delim = '\t', skipto = startTableLine, limit = numRows,
                        header=vcat(["empty"], keys)))
    select!(df, Not("empty"))
    select!(df, Not((1+length(keys)):ncol(df)))
    return df
end

# example functionality.
# testDf = SystemDataTable("CaliforniaTestSystem.m", "bus")
# println(testDf[1, :])
# println(testDf[end, :])

function writeTabJoinedRows(filehandle, table)
    for row in eachrow(table)
        write(filehandle, "\t"*join(row, "\t")*"\n")
    end
end

function writeMatpower(filepath, tableDict)
    dataTableKeys = String["bus", "gen", "branch"]
    open(filepath, "w") do file
        # define the format.
        write(file, """%% MATPOWER Case Format : Version 2
function mpc = CaliforniaTestSystem
mpc.version = '2';

%%-----  Power Flow Data  -----%%
%% system MVA base\n""")
        # base power
        local x
        if "baseMVA" in keys(tableDict)
            x = tableDict["baseMVA"]
        else
            x = 100
        end
        write(file, "mpc.baseMVA = $x;\n")
        # system data tables.
        colNames = Dict(
            "bus"=>String["bus_i", "type", "Pd", "Qd", "Gs", "Bs", "area", "Vm", "Va",
                            "baseKV", "zone", "Vmax", "Vmin"],
            "gen"=>String["bus", "Pg", "Qg", "Qmax", "Qmin", "Vg", "mBase", "status",
                            "Pmax", "Pmin", "Pc1", "Pc2", "Qc1min", "Qc1max", "Qc2min", "Qc2max",
                            "ramp_agc", "ramp_10", "ramp_30", "ramp_q", "apf"],
            "branch"=>String["f_bus", "t_bus", "r", "x", "b", "rateA", "rateB", "rateC",
                                    "ratio", "angle", "status", "angmin", "angmax"]
        )
        for key in dataTableKeys
            # println(key)
            if key == "gen"
                write(file, "%% generator data\n")
            else
                write(file, "%% $key data\n")
            end
            cols = colNames[key] # this forces the key to be among
            # the expected ones.
            write(file, "%    "*join(cols, "    ")*"\nmpc.$key = [\n")
            if key in keys(tableDict)
                table = tableDict[key]
                @assert names(table) == cols
                writeTabJoinedRows(file, table)
            else
                write(file, "\tNA\n")
            end
            write(file, "];\n\n")
        end
        # cost
        write(file, """%%-----  OPF Data  -----%%
        %% cost data
        %    1    startup    shutdown    n    x1    y1    ...    xn    yn
        %    2    startup    shutdown    n    c(n-1)    ...    c0
        mpc.gencost = [\n""")
        if "real power cost" in keys(tableDict)
            writeTabJoinedRows(file, tableDict["real power cost"])
            if "reactive power cost" in keys(tableDict)
                writeTabJoinedRows(file, tableDict["reactive power cost"])
            end
        else
            println("WARNING: no table with key \"real power cost\" present.")
            write(file, "\tNA\n")
            return
        end
        write(file, "];\n\n")
    end
end
# testing code.
#=
testDict = Dict()
MATPOWER_FILE = "CaliforniaTestSystem.m"
for s in ["bus", "gen", "branch"]
    searchKey = s
    if s == "gen"
        searchKey = "generator"
    end
    testDict[s] = SystemDataTable(MATPOWER_FILE, searchKey)
end
COST_KEYS = ["model", "startup", "shutdown", "n", "c0", "c1", "c2"]
costData = SystemDataTable(MATPOWER_FILE, "cost", COST_KEYS)
NUM_GENS = size(testDict["gen"])[1]
NUM_COSTS = size(costData)[1]
if NUM_GENS == NUM_COSTS
    testDict["real power cost"] = costData
elseif 2*NUM_GENS == NUM_COSTS
    testDict["real power cost"] = testDict[1:NUM_GENS, :]
    testDict["reactive power cost"] = costData[(1+NUM_GENS):NUM_COSTS,:]
end
writeMatpower("test_write_matpower.m", testDict)=#
# works, up to trailing whitespace and 0 vs 0.0