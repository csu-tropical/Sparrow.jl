"""
    PlotLargemapStep

Plot large-scale geographic map of composite reflectivity using GeoAxis.

# Configurable parameters (via workflow dict, with defaults)
- `radar_name`: Name in titles (default: `"Sparrow"`)
- `file_prefix`: Output filename prefix (default: `"Sparrow"`)
- `plot_width`: Axis width in pixels (default: `400`)
- `plot_height`: Axis height in pixels (default: `400`)
- `dbz_levels`: DBZ contour levels (default: `range(-4, 60, step=4)`)
- `geo_projection`: Map projection string (default: `"+proj=longlat +datum=WGS84"`)
- `geo_xlims`: Longitude limits tuple (default: `(-65.0, -15.0)`)
- `geo_ylims`: Latitude limits tuple (default: `(0.0, 20.0)`)
- `xdim`: X grid dimension (default: `251`)
- `ydim`: Y grid dimension (default: `251`)
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PlotLargemapStep},
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
    geo_projection = get_param(workflow, "geo_projection", "+proj=longlat +datum=WGS84")
    geo_xlims = get_param(workflow, "geo_xlims", (-65.0, -15.0))
    geo_ylims = get_param(workflow, "geo_ylims", (0.0, 20.0))
    xdim = get_param(workflow, "xdim", 251)
    ydim = get_param(workflow, "ydim", 251)

    mkpath(output_dir)
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)

    for file in input_files
        x, y, lat, lon, start_t, stop_t, radardata = Daisho.read_gridded_ppi(file, moment_dict)

        x_center = Int((xdim-1)/2 + 1)
        y_center = Int((ydim-1)/2 + 1)

        sqi = reshape(radardata[moment_dict["SQI"],:], xdim, ydim)
        sqiraster = nomissing(sqi[:,:], -32768.0)
        blanking = ifelse.(sqiraster .> -32768.0, NaN, 0.0)

        dbz = reshape(radardata[moment_dict["DBZ"],:], xdim, ydim)
        dbzmax = nomissing(dbz[:,:], -32768.0)
        replace!(dbzmax, -32768.0 => NaN)

        date = Dates.format(start_time, "YYYYmmdd")
        start_str = Dates.format(start_t[1], "HHMM")
        stop_str = Dates.format(stop_t[1], "HHMM")
        timestr = date * " " * start_str * "-" * stop_str * " UTC"

        fig = Figure(backgroundcolor = :transparent)
        ax = GeoAxis(fig[1,1],
            width=plot_width,
            height=plot_height,
            dest=geo_projection)
        xlims!(ax, geo_xlims...)
        ylims!(ax, geo_ylims...)

        lines!(ax, GeoMakie.coastlines(), color = :black)

        blanking_cbar = [(:gray, 0.5)]
        contourf!(ax, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow= (:gray, 0.5))
        composite = contourf!(ax, lon[:,y_center], lat[x_center,:], dbzmax[:,:], levels = dbz_levels,
            colormap = colorschemes[:chaseSpectral])
        Textbox(fig[1, 1], placeholder = "$(radar_name) dBZ $timestr",
            valign = :top, halign = :left, boxcolor= :white, fontsize = :12)
        ax.xticks = [geo_xlims[1], geo_xlims[2]]
        ax.yticks = [geo_ylims[1], geo_ylims[2]]
        hidedecorations!(ax, grid = false)
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        Colorbar(fig[1,2], composite, ticks = 0:10:60, label = "dBZ")
        resize_to_layout!(fig)

        outfile = joinpath(output_dir, "$(file_prefix)_largemap_$(date)_$(start_str)-$(stop_str).png")
        save(outfile, fig)
    end
end
