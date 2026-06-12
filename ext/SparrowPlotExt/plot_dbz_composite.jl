"""
    PlotDBZCompositeStep

Plot composite reflectivity with range rings (chaseSpectral colormap).

Reads gridded composite NetCDF via the Daisho Fields API; reflectivity resolves
from the `define_detection` tag and un-scanned blanking from `define_scanned`.

# Configurable parameters (via workflow dict, with defaults)
- `radar_name`, `file_prefix`: title / filename prefix (default: `"Sparrow"`)
- `plot_width`, `plot_height`: axis size in pixels (default: `400`)
- `dbz_levels`/`dbz_colormap`/`dbz_ticks`: contour levels, colormap, colorbar ticks
- `blank_color`, `range_ring_color`: blanking and ring colors (default: `(:gray, 0.5)`)
- `range_ring_radii`/`range_ring_labels`: rings in degrees (default `[1.08, 2.21]` / `["120 km", "245 km"]`)
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PlotDBZCompositeStep},
                       input_dir::String, output_dir::String;
                       start_time::DateTime, stop_time::DateTime,
                       step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    ensure_colorschemes()

    p = get_daisho_params(workflow)
    refl_field    = role_field(p, :define_detection, "Composite plot")
    scanned_field = role_field(p, :define_scanned, "Composite plot")

    radar_name = get_param(workflow, "radar_name", "Sparrow")
    file_prefix = get_param(workflow, "file_prefix", "Sparrow")
    plot_width = get_param(workflow, "plot_width", 400)
    plot_height = get_param(workflow, "plot_height", 400)
    dbz_levels = get_param(workflow, "dbz_levels", range(-4, 60, step=4))
    dbz_colormap = get_param(workflow, "dbz_colormap", :chaseSpectral)
    dbz_ticks = get_param(workflow, "dbz_ticks", 0:10:60)
    blank_color = get_param(workflow, "blank_color", (:gray, 0.5))
    range_ring_color = get_param(workflow, "range_ring_color", (:gray, 0.5))
    range_ring_radii = get_param(workflow, "range_ring_radii", [1.08, 2.21])
    range_ring_labels = get_param(workflow, "range_ring_labels", ["120 km", "245 km"])

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
        dbzmax = masked(g, refl_field, "Composite plot")

        date = Dates.format(start_time, "YYYYmmdd")
        start_str = Dates.format(DateTime(g.start_time[1]), "HHMM")
        stop_str = Dates.format(DateTime(g.stop_time[1]), "HHMM")
        timestr = date * " " * start_str * "-" * stop_str * " UTC"

        fig = Figure()
        ax = CairoMakie.Axis(fig[1,1],
            width=plot_width,
            height=plot_height,
            title = "$(radar_name) $timestr Composite Reflectivity",
            xlabel = "Longitude", ylabel = "Latitude")
        center_lon = lon[x_center, y_center]
        center_lat = lat[x_center, y_center]
        xlims!(ax, lon[1, y_center], lon[xdim, y_center])
        ylims!(ax, lat[x_center, 1], lat[x_center, ydim])

        blanking_cbar = [blank_color]

        # Draw range rings
        for (radius, label) in zip(range_ring_radii, range_ring_labels)
            poly!(fig[1, 1], Circle(Point2f(center_lon, center_lat), radius),
                color= :transparent,
                strokecolor = range_ring_color, strokewidth = 0.5)
            text!(fig[1, 1], Point2f(center_lon, center_lat - radius - 0.02),
                text = label, color = range_ring_color,
                fontsize = :12, align = (:center, :baseline))
        end

        contourf!(ax, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow = blank_color)
        composite = contourf!(ax, lon[:,y_center], lat[x_center,:], dbzmax[:,:], levels = dbz_levels,
            colormap = cmap(dbz_colormap))
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        Colorbar(fig[1,2], composite, ticks = dbz_ticks, label = "dBZ")
        resize_to_layout!(fig)

        outfile = joinpath(out_dir, "$(file_prefix)_composite_$(date)_$(start_str)-$(stop_str).png")
        save(outfile, fig)
    end
end
