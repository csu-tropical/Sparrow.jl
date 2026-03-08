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
        source = S3BucketSource(bucket="unidata-nexrad-level2", station="KFTG")
        @test source isa DataSource
        @test source isa S3BucketSource
        @test source.bucket == "unidata-nexrad-level2"
        @test source.station == "KFTG"
        @test source.prefix_template == "{YYYY}/{MM}/{DD}/{station}/"
        @test source.region == "us-east-1"
        @test source.endpoint == "https://unidata-nexrad-level2.s3.us-east-1.amazonaws.com"
        @test is_remote(source) == true

        # Custom endpoint
        source2 = S3BucketSource(
            bucket="my-bucket",
            station="KXYZ",
            endpoint="https://custom.endpoint.com"
        )
        @test source2.endpoint == "https://custom.endpoint.com"

        # Custom region
        source3 = S3BucketSource(
            bucket="my-bucket",
            station="KXYZ",
            region="eu-west-1"
        )
        @test source3.endpoint == "https://my-bucket.s3.eu-west-1.amazonaws.com"

        # File pattern
        source4 = S3BucketSource(
            bucket="my-bucket",
            station="KXYZ",
            file_pattern=r"\.nc$"
        )
        @test source4.file_pattern == r"\.nc$"

        # Custom prefix template (RTMA-style)
        source5 = S3BucketSource(
            bucket="noaa-rtma-pds",
            station="rtma2p5",
            prefix_template="{station}.{YYYYmmdd}/"
        )
        @test source5.prefix_template == "{station}.{YYYYmmdd}/"
    end

    @testset "S3 prefix template resolution" begin
        # Default NEXRAD template
        nexrad = S3BucketSource(bucket="test", station="KFTG")
        @test Sparrow._s3_resolve_prefix(nexrad, "20240101") == "2024/01/01/KFTG/"

        # RTMA template
        rtma = S3BucketSource(bucket="test", station="rtma2p5",
                              prefix_template="{station}.{YYYYmmdd}/")
        @test Sparrow._s3_resolve_prefix(rtma, "20240101") == "rtma2p5.20240101/"

        # Custom template with all placeholders
        custom = S3BucketSource(bucket="test", station="SITE1",
                                prefix_template="{station}/{YYYY}/{MM}/{DD}/data/")
        @test Sparrow._s3_resolve_prefix(custom, "20240903") == "SITE1/2024/09/03/data/"
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
        s3 = S3BucketSource(bucket="test-bucket", station="KFTG")
        wf2 = DSTestWorkflow(base_data_dir="/unused", data_source=s3)
        source2 = get_data_source(wf2)
        @test source2 isa S3BucketSource
        @test source2.bucket == "test-bucket"
    end

    @testset "supports_streaming default" begin
        source = LocalDirSource("/tmp")
        @test Sparrow.supports_streaming(source) == false
        @test_throws ErrorException Sparrow.fetch_stream(source, "file", "date")
    end

    # Live S3 integration test — requires network access
    if get(ENV, "SPARROW_RUN_INTEGRATION_TESTS", "") == "1"
        @testset "S3BucketSource live access (unidata-nexrad-level2)" begin
            source = S3BucketSource(
                bucket = "unidata-nexrad-level2",
                station = "KFTG",
            )

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
            source_filtered = S3BucketSource(
                bucket = "unidata-nexrad-level2",
                station = "KFTG",
                file_pattern = r"_V06$",
            )
            filtered = discover_files(source_filtered, "20240101")
            @test length(filtered) > 0
            @test all(f -> endswith(f, "_V06"), filtered)
        end

        @testset "S3BucketSource live access (noaa-rtma-pds)" begin
            source = S3BucketSource(
                bucket = "noaa-rtma-pds",
                station = "rtma2p5",
                prefix_template = "{station}.{YYYYmmdd}/",
                file_pattern = r"\.grb2$",
            )

            # Discover files for a known date
            files = discover_files(source, "20240101")
            @test length(files) > 0
            @test all(f -> endswith(f, ".grb2"), files)

            # has_data
            @test has_data(source, "20240101") == true

            # Fetch a single small file (index files are tiny, but grab a grb2)
            dest = mktempdir()
            path = fetch_file(source, files[1], dest, "20240101")
            @test isfile(path)
            @test filesize(path) > 0
            rm(dest, recursive=true)
        end
    end
end
