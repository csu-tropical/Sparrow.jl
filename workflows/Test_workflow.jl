# Sparrow parameter list
@workflow_type TestWorkflow

# Define custom steps
@workflow_step TestStep1
@workflow_step TestStep2

workflow = TestWorkflow(

    # Working directories
    base_working_dir = "/path/to/data/working",
    base_archive_dir = "/path/to/data/archive",
    base_plot_dir = "/path/to/data/figures",
    base_data_dir = "/path/to/data/raw",

    minute_span = 10,
    reverse = false,

    steps = [
        "TestStep1" => TestStep1
        "TestStep2" => TestStep2
    ],

    # If true, then archive this product, otherwise it is temporary and will be deleted after the workflow is complete
    archive = [
        "TestStep1" => false,
        "TestStep2" => true
    ],

    # Raw moment names
    raw_moment_names = ["DBZ","VEL","SQI"],

    # QC moment names
    qc_moment_names = ["DBZ","VEL","SQI"],
    moment_grid_type = [:linear, :weighted, :weighted],

    sqi_threshold = 0.35
)

function workflow_step(workflow::TestWorkflow, TestStep1, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, kwargs...)

    println("Executing Step $(step_name) for $(typeof(workflow)) ...")
    copy_each_file(input_dir, output_dir, start_time, stop_time)
end

function workflow_step(workflow::TestWorkflow, TestStep2, input_dir::String, output_dir::String; step_name::String, kwargs...)

    # Do nothing
    println("Executing Step $(step_name) for $(typeof(workflow)) ...")
end
