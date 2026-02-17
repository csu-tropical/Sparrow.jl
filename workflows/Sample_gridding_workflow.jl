# Sparrow parameter list
@workflow_type GridWorkflow
workflow = GridWorkflow(

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
    minute_span = 20,

    # If true, then process the data in reverse chronological order (newest to oldest), otherwise process in chronological order (oldest to newest)
    reverse = false,

    steps = [
        # Format is (step_name, step_type, input_directory, archive = true/false)
        # If archive = true then archive this product, otherwise it is temporary and will be deleted after the workflow is complete
        # First step should always start with "base_data" as the input directory
        ("rhi", GridRHIStep, "base_data", true),
        # Additional steps can use a prior step's output as their input, or the base_data
        ("composite", GridCompositeStep, "base_data", true),
        ("ppi", GridPPIStep, "base_data", true),
        # Final step should always archive the processed data or it will be deleted
        ("latlon", GridLatlonStep, "base_data", true),
    ],

    # Raw moment names that are used in the first step of the workflow, usually the names of the moments in the base data files
    raw_moment_names = ["DBZ", "ZDR", "PID", "KDP_RADX"],

    # QC moment names are used subsequently in the workflow steps, and can be the same as the raw moment names or different if the moments are renamed during processing. The moment_grid_type parameter specifies how each moment is gridded (e.g. :linear, :nearest, :weighted, etc.)
    qc_moment_names = ["DBZ", "ZDR", "PID", "KDP_RADX"],

    # Moment grid type specifies how each moment is gridded and should match the qc_moment_names list.
    moment_grid_type = [:linear, :linear, :nearest, :weighted],

    # Missing key is the moment name that indicates missing data, usually PID or SQI or some other quality indicator
    # Valid key is the moment name that indicates valid data, usually DBZ or reflectivity or some power related variable
    missing_key = "PID",
    valid_key = "DBZ",

    # Grid parameters
    # Long parameters are in meters and are used for composite and ppi grids
    long_xmin = -120000.0,
    long_xincr = 1000.0,
    long_xdim = 241,

    long_ymin = -120000.0,
    long_yincr = 1000.0,
    long_ydim = 241,

    # Vol parameters are in meters and are used for volume grids
    vol_xmin = -120000.0,
    vol_xincr = 1000.0,
    vol_xdim = 241,

    vol_ymin = -120000.0,
    vol_yincr = 1000.0,
    vol_ydim = 241,

    # Latlon parameters are in degrees and are used for latlon grids
    lonmin = -1.0,
    londim = 101,
    latmin = -1.0,
    latdim = 101,
    degincr = 0.02,

    # Z parameters are in meters and are used for vertical extent of volume and latlon grids
    zmin = 0.0,
    zincr = 1000.0,
    zdim = 19,

    # R parameters are in meters and are used for radial extent of rhi grids
    rmin = 0.0,
    rincr = 250.0,
    rdim = 481,

    # RHI Z parameters are in meters and are used for vertical extent of rhi grids
    rhi_zmin = 0.0,
    rhi_zincr = 250.0,
    rhi_zdim = 73,

    # Max PPI angle is in degrees and is used to restrict which elevations get gridded (e.g. < 1.0)
    max_ppi_angle = 90.0,

    # Daisho parameters that control the gridding weights
    beam_inflation = 0.0175,
    power_threshold = 0.25,
    ppi_power_threshold = 0.25,
    rhi_power_threshold = 0.50,
    qvp_power_threshold = 0.001
)
