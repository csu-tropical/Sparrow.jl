# Sparrow parameter list
@workflow_type P3RoninWorkflow

# Define custom steps
@workflow_step P3QCStep
@workflow_step RoninQCStep

workflow = P3RoninWorkflow(

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
    minute_span = 1,

    # If true, then process the data in reverse chronological order (newest to oldest), otherwise process in chronological order (oldest to newest)
    reverse = false,

    steps = [
        # Format is (step_name, step_type, input_directory, archive = true/false)
        # If archive = true then archive this product, otherwise it is temporary and will be deleted after the workflow is complete
        # First step should always start with "base_data" as the input directory
        ("cfradial_raw", RadxConvertStep, "base_data", true)
        #("threshold_qc", P3QCStep, "cfradial_raw", false),
        #("RoninQC", RoninQCStep, "cfradial_raw", true),
    ],

    # If true, then ignore the time filter and process all files in the input directory
    process_all = true,

    # Raw moment names that are used in the first step of the workflow, usually the names of the moments in the base data files
    raw_moment_names = ["DBZ", "VEL", "WIDTH", "SQI"],

    # QC moment names are used subsequently in the workflow steps, and can be the same as the raw moment names or different if the moments are renamed during processing. The moment_grid_type parameter specifies how each moment is gridded (e.g. :linear, :nearest, :weighted, etc.)
    qc_moment_names = ["DBZ", "VEL", "WIDTH", "SQI"],
    moment_grid_type = [:linear, :weighted, :weighted, :weighted],

    # Additional parameters needed by the various workflow steps are added here
    sqi_threshold = 0.35,
    # Use this field to indicate missing data
    missing_key = "SQI",
    # Use this field to indicate valid echo
    valid_key = "DBZ",

    ronin_config = "ronin_config.jld2"
)

function workflow_step(workflow::P3RoninWorkflow, ::Type{P3QCStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    println("Executing Step $(step_name) for $(typeof(workflow)) ...")
    raw_moment_dict = workflow["raw_moment_dict"]
    qc_moment_dict = workflow["qc_moment_dict"]
    missing_key = workflow["missing_key"]
    threshold_field = missing_key
    threshold_value = workflow["sqi_threshold"]

    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for file in input_files
        radar_volume = Daisho.read_cfradial(file, raw_moment_dict)
        raw_moments = radar_volume.moments
        qc_moments = Daisho.initialize_qc_fields(radar_volume, raw_moment_dict, qc_moment_dict)
        qc_moments = Daisho.threshold_qc(raw_moments, raw_moment_dict, qc_moments, qc_moment_dict, threshold_field, threshold_value, missing_key)
        qc_file = replace(file, "AIR" => "AIR_QC")
        qc_file = replace(qc_file, input_dir => output_dir)
        Daisho.write_qced_cfradial_P3(file, qc_file, raw_moments, qc_moment_dict)
        flush(stdout)
    end
end
