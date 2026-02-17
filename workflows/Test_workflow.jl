# Sparrow parameter list
@workflow_type TestWorkflow

# Define custom steps
@workflow_step TestStep1

# Test renaming of step types as aliases
TestStep2 = PassThroughStep

workflow = TestWorkflow(

    # Working directory is a temporary directory where intermediate products are stored during processing and deleted at the end of the workflow
    # Archive directory is where final products are stored after processing
    # Plot directory is where figures are stored after processing
    # Data directory is where data is located before processing. It is symlinked into the working directory for processing, but the original data is not modified.
    # These can be overriden with the --paths_file command line argument to supply different paths, which let's you keep the same workflow but run it on different data or machine
    base_working_dir = "/path/to/data/working",
    base_archive_dir = "/path/to/data/archive",
    base_plot_dir = "/path/to/data/figures",
    base_data_dir = "/path/to/data/raw",

    # How long to span each workflow step in minutes (should be equal to the radar cycle)
    minute_span = 10,

    # If true, then process the data in reverse chronological order (newest to oldest), otherwise process in chronological order (oldest to newest)
    reverse = false,

    steps = [
        # Format is (step_name, step_type, input_directory, archive = true/false)
        # If archive = true then archive this product, otherwise it is temporary and will be deleted after the workflow is complete
        # First step should always start with "base_data" as the input directory
        ("pass", PassThroughStep, "base_data", true),
        # Additional steps can use a prior step's output as their input, or the raw data
        ("pass2", TestStep1, "pass", false),
        # Final step should archive the processed data or it will be deleted
        ("copy", TestStep2, "pass2", true)
    ],

    # Raw moment names that are used in the first step of the workflow, usually the names of the moments in the base data files
    raw_moment_names = ["DBZ","VEL","SQI"],

    # QC moment names are used subsequently in the workflow steps, and can be the same as the raw moment names or different if the moments are renamed during processing. The moment_grid_type parameter specifies how each moment is gridded (e.g. :linear, :nearest, :weighted, etc.)
    qc_moment_names = ["DBZ","VEL","SQI"],

    # Moment grid type specifies how each moment is gridded and should match the qc_moment_names list.
    moment_grid_type = [:linear, :weighted, :weighted],

    # Additional parameters needed by the various workflow steps are added here
    sqi_threshold = 0.35
)

# Example workflow step function for TestStep1, which just copies files from the input directory to the output directory.
# This is identical to PassThroughStep, but is used here to test custom steps and step type renaming.
function workflow_step(workflow::TestWorkflow, ::Type{TestStep1}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    println("Executing Step $(step_name) for $(typeof(workflow)) ...")
    # Identical to PassThroughStep for testing
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for input_file in input_files
        output_file = replace(input_file, input_dir => output_dir)
        cp(input_file, output_file, follow_symlinks=true)
    end
end
