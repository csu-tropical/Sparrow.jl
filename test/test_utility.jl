using Dates

include("generate_test_cfradial.jl")

# Runtime detection of external tools
const HAS_RADXPRINT = Sys.which("RadxPrint") !== nothing

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
    else
        @testset "get_scan_start (skipped — RadxPrint not found)" begin
            @test_skip true
            @info "Skipping get_scan_start tests: RadxPrint not found on PATH"
        end
    end
end
