@testset "Plot Step Types" begin

    @testset "Step types are defined" begin
        @test isdefined(Sparrow, :PlotLargemapStep)
        @test isdefined(Sparrow, :PlotDBZCompositeStep)
        @test isdefined(Sparrow, :PlotCompositeStep)
        @test isdefined(Sparrow, :PlotDBZVelStep)
        @test isdefined(Sparrow, :PlotDBZRainrateStep)
        @test isdefined(Sparrow, :PlotRHIStep)
        @test isdefined(Sparrow, :PlotPPIVolStep)
    end

    @testset "Step types are proper DataTypes" begin
        @test PlotLargemapStep isa DataType
        @test PlotDBZCompositeStep isa DataType
        @test PlotCompositeStep isa DataType
        @test PlotDBZVelStep isa DataType
        @test PlotDBZRainrateStep isa DataType
        @test PlotRHIStep isa DataType
        @test PlotPPIVolStep isa DataType
    end

    @testset "Plot parameter defaults via get_param" begin
        @workflow_type PlotTestWorkflow
        wf = PlotTestWorkflow()

        # Missing parameters should return defaults without error
        @test get_param(wf, "radar_name", "Sparrow") == "Sparrow"
        @test get_param(wf, "file_prefix", "Sparrow") == "Sparrow"
        @test get_param(wf, "plot_width", 400) == 400
        @test get_param(wf, "plot_height", 400) == 400
        @test get_param(wf, "xdim", 251) == 251
        @test get_param(wf, "ydim", 251) == 251
        @test get_param(wf, "rdim", 501) == 501
        @test get_param(wf, "rhi_zdim", 51) == 51
        @test get_param(wf, "marker_lon", nothing) === nothing
        @test get_param(wf, "marker_lat", nothing) === nothing
    end

    @testset "Plot parameter overrides" begin
        @workflow_type PlotOverrideWorkflow
        wf = PlotOverrideWorkflow(
            radar_name = "SEA-POL",
            file_prefix = "SEAPOL",
            xdim = 361,
            ydim = 361,
            marker_lon = -106.744,
            marker_lat = 40.455
        )

        @test get_param(wf, "radar_name", "Sparrow") == "SEA-POL"
        @test get_param(wf, "file_prefix", "Sparrow") == "SEAPOL"
        @test get_param(wf, "xdim", 251) == 361
        @test get_param(wf, "ydim", 251) == 361
        @test get_param(wf, "marker_lon", nothing) == -106.744
        @test get_param(wf, "marker_lat", nothing) == 40.455
        # Unset params still use defaults
        @test get_param(wf, "plot_width", 400) == 400
    end
end
