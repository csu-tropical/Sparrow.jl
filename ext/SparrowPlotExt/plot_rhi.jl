"""
    PlotRHIStep

Plot 6-panel RHI display: DBZ, velocity, ZDR, RhoHV, KDP, PhiDP.

# Configurable parameters (via workflow dict, with defaults)
- `radar_name`: Name in titles (default: `"Sparrow"`)
- `file_prefix`: Output filename prefix (default: `"Sparrow"`)
- `rdim`: Range dimension (default: `501`)
- `rhi_zdim`: Height dimension (default: `51`)
- `rhi_plot_size`: Figure size tuple (default: `(1500, 1200)`)
- `rhi_aspect`: Panel aspect ratio (default: `7.5`)
- `rhi_range_max`: Max range in km (default: `120.0`)
- `rhi_height_max`: Max height in km (default: `16.0`)
- `dbz_levels`: DBZ contour levels (default: `range(-4, 60, step=4)`)
- `vel_levels`: Velocity levels (default: `range(-32, 32, step=4)`)
- `vel_colormap`: Velocity colormap (default: `:balance`)
- `zdr_levels`: ZDR levels (default: `range(-0.5, 3.5, step=0.2)`)
- `zdr_colormap`: ZDR colormap (default: `:PRGn`)
- `rhohv_levels`: RhoHV levels (default: `range(0.8, 1.0, step=0.01)`)
- `kdp_levels`: KDP levels (default: `range(-1, 4, step=0.1)`)
- `kdp_colormap`: KDP colormap (default: `Reverse(:RdYlGn)`)
- `phidp_levels`: PhiDP levels (default: `range(0, 360)`)
- `phidp_colormap`: PhiDP colormap (default: `:davos`)
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PlotRHIStep},
                       input_dir::String, output_dir::String;
                       start_time::DateTime, stop_time::DateTime,
                       step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    ensure_colorschemes()

    moment_dict = workflow["qc_moment_dict"]
    radar_name = get_param(workflow, "radar_name", "Sparrow")
    file_prefix = get_param(workflow, "file_prefix", "Sparrow")
    rdim = get_param(workflow, "rdim", 501)
    rhi_zdim = get_param(workflow, "rhi_zdim", 51)
    rhi_plot_size = get_param(workflow, "rhi_plot_size", (1500, 1200))
    rhi_aspect = get_param(workflow, "rhi_aspect", 7.5)
    rhi_range_max = get_param(workflow, "rhi_range_max", 120.0)
    rhi_height_max = get_param(workflow, "rhi_height_max", 16.0)
    dbz_levels = get_param(workflow, "dbz_levels", range(-4, 60, step=4))
    vel_levels = get_param(workflow, "vel_levels", range(-32, 32, step=4))
    vel_colormap = get_param(workflow, "vel_colormap", :balance)
    zdr_levels = get_param(workflow, "zdr_levels", range(-0.5, 3.5, step=0.2))
    zdr_colormap = get_param(workflow, "zdr_colormap", :PRGn)
    rhohv_levels = get_param(workflow, "rhohv_levels", range(0.8, 1.0, step=0.01))
    kdp_levels = get_param(workflow, "kdp_levels", range(-1, 4, step=0.1))
    kdp_colormap = get_param(workflow, "kdp_colormap", Reverse(:RdYlGn))
    phidp_levels = get_param(workflow, "phidp_levels", range(0, 360))
    phidp_colormap = get_param(workflow, "phidp_colormap", :davos)

    mkpath(output_dir)
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)

    for file in input_files
        r, z, lat, lon, start_t, stop_t, radardata = Daisho.read_gridded_rhi(file, moment_dict)

        # Convert to km
        r = r ./ 1000.0
        z = z ./ 1000.0

        dbz = reshape(radardata[moment_dict["DBZ"],:], rdim, rhi_zdim)
        dbz = nomissing(dbz[:,:], -32768.0)
        replace!(dbz, -32768.0 => NaN)

        vel = reshape(radardata[moment_dict["VEL"],:], rdim, rhi_zdim)
        vel = nomissing(vel[:,:], -32768.0)
        replace!(vel, -32768.0 => NaN)

        zdr = reshape(radardata[moment_dict["ZDR"],:], rdim, rhi_zdim)
        zdr = nomissing(zdr[:,:], -32768.0)
        replace!(zdr, -32768.0 => NaN)

        kdp = reshape(radardata[moment_dict["KDP"],:], rdim, rhi_zdim)
        kdp = nomissing(kdp[:,:], -32768.0)
        replace!(kdp, -32768.0 => NaN)

        phidp = reshape(radardata[moment_dict["PHIDP"],:], rdim, rhi_zdim)
        phidp = nomissing(phidp[:,:], -32768.0)
        replace!(phidp, -32768.0 => NaN)

        rhohv = reshape(radardata[moment_dict["RHOHV"],:], rdim, rhi_zdim)
        rhohv = nomissing(rhohv[:,:], -32768.0)
        replace!(rhohv, -32768.0 => NaN)

        date = Dates.format(start_time, "YYYYmmdd")
        start_str = Dates.format(DateTime(start_t[1]), "HHMM")
        stop_str = Dates.format(DateTime(stop_t[1]), "HHMM")
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

        dbz_plot = contourf!(ax1, r[:], z[:], dbz[:,:], levels = dbz_levels,
            colormap = colorschemes[:chaseSpectral])
        vel_plot = contourf!(ax2, r[:], z[:], vel[:,:], levels = vel_levels,
            colormap = vel_colormap)
        zdr_plot = contourf!(ax3, r[:], z[:], zdr[:,:], levels = zdr_levels,
            colormap = zdr_colormap)
        rhohv_plot = contourf!(ax4, r[:], z[:], rhohv[:,:], levels = rhohv_levels,
            colormap = Reverse(colorschemes[:romaRhoHV]))
        kdp_plot = contourf!(ax5, r[:], z[:], kdp[:,:], levels = kdp_levels,
            colormap = kdp_colormap)
        phidp_plot = contourf!(ax6, r[:], z[:], phidp[:,:], levels = phidp_levels,
            colormap = phidp_colormap)

        colsize!(fig.layout, 1, Aspect(1, 6.0))
        Colorbar(fig[1,2], dbz_plot, ticks = 0:10:60, label = "dBZ")
        Colorbar(fig[2,2], vel_plot, ticks = -32:8:32, label = "m/s")
        Colorbar(fig[3,2], zdr_plot, ticks = -0.5:0.5:3.5, label = "dB")
        Colorbar(fig[4,2], rhohv_plot, ticks = 0.8:0.05:1.0)
        Colorbar(fig[5,2], kdp_plot, ticks = -1:1:4, label = "Deg/km")
        Colorbar(fig[6,2], phidp_plot, ticks = 0:45:360, label = "Deg")
        resize_to_layout!(fig)
        trim!(fig.layout)

        outfile = joinpath(output_dir, "$(file_prefix)_RHI_$(date)_$(start_str)-$(stop_str)_$(angle)_deg.png")
        save(outfile, fig)
    end
end
