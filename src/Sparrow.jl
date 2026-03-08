__precompile__()
module Sparrow

# Sparrow.jl
# Ship, Plane, and Anchored Radar Research and Operational Workflows

using Daisho, Ronin
using Dates, NCDatasets
using Printf
using Downloads
using Distributed, DistributedData
using ClusterManagers, SlurmClusterManager
using Random
using Statistics
using ArgParse
using NCDatasets, JLD2

include("driver.jl")
include("data_sources.jl")
include("workflow.jl")
include("io.jl")
include("qc.jl")
include("merge.jl")
include("plot_steps.jl")
include("grid.jl")
include("utility.jl")

export @workflow_type, @workflow_step, assign_workers, run_workflow, process_workflow
export SparrowWorkflow, workflow_step, get_param
export DataSource, LocalDirSource, S3BucketSource, HTTPDirSource
export discover_files, fetch_file, is_remote, has_data, get_data_source
export poll_directory
export RadxConvertStep, RoninQCStep
export GridRHIStep, GridCompositeStep, GridVolumeStep, GridLatlonStep, GridPPIStep, GridQVPStep
export PlotLargemapStep, PlotDBZCompositeStep, PlotCompositeStep, PlotDBZVelStep, PlotDBZRainrateStep, PlotRHIStep, PlotPPIVolStep
export MergeVolumesStep, PiccoloMergeStep
export PassThroughStep, filterByTimeStep
export message, msg_error, msg_warning, msg_info, msg_debug, msg_trace
export set_message_level, MSG_ERROR, MSG_WARNING, MSG_INFO, MSG_DEBUG, MSG_TRACE

function main(parsed_args)

    # Set message level in case the user wants errors or warnings only
    msg_level = parsed_args["verbose"]
    if msg_level != 2
        # Set message level from verbose flag if not at default (2)
        set_message_level(msg_level)
        msg_debug("Setting verbosity level to $(parsed_args["verbose"]) based on command line argument")
    else
        # Set the default
        set_message_level(MSG_INFO)
    end

    msg_info("Starting Sparrow workflow... ")

    # Load the workflow file in Sparrow module scope on the main process
    # This ensures all @workflow_type and @workflow_step definitions live in Sparrow,
    # consistent with how workers load it, avoiding scope mismatches
    workflow_file = parsed_args["workflow"]
    Base.include(Sparrow, workflow_file)

    # The workflow file defines a `workflow` variable in Sparrow module scope
    # Use invokelatest to cross the world-age boundary after Base.include
    if !Base.invokelatest(isdefined, Sparrow, :workflow)
        msg_error("Workflow file $workflow_file must define a `workflow` variable")
    end
    workflow = Base.invokelatest(getfield, Sparrow, :workflow)

    # Override the paths if a paths file is provided
    if parsed_args["paths_file"] != "none"
        paths_file = parsed_args["paths_file"]
        Base.include(Sparrow, paths_file)
        workflow["base_data_dir"] = Base.invokelatest(getfield, Sparrow, :base_data_dir)
        workflow["base_working_dir"] = Base.invokelatest(getfield, Sparrow, :base_working_dir)
        workflow["base_archive_dir"] = Base.invokelatest(getfield, Sparrow, :base_archive_dir)
        workflow["base_plot_dir"] = Base.invokelatest(getfield, Sparrow, :base_plot_dir)
    end

    # Update message level from workflow if specified and verbose flag is at default (2)
    if (haskey(workflow.params, "message_level")) && msg_level == 2
        msg_level = get_param(workflow, "message_level", MSG_INFO)
        set_message_level(msg_level)
        msg_debug("Setting verbosity level to $(msg_level) based on workflow parameter")
    end

    # Try to load plot extension packages if available
    try
        @eval Main begin
            using CairoMakie, GeoMakie, ColorSchemes, Images
        end
        msg_info("Plot extension loaded")
    catch
        msg_debug("Plot extension packages not available, plot steps will be skipped")
    end

    # Setup distributed workers
    setup_workers(parsed_args)

    # Load the workflow file on all workers in Sparrow module scope
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
