# Gridding helper functions and workflow steps

function grid_composite(composite_grid_dir,date,radar_volume, qc_moment_dict, grid_type_dict, output_file, start_time,
    long_xmin, long_xincr, long_xdim, long_ymin, long_yincr, long_ydim, beam_inflation, missing_key, valid_key, mean_heading)

    # Grid the composite
    output_file = "$(composite_grid_dir)/$(date)/gridded_composite_" *
        Dates.format(start_time, "YYYYmmdd") *
        "_" * Dates.format(start_time, "HHMM") * ".nc"
    println("Gridding composite $output_file")
    @time Daisho.grid_radar_composite(radar_volume, qc_moment_dict, grid_type_dict, output_file, start_time,
        long_xmin, long_xincr, long_xdim, long_ymin, long_yincr, long_ydim, beam_inflation, missing_key, valid_key, mean_heading)
end

function grid_volume(volume_grid_dir, date, radar_volume, qc_moment_dict, grid_type_dict, output_file, start_time,
    vol_xmin, vol_xincr, vol_xdim, vol_ymin, vol_yincr, vol_ydim, zmin, zincr, zdim, beam_inflation, ppi_power_threshold, missing_key, valid_key, mean_heading)

    # Grid the volume
    output_file = "$(volume_grid_dir)/$(date)/gridded_volume_" *
    Dates.format(start_time, "YYYYmmdd") *
        "_" * Dates.format(start_time, "HHMM") * ".nc"
    println("Gridding volume $output_file")
    @time Daisho.grid_radar_volume(radar_volume, qc_moment_dict, grid_type_dict, output_file, start_time,
        vol_xmin, vol_xincr, vol_xdim, vol_ymin, vol_yincr, vol_ydim, zmin, zincr, zdim, beam_inflation, ppi_power_threshold, missing_key, valid_key, mean_heading)
end

function grid_latlon(latlon_grid_dir, date, radar_volume, qc_moment_dict, grid_type_dict, output_file, start_time,
    lonmin, londim, latmin, latdim, degincr, zmin, zincr, zdim, beam_inflation, ppi_power_threshold, missing_key, valid_key, mean_heading)

    # Grid the volume using lat/lon grid
    output_file = "$(latlon_grid_dir)/$(date)/gridded_latlon_" *
        Dates.format(start_time, "YYYYmmdd") *
            "_" * Dates.format(start_time, "HHMM") * ".nc"
    @time Daisho.grid_radar_latlon_volume(radar_volume, qc_moment_dict, grid_type_dict, output_file, start_time,
        lonmin, londim, latmin, latdim, degincr, zmin, zincr, zdim, beam_inflation, ppi_power_threshold, missing_key, valid_key, mean_heading)
end

function grid_ppi(ppi_grid_dir, date, radar_volume, qc_moment_dict, grid_type_dict, output_file, start_time,
    long_xmin, long_xincr, long_xdim, long_ymin, long_yincr, long_ydim, beam_inflation, ppi_power_threshold, missing_key, valid_key, mean_heading,
    max_ppi_angle = 90.0)

    # Grid the PPIs
    if sweep.fixed_angles[1] <= max_ppi_angle
        output_file = "$(ppi_grid_dir)/$(date)/gridded_ppi_" *
        Dates.format(start_time, "YYYYmmdd") *
        "_" * Dates.format(start_time, "HHMM") *
        "_" * @sprintf("%.1f",sweep.fixed_angles[1]) * ".nc"
        println("Gridding PPI $output_file")
        @time Daisho.grid_radar_ppi(sweep, qc_moment_dict, grid_type_dict, output_file, start_time,
            long_xmin, long_xincr, long_xdim, long_ymin, long_yincr, long_ydim, beam_inflation, ppi_power_threshold, missing_key, valid_key, mean_heading)
    end
end

function grid_qvp(qvp_grid_dir, date, radar_volume, qc_moment_dict, grid_type_dict, output_file, start_time,
    qvp_zmin, qvp_zincr, qvp_zdim, beam_inflation, qvp_power_threshold, missing_key, valid_key,
    min_qvp_angle = 40.0)

    # Grid the QVP
    if sweep.fixed_angles[1] >= min_qvp_angle
        output_file = "$(qvp_grid_dir)/$(date)/gridded_qvp_" *
        Dates.format(start_time, "YYYYmmdd") *
            "_" * Dates.format(start_time, "HHMM") * ".nc"
        println("Gridding QVP $output_file")
        @time Daisho.grid_radar_column(sweep, qc_moment_dict, grid_type_dict, output_file, start_time,
            qvp_zmin, qvp_zincr, qvp_zdim, beam_inflation, qvp_power_threshold, missing_key, valid_key)
    end
end

function grid_rhi(rhi_grid_dir, date, radar_volume,qc_moment_dict, grid_type_dict, output_file, start_time,
    rmin, rincr, rdim, rhi_zmin, rhi_zincr, rhi_zdim, beam_inflation, rhi_power_threshold, missing_key, valid_key)

    # Grid the RHI
    output_file = "$(rhi_grid_dir)/$(date)/gridded_rhi_" *
        Dates.format(start_time, "YYYYmmdd") *
        "_" * Dates.format(start_time, "HHMM") *
        "_" * @sprintf("%.1f",rhi.fixed_angles[1]) * ".nc"
    println("Gridding RHI $output_file")
    @time Daisho.grid_radar_rhi(rhi, qc_moment_dict, grid_type_dict, output_file, start_time,
        rmin, rincr, rdim, rhi_zmin, rhi_zincr, rhi_zdim, beam_inflation, rhi_power_threshold, missing_key, valid_key)
end
