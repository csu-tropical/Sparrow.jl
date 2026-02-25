# Test I/O functions

using Test
using Sparrow
using Dates

@testset "I/O Functions" begin
    
    @testset "check_processed" begin
        # Create a temporary test environment
        mktempdir() do tmpdir
            archive_dir = joinpath(tmpdir, "archive")
            mkpath(archive_dir)
            
            @workflow_type TestIOWorkflow
            wf = TestIOWorkflow(base_archive_dir=archive_dir)
            
            # Test file that hasn't been processed
            test_file = "test_file.nc"
            @test !Sparrow.check_processed(wf, test_file, archive_dir)
            
            # Mark file as processed by creating the .processed file
            processed_dir = joinpath(archive_dir, ".processed")
            mkpath(processed_dir)
            processed_file = joinpath(processed_dir, test_file)
            touch(processed_file)
            
            # Now it should be marked as processed
            @test Sparrow.check_processed(wf, test_file, archive_dir)
        end
    end
    
    @testset "initialize_working_dirs" begin
        mktempdir() do tmpdir
            @workflow_type TestDirWorkflow
            
            date = "20240816"
            base_working_dir = joinpath(tmpdir, "working")
            base_archive_dir = joinpath(tmpdir, "archive")
            
            wf = TestDirWorkflow(
                base_working_dir=base_working_dir,
                base_archive_dir=base_archive_dir,
                steps=["step1" => Sparrow.PassThroughStep],
                force_reprocess=false
            )
            
            temp_dir, step_dirs = Sparrow.initialize_working_dirs(wf, date)
            
            # Test that temp directory was created
            @test isdir(temp_dir)
            @test occursin(date, temp_dir)
            
            # Test that step directories were created
            @test haskey(step_dirs, "step1")
            @test isdir(step_dirs["step1"]["input"])
            @test isdir(step_dirs["step1"]["output"])
            
            # Cleanup
            rm(temp_dir, recursive=true)
        end
    end
    
    @testset "Directory Creation" begin
        mktempdir() do tmpdir
            # Test creating nested directories
            nested_path = joinpath(tmpdir, "level1", "level2", "level3")
            mkpath(nested_path)
            
            @test isdir(nested_path)
            @test isdir(joinpath(tmpdir, "level1"))
            @test isdir(joinpath(tmpdir, "level1", "level2"))
        end
    end
    
    @testset "File Filtering" begin
        mktempdir() do tmpdir
            # Create test files and directories
            touch(joinpath(tmpdir, "file1.nc"))
            touch(joinpath(tmpdir, "file2.nc"))
            touch(joinpath(tmpdir, "file3.txt"))
            mkpath(joinpath(tmpdir, "subdir"))
            
            # Test readdir with filtering
            all_items = readdir(tmpdir)
            @test length(all_items) == 4  # 3 files + 1 dir
            
            # Filter out directories
            files = readdir(tmpdir; join=false)
            filter!(!isdir, [joinpath(tmpdir, f) for f in files])
            @test length(files) == 3
            
            # Filter for .nc files
            nc_files = filter(f -> endswith(f, ".nc"), readdir(tmpdir))
            @test length(nc_files) == 2
        end
    end
    
    @testset "Symlink Operations" begin
        mktempdir() do tmpdir
            # Create a source file
            source_file = joinpath(tmpdir, "source.txt")
            write(source_file, "test content")
            
            # Create a symlink
            link_file = joinpath(tmpdir, "link.txt")
            symlink(source_file, link_file)
            
            @test islink(link_file)
            @test isfile(link_file)
            @test read(link_file, String) == "test content"
            
            # Test that modifying through link affects source
            write(link_file, "modified")
            @test read(source_file, String) == "modified"
        end
    end
    
    @testset "File Copy Operations" begin
        mktempdir() do tmpdir
            source_dir = joinpath(tmpdir, "source")
            dest_dir = joinpath(tmpdir, "dest")
            mkpath(source_dir)
            mkpath(dest_dir)
            
            # Create source file
            source_file = joinpath(source_dir, "test.nc")
            write(source_file, "test data")
            
            # Copy file
            dest_file = joinpath(dest_dir, "test.nc")
            cp(source_file, dest_file)
            
            @test isfile(dest_file)
            @test read(dest_file, String) == "test data"
            
            # Verify it's a copy, not a link
            write(dest_file, "modified")
            @test read(source_file, String) == "test data"
            @test read(dest_file, String) == "modified"
        end
    end
    
    @testset "Path Replacement" begin
        # Test replacing path components
        input_file = "/path/to/input/data/file.nc"
        output_file = replace(input_file, "/input/" => "/output/")
        
        @test output_file == "/path/to/output/data/file.nc"
        @test occursin("output", output_file)
        @test !occursin("/input/", output_file)
    end
    
    @testset "Basename and Dirname" begin
        full_path = "/path/to/some/file.nc"
        
        @test basename(full_path) == "file.nc"
        @test dirname(full_path) == "/path/to/some"
        
        # Test with no directory
        @test basename("file.nc") == "file.nc"
        @test dirname("file.nc") == ""
    end
end