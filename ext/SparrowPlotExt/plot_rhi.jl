"""
    PlotRHIStep

Plot 6-panel RHI display: reflectivity, velocity, ZDR, RhoHV, KDP, PhiDP.

Reads gridded RHI NetCDF via the Daisho Fields API. The reflectivity and
velocity panels resolve their field from the Daisho config tags
(`define_detection`, `velocity`); the remaining dual-pol fields default to
conventional names and are overridable.

# Configurable parameters (via workflow dict, with defaults)
- `radar_name`, `file_prefix`: title / filename prefix (default: `"Sparrow"`)
- `zdr_field`/`kdp_field`/`phidp_field`/`rhohv_field`: field names for the
  non-role panels (defaults `"ZDR"`/`"KDP"`/`"PHIDP"`/`"RHOHV"`)
- `rhi_plot_size`, `rhi_aspect`, `rhi_range_max`, `rhi_height_max`: figure geometry
- `*_levels`, `*_colormap`, `*_ticks`: per-panel contour levels, colormaps, and
  colorbar ticks (defaults preserve the prior appearance)
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PlotRHIStep},
                       input_dir::String, output_dir::String;
                       start_time::DateTime, stop_time::DateTime,
                       step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    ensure_colorschemes()

    p = get_daisho_params(workflow)
    refl_field  = role_field(p, :define_detection, "RHI plot")
    vel_field   = role_field(p, :velocity, "RHI plot")
    zdr_field   = get_param(workflow, "zdr_field", "ZDR")
    kdp_field   = get_param(workflow, "kdp_field", "KDP")
    phidp_field = get_param(workflow, "phidp_field", "PHIDP")
    rhohv_field = get_param(workflow, "rhohv_field", "RHOHV")

    radar_name = get_param(workflow, "radar_name", "Sparrow")
    file_prefix = get_param(workflow, "file_prefix", "Sparrow")
    rhi_plot_size = get_param(workflow, "rhi_plot_size", (1500, 1200))
    rhi_aspect = get_param(workflow, "rhi_aspect", 7.5)
    rhi_range_max = get_param(workflow, "rhi_range_max", 120.0)
    rhi_height_max = get_param(workflow, "rhi_height_max", 16.0)
    dbz_levels = get_param(workflow, "dbz_levels", range(-4, 60, step=4))
    dbz_colormap = get_param(workflow, "dbz_colormap", :chaseSpectral)
    vel_levels = get_param(workflow, "vel_levels", range(-32, 32, step=4))
    vel_colormap = get_param(workflow, "vel_colormap", :balance)
    zdr_levels = get_param(workflow, "zdr_levels", range(-0.5, 3.5, step=0.2))
    zdr_colormap = get_param(workflow, "zdr_colormap", :PRGn)
    rhohv_levels = get_param(workflow, "rhohv_levels", range(0.8, 1.0, step=0.01))
    rhohv_colormap = get_param(workflow, "rhohv_colormap", :romaRhoHV)
    kdp_levels = get_param(workflow, "kdp_levels", range(-1, 4, step=0.1))
    kdp_colormap = get_param(workflow, "kdp_colormap", Reverse(:RdYlGn))
    phidp_levels = get_param(workflow, "phidp_levels", range(0, 360))
    phidp_colormap = get_param(workflow, "phidp_colormap", :davos)
    dbz_ticks = get_param(workflow, "dbz_ticks", 0:10:60)
    vel_ticks = get_param(workflow, "vel_ticks", -32:8:32)
    zdr_ticks = get_param(workflow, "zdr_ticks", -0.5:0.5:3.5)
    rhohv_ticks = get_param(workflow, "rhohv_ticks", 0.8:0.05:1.0)
    kdp_ticks = get_param(workflow, "kdp_ticks", -1:1:4)
    phidp_ticks = get_param(workflow, "phidp_ticks", 0:45:360)

    out_dir = plot_output_dir(workflow, step_name, start_time, output_dir)
    mkpath(out_dir)
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)

    for file in input_files
        g = Daisho.read_gridded_rhi(file, p)

        # Convert coordinates to km
        r = g.R ./ 1000.0
        z = g.Z ./ 1000.0

        dbz   = masked(g, refl_field,  "RHI plot")
        vel   = masked(g, vel_field,   "RHI plot")
        zdr   = masked(g, zdr_field,   "RHI plot")
        kdp   = masked(g, kdp_field,   "RHI plot")
        phidp = masked(g, phidp_field, "RHI plot")
        rhohv = masked(g, rhohv_field, "RHI plot")

        date = Dates.format(start_time, "YYYYmmdd")
        start_str = Dates.format(DateTime(g.start_time[1]), "HHMM")
        stop_str = Dates.format(DateTime(g.stop_time[1]), "HHMM")
        timestr = date * " " * start_str * "-" * stop_str * " UTC"

        angle = chop(split(file, "_")[end], tail=3)

        fig = Figure(size = rhi_plot_size)
        ax1 = CairoMakie.Axis(fig[1,1], aspect = rhi_aspect,
            title = "$(radar_name) $timestr RHI at $(angle)°\n Reflectivity", ylabel = "Height")
        xlims!(ax1, 0.0, rhi_range_max)
        ylims!(ax1, 0.0, rhi_height_max)

        ax2 = CairoMakie.Axis(fig[2,1], aspect = rhi_aspect,
            title = "Doppler Velocity", ylabel = "Height")
        xlims!(ax2, 0.0, rhi_range_max)
        ylims!(ax2, 0.0, rhi_height_max)

        ax3 = CairoMakie.Axis(fig[3,1], aspect = rhi_aspect,
            title = "Differential Reflectivity (ZDR)", ylabel = "Height")
        xlims!(ax3, 0.0, rhi_range_max)
        ylims!(ax3, 0.0, rhi_height_max)

        ax4 = CairoMakie.Axis(fig[4,1], aspect = rhi_aspect,
            title = "Correlation Coefficient (RhoHV)", ylabel = "Height")
        xlims!(ax4, 0.0, rhi_range_max)
        ylims!(ax4, 0.0, rhi_height_max)

        ax5 = CairoMakie.Axis(fig[5,1], aspect = rhi_aspect,
            title = "Specific Differential Phase (KDP)", ylabel = "Height")
        xlims!(ax5, 0.0, rhi_range_max)
        ylims!(ax5, 0.0, rhi_height_max)

        ax6 = CairoMakie.Axis(fig[6,1], aspect = rhi_aspect,
            title = "Differential Phase (PhiDP)", ylabel = "Height",
            xlabel = "Range")
        xlims!(ax6, 0.0, rhi_range_max)
        ylims!(ax6, 0.0, rhi_height_max)

        dbz_plot = safe_contourf!(ax1, r[:], z[:], dbz[:,:], levels = dbz_levels,
            colormap = cmap(dbz_colormap))
        vel_plot = safe_contourf!(ax2, r[:], z[:], vel[:,:], levels = vel_levels,
            colormap = cmap(vel_colormap))
        zdr_plot = safe_contourf!(ax3, r[:], z[:], zdr[:,:], levels = zdr_levels,
            colormap = cmap(zdr_colormap))
        rhohv_plot = safe_contourf!(ax4, r[:], z[:], rhohv[:,:], levels = rhohv_levels,
            colormap = Reverse(cmap(rhohv_colormap)))
        kdp_plot = safe_contourf!(ax5, r[:], z[:], kdp[:,:], levels = kdp_levels,
            colormap = cmap(kdp_colormap))
        phidp_plot = safe_contourf!(ax6, r[:], z[:], phidp[:,:], levels = phidp_levels,
            colormap = cmap(phidp_colormap))

        colsize!(fig.layout, 1, Aspect(1, 6.0))
        data_colorbar!(fig[1,2], dbz_plot; colormap = cmap(dbz_colormap), levels = dbz_levels, ticks = dbz_ticks, label = "dBZ")
        data_colorbar!(fig[2,2], vel_plot; colormap = cmap(vel_colormap), levels = vel_levels, ticks = vel_ticks, label = "m/s")
        data_colorbar!(fig[3,2], zdr_plot; colormap = cmap(zdr_colormap), levels = zdr_levels, ticks = zdr_ticks, label = "dB")
        data_colorbar!(fig[4,2], rhohv_plot; colormap = Reverse(cmap(rhohv_colormap)), levels = rhohv_levels, ticks = rhohv_ticks)
        data_colorbar!(fig[5,2], kdp_plot; colormap = cmap(kdp_colormap), levels = kdp_levels, ticks = kdp_ticks, label = "Deg/km")
        data_colorbar!(fig[6,2], phidp_plot; colormap = cmap(phidp_colormap), levels = phidp_levels, ticks = phidp_ticks, label = "Deg")
        resize_to_layout!(fig)
        trim!(fig.layout)

        outfile = joinpath(out_dir, "$(file_prefix)_RHI_$(date)_$(start_str)-$(stop_str)_$(angle)_deg.png")
        save(outfile, fig)
    end
end
