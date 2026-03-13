# NEXRAD Composite Reflectivity Workflow
# Example: Hurricane Michael landfall, KEVX radar, 10 Oct 2018
#
# Data is fetched directly from the Unidata NEXRAD Level 2 S3 archive
# (anonymous access, no AWS credentials required).
#
# Run workflow:
#  ./sparrow --datetime 20181010_1420 workflows/NEXRAD_composite_workflow.jl
#

@workflow_type NEXRADcompositeWorkflow

workflow = NEXRADcompositeWorkflow(

    # S3 data source — pulls directly from public NEXRAD archive
    data_source = NEXRADSource("KEVX"),

    # Local directories for fetched data and outputs
    base_data_dir = "/tmp/sparrow/nexrad/raw",
    base_working_dir = "/tmp/sparrow/nexrad/working",
    base_archive_dir = "/tmp/sparrow/nexrad/archive",
    base_plot_dir = "/tmp/sparrow/nexrad/figures",

    # Time configuration
    minute_span = 5,
    reverse = false,

    # Processing pipeline:
    #  1. Convert NEXRAD Level 2 to CfRadial (temporary)
    #  2. Grid composite reflectivity (archived)
    #  3. Plot composite reflectivity (archived)
    steps = [
        ("cfradial",  RadxConvertStep,        "base_data",  false),
        ("composite", GridCompositeStep,       "cfradial",   true),
        ("plot",      PlotDBZCompositeStep,    "composite",  true),
    ],

    # NEXRAD Level 2 dual-pol moment names (native names from RadxConvert)
    # REF=reflectivity, VEL=velocity, SW=spectrum width,
    # ZDR=differential reflectivity, PHI=differential phase, RHO=correlation coefficient
    raw_moment_names = ["REF", "VEL", "SW", "ZDR", "PHI", "RHO"],
    qc_moment_names  = ["REF", "VEL", "SW", "ZDR", "PHI", "RHO"],
    moment_grid_type = [:linear, :weighted, :weighted, :linear, :linear, :linear],

    # Quality masking — use RHO (correlation coefficient) as the data presence indicator
    missing_key = "RHO",
    valid_key = "REF",

    # Composite grid: 240 km x 240 km, 1 km spacing, centered on radar
    long_xmin = -240000.0,
    long_xincr = 1000.0,
    long_xdim = 481,

    long_ymin = -240000.0,
    long_yincr = 1000.0,
    long_ydim = 481,

    # Gridding parameters
    beam_inflation = 0.0175,
    rhi_power_threshold = 0.50,

    # Plot configuration
    radar_name = "KEVX",
    file_prefix = "KEVX",

    # Range rings at 120 km and 240 km
    range_ring_radii = [1.08, 2.16],
    range_ring_labels = ["120 km", "240 km"],
)
