# Sample workflow: Grid RHI data and plot the results.
#
# All grid geometry and field configuration come from the Daisho TOML referenced
# by `daisho_config` (the new Fields API). To use plotting steps, load the
# plotting dependencies before running:
#   using CairoMakie, GeoMakie, ColorSchemes, Images

using CairoMakie, GeoMakie, ColorSchemes, Images

@workflow_type RHIPlotWorkflow
workflow = RHIPlotWorkflow(

    # Working directory is a temporary directory for intermediate products
    # Archive directory is where final gridded products are stored
    # Plot directory is where figures are stored
    # Data directory is where raw data is located (symlinked, not modified)
    # Override with --paths_file for different machines/data
    base_working_dir = "/path/to/data/working",
    base_archive_dir = "/path/to/data/archive",
    base_plot_dir = "/path/to/data/figures",
    base_data_dir = "/path/to/data/raw",

    # How long to span each workflow step in seconds (should match radar cycle)
    span_seconds = 1200,

    # Process in chronological order
    reverse = false,

    # All gridding + field configuration (grid geometry, fields, interpolation,
    # tags, thresholds, CF metadata) comes from this Daisho TOML. Generate a
    # template with `using Daisho; print_config("daisho.toml")` and edit it, or
    # point at an existing one (e.g. workflows/Piccolo_gridding.toml).
    daisho_config = "/path/to/daisho.toml",

    # Step 1 grids the raw RHI scans; step 2 plots the gridded RHIs (reading
    # step 1's output). The plot step writes PNGs to base_plot_dir, so archive=false.
    steps = [
        ("rhi_grid", GridRHIStep, "base_data", true),
        ("rhi_plot", PlotRHIStep, "rhi_grid", false),
    ],

    # Plot parameters (all optional -- defaults are used if omitted). Field roles
    # (reflectivity, velocity) come from the Daisho config tags; the remaining
    # dual-pol panels default to conventional names (zdr_field, kdp_field, ...).
    radar_name = "MyRadar",
    file_prefix = "MyRadar",
    rhi_plot_size = (1500, 1200),
    rhi_aspect = 7.5,
    rhi_range_max = 120.0,
    rhi_height_max = 16.0,
)
