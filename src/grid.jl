# Gridding helper functions and workflow steps
@workflow_step GridRHIStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridRHIStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    println("Executing Step $(step_name) for $(typeof(workflow)) ...")
    qc_moment_dict = workflow["qc_moment_dict"]
    grid_type_dict = workflow["grid_type_dict"]
    rmin = workflow["rmin"]
    rincr = workflow["rincr"]
    rdim = workflow["rdim"]
    rhi_zmin = workflow["rhi_zmin"]
    rhi_zincr = workflow["rhi_zincr"]
    rhi_zdim = workflow["rhi_zdim"]
    beam_inflation = workflow["beam_inflation"]
    rhi_power_threshold = workflow["rhi_power_threshold"]
    missing_key = workflow["missing_key"]
    valid_key = workflow["valid_key"]

    # Grid if within the time limit
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for file in input_files
        if contains(file, "RHI")
            scan_start = get_scan_start(file)
            #println("Checking $file at $(Dates.format(scan_start, "YYYYmmdd HHMM"))")
            if scan_start < start_time || scan_start >= stop_time
                #println("Skipping $file")
                continue
            end
            radar_volume = Daisho.read_cfradial(file, qc_moment_dict)
            rhis = Daisho.split_sweeps(radar_volume)
            for rhi in rhis
                # Grid the RHI
                output_file = output_dir * "/gridded_rhi_" *
                    Dates.format(start_time, "YYYYmmdd_HHMM") *
                    "_" * @sprintf("%.1f",rhi.fixed_angles[1]) * ".nc"
                println("Gridding RHI $output_file")
                flush(stdout)
                @time Daisho.grid_radar_rhi(rhi, qc_moment_dict, grid_type_dict, output_file, start_time,
                    rmin, rincr, rdim, rhi_zmin, rhi_zincr, rhi_zdim, beam_inflation, rhi_power_threshold, missing_key, valid_key)
            end
        end
    end
end

@workflow_step GridCompositeStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridCompositeStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    println("Executing Step $(step_name) for $(typeof(workflow)) ...")
    qc_moment_dict = workflow["qc_moment_dict"]
    grid_type_dict = workflow["grid_type_dict"]
    long_xmin = workflow["long_xmin"]
    long_xincr = workflow["long_xincr"]
    long_xdim = workflow["long_xdim"]
    long_ymin = workflow["long_ymin"]
    long_yincr = workflow["long_yincr"]
    long_ydim = workflow["long_ydim"]
    beam_inflation = workflow["beam_inflation"]
    rhi_power_threshold = workflow["rhi_power_threshold"]
    missing_key = workflow["missing_key"]
    valid_key = workflow["valid_key"]

    # Grid if within the time limit
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for file in input_files
        #println("Checking $file")
        if !contains(file, "RHI")
            scan_start = get_scan_start(file)
            #println("Checking $file at $(Dates.format(scan_start, "YYYYmmdd HHMM"))")
            if scan_start < start_time || scan_start >= stop_time
                #println("Skipping $file")
                continue
            end
            radar_volume = Daisho.read_cfradial(file, qc_moment_dict)
            radar_orientation = Daisho.get_radar_orientation(file)
            # Just use the heading for now
            mean_heading = mean(radar_orientation[:,1])
            # Grid the composite
            output_file = output_dir * "/gridded_composite_" *
                Dates.format(start_time, "YYYYmmdd") *
                "_" * Dates.format(start_time, "HHMM") * ".nc"
            println("Gridding composite $output_file")
            flush(stdout)
            @time Daisho.grid_radar_composite(radar_volume, qc_moment_dict, grid_type_dict, output_file, start_time,
                long_xmin, long_xincr, long_xdim, long_ymin, long_yincr, long_ydim, beam_inflation, missing_key, valid_key, mean_heading)
        end
    end
end

@workflow_step GridVolumeStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridVolumeStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    println("Executing Step $(step_name) for $(typeof(workflow)) ...")
    qc_moment_dict = workflow["qc_moment_dict"]
    grid_type_dict = workflow["grid_type_dict"]
    vol_xmin = workflow["vol_xmin"]
    vol_xincr = workflow["vol_xincr"]
    vol_xdim = workflow["vol_xdim"]
    vol_ymin = workflow["vol_ymin"]
    vol_yincr = workflow["vol_yincr"]
    vol_ydim = workflow["vol_ydim"]
    zmin = workflow["zmin"]
    zincr = workflow["zincr"]
    zdim = workflow["zdim"]

    beam_inflation = workflow["beam_inflation"]
    ppi_power_threshold = workflow["ppi_power_threshold"]
    missing_key = workflow["missing_key"]
    valid_key = workflow["valid_key"]

    # Grid if within the time limit
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for file in input_files
        if !contains(file, "RHI")
            scan_start = get_scan_start(file)
            #println("Checking $file at $(Dates.format(scan_start, "YYYYmmdd HHMM"))")
            if scan_start < start_time || scan_start >= stop_time
                #println("Skipping $file")
                continue
            end
            radar_volume = Daisho.read_cfradial(file, qc_moment_dict)
            radar_orientation = Daisho.get_radar_orientation(file)
            # Just use the heading for now
            mean_heading = mean(radar_orientation[:,1])
            # Grid the composite
            output_file = output_dir * "/gridded_volume_" *
                Dates.format(start_time, "YYYYmmdd") *
                "_" * Dates.format(start_time, "HHMM") * ".nc"
            println("Gridding volume $output_file")
            flush(stdout)
            @time Daisho.grid_radar_volume(radar_volume, qc_moment_dict, grid_type_dict, output_file, start_time,
                vol_xmin, vol_xincr, vol_xdim, vol_ymin, vol_yincr, vol_ydim, zmin, zincr, zdim, beam_inflation, ppi_power_threshold, missing_key, valid_key, mean_heading)
        end
    end
end

@workflow_step GridLatlonStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridLatlonStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    println("Executing Step $(step_name) for $(typeof(workflow)) ...")
    qc_moment_dict = workflow["qc_moment_dict"]
    grid_type_dict = workflow["grid_type_dict"]
    latmin = workflow["latmin"]
    latdim = workflow["latdim"]
    lonmin = workflow["lonmin"]
    londim = workflow["londim"]
    degincr = workflow["degincr"]
    zmin = workflow["zmin"]
    zincr = workflow["zincr"]
    zdim = workflow["zdim"]
    beam_inflation = workflow["beam_inflation"]
    ppi_power_threshold = workflow["ppi_power_threshold"]
    missing_key = workflow["missing_key"]
    valid_key = workflow["valid_key"]

    # Grid if within the time limit
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for file in input_files
        if !contains(file, "RHI")
            scan_start = get_scan_start(file)
            #println("Checking $file at $(Dates.format(scan_start, "YYYYmmdd HHMM"))")
            if scan_start < start_time || scan_start >= stop_time
                #println("Skipping $file")
                continue
            end
            radar_volume = Daisho.read_cfradial(file, qc_moment_dict)
            radar_orientation = Daisho.get_radar_orientation(file)
            # Just use the heading for now
            mean_heading = mean(radar_orientation[:,1])
            # Grid the composite
            output_file = output_dir * "/gridded_latlon_" *
                Dates.format(start_time, "YYYYmmdd") *
                "_" * Dates.format(start_time, "HHMM") * ".nc"
            println("Gridding volume $output_file")
            flush(stdout)
            @time Daisho.grid_radar_latlon_volume(radar_volume, qc_moment_dict, grid_type_dict, output_file, start_time,
                lonmin, londim, latmin, latdim, degincr, zmin, zincr, zdim, beam_inflation, ppi_power_threshold, missing_key, valid_key, mean_heading)
        end
    end
end

@workflow_step GridPPIStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridPPIStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    println("Executing Step $(step_name) for $(typeof(workflow)) ...")
    qc_moment_dict = workflow["qc_moment_dict"]
    grid_type_dict = workflow["grid_type_dict"]
    long_xmin = workflow["long_xmin"]
    long_xincr = workflow["long_xincr"]
    long_xdim = workflow["long_xdim"]
    long_ymin = workflow["long_ymin"]
    long_yincr = workflow["long_yincr"]
    long_ydim = workflow["long_ydim"]
    beam_inflation = workflow["beam_inflation"]
    ppi_power_threshold = workflow["ppi_power_threshold"]
    max_ppi_angle = workflow["max_ppi_angle"]
    missing_key = workflow["missing_key"]
    valid_key = workflow["valid_key"]

    # Grid if within the time limit
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for file in input_files
        if !contains(file, "RHI")
            scan_start = get_scan_start(file)
            #println("Checking $file at $(Dates.format(scan_start, "YYYYmmdd HHMM"))")
            if scan_start < start_time || scan_start >= stop_time
                #println("Skipping $file")
                continue
            end
            radar_volume = Daisho.read_cfradial(file, qc_moment_dict)
            radar_orientation = Daisho.get_radar_orientation(file)
            # Just use the heading for now
            mean_heading = mean(radar_orientation[:,1])
            # Grid the PPIs
            sweeps = Daisho.split_sweeps(radar_volume)
            for sweep in sweeps
                if sweep.fixed_angles[1] <= max_ppi_angle
                    output_file = output_dir * "/gridded_ppi_" *
                        Dates.format(start_time, "YYYYmmdd") *
                        "_" * Dates.format(start_time, "HHMM") *
                        "_" * @sprintf("%.1f",sweep.fixed_angles[1]) * ".nc"
                    println("Gridding PPI $output_file")
                    @time Daisho.grid_radar_ppi(sweep, qc_moment_dict, grid_type_dict, output_file, start_time,
                        long_xmin, long_xincr, long_xdim, long_ymin, long_yincr, long_ydim, beam_inflation, ppi_power_threshold, missing_key, valid_key, mean_heading)
                end
            end
        end
    end
end

@workflow_step GridQVPStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridQVPStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    println("Executing Step $(step_name) for $(typeof(workflow)) ...")
    qc_moment_dict = workflow["qc_moment_dict"]
    grid_type_dict = workflow["grid_type_dict"]
    qvp_zmin = workflow["zmin"]
    qvp_zincr = workflow["zincr"]
    qvp_zdim = workflow["zdim"]
    beam_inflation = workflow["beam_inflation"]
    qvp_power_threshold = workflow["qvp_power_threshold"]
    min_qvp_angle = workflow["min_qvp_angle"]
    missing_key = workflow["missing_key"]
    valid_key = workflow["valid_key"]

    # Grid if within the time limit
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for file in input_files
        if !contains(file, "RHI")
            scan_start = get_scan_start(file)
            #println("Checking $file at $(Dates.format(scan_start, "YYYYmmdd HHMM"))")
            if scan_start < start_time || scan_start >= stop_time
                #println("Skipping $file")
                continue
            end
            radar_volume = Daisho.read_cfradial(file, qc_moment_dict)
            radar_orientation = Daisho.get_radar_orientation(file)
            # Just use the heading for now
            mean_heading = mean(radar_orientation[:,1])
            # Grid the PPIs
            sweeps = Daisho.split_sweeps(radar_volume)
            for sweep in sweeps
                if sweep.fixed_angles[1] >= min_qvp_angle
                    output_file = "$(ppi_grid_dir)/$(date)/gridded_ppi_" *
                    Dates.format(start_time, "YYYYmmdd") *
                    "_" * Dates.format(start_time, "HHMM") *
                    "_" * @sprintf("%.1f",sweep.fixed_angles[1]) * ".nc"
                    println("Gridding PPI $output_file")
                    @time Daisho.grid_radar_column(sweep, qc_moment_dict, grid_type_dict, output_file, start_time,
                        long_xmin, long_xincr, long_xdim, long_ymin, long_yincr, long_ydim, beam_inflation, qvp_power_threshold, missing_key, valid_key)
                end
            end
        end
    end
end
