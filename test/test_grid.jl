# Tests for the Daisho TOML configuration plumbing and the gridding helpers.
#
# These cover the fix for issue #4: workflows without a `daisho_config` must
# set up cleanly (gridding is optional), grid steps must fail with an
# actionable message when the config is missing, and a provided TOML must be
# loaded into a DaishoParameters during setup.

using Test
using Sparrow
using Dates
using Daisho

@workflow_type GridConfigTestWorkflow

const DAISHO_FIXTURE = joinpath(@__DIR__, "fixtures", "daisho_test_config.toml")

# Minimal parsed_args as produced by Sparrow.parse_arguments
function _test_parsed_args()
    return Dict{String,Any}(
        "realtime" => false,
        "datetime" => "20240101_000000",
        "force_reprocess" => false,
        "log_prefix" => "default",
    )
end

@testset "setup_workflow_params and daisho_config" begin

    @testset "no daisho_config required (issue #4)" begin
        wf = GridConfigTestWorkflow(span_seconds = 600)
        Sparrow.setup_workflow_params(wf, _test_parsed_args())
        @test !haskey(wf.params, "daisho_params")
    end

    @testset "daisho_config TOML loads into daisho_params" begin
        wf = GridConfigTestWorkflow(daisho_config = DAISHO_FIXTURE)
        Sparrow.setup_workflow_params(wf, _test_parsed_args())
        @test haskey(wf.params, "daisho_params")
        @test wf["daisho_params"] isa Daisho.DaishoParameters
        @test Sparrow.get_daisho_params(wf) === wf["daisho_params"]
    end

    @testset "get_daisho_params error names daisho_config" begin
        wf = GridConfigTestWorkflow(span_seconds = 600)
        err = try
            Sparrow.get_daisho_params(wf)
            nothing
        catch e
            e
        end
        @test err isa ErrorException
        @test occursin("daisho_config", err.msg)
    end
end

# A small two-sweep Volume for the helper tests
function _test_volume(; with_heading::Bool)
    sweeps = map(1:2) do i
        georef = with_heading ?
            Daisho.Georeference(
                latitude = fill(10.0, 3),
                longitude = fill(20.0, 3),
                altitude = fill(100.0, 3),
                heading = fill(80.0 + 20.0 * i, 3),
            ) : nothing
        Daisho.SweepGroup(
            sweep_number = i,
            sweep_mode = "rhi",
            fixed_angle = 10.0 * i,
            time = [DateTime(2024, 1, 1, 0, 0, i)],
            range = collect(0.0:250.0:1000.0),
            azimuth = [45.0],
            elevation = [10.0 * i],
            georeference = georef,
        )
    end
    return Daisho.Volume(
        scan_name = "TEST_RHI",
        time_coverage_start = DateTime(2024, 1, 1),
        time_coverage_end = DateTime(2024, 1, 1, 0, 1),
        latitude = 10.0,
        longitude = 20.0,
        altitude = 100.0,
        sweeps = sweeps,
    )
end

@testset "single_sweep_volume" begin
    vol = _test_volume(with_heading = false)
    single = Sparrow.single_sweep_volume(vol, 2)
    @test single isa Daisho.Volume
    @test length(single.sweeps) == 1
    @test single.sweeps[1] === vol.sweeps[2]
    # Volume-level metadata carries over
    @test single.scan_name == vol.scan_name
    @test single.latitude == vol.latitude
    @test single.time_coverage_start == vol.time_coverage_start
    # Original volume is untouched
    @test length(vol.sweeps) == 2
end

@testset "mean_volume_heading" begin
    @test Sparrow.mean_volume_heading(_test_volume(with_heading = false)) == -9999.0
    # Sweep headings are 100.0 and 120.0 → mean 110.0
    @test Sparrow.mean_volume_heading(_test_volume(with_heading = true)) ≈ 110.0
end

@testset "grid output naming includes seconds (issue #1)" begin
    t = DateTime(2022, 9, 17, 18, 40, 23)
    @test Sparrow.grid_output_name("rhi", t, 12.5) == "gridded_rhi_20220917_184023_12.5.nc"
    @test Sparrow.grid_output_name("composite", t) == "gridded_composite_20220917_184023.nc"
    # Scans seconds apart in the same minute get distinct names
    t2 = DateTime(2022, 9, 17, 18, 40, 43)
    @test Sparrow.grid_output_name("rhi", t, 12.5) != Sparrow.grid_output_name("rhi", t2, 12.5)
end

@testset "warn_legacy_grid_params" begin
    wf = GridConfigTestWorkflow(beam_inflation = 0.0175, vol_xmin = -1000.0)
    _, output = _capture_stdout() do
        Sparrow.warn_legacy_grid_params(wf)
    end
    @test occursin("beam_inflation", output)
    @test occursin("vol_xmin", output)
    @test occursin("daisho_config", output)

    clean = GridConfigTestWorkflow(daisho_config = DAISHO_FIXTURE)
    _, output = _capture_stdout() do
        Sparrow.warn_legacy_grid_params(clean)
    end
    @test output == ""
end
