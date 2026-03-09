"""
    PlotDBZVelStep

Plot side-by-side reflectivity and velocity panels for PPI scans.

# Configurable parameters (via workflow dict, with defaults)
- `radar_name`: Name in titles (default: `"Sparrow"`)
- `file_prefix`: Output filename prefix (default: `"Sparrow"`)
- `plot_width`, `plot_height`: Axis size in pixels (default: `400`)
- `dbz_levels`: DBZ contour levels (default: `range(-10, 45)`)
- `dbz_colormap`: DBZ colormap (default: `:chaseSpectral`)
- `vel_levels`: Velocity contour levels (default: `range(-32, 32, step=4)`)
- `vel_colormap`: Velocity colormap (default: `:balance`)
- `xdim`, `ydim`: Grid dimensions (default: `251`)
- `marker_lon`, `marker_lat`: Optional scatter marker position (default: `nothing`)
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PlotDBZVelStep},
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
    dbz_levels = get_param(workflow, "dbz_levels", range(-10, 45))
    dbz_colormap = get_param(workflow, "dbz_colormap", :chaseSpectral)
    vel_levels = get_param(workflow, "vel_levels", range(-32, 32, step=4))
    vel_colormap = get_param(workflow, "vel_colormap", :balance)
    xdim = get_param(workflow, "xdim", 251)
    ydim = get_param(workflow, "ydim", 251)
    marker_lon = get_param(workflow, "marker_lon", nothing)
    marker_lat = get_param(workflow, "marker_lat", nothing)

    mkpath(output_dir)
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)

    x_center = Int((xdim-1)/2 + 1)
    y_center = Int((ydim-1)/2 + 1)

    for file in input_files
        x, y, lat, lon, start_t, stop_t, radardata = Daisho.read_gridded_ppi(file, moment_dict)

        sqi = reshape(radardata[moment_dict["SQI"],:], xdim, ydim)
        sqiraster = nomissing(sqi[:,:], -32768.0)
        blanking = ifelse.(sqiraster .> -32768.0, NaN, 0.0)

        dbz = reshape(radardata[moment_dict["DBZ"],:], xdim, ydim)
        dbz = nomissing(dbz[:,:], -32768.0)
        replace!(dbz, -32768.0 => NaN)
        replace!(dbz, -9999.0 => NaN)

        vel = reshape(radardata[moment_dict["VEL"],:], xdim, ydim)
        vel = nomissing(vel[:,:], -32768.0)
        replace!(vel, -32768.0 => NaN)
        replace!(vel, -9999.0 => NaN)

        date = Dates.format(start_time, "YYYYmmdd")
        start_str = Dates.format(DateTime(start_t[1]), "HHMM")
        stop_str = Dates.format(DateTime(stop_t[1]), "HHMM")
        timestr = date * " " * start_str * "-" * stop_str * " UTC"

        elevation = chop(split(file, "_")[end], tail=3)

        # Use chaseSpectral colormap
        dbz_cmap = dbz_colormap == :chaseSpectral ? colorschemes[:chaseSpectral] : dbz_colormap

        fig = Figure()
        ax1 = CairoMakie.Axis(fig[1,1],
            width=plot_width,
            height=plot_height,
            title = "$(radar_name) $timestr Reflectivity at $(elevation)°",
            xlabel = "Longitude", ylabel = "Latitude")
        center_lon = lon[x_center, y_center]
        center_lat = lat[x_center, y_center]
        xlims!(ax1, lon[1, y_center], lon[xdim, y_center])
        ylims!(ax1, lat[x_center, 1], lat[x_center, ydim])

        blanking_cbar = [(:gray, 0.5)]
        contourf!(ax1, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow = (:gray, 0.5))
        composite = contourf!(ax1, lon[:,y_center], lat[x_center,:], dbz[:,:], levels = dbz_levels,
            colormap = dbz_cmap)
        if marker_lon !== nothing && marker_lat !== nothing
            scatter!(ax1, marker_lon, marker_lat, marker=:diamond, markersize = 5, color = :black)
        end
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        Colorbar(fig[1,2], composite, ticks = -10:5:45, label = "dBZ")

        ax2 = CairoMakie.Axis(fig[1,3],
            width=plot_width,
            height=plot_height,
            title = "$(radar_name) $timestr Velocity at $(elevation)°",
            xlabel = "Longitude", ylabel = "Latitude")
        xlims!(ax2, lon[1, y_center], lon[xdim, y_center])
        ylims!(ax2, lat[x_center, 1], lat[x_center, ydim])

        contourf!(ax2, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow = (:gray, 0.5))
        velocity = contourf!(ax2, lon[:,y_center], lat[x_center,:], vel[:,:], levels = vel_levels,
            colormap = vel_colormap)
        if marker_lon !== nothing && marker_lat !== nothing
            scatter!(ax2, marker_lon, marker_lat, marker=:diamond, markersize = 5, color = :black)
        end
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        Colorbar(fig[1,4], velocity, ticks = -32:4:32, label = "Velocity m/s")

        resize_to_layout!(fig)
        outfile = joinpath(output_dir, "$(file_prefix)_PPI_$(date)_$(start_str)-$(stop_str)_$(elevation)_deg.png")
        save(outfile, fig)
    end
end
