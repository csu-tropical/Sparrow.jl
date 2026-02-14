__precompile__()
module Sparrow

# Sparrow.jl
# Ship, Plane, and Anchored Radar Research and Operational Workflows

using Daisho
using Dates, NCDatasets
using Printf
using FileWatching
using Distributed, DistributedData
using ClusterManagers
using Random
using Statistics
using ColorSchemes
using Makie, GeoMakie, CairoMakie
using Images
using ArgParse
using ClusterManagers, SlurmClusterManager

include("driver.jl")
include("workflow.jl")
include("io.jl")
include("qc.jl")
include("merge.jl")
include("plot.jl")
include("grid.jl")
include("utility.jl")

export @workflow_type, @workflow_step, assign_workers, run_workflow, process_workflow

function main(args=ARGS)

    println("𓅪 Starting Sparrow workflow... ")
    parsed_args = parse_arguments(args)

    # Setup distributed workers
    setup_workers(parsed_args)

    try
        # Run the workflow
        run_workflow(parsed_args)
    finally
        # Clean up workers
        rmprocs(workers())
    end

    println("𓅪 All done with Sparrow workflow!")
end

# This makes the module executable
function julia_main()::Cint
    try
        main()
        return 0  # Success
    catch
        Base.invokelatest(Base.display_error, Base.catch_stack())
        return 1  # Error
    end
end

# Module end
end
