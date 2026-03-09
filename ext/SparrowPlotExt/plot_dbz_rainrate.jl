"""
    PlotDBZRainrateStep

Plot side-by-side reflectivity and rain rate panels for PPI scans.

# Configurable parameters (via workflow dict, with defaults)
- `radar_name`: Name in titles (default: `"Sparrow"`)
- `file_prefix`: Output filename prefix (default: `"Sparrow"`)
- `plot_width`, `plot_height`: Axis size in pixels (default: `400`)
- `dbz_levels`: DBZ contour levels (default: `range(-4, 60, step=4)`)
- `long_xdim`, `long_ydim`: Long-range dims for DBZ panel (default: `251`)
- `xdim`, `ydim`: Dims for rain rate panel (default: `251`)
- `rainrate_levels`: Rain rate contour levels (default: `range(0, 150, step=10)`)
- `rainrate_colormap`: Rain rate colormap (default: `:Paired_6`)
- `rainrate_moment`: Moment name for rain rate (default: `"RATE_CSU_BLENDED"`)
- `marker_lon`, `marker_lat`: Optional scatter marker position (default: `nothing`)
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PlotDBZRainrateStep},
                       input_dir::String, output_dir::String;
                       start_time::DateTime, stop_time::DateTime,
                       step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    ensure_colorschemes()

    moment_dict = workflow["qc_moment_dict"]
    radar_name = get_param(workflow, "radar_name", "Sparrow")
    file_prefix = get_param(workflow, "file_prefix", "Sparrow")
    plot_width = get_param(workflow, "plot_width", 400)
    plot_height = get_param(workflow, "plot_height", 400)
    dbz_levels = get_param(workflow, "dbz_levels", range(-4, 60, step=4))
    long_xdim = get_param(workflow, "long_xdim", 251)
    long_ydim = get_param(workflow, "long_ydim", 251)
    xdim = get_param(workflow, "xdim", 251)
    ydim = get_param(workflow, "ydim", 251)
    rainrate_levels = get_param(workflow, "rainrate_levels", range(0, 150, step=10))
    rainrate_colormap = get_param(workflow, "rainrate_colormap", :Paired_6)
    rainrate_moment = get_param(workflow, "rainrate_moment", "RATE_CSU_BLENDED")
    marker_lon = get_param(workflow, "marker_lon", nothing)
    marker_lat = get_param(workflow, "marker_lat", nothing)

    mkpath(output_dir)
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)

    for file in input_files
        x, y, lat, lon, start_t, stop_t, radardata = Daisho.read_gridded_ppi(file, moment_dict)

        x_center_long = Int((long_xdim-1)/2 + 1)
        y_center_long = Int((long_ydim-1)/2 + 1)
        x_center = Int((xdim-1)/2 + 1)
        y_center = Int((ydim-1)/2 + 1)

        sqi = reshape(radardata[moment_dict["SQI"],:], long_xdim, long_ydim)
        sqiraster = nomissing(sqi[:,:], -32768.0)
        blanking = ifelse.(sqiraster .> -32768.0, NaN, 0.0)

        dbz = reshape(radardata[moment_dict["DBZ"],:], long_xdim, long_ydim)
        dbz = nomissing(dbz[:,:], -32768.0)
        replace!(dbz, -32768.0 => NaN)
        replace!(dbz, -9999.0 => NaN)

        rr = reshape(radardata[moment_dict[rainrate_moment],:], long_xdim, long_ydim)
        rr = nomissing(rr[:,:], -32768.0)
        replace!(rr, -32768.0 => NaN)
        replace!(rr, -9999.0 => NaN)

        date = Dates.format(start_time, "YYYYmmdd")
        start_str = Dates.format(DateTime(start_t[1]), "HHMM")
        stop_str = Dates.format(DateTime(stop_t[1]), "HHMM")
        timestr = date * " " * start_str * "-" * stop_str * " UTC"

        elevation = chop(split(file, "_")[end], tail=3)

        fig = Figure()
        ax1 = CairoMakie.Axis(fig[1,1],
            width=plot_width,
            height=plot_height,
            title = "$(radar_name) $timestr Reflectivity at $(elevation)°",
            xlabel = "Longitude", ylabel = "Latitude")
        center_lon = lon[x_center_long, y_center_long]
        center_lat = lat[x_center_long, y_center_long]
        xlims!(ax1, lon[1, y_center_long], lon[long_xdim, y_center_long])
        ylims!(ax1, lat[x_center_long, 1], lat[x_center_long, long_ydim])

        blanking_cbar = [(:gray, 0.5)]
        contourf!(ax1, lon[:,y_center_long], lat[x_center_long,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow = (:gray, 0.5))
        composite = contourf!(ax1, lon[:,y_center_long], lat[x_center_long,:], dbz[:,:], levels = dbz_levels,
            colormap = colorschemes[:chaseSpectral])
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        Colorbar(fig[1,2], composite, ticks = 0:10:60, label = "dBZ")

        ax2 = CairoMakie.Axis(fig[1,3],
            width=plot_width,
            height=plot_height,
            title = "$(radar_name) $timestr Rain rate at $(elevation)°",
            xlabel = "Longitude", ylabel = "Latitude")
        xlims!(ax2, lon[1, y_center], lon[xdim, y_center])
        ylims!(ax2, lat[x_center, 1], lat[x_center, ydim])

        contourf!(ax2, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow = (:gray, 0.5))
        rainrate = contourf!(ax2, lon[:,y_center], lat[x_center,:], rr[:,:], levels = rainrate_levels,
            colormap = rainrate_colormap)
        if marker_lon !== nothing && marker_lat !== nothing
            scatter!(ax2, marker_lon, marker_lat, marker=:diamond, markersize = 5, color = :black)
        end
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        Colorbar(fig[1,4], rainrate, ticks = 0:10:150, label = "Rain rate mm/hr")

        resize_to_layout!(fig)
        outfile = joinpath(output_dir, "$(file_prefix)_PPI_$(date)_$(start_str)-$(stop_str)_$(elevation)_deg.png")
        save(outfile, fig)
    end
end
