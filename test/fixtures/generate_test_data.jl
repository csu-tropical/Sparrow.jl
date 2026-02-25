# Generate minimal test data files for integration testing
# Run this script to create sample data files in the fixtures/data directory

using Dates

"""
    generate_test_data(data_dir::String; num_files::Int=3)

Generate minimal test data files that simulate radar data filenames.
Creates simple text files with timestamps in the filename.
"""
function generate_test_data(data_dir::String; num_files::Int=3)
    mkpath(data_dir)
    
    println("Generating $num_files test data files in $data_dir...")
    
    base_time = DateTime(2024, 8, 16, 8, 0, 0)
    
    for i in 1:num_files
        # Generate a timestamp
        file_time = base_time + Minute((i-1) * 5)
        date_str = Dates.format(file_time, "YYYYmmdd")
        time_str = Dates.format(file_time, "HHMMSS")
        
        # Create a CfRadial-style filename
        next_time = file_time + Minute(5)
        next_time_str = Dates.format(next_time, "HHMMSS")
        
        filename = "cfrad.$(date_str)_$(time_str).000_to_$(date_str)_$(next_time_str).000_TEST_SUR.nc"
        filepath = joinpath(data_dir, filename)
        
        # Create a simple text file (not real NetCDF for simplicity)
        # In real tests, you'd want actual NetCDF files
        content = """
        Test radar data file
        Time: $(file_time)
        File: $(filename)
        Data: DBZ, VEL, SQI
        Simulated radar moments for testing
        """
        
        write(filepath, content)
        println("  Created: $filename")
    end
    
    println("✅ Test data generation complete!")
    return num_files
end

"""
    generate_seapol_test_data(data_dir::String; num_files::Int=3)

Generate SEAPOL-style test data files.
"""
function generate_seapol_test_data(data_dir::String; num_files::Int=3)
    mkpath(data_dir)
    
    println("Generating $num_files SEAPOL test files in $data_dir...")
    
    base_time = DateTime(2024, 8, 16, 8, 0, 0)
    
    for i in 1:num_files
        file_time = base_time + Minute((i-1) * 5)
        date_str = Dates.format(file_time, "YYYYmmdd")
        time_str = Dates.format(file_time, "HHMMSS")
        
        filename = "SEA$(date_str)_$(time_str)"
        filepath = joinpath(data_dir, filename)
        
        content = """
        SEAPOL Test Data
        Timestamp: $(file_time)
        Scan: SUR
        """
        
        write(filepath, content)
        println("  Created: $filename")
    end
    
    println("✅ SEAPOL test data generation complete!")
    return num_files
end

"""
    cleanup_test_data(data_dir::String)

Remove all test data files from the specified directory.
"""
function cleanup_test_data(data_dir::String)
    if isdir(data_dir)
        println("Cleaning up test data in $data_dir...")
        for file in readdir(data_dir; join=true)
            if isfile(file)
                rm(file)
                println("  Removed: $(basename(file))")
            end
        end
        println("✅ Cleanup complete!")
    else
        println("Directory $data_dir does not exist, nothing to clean up.")
    end
end

# If run as a script, generate test data
if abspath(PROGRAM_FILE) == @__FILE__
    data_dir = joinpath(@__DIR__, "data")
    
    println("=" ^ 50)
    println("Sparrow Test Data Generator")
    println("=" ^ 50)
    
    # Generate CfRadial-style test files
    generate_test_data(data_dir, num_files=5)
    
    println()
    
    # Generate SEAPOL-style test files
    seapol_dir = joinpath(data_dir, "seapol")
    generate_seapol_test_data(seapol_dir, num_files=3)
    
    println()
    println("Test data files are ready for integration testing!")
    println("Data location: $data_dir")
end