# Examples

This page provides complete, practical examples of Sparrow workflows for common use cases.

## Example 1: Basic Radar Quality Control Workflow

This example demonstrates a simple workflow that converts raw radar data and applies quality control.

```julia
using Sparrow

# Define the workflow type
@workflow_type RadarQCWorkflow

# Define processing steps
@workflow_step ConvertToNetCDF
@workflow_step RemoveClutter
@workflow_step FlagSuspiciousData

# Create the workflow instance
workflow = RadarQCWorkflow(
    # Required directories
    base_working_dir = "/tmp/radar_qc",
    base_archive_dir = "/data/processed/qc",
    base_data_dir = "/data/raw/radar",
    base_plot_dir = "/data/plots",
    
    # Processing parameters
    minute_span = 10,
    reverse = false,
    
    # Define the processing pipeline
    # Format: (step_name, step_type, input_directory, archive)
    steps = [
        ("convert", ConvertToNetCDF, "base_data", false),
        ("declutter", RemoveClutter, "convert", false),
        ("flag", FlagSuspiciousData, "declutter", true)
    ],
    
    # Radar configuration
    raw_moment_names = ["DBZ", "VEL", "WIDTH", "ZDR", "PHIDP"],
    qc_moment_names = ["DBZ", "VEL", "WIDTH"],
    
    # QC thresholds
    dbz_min = -10.0,
    dbz_max = 70.0,
    vel_max = 30.0,
    
    message_level = 2
)

# Step 1: Convert raw data to NetCDF
function Sparrow.workflow_step(workflow::RadarQCWorkflow, ::Type{ConvertToNetCDF},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_info("Converting raw radar files to NetCDF format")
    mkpath(output_dir)
    
    # Find raw files
    raw_files = readdir(input_dir; join=true)
    filter!(f -> endswith(f, ".raw") || endswith(f, ".uf"), raw_files)
    
    for raw_file in raw_files
        output_file = joinpath(output_dir, basename(raw_file) * ".nc")
        
        # Use RadxConvert to convert to CF-Radial format
        cmd = `RadxConvert -f $(raw_file) -outdir $(output_dir) -outformat cfradial`
        run(cmd)
        
        msg_debug("Converted $(basename(raw_file))")
    end
    
    return length(raw_files)
end

# Step 2: Remove ground clutter
function Sparrow.workflow_step(workflow::RadarQCWorkflow, ::Type{RemoveClutter},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_info("Removing ground clutter from radar data")
    mkpath(output_dir)
    
    using NCDatasets
    
    netcdf_files = readdir(input_dir; join=true)
    filter!(f -> endswith(f, ".nc"), netcdf_files)
    
    for nc_file in netcdf_files
        output_file = joinpath(output_dir, basename(nc_file))
        
        # Simple clutter removal based on velocity texture
        Dataset(nc_file, "r") do ds_in
            Dataset(output_file, "c") do ds_out
                # Copy dimensions and variables
                for (dimname, dim) in ds_in.dim
                    defDim(ds_out, dimname, length(dim))
                end
                
                # Process reflectivity with clutter filter
                if haskey(ds_in, "DBZ")
                    dbz = ds_in["DBZ"][:]
                    vel = ds_in["VEL"][:]
                    
                    # Flag low velocity variance as clutter
                    dbz[abs.(vel) .< 0.5] .= NaN
                    
                    defVar(ds_out, "DBZ", dbz, ("time", "range", "azimuth"))
                end
            end
        end
        
        msg_debug("Decluttered $(basename(nc_file))")
    end
    
    return length(netcdf_files)
end

# Step 3: Flag suspicious data
function Sparrow.workflow_step(workflow::RadarQCWorkflow, ::Type{FlagSuspiciousData},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_info("Flagging suspicious data values")
    mkpath(output_dir)
    
    dbz_min = get_param(workflow, "dbz_min", -10.0)
    dbz_max = get_param(workflow, "dbz_max", 70.0)
    vel_max = get_param(workflow, "vel_max", 30.0)
    
    using NCDatasets
    
    nc_files = readdir(input_dir; join=true)
    filter!(f -> endswith(f, ".nc"), nc_files)
    
    flagged_count = 0
    for nc_file in nc_files
        output_file = joinpath(output_dir, basename(nc_file))
        cp(nc_file, output_file; force=true)
        
        Dataset(output_file, "a") do ds
            # Flag out-of-range reflectivity
            if haskey(ds, "DBZ")
                dbz = ds["DBZ"][:]
                mask = (dbz .< dbz_min) .| (dbz .> dbz_max)
                if any(mask)
                    dbz[mask] .= NaN
                    ds["DBZ"][:] = dbz
                    flagged_count += sum(mask)
                end
            end
            
            # Flag unrealistic velocities
            if haskey(ds, "VEL")
                vel = ds["VEL"][:]
                mask = abs.(vel) .> vel_max
                if any(mask)
                    vel[mask] .= NaN
                    ds["VEL"][:] = vel
                    flagged_count += sum(mask)
                end
            end
        end
    end
    
    msg_info("Flagged $(flagged_count) suspicious data points")
    return length(nc_files)
end
```

Run this workflow with:

```bash
julia sparrow radar_qc_workflow.jl --datetime 20240115_000000 --num_workers 4
```

## Example 2: Multi-Radar Merge Workflow

This example merges data from multiple radar sources into a common grid.

```julia
using Sparrow

@workflow_type MultiRadarMerge

@workflow_step CollectRadarData
@workflow_step GridEachRadar
@workflow_step MergeGrids
@workflow_step CreateComposite

workflow = MultiRadarMerge(
    base_working_dir = "/tmp/merge",
    base_archive_dir = "/data/merged",
    base_data_dir = "/data/radars",
    base_plot_dir = "/plots/composites",
    
    minute_span = 5,
    
    # Format: (step_name, step_type, input_directory, archive)
    steps = [
        ("collect", CollectRadarData, "base_data", false),
        ("grid", GridEachRadar, "collect", false),
        ("merge", MergeGrids, "grid", false),
        ("composite", CreateComposite, "merge", true)
    ],
    
    # Radar sites
    radar_sites = ["SITE1", "SITE2", "SITE3"],
    
    # Grid specification
    grid_nx = 400,
    grid_ny = 400,
    grid_dx = 1000.0,  # 1 km
    grid_dy = 1000.0,
    grid_origin_lat = 40.0,
    grid_origin_lon = -105.0,
    
    raw_moment_names = ["DBZ"],
    qc_moment_names = ["DBZ"],
    
    message_level = 2
)

function Sparrow.workflow_step(workflow::MultiRadarMerge, ::Type{CollectRadarData},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_info("Collecting data from multiple radar sites")
    mkpath(output_dir)
    
    sites = get_param(workflow, "radar_sites", Vector{String})
    base_dir = workflow["base_data_dir"]
    
    collected = 0
    for site in sites
        site_dir = joinpath(base_dir, site)
        if !isdir(site_dir)
            msg_warning("Radar site directory not found: $(site_dir)")
            continue
        end
        
        # Copy files from each site to output
        for file in readdir(site_dir; join=true)
            if endswith(file, ".nc")
                dest = joinpath(output_dir, "$(site)_$(basename(file))")
                cp(file, dest; force=true)
                collected += 1
            end
        end
    end
    
    msg_info("Collected $(collected) files from $(length(sites)) radar sites")
    return collected
end

function Sparrow.workflow_step(workflow::MultiRadarMerge, ::Type{GridEachRadar},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_info("Gridding each radar to common grid")
    mkpath(output_dir)
    
    nx = workflow["grid_nx"]
    ny = workflow["grid_ny"]
    dx = workflow["grid_dx"]
    dy = workflow["grid_dy"]
    
    files = readdir(input_dir; join=true)
    filter!(f -> endswith(f, ".nc"), files)
    
    for file in files
        # Grid this radar file
        output_file = joinpath(output_dir, basename(file))
        
        # Call gridding function (simplified)
        grid_radar_to_cartesian(file, output_file, nx, ny, dx, dy)
        
        msg_debug("Gridded $(basename(file))")
    end
    
    return length(files)
end

function Sparrow.workflow_step(workflow::MultiRadarMerge, ::Type{MergeGrids},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_info("Merging grids from all radars")
    mkpath(output_dir)
    
    gridded_files = readdir(input_dir; join=true)
    filter!(f -> endswith(f, ".nc"), gridded_files)
    
    if isempty(gridded_files)
        msg_warning("No gridded files to merge")
        return 0
    end
    
    # Create merged grid (simplified - would use proper weighted averaging)
    output_file = joinpath(output_dir, "merged_composite.nc")
    
    # Load all grids and merge
    using NCDatasets
    
    all_dbz = []
    for file in gridded_files
        Dataset(file, "r") do ds
            push!(all_dbz, ds["DBZ"][:])
        end
    end
    
    # Simple maximum merge
    merged_dbz = maximum(cat(all_dbz...; dims=4); dims=4)[:,:,:,1]
    
    # Save merged grid
    Dataset(output_file, "c") do ds
        defDim(ds, "x", size(merged_dbz, 1))
        defDim(ds, "y", size(merged_dbz, 2))
        defDim(ds, "z", size(merged_dbz, 3))
        defVar(ds, "DBZ", merged_dbz, ("x", "y", "z"))
    end
    
    msg_info("Merged $(length(gridded_files)) radar grids")
    return 1
end

function Sparrow.workflow_step(workflow::MultiRadarMerge, ::Type{CreateComposite},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_info("Creating composite visualization")
    mkpath(output_dir)
    
    # Find merged file
    merged_file = joinpath(input_dir, "merged_composite.nc")
    if !isfile(merged_file)
        msg_error("Merged file not found: $(merged_file)")
        return 0
    end
    
    using NCDatasets, CairoMakie
    
    Dataset(merged_file, "r") do ds
        dbz = ds["DBZ"][:,:,1]  # Get lowest level
        
        # Create plot
        fig = Figure(resolution=(800, 600))
        ax = Axis(fig[1, 1], title="Multi-Radar Composite")
        
        hm = heatmap!(ax, dbz', colormap=:viridis, colorrange=(-10, 60))
        Colorbar(fig[1, 2], hm, label="Reflectivity (dBZ)")
        
        output_plot = joinpath(output_dir, "composite.png")
        save(output_plot, fig)
        
        msg_info("Created composite plot: $(output_plot)")
    end
    
    return 1
end

# Helper function (would be in separate file)
function grid_radar_to_cartesian(input_file, output_file, nx, ny, dx, dy)
    # Simplified gridding - in practice would use proper interpolation
    msg_debug("Gridding $(basename(input_file))")
    cp(input_file, output_file; force=true)
end
```

## Example 3: Continuous Monitoring Workflow

This example demonstrates a workflow that continuously monitors for new files and processes them.

```julia
using Sparrow

@workflow_type ContinuousMonitor

@workflow_step WatchForFiles
@workflow_step QuickQC
@workflow_step GenerateAlert

workflow = ContinuousMonitor(
    base_working_dir = "/tmp/monitor",
    base_archive_dir = "/data/archive/monitor",
    base_data_dir = "/data/incoming",
    base_plot_dir = "/data/alerts",
    
    minute_span = 1,  # Check every minute
    
    # Format: (step_name, step_type, input_directory, archive)
    steps = [
        ("watch", WatchForFiles, "base_data", false),
        ("qc", QuickQC, "watch", false),
        ("alert", GenerateAlert, "qc", true)
    ],
    
    # Monitoring parameters
    watch_pattern = r".*\.nc$",
    alert_threshold_dbz = 50.0,
    alert_email = "radar@example.com",
    
    raw_moment_names = ["DBZ"],
    qc_moment_names = ["DBZ"],
    
    message_level = 3  # Debug level for monitoring
)

function Sparrow.workflow_step(workflow::ContinuousMonitor, ::Type{WatchForFiles},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_debug("Watching for new files in $(input_dir)")
    mkpath(output_dir)
    
    pattern = get_param(workflow, "watch_pattern", r".*\.nc$")
    
    # Find new files
    files = readdir(input_dir; join=true)
    filter!(f -> occursin(pattern, basename(f)), files)
    filter!(isfile, files)
    
    # Copy new files to processing directory
    for file in files
        dest = joinpath(output_dir, basename(file))
        if !isfile(dest)
            cp(file, dest)
            msg_info("New file detected: $(basename(file))")
        end
    end
    
    return length(files)
end

function Sparrow.workflow_step(workflow::ContinuousMonitor, ::Type{QuickQC},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_debug("Performing quick QC on new files")
    mkpath(output_dir)
    
    using NCDatasets
    
    files = readdir(input_dir; join=true)
    filter!(f -> endswith(f, ".nc"), files)
    
    for file in files
        output_file = joinpath(output_dir, basename(file))
        
        # Quick QC: check for valid data
        Dataset(file, "r") do ds
            if haskey(ds, "DBZ")
                dbz = ds["DBZ"][:]
                
                # Basic checks
                valid_data = !all(isnan.(dbz))
                reasonable_range = all(dbz[.!isnan.(dbz)] .< 100.0)
                
                if valid_data && reasonable_range
                    cp(file, output_file; force=true)
                    msg_debug("QC passed: $(basename(file))")
                else
                    msg_warning("QC failed: $(basename(file))")
                end
            end
        end
    end
    
    return length(readdir(output_dir))
end

function Sparrow.workflow_step(workflow::ContinuousMonitor, ::Type{GenerateAlert},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_debug("Checking for alert conditions")
    mkpath(output_dir)
    
    threshold = get_param(workflow, "alert_threshold_dbz", 50.0)
    
    using NCDatasets
    
    files = readdir(input_dir; join=true)
    filter!(f -> endswith(f, ".nc"), files)
    
    alerts_generated = 0
    for file in files
        Dataset(file, "r") do ds
            if haskey(ds, "DBZ")
                dbz = ds["DBZ"][:]
                max_dbz = maximum(filter(!isnan, dbz))
                
                if max_dbz >= threshold
                    msg_warning("ALERT: High reflectivity detected: $(max_dbz) dBZ in $(basename(file))")
                    
                    # Generate alert file
                    alert_file = joinpath(output_dir, "alert_$(basename(file)).txt")
                    open(alert_file, "w") do io
                        println(io, "Alert generated at $(now())")
                        println(io, "File: $(basename(file))")
                        println(io, "Max reflectivity: $(max_dbz) dBZ")
                        println(io, "Threshold: $(threshold) dBZ")
                    end
                    
                    alerts_generated += 1
                end
            end
        end
    end
    
    if alerts_generated > 0
        msg_warning("Generated $(alerts_generated) alerts")
    end
    
    return alerts_generated
end
```

Run this in continuous mode:

```bash
# Process data as it arrives
while true; do
    julia sparrow monitor_workflow.jl --datetime now -v 3
    sleep 60
done
```

## Example 4: Research Data Processing Pipeline

A complete pipeline for research applications with visualization.

```julia
using Sparrow

@workflow_type ResearchPipeline

@workflow_step QualityControl
@workflow_step DopplerDealiasing
@workflow_step AttentuationCorrection
@workflow_step GridData
@workflow_step CalculateDerivedProducts
@workflow_step CreateVisualizations

workflow = ResearchPipeline(
    base_working_dir = "/scratch/research",
    base_archive_dir = "/data/research/processed",
    base_data_dir = "/data/research/raw",
    base_plot_dir = "/data/research/figures",
    
    minute_span = 5,
    
    # Format: (step_name, step_type, input_directory, archive)
    steps = [
        ("qc", QualityControl, "base_data", false),
        ("dealias", DopplerDealiasing, "qc", false),
        ("atten", AttentuationCorrection, "dealias", false),
        ("grid", GridData, "atten", false),
        ("derived", CalculateDerivedProducts, "grid", false),
        ("visualize", CreateVisualizations, "derived", true)
    ],
    
    raw_moment_names = ["DBZ", "VEL", "WIDTH", "ZDR", "KDP", "PHIDP", "RHOHV"],
    qc_moment_names = ["DBZ", "VEL", "WIDTH", "ZDR", "KDP", "RHOHV"],
    
    # Grid parameters
    grid_nx = 500,
    grid_ny = 500,
    grid_nz = 30,
    grid_dx = 500.0,
    grid_dy = 500.0,
    grid_dz = 250.0,
    
    # Analysis parameters
    calculate_rainfall = true,
    calculate_hydrometeor_id = true,
    
    message_level = 2
)

# Implement each step as needed...
# (Similar to previous examples)
```

## Tips for Writing Workflows

1. **Start Simple**: Begin with a minimal workflow and add complexity incrementally
2. **Test Each Step**: Verify each step works independently before chaining
3. **Use Fixtures**: Create small test datasets for development
4. **Log Liberally**: Use debug/trace messages during development
5. **Handle Errors**: Always wrap risky operations in try-catch blocks
6. **Document Parameters**: Comment what each workflow parameter does
7. **Modularize**: Extract common operations into helper functions
8. **Version Control**: Keep workflow files in git for reproducibility

## See Also

- [Workflow Guide](workflow_guide.md) - Detailed workflow concepts
- [API Reference](api.md) - Function documentation