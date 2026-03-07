# Sample workflow: Grid RHI data and plot the results
# To use plotting steps, load the plotting dependencies before running:
#   using CairoMakie, GeoMakie, ColorSchemes, Images

using CairoMakie, GeoMakie, ColorSchemes, Images

@workflow_type RHIPlotWorkflow
workflow = RHIPlotWorkflow(

    # Working directory is a temporary directory for intermediate products
    # Archive directory is where final products are stored
    # Plot directory is where figures are stored
    # Data directory is where raw data is located (symlinked, not modified)
    # Override with --paths_file for different machines/data
    base_working_dir = "/path/to/data/working",
    base_archive_dir = "/path/to/data/archive",
    base_plot_dir = "/path/to/data/figures",
    base_data_dir = "/path/to/data/raw",

    # How long to span each workflow step in minutes (should match radar cycle)
    minute_span = 20,

    # Process in chronological order
    reverse = false,

    steps = [
        # Step 1: Grid the raw RHI scans
        ("rhi_grid", GridRHIStep, "base_data", true),
        # Step 2: Plot the gridded RHI data (uses output from step 1)
        ("rhi_plot", PlotRHIStep, "rhi_grid", true),
    ],

    # Moment configuration
    raw_moment_names = ["DBZ", "VEL", "ZDR", "RHOHV", "KDP", "PHIDP", "SQI"],
    qc_moment_names = ["DBZ", "VEL", "ZDR", "RHOHV", "KDP", "PHIDP", "SQI"],
    moment_grid_type = [:linear, :linear, :linear, :linear, :weighted, :linear, :linear],

    missing_key = "SQI",
    valid_key = "DBZ",

    # RHI grid parameters (meters)
    rmin = 0.0,
    rincr = 250.0,
    rdim = 481,

    rhi_zmin = 0.0,
    rhi_zincr = 250.0,
    rhi_zdim = 73,

    # Daisho gridding weights
    beam_inflation = 0.0175,
    power_threshold = 0.25,
    rhi_power_threshold = 0.50,

    # Plot parameters (all optional -- defaults are used if omitted)
    radar_name = "MyRadar",
    file_prefix = "MyRadar",
    rhi_plot_size = (1500, 1200),
    rhi_aspect = 7.5,
    rhi_range_max = 120.0,
    rhi_height_max = 16.0,
)
