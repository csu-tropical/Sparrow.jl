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

function main(workflow::SparrowWorkflow, parsed_args)

    println("𓅪 Starting Sparrow workflow... ")

    # Setup distributed workers
    setup_workers(parsed_args)

    # Load the workflow file on all workers
    workflow_file = parsed_args["workflow"]
    @everywhere workers() begin
        Base.include(Sparrow, $workflow_file)
    end

    try
        # Run the workflow
        status = run_workflow(workflow, parsed_args)
        if status
            println("𓅪 All done with Sparrow workflow!")
        else
            println("𓅪 Sparrow workflow failed with errors. Please check the logs for details.")
        end
    finally
        # Clean up workers
        rmprocs(workers())
    end

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
