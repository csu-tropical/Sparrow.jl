"""
    PlotDBZCompositeStep

Plot composite reflectivity with range rings.

# Configurable parameters (via workflow dict, with defaults)
- `radar_name`: Name in titles (default: `"Sparrow"`)
- `file_prefix`: Output filename prefix (default: `"Sparrow"`)
- `plot_width`, `plot_height`: Axis size in pixels (default: `400`)
- `dbz_levels`: DBZ contour levels (default: `range(-4, 60, step=4)`)
- `long_xdim`, `long_ydim`: Long-range grid dimensions (default: `251`)
- `range_ring_radii`: Range ring radii in degrees (default: `[1.08, 2.21]`)
- `range_ring_labels`: Labels for range rings (default: `["120 km", "245 km"]`)
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PlotDBZCompositeStep},
                       input_dir::String, output_dir::String;
                       start_time::DateTime, stop_time::DateTime,
                       step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    ensure_colorschemes()

    moment_dict = workflow["qc_moment_dict"]
    missing_key = get_param(workflow, "missing_key", "SQI")
    radar_name = get_param(workflow, "radar_name", "Sparrow")
    file_prefix = get_param(workflow, "file_prefix", "Sparrow")
    plot_width = get_param(workflow, "plot_width", 400)
    plot_height = get_param(workflow, "plot_height", 400)
    dbz_levels = get_param(workflow, "dbz_levels", range(-4, 60, step=4))
    long_xdim = get_param(workflow, "long_xdim", 251)
    long_ydim = get_param(workflow, "long_ydim", 251)
    range_ring_radii = get_param(workflow, "range_ring_radii", [1.08, 2.21])
    range_ring_labels = get_param(workflow, "range_ring_labels", ["120 km", "245 km"])

    mkpath(output_dir)
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)

    for file in input_files
        x, y, lat, lon, start_t, stop_t, radardata = Daisho.read_gridded_ppi(file, moment_dict)

        x_center = Int((long_xdim-1)/2 + 1)
        y_center = Int((long_ydim-1)/2 + 1)

        mask_field = reshape(radardata[moment_dict[missing_key],:], long_xdim, long_ydim)
        mask_raster = nomissing(mask_field[:,:], -32768.0)
        blanking = ifelse.(mask_raster .> -32768.0, NaN, 0.0)

        dbz = reshape(radardata[moment_dict["DBZ"],:], long_xdim, long_ydim)
        dbzmax = nomissing(dbz[:,:], -32768.0)
        replace!(dbzmax, -32768.0 => NaN)

        date = Dates.format(start_time, "YYYYmmdd")
        start_str = Dates.format(DateTime(start_t[1]), "HHMM")
        stop_str = Dates.format(DateTime(stop_t[1]), "HHMM")
        timestr = date * " " * start_str * "-" * stop_str * " UTC"

        fig = Figure()
        ax = CairoMakie.Axis(fig[1,1],
            width=plot_width,
            height=plot_height,
            title = "$(radar_name) $timestr Composite Reflectivity",
            xlabel = "Longitude", ylabel = "Latitude")
        center_lon = lon[x_center, y_center]
        center_lat = lat[x_center, y_center]
        xlims!(ax, lon[1, y_center], lon[long_xdim, y_center])
        ylims!(ax, lat[x_center, 1], lat[x_center, long_ydim])

        blanking_cbar = [(:gray, 0.5)]

        # Draw range rings
        for (radius, label) in zip(range_ring_radii, range_ring_labels)
            poly!(fig[1, 1], Circle(Point2f(center_lon, center_lat), radius),
                color= :transparent,
                strokecolor = (:gray, 0.5), strokewidth = 0.5)
            text!(fig[1, 1], Point2f(center_lon, center_lat - radius - 0.02),
                text = label, color = (:gray, 0.5),
                fontsize = :12, align = (:center, :baseline))
        end

        contourf!(ax, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow = (:gray, 0.5))
        composite = contourf!(ax, lon[:,y_center], lat[x_center,:], dbzmax[:,:], levels = dbz_levels,
            colormap = colorschemes[:chaseSpectral])
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        Colorbar(fig[1,2], composite, ticks = 0:10:60, label = "dBZ")
        resize_to_layout!(fig)

        outfile = joinpath(output_dir, "$(file_prefix)_composite_$(date)_$(start_str)-$(stop_str).png")
        save(outfile, fig)
    end
end
