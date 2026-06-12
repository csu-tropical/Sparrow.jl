# Test that plot step stub types are defined
# Actual plot implementations are in SparrowPlotExt (requires CairoMakie, etc.)

using Dates

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

# plot_output_dir routes figures to base_plot_dir/<step>/<date>, with a fallback
# to the step's working dir when base_plot_dir is unset.
@testset "plot_output_dir" begin
    @workflow_type PlotDirTestWorkflow
    t = Dates.DateTime(2026, 6, 11, 12, 0, 0)

    wf = PlotDirTestWorkflow(base_plot_dir = "/figs")
    @test Sparrow.plot_output_dir(wf, "plot_rhi", t, "/tmp/fallback") ==
          joinpath("/figs", "plot_rhi", "20260611")

    wf_nodir = PlotDirTestWorkflow(other = 1)
    @test Sparrow.plot_output_dir(wf_nodir, "plot_rhi", t, "/tmp/fallback") == "/tmp/fallback"
end
