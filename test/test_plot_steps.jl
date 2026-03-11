# Test that plot step stub types are defined
# Actual plot implementations are in SparrowPlotExt (requires CairoMakie, etc.)

@test isdefined(Sparrow, :PlotLargemapStep)
@test isdefined(Sparrow, :PlotDBZCompositeStep)
@test isdefined(Sparrow, :PlotCompositeStep)
@test isdefined(Sparrow, :PlotDBZVelStep)
@test isdefined(Sparrow, :PlotDBZRainrateStep)
@test isdefined(Sparrow, :PlotRHIStep)
@test isdefined(Sparrow, :PlotPPIVolStep)

# Verify they are proper DataTypes (created by @workflow_step)
@test PlotLargemapStep isa DataType
@test PlotDBZCompositeStep isa DataType
@test PlotCompositeStep isa DataType
@test PlotDBZVelStep isa DataType
@test PlotDBZRainrateStep isa DataType
@test PlotRHIStep isa DataType
@test PlotPPIVolStep isa DataType
