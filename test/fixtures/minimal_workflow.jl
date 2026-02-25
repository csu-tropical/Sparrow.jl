# Minimal test workflow for integration testing
@workflow_type MinimalTestWorkflow

# Define test steps
@workflow_step CopyStep

workflow = MinimalTestWorkflow(
    # Use temporary directories for testing
    base_working_dir = tempdir(),
    base_archive_dir = joinpath(tempdir(), "archive"),
    base_plot_dir = joinpath(tempdir(), "plots"),
    base_data_dir = joinpath(@__DIR__, "data"),
    
    # Minimal span
    minute_span = 5,
    
    # Don't reverse
    reverse = false,
    
    # Simple two-step workflow
    steps = [
        "copy" => CopyStep,
        "verify" => CopyStep
    ],
    
    # Minimal moments
    raw_moment_names = ["DBZ"],
    qc_moment_names = ["DBZ"],
    moment_grid_type = [:linear],
    
    # Test parameters
    test_mode = true,
    message_level = 3  # Debug level
)

# Simple step that copies files
function Sparrow.workflow_step(workflow::MinimalTestWorkflow, ::Type{CopyStep},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    Sparrow.msg_debug("Executing test step $(step_num): $(step_name)")
    
    # Create output directory
    mkpath(output_dir)
    
    # Copy all files from input to output
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    
    for input_file in input_files
        output_file = joinpath(output_dir, basename(input_file))
        cp(input_file, output_file; follow_symlinks=true, force=true)
        Sparrow.msg_debug("Copied $(basename(input_file)) to $(output_dir)")
    end
    
    return length(input_files)
end