# Sparrow parameter list
@workflow_type TestWorkflow

# Define custom steps
@workflow_step TestStep1

# Test renaming of step types as aliases
TestStep2 = PassThroughStep

workflow = TestWorkflow(

    # Working directories
    base_working_dir = "/path/to/data/working",
    base_archive_dir = "/path/to/data/archive",
    base_plot_dir = "/path/to/data/figures",
    base_data_dir = "/path/to/data/raw",

    minute_span = 10,
    reverse = false,

    steps = [
        "pass" => PassThroughStep,
        "pass2" => TestStep1,
        "copy" => TestStep2
    ],
    archive = [
        "pass" => false,
        "pass2" => false,
        "copy" => true
    ],

    # Raw moment names
    raw_moment_names = ["DBZ","VEL","SQI"],

    # QC moment names
    qc_moment_names = ["DBZ","VEL","SQI"],
    moment_grid_type = [:linear, :weighted, :weighted],

    sqi_threshold = 0.35
)

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
