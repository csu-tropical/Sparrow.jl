module SparrowPlotExt

using Sparrow
using CairoMakie, GeoMakie, ColorSchemes, Images
using Dates, Printf
using Daisho

import Sparrow: workflow_step, get_param, get_daisho_params, plot_output_dir,
    SparrowWorkflow,
    PlotLargemapStep, PlotDBZCompositeStep, PlotCompositeStep,
    PlotDBZVelStep, PlotDBZRainrateStep, PlotRHIStep, PlotPPIVolStep,
    msg_info, msg_debug, msg_warning, msg_error

include("colorschemes.jl")
include("plot_helpers.jl")
include("plot_largemap.jl")
include("plot_dbz_composite.jl")
include("plot_composite.jl")
include("plot_dbz_vel.jl")
include("plot_dbz_rainrate.jl")
include("plot_rhi.jl")
include("plot_ppi_vol.jl")

end # module
