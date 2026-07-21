# Hybrid-scan step registration, naming, and guard behaviour.
# The selection science itself is tested in Daisho (test/test_hybrid_scan.jl).

using Dates

@test isdefined(Sparrow, :HybridScanStep)
@test HybridScanStep isa DataType

# The step must dispatch through the generic Sparrow method, the way the driver
# resolves it in run_workflow_step.
@test hasmethod(Sparrow.workflow_step,
                Tuple{Sparrow.SparrowWorkflow, Type{HybridScanStep}, String, String})

@testset "hybrid output naming" begin
    t = DateTime(2022, 9, 17, 18, 40, 23)
    @test Sparrow.hybrid_output_name(t) == "gridded_hybrid_20220917_184023.nc"
    # Chunks seconds apart get distinct names, as the archiving marker logic needs
    @test Sparrow.hybrid_output_name(t) !=
          Sparrow.hybrid_output_name(DateTime(2022, 9, 17, 18, 40, 43))
end

@testset "step skips cleanly without work" begin
    @workflow_type HybridStepTestWorkflow

    config = joinpath(mktempdir(), "hybrid.toml")
    open(config, "w") do f
        write(f, """
        [fields]
        DBZ = ["linear_interp", "define_detection"]
        SQI = ["weighted_interp", "define_scanned"]

        [io]
        fill_value = -32768.0
        undetect   = -9999.0

        [hybrid_scan]
        enabled = true
        base_angle = 0.5
        beam_height_maximum = 1000.0
        """)
    end

    wf = HybridStepTestWorkflow(daisho_config = config)
    wf["daisho_params"] = Daisho.DaishoParameters(config)
    @test wf["daisho_params"].hybrid_scan.enabled

    # An empty input directory is a no-op, not an error (a chunk may have no PPIs).
    in_dir = mktempdir()
    out_dir = mktempdir()
    Sparrow.workflow_step(wf, HybridScanStep, in_dir, out_dir;
        start_time = DateTime(2024, 9, 3, 15, 0, 0),
        stop_time = DateTime(2024, 9, 3, 15, 5, 0),
        step_name = "hybrid")
    @test isempty(readdir(out_dir))

    # A disabled [hybrid_scan] block is also a no-op rather than a failure.
    config_off = joinpath(mktempdir(), "hybrid_off.toml")
    open(config_off, "w") do f
        write(f, """
        [fields]
        DBZ = ["linear_interp", "define_detection"]

        [io]
        fill_value = -32768.0
        undetect   = -9999.0
        """)
    end
    wf_off = HybridStepTestWorkflow(daisho_config = config_off)
    wf_off["daisho_params"] = Daisho.DaishoParameters(config_off)
    @test !wf_off["daisho_params"].hybrid_scan.enabled
    Sparrow.workflow_step(wf_off, HybridScanStep, in_dir, out_dir;
        start_time = DateTime(2024, 9, 3, 15, 0, 0),
        stop_time = DateTime(2024, 9, 3, 15, 5, 0),
        step_name = "hybrid")
    @test isempty(readdir(out_dir))
end
