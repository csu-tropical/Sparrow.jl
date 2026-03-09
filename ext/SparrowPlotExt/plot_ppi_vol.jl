"""
    PlotPPIVolStep

Plot multi-panel PPI volume scan with all elevation angles in a single figure.

# Configurable parameters (via workflow dict, with defaults)
- `radar_name`: Name in titles (default: `"Sparrow"`)
- `file_prefix`: Output filename prefix (default: `"Sparrow"`)
- `plot_width`, `plot_height`: Axis size in pixels (default: `400`)
- `dbz_levels`: DBZ contour levels (default: `range(-10, 45)`)
- `dbz_colormap`: DBZ colormap (default: `:chaseSpectral`)
- `xdim`, `ydim`: Grid dimensions (default: `251`)
- `ppi_vol_columns`: Number of layout columns (default: `3`)
- `marker_lon`, `marker_lat`: Optional scatter marker position (default: `nothing`)
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PlotPPIVolStep},
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
    xdim = get_param(workflow, "xdim", 251)
    ydim = get_param(workflow, "ydim", 251)
    ppi_vol_columns = get_param(workflow, "ppi_vol_columns", 3)
    marker_lon = get_param(workflow, "marker_lon", nothing)
    marker_lat = get_param(workflow, "marker_lat", nothing)

    mkpath(output_dir)
    files = readdir(input_dir; join=true)
    filter!(!isdir, files)

    if isempty(files)
        msg_info("No files found in $(input_dir), skipping PlotPPIVolStep")
        return
    end

    date = Dates.format(start_time, "YYYYmmdd")
    x_center = Int((xdim-1)/2 + 1)
    y_center = Int((ydim-1)/2 + 1)

    # Use chaseSpectral colormap
    dbz_cmap = dbz_colormap == :chaseSpectral ? colorschemes[:chaseSpectral] : dbz_colormap
    num_columns = length(files) > 2 ? ppi_vol_columns : 2

    fig = Figure()
    ax = Array{CairoMakie.Axis}(undef, length(files))

    row = 1
    col = 0
    for f in 1:length(files)
        x, y, lat, lon, start_t, stop_t, radardata = Daisho.read_gridded_ppi(files[f], moment_dict)

        sqi = reshape(radardata[moment_dict["SQI"],:], xdim, ydim)
        sqiraster = nomissing(sqi[:,:], -32768.0)
        blanking = ifelse.(sqiraster .> -32768.0, NaN, 0.0)

        dbz = reshape(radardata[moment_dict["DBZ"],:], xdim, ydim)
        dbz = nomissing(dbz[:,:], -32768.0)
        replace!(dbz, -32768.0 => NaN)
        replace!(dbz, -9999.0 => NaN)

        start_str = Dates.format(DateTime(start_t[1]), "HHMM")
        stop_str = Dates.format(DateTime(stop_t[1]), "HHMM")
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

        center_lon = lon[x_center, y_center]
        center_lat = lat[x_center, y_center]
        xlims!(ax[f], lon[1, y_center], lon[xdim, y_center])
        ylims!(ax[f], lat[x_center, 1], lat[x_center, ydim])

        blanking_cbar = [(:gray, 0.5)]
        contourf!(ax[f], lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow = (:gray, 0.5))
        composite = contourf!(ax[f], lon[:,y_center], lat[x_center,:], dbz[:,:], levels = dbz_levels,
            colormap = dbz_cmap)
        if marker_lon !== nothing && marker_lat !== nothing
            scatter!(ax[f], marker_lon, marker_lat, marker=:diamond, markersize = 5, color = :black)
        end
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        if col == num_columns || f == length(files)
            Colorbar(fig[row, num_columns + 1], composite, ticks = -10:5:45, label = "dBZ")
        end
    end

    resize_to_layout!(fig)

    # Get volume start/stop times from first and last files
    x, y, lat, lon, start_vol, stop_t, radardata = Daisho.read_gridded_ppi(files[1], moment_dict)
    x, y, lat, lon, start_t, stop_vol, radardata = Daisho.read_gridded_ppi(files[end], moment_dict)
    start_str = Dates.format(DateTime(start_vol[1]), "HHMM")
    stop_str = Dates.format(DateTime(stop_vol[1]), "HHMM")

    outfile = joinpath(output_dir, "$(file_prefix)_VOL_$(date)_$(start_str)-$(stop_str).png")
    save(outfile, fig)
end
