using Test
using Sparrow

@testset "Realtime Helper Functions" begin

    @testset "poll_directory" begin
        # Create a temporary directory with test files
        tmp = mktempdir()

        # Empty directory
        @test poll_directory(tmp) == String[]

        # Add files
        touch(joinpath(tmp, "file_c.nc"))
        touch(joinpath(tmp, "file_a.nc"))
        touch(joinpath(tmp, "file_b.nc"))
        touch(joinpath(tmp, ".hidden"))
        mkdir(joinpath(tmp, "subdir"))

        files = poll_directory(tmp)
        @test length(files) == 3
        # Should be reversed (newest first by name)
        @test files[1] == "file_c.nc"
        @test files[2] == "file_b.nc"
        @test files[3] == "file_a.nc"

        # Hidden files excluded
        @test !(".hidden" in files)
        # Directories excluded
        @test !("subdir" in files)

        rm(tmp, recursive=true)
    end

    @testset "poll_directory non-existent" begin
        # Non-existent directory should return empty, not crash
        files = poll_directory("/nonexistent/path/that/does/not/exist")
        @test files == String[]
    end

    @testset "poll_directory with only hidden files" begin
        tmp = mktempdir()
        touch(joinpath(tmp, ".hidden1"))
        touch(joinpath(tmp, ".hidden2"))
        @test poll_directory(tmp) == String[]
        rm(tmp, recursive=true)
    end

    @testset "poll_directory with only directories" begin
        tmp = mktempdir()
        mkdir(joinpath(tmp, "dir1"))
        mkdir(joinpath(tmp, "dir2"))
        @test poll_directory(tmp) == String[]
        rm(tmp, recursive=true)
    end
end
