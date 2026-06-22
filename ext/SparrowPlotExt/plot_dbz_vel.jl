"""
    PlotDBZVelStep

Plot side-by-side reflectivity and velocity panels for PPI scans.

Reads gridded PPI NetCDF via the Daisho Fields API; reflectivity/velocity are
resolved from the `define_detection`/`velocity` tags and the un-scanned blanking
from the `define_scanned` tag.

# Configurable parameters (via workflow dict, with defaults)
- `radar_name`, `file_prefix`: title / filename prefix (default: `"Sparrow"`)
- `plot_width`, `plot_height`: axis size in pixels (default: `400`)
- `dbz_levels`/`dbz_colormap`/`dbz_ticks`, `vel_levels`/`vel_colormap`/`vel_ticks`
- `blank_color`: color for un-scanned regions (default: `(:gray, 0.5)`)
- `marker_lon`, `marker_lat`: optional scatter marker position (default: `nothing`)
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PlotDBZVelStep},
                       input_dir::String, output_dir::String;
                       start_time::DateTime, stop_time::DateTime,
                       step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    ensure_colorschemes()

    p = get_daisho_params(workflow)
    refl_field    = role_field(p, :define_detection, "PPI DBZ/Vel plot")
    vel_field     = role_field(p, :velocity, "PPI DBZ/Vel plot")
    scanned_field = role_field(p, :define_scanned, "PPI DBZ/Vel plot")

    radar_name = get_param(workflow, "radar_name", "Sparrow")
    file_prefix = get_param(workflow, "file_prefix", "Sparrow")
    plot_width = get_param(workflow, "plot_width", 400)
    plot_height = get_param(workflow, "plot_height", 400)
    dbz_levels = get_param(workflow, "dbz_levels", range(-10, 45))
    dbz_colormap = get_param(workflow, "dbz_colormap", :chaseSpectral)
    dbz_ticks = get_param(workflow, "dbz_ticks", -10:5:45)
    vel_levels = get_param(workflow, "vel_levels", range(-32, 32, step=4))
    vel_colormap = get_param(workflow, "vel_colormap", :balance)
    vel_ticks = get_param(workflow, "vel_ticks", -32:4:32)
    blank_color = get_param(workflow, "blank_color", (:gray, 0.5))
    marker_lon = get_param(workflow, "marker_lon", nothing)
    marker_lat = get_param(workflow, "marker_lat", nothing)

    out_dir = plot_output_dir(workflow, step_name, start_time, output_dir)
    mkpath(out_dir)
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)

    for file in input_files
        g = Daisho.read_gridded_ppi(file, p)
        xdim = length(g.X); ydim = length(g.Y)
        lon = g.longitude; lat = g.latitude
        x_center = Int((xdim-1)/2 + 1)
        y_center = Int((ydim-1)/2 + 1)

        blanking = scanned_blanking(g, scanned_field)
        dbz = masked(g, refl_field, "PPI DBZ/Vel plot")
        vel = masked(g, vel_field, "PPI DBZ/Vel plot")

        date = Dates.format(start_time, "YYYYmmdd")
        start_str = Dates.format(DateTime(g.start_time[1]), "HHMM")
        stop_str = Dates.format(DateTime(g.stop_time[1]), "HHMM")
        timestr = date * " " * start_str * "-" * stop_str * " UTC"

        elevation = chop(split(file, "_")[end], tail=3)

        blanking_cbar = [blank_color]
        fig = Figure()
        ax1 = CairoMakie.Axis(fig[1,1],
            width=plot_width,
            height=plot_height,
            title = "$(radar_name) $timestr Reflectivity at $(elevation)°",
            xlabel = "Longitude", ylabel = "Latitude")
        xlims!(ax1, lon[1, y_center], lon[xdim, y_center])
        ylims!(ax1, lat[x_center, 1], lat[x_center, ydim])

        safe_contourf!(ax1, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow = blank_color)
        composite = safe_contourf!(ax1, lon[:,y_center], lat[x_center,:], dbz[:,:], levels = dbz_levels,
            colormap = cmap(dbz_colormap))
        if marker_lon !== nothing && marker_lat !== nothing
            scatter!(ax1, marker_lon, marker_lat, marker=:diamond, markersize = 5, color = :black)
        end
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        data_colorbar!(fig[1,2], composite; colormap = cmap(dbz_colormap),
            levels = dbz_levels, ticks = dbz_ticks, label = "dBZ")

        ax2 = CairoMakie.Axis(fig[1,3],
            width=plot_width,
            height=plot_height,
            title = "$(radar_name) $timestr Velocity at $(elevation)°",
            xlabel = "Longitude", ylabel = "Latitude")
        xlims!(ax2, lon[1, y_center], lon[xdim, y_center])
        ylims!(ax2, lat[x_center, 1], lat[x_center, ydim])

        safe_contourf!(ax2, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow = blank_color)
        velocity = safe_contourf!(ax2, lon[:,y_center], lat[x_center,:], vel[:,:], levels = vel_levels,
            colormap = cmap(vel_colormap))
        if marker_lon !== nothing && marker_lat !== nothing
            scatter!(ax2, marker_lon, marker_lat, marker=:diamond, markersize = 5, color = :black)
        end
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        data_colorbar!(fig[1,4], velocity; colormap = cmap(vel_colormap),
            levels = vel_levels, ticks = vel_ticks, label = "Velocity m/s")

        resize_to_layout!(fig)
        outfile = joinpath(out_dir, "$(file_prefix)_PPI_$(date)_$(start_str)-$(stop_str)_$(elevation)_deg.png")
        save(outfile, fig)
    end
end
