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

    # How long to span each workflow step (should be equal to the radar cycle).
    # Accepts seconds (1200) or a string with a unit code: "20S", "5M", "10H", "1D"
    span_seconds = "20M",

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

    # All grid geometry, field selection, interpolation types, and gridding
    # weights are configured in a Daisho TOML file. Generate a template with
    # `using Daisho; print_config("daisho.toml")` and edit it for your radar:
    #   [fields]          - moments to grid, interpolation type, and special tags
    #   [gridding]        - power threshold and weighting options
    #   [grid.cartesian]  - shared base x/y/z extents for the Cartesian products
    #   [grid.volume]     - optional override for the 3D volume grid
    #   [grid.composite]  - optional override for the composite grid
    #   [grid.ppi]        - optional override for the PPI grid
    #   [grid.column]     - optional override for the QVP/column grid (z-axis)
    #   [grid.rhi]        - range/height extents for RHI grids
    #   [grid.latlon]     - lat/lon extents for geographic grids
    # Each [grid.<product>] section inherits [grid.cartesian] when omitted.
    daisho_config = "/path/to/daisho.toml",

    # Max PPI angle is in degrees and is used to restrict which elevations get gridded (e.g. < 1.0)
    max_ppi_angle = 90.0,
)
