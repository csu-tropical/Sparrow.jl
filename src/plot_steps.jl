# Plot workflow step type declarations
#
# These are stub types for dispatch. The actual implementations are provided
# by the SparrowPlotExt package extension, which is activated when the user
# loads CairoMakie, GeoMakie, ColorSchemes, and Images.
#
# Usage: install CairoMakie, GeoMakie, ColorSchemes and Images in the
# environment Sparrow runs in; `main` loads them automatically at startup, so a
# `using` line in the workflow file is optional.

@workflow_step PlotLargemapStep
@workflow_step PlotDBZCompositeStep
@workflow_step PlotCompositeStep
@workflow_step PlotDBZVelStep
@workflow_step PlotDBZRainrateStep
@workflow_step PlotRHIStep
@workflow_step PlotPPIVolStep

"""
    PLOT_STEP_TYPES

The step types implemented by the `SparrowPlotExt` package extension. Used by
[`run_workflow_step`](@ref) to give a specific error, naming the required
packages, when one of these steps is used without the extension loaded.
"""
const PLOT_STEP_TYPES = (PlotLargemapStep, PlotDBZCompositeStep, PlotCompositeStep,
                          PlotDBZVelStep, PlotDBZRainrateStep, PlotRHIStep, PlotPPIVolStep)
