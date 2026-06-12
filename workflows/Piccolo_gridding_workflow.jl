# Sparrow parameter list
#
# PICCOLO gridding-only workflow. QC and merging are assumed already done; this
# takes the merged, QC'd CfRadial volumes in base_data and produces every grid
# product Daisho offers (RHI, composite, volume, lat/lon, PPI, QVP). All grid
# geometry, field selection, interpolation, and weighting live in the Daisho
# TOML referenced by daisho_config -- see Piccolo_gridding.toml.
#
# Plot steps require the plotting dependencies, loaded here so the SparrowPlotExt
# extension is active before the workflow runs.
using CairoMakie, GeoMakie, ColorSchemes, Images

@workflow_type PiccoloGriddingWorkflow
workflow = PiccoloGriddingWorkflow(

    # Working/archive/plot/data directories. base_data should point at the
    # already-QC'd and merged CfRadial files (the merge output of the dual-pol
    # workflow). Override any of these at runtime with --paths_file.
    base_data_dir    = "/Users/mmbell/Science/PICCOLO/postprocessing/final_qc/cfrad_merge",
    base_working_dir = "/Users/mmbell/Science/PICCOLO/postprocessing/final_qc/working",
    base_archive_dir = "/Users/mmbell/Science/PICCOLO/postprocessing/final_qc/gridded_data",
    base_plot_dir    = "/Users/mmbell/Science/PICCOLO/postprocessing/final_qc/figures",

    # Radar scan cycle length. One step spans one cycle.
    span_seconds = "5M",

    # Process oldest-to-newest (set true to run newest-first).
    reverse = false,

    # All gridding configuration (grid geometry, fields, interpolation,
    # thresholds, CF metadata) comes from this Daisho TOML file.
    daisho_config = "/Users/mmbell/Development/Sparrow.jl/workflows/Piccolo_gridding.toml",

    # Grid every product Daisho supports, then plot the 2D products. Each grid
    # step reads the merged CfRadial files in base_data; archive=true keeps the
    # product, false deletes it. Each plot step's input_directory is the grid
    # step it plots (it reads that step's gridded NetCDF). Plot steps write their
    # PNGs straight to base_plot_dir and so are archive=false.
    #   Format: (step_name, step_type, input_directory, archive)
    steps = [
        ("rhi",       GridRHIStep,       "base_data", true),
        ("composite", GridCompositeStep, "base_data", true),
        ("volume",    GridVolumeStep,    "base_data", true),
        ("latlon",    GridLatlonStep,    "base_data", true),
        ("ppi",       GridPPIStep,       "base_data", true),
        ("qvp",       GridQVPStep,       "base_data", true),

        # Plots of the 2D products (figures land in base_plot_dir/<name>/<date>).
        # The 3D volume/latlon and the QVP column profile have no plotter yet.
        ("plot_rhi",       PlotRHIStep,          "rhi",       false),
        ("plot_composite", PlotDBZCompositeStep, "composite", false),
        ("plot_ppi",       PlotDBZVelStep,       "ppi",       false),
        ("plot_ppi_vol",   PlotPPIVolStep,       "ppi",       false),
    ],

    # PPI step grids every sweep with fixed_angle <= max_ppi_angle (degrees).
    max_ppi_angle = 90.0,

    # QVP step grids every sweep with fixed_angle >= min_qvp_angle (degrees).
    # Tune to select the high-elevation sweep(s) used for quasi-vertical profiles.
    min_qvp_angle = 10.0,
)
