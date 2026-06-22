"""
    PlotPPIVolStep

Plot multi-panel PPI volume scan with all elevation angles in a single figure.

Reads gridded PPI NetCDF via the Daisho Fields API; reflectivity resolves from
the `define_detection` tag and blanking from `define_scanned`.

# Configurable parameters (via workflow dict, with defaults)
- `radar_name`, `file_prefix`: title / filename prefix (default: `"Sparrow"`)
- `plot_width`, `plot_height`: axis size in pixels (default: `400`)
- `dbz_levels`/`dbz_colormap`/`dbz_ticks`: contour levels, colormap, colorbar ticks
- `ppi_vol_columns`: number of layout columns (default: `3`)
- `blank_color`: color for un-scanned regions (default: `(:gray, 0.5)`)
- `marker_lon`, `marker_lat`: optional scatter marker position (default: `nothing`)
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PlotPPIVolStep},
                       input_dir::String, output_dir::String;
                       start_time::DateTime, stop_time::DateTime,
                       step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    ensure_colorschemes()

    p = get_daisho_params(workflow)
    refl_field    = role_field(p, :define_detection, "PPI volume plot")
    scanned_field = role_field(p, :define_scanned, "PPI volume plot")

    radar_name = get_param(workflow, "radar_name", "Sparrow")
    file_prefix = get_param(workflow, "file_prefix", "Sparrow")
    plot_width = get_param(workflow, "plot_width", 400)
    plot_height = get_param(workflow, "plot_height", 400)
    dbz_levels = get_param(workflow, "dbz_levels", range(-10, 45))
    dbz_colormap = get_param(workflow, "dbz_colormap", :chaseSpectral)
    dbz_ticks = get_param(workflow, "dbz_ticks", -10:5:45)
    ppi_vol_columns = get_param(workflow, "ppi_vol_columns", 3)
    blank_color = get_param(workflow, "blank_color", (:gray, 0.5))
    marker_lon = get_param(workflow, "marker_lon", nothing)
    marker_lat = get_param(workflow, "marker_lat", nothing)

    out_dir = plot_output_dir(workflow, step_name, start_time, output_dir)
    mkpath(out_dir)
    files = readdir(input_dir; join=true)
    filter!(!isdir, files)

    if isempty(files)
        msg_info("No files found in $(input_dir), skipping PlotPPIVolStep")
        return
    end

    date = Dates.format(start_time, "YYYYmmdd")
    blanking_cbar = [blank_color]
    num_columns = length(files) > 2 ? ppi_vol_columns : 2

    fig = Figure()
    ax = Array{CairoMakie.Axis}(undef, length(files))

    row = 1
    col = 0
    for f in 1:length(files)
        g = Daisho.read_gridded_ppi(files[f], p)
        xdim = length(g.X); ydim = length(g.Y)
        lon = g.longitude; lat = g.latitude
        x_center = Int((xdim-1)/2 + 1)
        y_center = Int((ydim-1)/2 + 1)

        blanking = scanned_blanking(g, scanned_field)
        dbz = masked(g, refl_field, "PPI volume plot")

        start_str = Dates.format(DateTime(g.start_time[1]), "HHMM")
        stop_str = Dates.format(DateTime(g.stop_time[1]), "HHMM")
        timestr = date * " " * start_str * "-" * stop_str * " UTC"

        elevation = chop(split(files[f], "_")[end], tail=3)

        col = col + 1
        if col > num_columns
            col = 1
            row = row + 1
        end

        ax[f] = CairoMakie.Axis(fig[row, col],
            width=plot_width,
            height=plot_height,
            title = "$(radar_name) $timestr Reflectivity at $(elevation)°",
            xlabel = "Longitude", ylabel = "Latitude")

        xlims!(ax[f], lon[1, y_center], lon[xdim, y_center])
        ylims!(ax[f], lat[x_center, 1], lat[x_center, ydim])

        safe_contourf!(ax[f], lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow = blank_color)
        composite = safe_contourf!(ax[f], lon[:,y_center], lat[x_center,:], dbz[:,:], levels = dbz_levels,
            colormap = cmap(dbz_colormap))
        if marker_lon !== nothing && marker_lat !== nothing
            scatter!(ax[f], marker_lon, marker_lat, marker=:diamond, markersize = 5, color = :black)
        end
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        if col == num_columns || f == length(files)
            data_colorbar!(fig[row, num_columns + 1], composite; colormap = cmap(dbz_colormap),
                levels = dbz_levels, ticks = dbz_ticks, label = "dBZ")
        end
    end

    resize_to_layout!(fig)

    # Get volume start/stop times from first and last files
    g_first = Daisho.read_gridded_ppi(files[1], p)
    g_last = Daisho.read_gridded_ppi(files[end], p)
    start_str = Dates.format(DateTime(g_first.start_time[1]), "HHMM")
    stop_str = Dates.format(DateTime(g_last.stop_time[1]), "HHMM")

    outfile = joinpath(out_dir, "$(file_prefix)_VOL_$(date)_$(start_str)-$(stop_str).png")
    save(outfile, fig)
end
