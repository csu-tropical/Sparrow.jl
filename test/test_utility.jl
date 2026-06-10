using Dates

include("generate_test_cfradial.jl")

# Runtime detection of external tools
const HAS_RADXPRINT = Sys.which("RadxPrint") !== nothing
const HAS_RADXCONVERT = Sys.which("RadxConvert") !== nothing

@testset "Utility Functions" begin

    @testset "Step types are defined" begin
        @test isdefined(Sparrow, :PassThroughStep)
        @test PassThroughStep isa DataType
        @test isdefined(Sparrow, :filterByTimeStep)
        @test filterByTimeStep isa DataType
        @test isdefined(Sparrow, :MergeVolumesStep)
        @test MergeVolumesStep isa DataType
        @test isdefined(Sparrow, :PiccoloMergeStep)
        @test PiccoloMergeStep isa DataType
    end

    @testset "get_scan_start exists and is callable" begin
        @test hasmethod(Sparrow.get_scan_start, Tuple{String})
    end

    if HAS_RADXPRINT
        @testset "get_scan_start with generated CfRadial" begin
            # Generate a test CfRadial file and verify get_scan_start reads it
            fixture_dir = joinpath(@__DIR__, "fixtures", "data")
            mkpath(fixture_dir)
            testfile = joinpath(fixture_dir, "cfrad.20240903_120008_test.nc")
            expected_time = DateTime(2024, 9, 3, 12, 0, 8)

            generate_test_cfradial(testfile;
                start_time = expected_time,
                instrument_name = "TEST_RADAR",
                scan_name = "TEST_VOL1")

            try
                result = Sparrow.get_scan_start(testfile)
                @test result == expected_time
                @test result isa DateTime
            finally
                rm(testfile; force=true)
            end
        end

        @testset "get_scan_start with multiple times" begin
            fixture_dir = joinpath(@__DIR__, "fixtures", "data")
            mkpath(fixture_dir)

            times = [
                DateTime(2024, 1, 15, 0, 0, 0),
                DateTime(2024, 6, 30, 23, 59, 59),
                DateTime(2024, 12, 31, 12, 30, 45),
            ]

            for (i, t) in enumerate(times)
                testfile = joinpath(fixture_dir, "cfrad_time_test_$(i).nc")
                generate_test_cfradial(testfile; start_time=t)
                try
                    result = Sparrow.get_scan_start(testfile)
                    @test result == t
                finally
                    rm(testfile; force=true)
                end
            end
        end

        # CfRadial 2.0 regression: lrose leaves the volume startTimeSecs unset for
        # cfrad2.* files, so get_scan_start must fall back to time_coverage_start.
        if HAS_RADXCONVERT
            @testset "get_scan_start with CfRadial 2.0 (cfrad2)" begin
                fixture_dir = joinpath(@__DIR__, "fixtures", "data")
                v2_dir = joinpath(fixture_dir, "cf2")
                mkpath(fixture_dir); mkpath(v2_dir)
                v1file = joinpath(fixture_dir, "cfrad.20240903_120008_cf2src.nc")
                expected_time = DateTime(2024, 9, 3, 12, 0, 8)

                generate_test_cfradial(v1file; start_time = expected_time)
                try
                    # Convert to CfRadial 2.0; lrose writes to <outdir>/<YYYYMMDD>/cfrad2.*.nc
                    run(pipeline(`RadxConvert -cf2 -f $v1file -outdir $v2_dir`;
                                 stdout=devnull, stderr=devnull))
                    v2files = filter(f -> startswith(basename(f), "cfrad2"),
                                     [joinpath(root, f) for (root, _, fs) in walkdir(v2_dir)
                                      for f in fs if endswith(f, ".nc")])
                    @test !isempty(v2files)
                    if !isempty(v2files)
                        result = Sparrow.get_scan_start(first(v2files))
                        @test result == expected_time
                    end
                finally
                    rm(v1file; force=true)
                    rm(v2_dir; force=true, recursive=true)
                end
            end
        else
            @testset "get_scan_start cfrad2 (skipped — RadxConvert not found)" begin
                @test_skip true
                @info "Skipping cfrad2 test: RadxConvert not found on PATH"
            end
        end
    else
        @testset "get_scan_start (skipped — RadxPrint not found)" begin
            @test_skip true
            @info "Skipping get_scan_start tests: RadxPrint not found on PATH"
        end
    end

    @testset "get_scan_name" begin
        mktempdir() do dir
            file = joinpath(dir, "cfrad.20240101_000000_TEST_RHI.nc")
            generate_test_cfradial(file; scan_name = "TEST_RHI")
            @test Sparrow.get_scan_name(file) == "TEST_RHI"
        end
        # Unreadable file falls back to empty string with a warning
        @test Sparrow.get_scan_name("/nonexistent/file.nc") == ""
    end

    @testset "sparrow script delivery (issue #5)" begin
        @test isfile(Sparrow.sparrow_script_path())

        mktempdir() do dir
            dest = joinpath(dir, "bin")
            target = Sparrow.install_sparrow_script(dest = dest)
            @test target == joinpath(dest, "sparrow")
            @test isfile(target)
            @test uperm(target) & 0x01 != 0  # owner-executable

            # Refuses to overwrite without force
            @test_throws ErrorException Sparrow.install_sparrow_script(dest = dest)
            # force=true overwrites
            @test Sparrow.install_sparrow_script(dest = dest, force = true) == target
        end
    end

end
