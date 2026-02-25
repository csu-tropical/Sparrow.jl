__precompile__()
module Sparrow

# Sparrow.jl
# Ship, Plane, and Anchored Radar Research and Operational Workflows

using Daisho, Ronin
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
using NCDatasets, JLD2

include("driver.jl")
include("workflow.jl")
include("io.jl")
include("qc.jl")
include("merge.jl")
include("plot.jl")
include("grid.jl")
include("utility.jl")

export @workflow_type, @workflow_step, assign_workers, run_workflow, process_workflow
export message, msg_error, msg_warning, msg_info, msg_debug, msg_trace
export set_message_level, MSG_ERROR, MSG_WARNING, MSG_INFO, MSG_DEBUG, MSG_TRACE

function main(workflow::SparrowWorkflow, parsed_args)

    # Set message level in case the user wants errors or warnings only
    msg_level = parsed_args["verbose"]
    if (haskey(workflow.params, "message_level")) && msg_level == 2
        # Set message level from workflow if specified and verbose flag is at default (2)
        msg_level = get_param(workflow, "message_level", MSG_INFO)
        set_message_level(msg_level)
        msg_debug("Setting verbosity level to $(msg_level) based on workflow parameter")
    elseif msg_level != 2
        # Set message level from verbose flag if not at default (2)
        set_message_level(msg_level)
        msg_debug("Setting verbosity level to $(parsed_args["verbose"]) based on command line argument")
    else
        # Set the default
        set_message_level(MSG_INFO)
    end

    msg_info("Starting Sparrow workflow... ")

    # Setup distributed workers
    setup_workers(parsed_args)

    # Load the workflow file on all workers
    workflow_file = parsed_args["workflow"]
    @everywhere workers() begin
        Base.include(Sparrow, $workflow_file)
    end

    # Set message level on all workers
    @everywhere workers() begin
        Sparrow.set_message_level($msg_level)
    end

    try
        # Run the workflow
        status = run_workflow(workflow, parsed_args)
        if status
            msg_info("All done with Sparrow workflow!")
        else
            msg_warning("Sparrow workflow failed with errors. Please check the logs for details.")
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
