using Test
using Sparrow

@testset "DataSource Types" begin

    @testset "LocalDirSource" begin
        source = LocalDirSource("/tmp/test_data")
        @test source isa DataSource
        @test source isa LocalDirSource
        @test source.base_dir == "/tmp/test_data"
        @test is_remote(source) == false

        # has_data returns false for non-existent directory
        @test has_data(source, "20240903") == false

        # discover_files returns empty for non-existent directory
        @test discover_files(source, "20240903") == String[]
    end

    @testset "LocalDirSource with temp files" begin
        # Create a temporary directory structure
        tmp = mktempdir()
        date_dir = joinpath(tmp, "20240903")
        mkpath(date_dir)

        # Create test files
        touch(joinpath(date_dir, "file_a.nc"))
        touch(joinpath(date_dir, "file_b.nc"))
        touch(joinpath(date_dir, ".hidden_file"))
        mkdir(joinpath(date_dir, "subdir"))

        source = LocalDirSource(tmp)

        @test has_data(source, "20240903") == true
        @test has_data(source, "20240904") == false

        files = discover_files(source, "20240903")
        @test length(files) == 2
        # Files should be full paths, reversed alphabetically
        @test basename(files[1]) == "file_b.nc"
        @test basename(files[2]) == "file_a.nc"
        # Should not contain hidden files or directories
        @test all(f -> !startswith(basename(f), "."), files)
        @test all(f -> !isdir(f), files)

        # fetch_file returns local path
        path = fetch_file(source, "file_a.nc", "/tmp/dest", "20240903")
        @test path == joinpath(tmp, "20240903", "file_a.nc")

        rm(tmp, recursive=true)
    end

    @testset "S3BucketSource construction" begin
        # Minimal construction
        source = S3BucketSource(bucket="unidata-nexrad-level2")
        @test source isa DataSource
        @test source isa S3BucketSource
        @test source.bucket == "unidata-nexrad-level2"
        @test source.prefix_template == "{YYYY}/{MM}/{DD}/"
        @test source.extras == Dict{String,String}()
        @test source.region == "us-east-1"
        @test source.endpoint == "https://unidata-nexrad-level2.s3.us-east-1.amazonaws.com"
        @test is_remote(source) == true

        # With extras
        source2 = S3BucketSource(
            bucket="unidata-nexrad-level2",
            prefix_template="{YYYY}/{MM}/{DD}/{station}/",
            extras=Dict("station" => "KFTG"),
        )
        @test source2.extras["station"] == "KFTG"

        # Custom endpoint
        source3 = S3BucketSource(
            bucket="my-bucket",
            endpoint="https://custom.endpoint.com"
        )
        @test source3.endpoint == "https://custom.endpoint.com"

        # Custom region
        source4 = S3BucketSource(
            bucket="my-bucket",
            region="eu-west-1"
        )
        @test source4.endpoint == "https://my-bucket.s3.eu-west-1.amazonaws.com"

        # File pattern
        source5 = S3BucketSource(
            bucket="my-bucket",
            file_pattern=r"\.nc$"
        )
        @test source5.file_pattern == r"\.nc$"
    end

    @testset "S3 prefix template resolution" begin
        # Default template (no extras)
        basic = S3BucketSource(bucket="test")
        @test Sparrow._s3_resolve_prefix(basic, "20240101") == "2024/01/01/"

        # NEXRAD template with station extra
        nexrad = S3BucketSource(bucket="test",
                                prefix_template="{YYYY}/{MM}/{DD}/{station}/",
                                extras=Dict("station" => "KFTG"))
        @test Sparrow._s3_resolve_prefix(nexrad, "20240101") == "2024/01/01/KFTG/"

        # RTMA template
        rtma = S3BucketSource(bucket="test",
                              prefix_template="{station}.{YYYYmmdd}/",
                              extras=Dict("station" => "rtma2p5"))
        @test Sparrow._s3_resolve_prefix(rtma, "20240101") == "rtma2p5.20240101/"

        # MRMS template with region and product extras
        mrms = S3BucketSource(bucket="test",
                              prefix_template="{region}/{product}/{YYYYmmdd}/",
                              extras=Dict("region" => "CONUS", "product" => "QPE_01H"))
        @test Sparrow._s3_resolve_prefix(mrms, "20240903") == "CONUS/QPE_01H/20240903/"

        # NBM template with hour
        nbm = S3BucketSource(bucket="test",
                             prefix_template="blend.{YYYYmmdd}/{HH}/core/",
                             extras=Dict("region" => "co"))
        @test Sparrow._s3_resolve_prefix(nbm, "2024010112") == "blend.20240101/12/core/"

        # Minute-level date
        subhourly = S3BucketSource(bucket="test",
                                   prefix_template="{YYYY}/{MM}/{DD}/{HH}{mm}/")
        @test Sparrow._s3_resolve_prefix(subhourly, "202409031430") == "2024/09/03/1430/"

        # Hour placeholder not resolved when date is day-level only
        nbm_dayonly = S3BucketSource(bucket="test",
                                     prefix_template="blend.{YYYYmmdd}/{HH}/core/")
        prefix = Sparrow._s3_resolve_prefix(nbm_dayonly, "20240101")
        @test prefix == "blend.20240101/{HH}/core/"  # {HH} stays unresolved
    end

    @testset "S3 hour iteration detection" begin
        # Template with {HH}, day-level date -> needs iteration
        nbm = S3BucketSource(bucket="test",
                             prefix_template="blend.{YYYYmmdd}/{HH}/core/")
        @test Sparrow._s3_needs_hour_iteration(nbm, "20240101") == true
        @test Sparrow._s3_needs_hour_iteration(nbm, "2024010112") == false

        # Template without {HH} -> never needs iteration
        nexrad = S3BucketSource(bucket="test",
                                prefix_template="{YYYY}/{MM}/{DD}/")
        @test Sparrow._s3_needs_hour_iteration(nexrad, "20240101") == false
    end

    @testset "NEXRADSource convenience constructor" begin
        source = NEXRADSource("KFTG")
        @test source isa S3BucketSource
        @test source.bucket == "unidata-nexrad-level2"
        @test source.prefix_template == "{YYYY}/{MM}/{DD}/{station}/"
        @test source.extras == Dict("station" => "KFTG")
        @test source.file_pattern == r".*"

        # With file pattern
        source2 = NEXRADSource("KEVX", file_pattern=r"_V06$")
        @test source2.extras["station"] == "KEVX"
        @test source2.file_pattern == r"_V06$"

        # Prefix resolves correctly
        @test Sparrow._s3_resolve_prefix(source, "20240101") == "2024/01/01/KFTG/"
    end

    @testset "RTMASource convenience constructor" begin
        source = RTMASource()
        @test source isa S3BucketSource
        @test source.bucket == "noaa-rtma-pds"
        @test source.prefix_template == "{station}.{YYYYmmdd}/"
        @test source.extras == Dict("station" => "rtma2p5")
        @test source.file_pattern == r"\.grb2$"

        # Custom station
        source2 = RTMASource(station="akrtma")
        @test source2.extras["station"] == "akrtma"

        # Prefix resolves correctly
        @test Sparrow._s3_resolve_prefix(source, "20250101") == "rtma2p5.20250101/"
    end

    @testset "NBMSource convenience constructor" begin
        source = NBMSource()
        @test source isa S3BucketSource
        @test source.bucket == "noaa-nbm-grib2-pds"
        @test source.prefix_template == "blend.{YYYYmmdd}/{HH}/core/"
        @test source.extras == Dict("region" => "co")
        @test source.file_pattern == r"\.grib2$"

        # Custom region
        source2 = NBMSource(region="ak")
        @test source2.extras["region"] == "ak"

        # Prefix resolves with hour
        @test Sparrow._s3_resolve_prefix(source, "2025010100") == "blend.20250101/00/core/"

        # Needs hour iteration for day-level date
        @test Sparrow._s3_needs_hour_iteration(source, "20250101") == true
        @test Sparrow._s3_needs_hour_iteration(source, "2025010100") == false
    end

    @testset "MRMSSource convenience constructor" begin
        source = MRMSSource()
        @test source isa S3BucketSource
        @test source.bucket == "noaa-mrms-pds"
        @test source.prefix_template == "{region}/{product}/{YYYYmmdd}/"
        @test source.extras == Dict("region" => "CONUS",
                                     "product" => "MergedBaseReflectivity_00.50")
        @test source.file_pattern == r"\.grib2\.gz$"

        # Custom product
        source2 = MRMSSource(product="MultiSensor_QPE_01H_Pass2_00.00")
        @test source2.extras["product"] == "MultiSensor_QPE_01H_Pass2_00.00"

        # Custom region
        source3 = MRMSSource(region="ALASKA")
        @test source3.extras["region"] == "ALASKA"

        # Prefix resolves correctly
        @test Sparrow._s3_resolve_prefix(source, "20201014") ==
              "CONUS/MergedBaseReflectivity_00.50/20201014/"
    end

    @testset "HTTPDirSource construction" begin
        source = HTTPDirSource(base_url="https://data.noaa.gov/radar/{YYYY}/{MM}/{DD}/")
        @test source isa DataSource
        @test source isa HTTPDirSource
        @test source.base_url == "https://data.noaa.gov/radar/{YYYY}/{MM}/{DD}/"
        @test source.auth_type == :none
        @test is_remote(source) == true

        # With auth
        source2 = HTTPDirSource(
            base_url="https://private.server.com/data/",
            auth_type=:basic,
            auth_username="user",
            auth_password="pass"
        )
        @test source2.auth_type == :basic
        @test source2.auth_username == "user"

        source3 = HTTPDirSource(
            base_url="https://api.server.com/data/",
            auth_type=:api_key,
            api_key="my-key",
            api_key_header="X-Custom-Key"
        )
        @test source3.auth_type == :api_key
        @test source3.api_key_header == "X-Custom-Key"
    end

    @testset "HTTPDirSource URL resolution" begin
        source = HTTPDirSource(base_url="https://data.noaa.gov/{YYYY}/{MM}/{DD}/")
        url = Sparrow._http_resolve_url(source, "20240903")
        @test url == "https://data.noaa.gov/2024/09/03/"

        source2 = HTTPDirSource(base_url="https://data.noaa.gov/{YYYYmmdd}/")
        url2 = Sparrow._http_resolve_url(source2, "20240903")
        @test url2 == "https://data.noaa.gov/20240903/"
    end

    @testset "get_data_source helper" begin
        @workflow_type DSTestWorkflow

        # Without data_source param, falls back to LocalDirSource
        wf = DSTestWorkflow(base_data_dir="/data/raw")
        source = get_data_source(wf)
        @test source isa LocalDirSource
        @test source.base_dir == "/data/raw"

        # With explicit data_source param
        s3 = NEXRADSource("KFTG")
        wf2 = DSTestWorkflow(base_data_dir="/unused", data_source=s3)
        source2 = get_data_source(wf2)
        @test source2 isa S3BucketSource
        @test source2.bucket == "unidata-nexrad-level2"
    end

    @testset "supports_streaming default" begin
        source = LocalDirSource("/tmp")
        @test Sparrow.supports_streaming(source) == false
        @test_throws ErrorException Sparrow.fetch_stream(source, "file", "date")
    end

    # ---- Live S3 integration tests — requires network access ----
    if get(ENV, "SPARROW_RUN_INTEGRATION_TESTS", "") == "1"

        @testset "NEXRAD live access (unidata-nexrad-level2)" begin
            source = NEXRADSource("KFTG")

            # Discover files for a known date
            files = discover_files(source, "20240101")
            @test length(files) > 0
            @test all(f -> startswith(f, "KFTG"), files)

            # has_data
            @test has_data(source, "20240101") == true

            # Fetch a single file
            dest = mktempdir()
            path = fetch_file(source, files[1], dest, "20240101")
            @test isfile(path)
            @test filesize(path) > 0
            rm(dest, recursive=true)

            # File pattern filtering
            source_filtered = NEXRADSource("KFTG", file_pattern=r"_V06$")
            filtered = discover_files(source_filtered, "20240101")
            @test length(filtered) > 0
            @test all(f -> endswith(f, "_V06"), filtered)
        end

        @testset "RTMA live access (noaa-rtma-pds)" begin
            source = RTMASource()

            # Discover files for a known date
            files = discover_files(source, "20250101")
            @test length(files) > 0
            @test all(f -> endswith(f, ".grb2"), files)

            # has_data
            @test has_data(source, "20250101") == true

            # Fetch a single file
            dest = mktempdir()
            path = fetch_file(source, files[1], dest, "20250101")
            @test isfile(path)
            @test filesize(path) > 0
            rm(dest, recursive=true)
        end

        @testset "NBM live access (noaa-nbm-grib2-pds)" begin
            source = NBMSource(region="co")

            # Discover files for a specific hour (00Z cycle)
            files = discover_files(source, "2025010100")
            @test length(files) > 0
            @test all(f -> endswith(f, ".grib2"), files)
            # NBM core filenames contain the region code
            @test any(f -> occursin(".co.", f), files)

            # has_data
            @test has_data(source, "2025010100") == true

            # Fetch a single file (index files are small, but verify grib2 works)
            dest = mktempdir()
            path = fetch_file(source, files[1], dest, "2025010100")
            @test isfile(path)
            @test filesize(path) > 0
            rm(dest, recursive=true)
        end

        @testset "MRMS live access — QPE (noaa-mrms-pds)" begin
            source = MRMSSource(product="MultiSensor_QPE_01H_Pass2_00.00")

            # QPE has ~24 files/day (hourly)
            files = discover_files(source, "20201014")
            @test length(files) > 0
            @test all(f -> endswith(f, ".grib2.gz"), files)
            @test all(f -> startswith(f, "MRMS_MultiSensor_QPE"), files)

            # Fetch one file
            dest = mktempdir()
            path = fetch_file(source, files[1], dest, "20201014")
            @test isfile(path)
            @test filesize(path) > 0
            rm(dest, recursive=true)
        end

        @testset "MRMS live access — Reflectivity (noaa-mrms-pds)" begin
            # This tests pagination — reflectivity has ~720 files/day at 2-min intervals
            source = MRMSSource(product="MergedBaseReflectivity_00.50")

            files = discover_files(source, "20201014")
            @test length(files) > 100  # Should have hundreds of files
            @test all(f -> endswith(f, ".grib2.gz"), files)
            @test all(f -> startswith(f, "MRMS_MergedBaseReflectivity"), files)
        end

    end
end
