# Plot workflow step type declarations
#
# These are stub types for dispatch. The actual implementations are provided
# by the SparrowPlotExt package extension, which is activated when the user
# loads CairoMakie, GeoMakie, ColorSchemes, and Images.
#
# Usage: add `using CairoMakie, GeoMakie, ColorSchemes, Images` to your
# workflow file before using any plot steps.

@workflow_step PlotLargemapStep
@workflow_step PlotDBZCompositeStep
@workflow_step PlotCompositeStep
@workflow_step PlotDBZVelStep
@workflow_step PlotDBZRainrateStep
@workflow_step PlotRHIStep
@workflow_step PlotPPIVolStep
