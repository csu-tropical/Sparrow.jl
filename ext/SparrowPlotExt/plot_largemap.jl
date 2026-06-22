"""
    PlotLargemapStep

Plot large-scale geographic map of composite reflectivity using GeoAxis.

Reads gridded composite NetCDF via the Daisho Fields API; reflectivity resolves
from the `define_detection` tag and blanking from `define_scanned`.

# Configurable parameters (via workflow dict, with defaults)
- `radar_name`, `file_prefix`: title / filename prefix (default: `"Sparrow"`)
- `plot_width`, `plot_height`: axis size in pixels (default: `400`)
- `dbz_levels`/`dbz_colormap`/`dbz_ticks`: contour levels, colormap, colorbar ticks
- `geo_projection`, `geo_xlims`, `geo_ylims`: map projection and extent
- `blank_color`, `coastline_color`, `background_color`: styling
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PlotLargemapStep},
                       input_dir::String, output_dir::String;
                       start_time::DateTime, stop_time::DateTime,
                       step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    ensure_colorschemes()

    p = get_daisho_params(workflow)
    refl_field    = role_field(p, :define_detection, "Largemap plot")
    scanned_field = role_field(p, :define_scanned, "Largemap plot")

    radar_name = get_param(workflow, "radar_name", "Sparrow")
    file_prefix = get_param(workflow, "file_prefix", "Sparrow")
    plot_width = get_param(workflow, "plot_width", 400)
    plot_height = get_param(workflow, "plot_height", 400)
    dbz_levels = get_param(workflow, "dbz_levels", range(-4, 60, step=4))
    dbz_colormap = get_param(workflow, "dbz_colormap", :chaseSpectral)
    dbz_ticks = get_param(workflow, "dbz_ticks", 0:10:60)
    geo_projection = get_param(workflow, "geo_projection", "+proj=longlat +datum=WGS84")
    geo_xlims = get_param(workflow, "geo_xlims", (-65.0, -15.0))
    geo_ylims = get_param(workflow, "geo_ylims", (0.0, 20.0))
    blank_color = get_param(workflow, "blank_color", (:gray, 0.5))
    coastline_color = get_param(workflow, "coastline_color", :black)
    background_color = get_param(workflow, "background_color", :transparent)

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
        dbzmax = masked(g, refl_field, "Largemap plot")

        date = Dates.format(start_time, "YYYYmmdd")
        start_str = Dates.format(g.start_time[1], "HHMM")
        stop_str = Dates.format(g.stop_time[1], "HHMM")
        timestr = date * " " * start_str * "-" * stop_str * " UTC"

        fig = Figure(backgroundcolor = background_color)
        ax = GeoAxis(fig[1,1],
            width=plot_width,
            height=plot_height,
            dest=geo_projection)
        xlims!(ax, geo_xlims...)
        ylims!(ax, geo_ylims...)

        lines!(ax, GeoMakie.coastlines(), color = coastline_color)

        blanking_cbar = [blank_color]
        safe_contourf!(ax, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow= blank_color)
        composite = safe_contourf!(ax, lon[:,y_center], lat[x_center,:], dbzmax[:,:], levels = dbz_levels,
            colormap = cmap(dbz_colormap))
        Textbox(fig[1, 1], placeholder = "$(radar_name) dBZ $timestr",
            valign = :top, halign = :left, boxcolor= :white, fontsize = :12)
        ax.xticks = [geo_xlims[1], geo_xlims[2]]
        ax.yticks = [geo_ylims[1], geo_ylims[2]]
        hidedecorations!(ax, grid = false)
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        data_colorbar!(fig[1,2], composite; colormap = cmap(dbz_colormap),
            levels = dbz_levels, ticks = dbz_ticks, label = "dBZ")
        resize_to_layout!(fig)

        outfile = joinpath(out_dir, "$(file_prefix)_largemap_$(date)_$(start_str)-$(stop_str).png")
        save(outfile, fig)
    end
end
