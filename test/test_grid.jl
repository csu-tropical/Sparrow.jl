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

@testset "sweep_elevation_angle" begin
    _sweep(; mode = "azimuth_surveillance", angle = 45.0) = Daisho.SweepGroup(
        sweep_number = 1,
        sweep_mode = mode,
        fixed_angle = angle,
        time = [DateTime(2024, 1, 1)],
        range = collect(0.0:250.0:1000.0),
        azimuth = [45.0],
        elevation = [45.0],
    )

    # A PPI sweep passes its elevation straight through
    @test Sparrow.sweep_elevation_angle(_sweep(), "QVP", "vol.nc", 1) == 45.0

    # These modes do not store an elevation in fixed_angle, so they are rejected
    # even when the volume filename does not say "RHI"
    for mode in Sparrow.NON_ELEVATION_SWEEP_MODES
        @test Sparrow.is_rhi_sweep(_sweep(mode = mode))
        angle, output = _capture_stdout() do
            Sparrow.sweep_elevation_angle(_sweep(mode = mode), "QVP", "vol.nc", 3)
        end
        @test angle === nothing
        @test occursin("not an elevation angle", output)
        @test occursin(mode, output)
        @test occursin("vol.nc", output)
        @test occursin("sweep 3", output)
    end

    # Sweep mode is matched case- and whitespace-insensitively
    @test Sparrow.is_rhi_sweep(_sweep(mode = " RHI "))

    # The azimuth-scanning modes from the CfRadial enumeration are all accepted,
    # including the reader's default when the file has no sweep_mode variable
    for mode in ("azimuth_surveillance", "sector", "manual_ppi", "vertical_pointing")
        @test !Sparrow.is_rhi_sweep(_sweep(mode = mode))
        @test Sparrow.sweep_elevation_angle(_sweep(mode = mode), "PPI", "vol.nc", 1) == 45.0
    end

    # A missing fixed_angle reads back as NaN: skipped with a warning rather
    # than dropped silently by a comparison that is always false
    angle, output = _capture_stdout() do
        Sparrow.sweep_elevation_angle(_sweep(angle = NaN), "PPI", "vol.nc", 2)
    end
    @test angle === nothing
    @test occursin("NaN", output)
    @test occursin("PPI", output)
end

@testset "grid output naming includes seconds (issue #1)" begin
    t = DateTime(2022, 9, 17, 18, 40, 23)
    @test Sparrow.grid_output_name("rhi", t, 12.5) == "gridded_rhi_20220917_184023_12.5.nc"
    @test Sparrow.grid_output_name("composite", t) == "gridded_composite_20220917_184023.nc"
    # Scans seconds apart in the same minute get distinct names
    t2 = DateTime(2022, 9, 17, 18, 40, 43)
    @test Sparrow.grid_output_name("rhi", t, 12.5) != Sparrow.grid_output_name("rhi", t2, 12.5)
end

@testset "resolve_index_time" begin
    # Default preserves the per-scan time when the parameter is absent
    @test Sparrow.resolve_index_time(GridConfigTestWorkflow()) == :scan_start

    # Accepts strings and Symbols, matched case-insensitively
    for mode in Sparrow.INDEX_TIME_OPTIONS
        @test Sparrow.resolve_index_time(GridConfigTestWorkflow(index_time = mode)) == mode
        @test Sparrow.resolve_index_time(GridConfigTestWorkflow(index_time = String(mode))) == mode
        @test Sparrow.resolve_index_time(
            GridConfigTestWorkflow(index_time = uppercase(String(mode)))) == mode
    end

    # An unknown value names the valid options
    err = try
        Sparrow.resolve_index_time(GridConfigTestWorkflow(index_time = "scan_end"))
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("scan_start", err.msg)
    @test occursin("stop_time", err.msg)

    # A wrong-typed value is rejected rather than stringified
    @test_throws ErrorException Sparrow.resolve_index_time(GridConfigTestWorkflow(index_time = 3))

    # Validation happens at setup, before any data is read
    @test_throws ErrorException Sparrow.setup_workflow_params(
        GridConfigTestWorkflow(index_time = "scan_end"), _test_parsed_args())
end

@testset "grid_index_time" begin
    scan_start = DateTime(2022, 9, 17, 18, 40, 23)
    start_time = DateTime(2022, 9, 17, 18, 40, 0)
    stop_time = DateTime(2022, 9, 17, 18, 50, 0)

    @test Sparrow.grid_index_time(:scan_start, scan_start, start_time, stop_time) == scan_start
    @test Sparrow.grid_index_time(:start_time, scan_start, start_time, stop_time) == start_time
    @test Sparrow.grid_index_time(:stop_time, scan_start, start_time, stop_time) == stop_time
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
