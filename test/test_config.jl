# Tests for configuration helpers: `apply_paths_file!` (the `--paths_file`
# mechanism), the `reverse` workflow parameter defaulting to `false`, and the
# plot-extension diagnostics raised by `run_workflow_step`.

using Test
using Sparrow
using Dates

@workflow_type ConfigTestWorkflow

@testset "apply_paths_file!" begin

    @testset "overrides only the variables the file defines" begin
        tmp = mktempdir()
        path = joinpath(tmp, "paths1.jl")
        write(path, """
        base_data_dir = "/data/from/file"
        base_archive_dir = "/archive/from/file"
        """)

        wf = ConfigTestWorkflow(base_data_dir = "/data/original",
                                base_working_dir = "/work/original",
                                base_archive_dir = "/archive/original",
                                base_plot_dir = "/plot/original")
        Sparrow.apply_paths_file!(wf, path)

        @test wf["base_data_dir"] == "/data/from/file"
        @test wf["base_archive_dir"] == "/archive/from/file"
        # Untouched
        @test wf["base_working_dir"] == "/work/original"
        @test wf["base_plot_dir"] == "/plot/original"

        rm(tmp, recursive=true)
    end

    @testset "all five recognized variables, including date_subdir" begin
        tmp = mktempdir()
        path = joinpath(tmp, "paths2.jl")
        write(path, """
        base_data_dir = "/data"
        base_working_dir = "/work"
        base_archive_dir = "/archive"
        base_plot_dir = "/plot"
        date_subdir = false
        """)

        wf = ConfigTestWorkflow()
        Sparrow.apply_paths_file!(wf, path)

        @test wf["base_data_dir"] == "/data"
        @test wf["base_working_dir"] == "/work"
        @test wf["base_archive_dir"] == "/archive"
        @test wf["base_plot_dir"] == "/plot"
        @test wf["date_subdir"] == false

        rm(tmp, recursive=true)
    end

    @testset "unrecognized variables are ignored" begin
        tmp = mktempdir()
        path = joinpath(tmp, "paths3.jl")
        write(path, """
        base_data_dir = "/data"
        qc_base = "/qc"
        sigmet_base = "/sigmet"
        """)

        wf = ConfigTestWorkflow()
        Sparrow.apply_paths_file!(wf, path)

        @test wf["base_data_dir"] == "/data"
        @test !haskey(wf.params, "qc_base")
        @test !haskey(wf.params, "sigmet_base")

        rm(tmp, recursive=true)
    end

    @testset "a file defining only unrecognized variables throws" begin
        tmp = mktempdir()
        path = joinpath(tmp, "paths4.jl")
        write(path, """
        qc_base = "/qc"
        sigmet_base = "/sigmet"
        """)

        wf = ConfigTestWorkflow()
        @test_throws ErrorException Sparrow.apply_paths_file!(wf, path)

        rm(tmp, recursive=true)
    end

    @testset "a nonexistent path throws" begin
        wf = ConfigTestWorkflow()
        @test_throws ErrorException Sparrow.apply_paths_file!(wf, "/no/such/paths/file.jl")
    end

    @testset "calling twice with different files works (fresh module each time)" begin
        tmp = mktempdir()
        path_a = joinpath(tmp, "paths_a.jl")
        path_b = joinpath(tmp, "paths_b.jl")
        write(path_a, "base_data_dir = \"/data/a\"\n")
        write(path_b, "base_data_dir = \"/data/b\"\n")

        wf = ConfigTestWorkflow()
        Sparrow.apply_paths_file!(wf, path_a)
        @test wf["base_data_dir"] == "/data/a"

        Sparrow.apply_paths_file!(wf, path_b)
        @test wf["base_data_dir"] == "/data/b"

        rm(tmp, recursive=true)
    end
end

@testset "reverse defaults to false" begin
    @workflow_type ReverseDefaultTestWorkflow

    # A minimal workflow without `reverse` set should pass through
    # setup_workflow_params without error, and get_param should default to false.
    wf = ReverseDefaultTestWorkflow()
    parsed_args = Dict{String,Any}(
        "datetime" => "now",
        "start" => "none",
        "stop" => "none",
        "realtime" => false,
        "force_reprocess" => false,
        "log_prefix" => "default",
    )
    Sparrow.setup_workflow_params(wf, parsed_args)

    @test !haskey(wf.params, "reverse")
    @test Sparrow.get_param(wf, "reverse", false) == false
end

@testset "PLOT_STEP_TYPES and plot extension diagnostics" begin

    @testset "PLOT_STEP_TYPES contains the seven plot step stubs" begin
        @test Sparrow.PlotLargemapStep in Sparrow.PLOT_STEP_TYPES
        @test Sparrow.PlotDBZCompositeStep in Sparrow.PLOT_STEP_TYPES
        @test Sparrow.PlotCompositeStep in Sparrow.PLOT_STEP_TYPES
        @test Sparrow.PlotDBZVelStep in Sparrow.PLOT_STEP_TYPES
        @test Sparrow.PlotDBZRainrateStep in Sparrow.PLOT_STEP_TYPES
        @test Sparrow.PlotRHIStep in Sparrow.PLOT_STEP_TYPES
        @test Sparrow.PlotPPIVolStep in Sparrow.PLOT_STEP_TYPES
        @test length(Sparrow.PLOT_STEP_TYPES) == 7
    end

    @testset "run_workflow_step on a plot step without the extension raises a specific error" begin
        @test Base.get_extension(Sparrow, :SparrowPlotExt) === nothing

        wf = ConfigTestWorkflow(steps = [("plot", PlotRHIStep, "base_data", false)])

        temp_dir = mktempdir()
        date = "20240101"
        mkpath(joinpath(temp_dir, "base_data", date))
        mkpath(joinpath(temp_dir, "plot", date))

        err = try
            Sparrow.run_workflow_step(wf, 1, DateTime(2024, 1, 1), DateTime(2024, 1, 1, 0, 10), temp_dir)
            nothing
        catch e
            e
        end

        @test err isa ErrorException
        @test occursin("CairoMakie", err.msg)

        rm(temp_dir, recursive=true)
    end
end
