function plot_largemap(file, date, plot_dir, moment_dict)

    # Read in the gridded data
    x, y, lat, lon, start_time, stop_time, radardata = Daisho.read_gridded_ppi(file, moment_dict)

    x_center = Int((xdim-1)/2 + 1)
    y_center = Int((ydim-1)/2 + 1)

    # Mask out the blanking sector using SQI
    sqi = reshape(radardata[moment_dict["SQI"],:],xdim,ydim)
    sqiraster = nomissing(sqi[:,:],-32768.0)
    blanking = ifelse.(sqiraster .> -32768.0, NaN, 0.0)

    dbz = reshape(radardata[moment_dict["DBZ"],:],xdim,ydim)
    dbzmax = nomissing(dbz[:,:],-32768.0)
    replace!(dbzmax, -32768.0 => NaN)

    start = Dates.format(start_time[1], "HHMM")
    stop = Dates.format(stop_time[1], "HHMM")
    timestr = date * " " * start * "-" * stop * " UTC"
    fig = Figure(backgroundcolor = :transparent)
    ax = GeoAxis(fig[1,1],
        width=400,
        height=400,
        dest="+proj=longlat +datum=WGS84")
    xlims!(ax, -65.0, -15.0)
    ylims!(ax, 0.0, 20.0)

    # These functions can use more complicated map boundaries
    # We are not using it here since GeoMakie provides basic coastline support

    #coastline = DataFrame(naturalearth("admin_0_countries",110))
    #coastline.geometry
    #poly!(ax, coastline.geometry; color = :transparent, strokecolor = :black, strokewidth = 1)
    lines!(ax, GeoMakie.coastlines(), color = :black)

    # Define color bars
    dbz_cbar = [:peachpuff, :aqua, :dodgerblue, :mediumblue, :lime,
        :limegreen, :green, :yellow, :orange, :orangered,
        :red, :crimson, :fuchsia, :indigo, :darkcyan, :white]
    blanking_cbar = [(:gray, 0.5)]

    contourf!(ax, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
        colormap = blanking_cbar, extendlow= (:gray, 0.5))
    composite = contourf!(ax, lon[:,y_center], lat[x_center,:], dbzmax[:,:], levels = range(-4, 60, step=4),
        colormap = colorschemes[:chaseSpectral])
    Textbox(fig[1, 1], placeholder = "SEA-POL dBZ $timestr Box [-65,-45,0,20]",
        valign = :top, halign = :left, boxcolor= :white, fontsize = :12)
    ax.xticks = [-65,-15]
    ax.yticks = [0,20]
    hidedecorations!(ax, grid = false)
    colsize!(fig.layout, 1, Aspect(1, 1.0))
    #Colorbar(fig,composite,vertical = false, bbox=ax.scene.viewport,
    #    valign = :bottom, ticks = 0:10:60)
    Colorbar(fig[1,2],composite, ticks = 0:10:60, label = "dBZ")
    resize_to_layout!(fig)

    #Box(fig[1, 1], color = (:red, 0.2), strokewidth = 0)
    outfile = plot_dir * "/SEAPOL_largemap_" * date * "_" * start * "-" * stop * ".png"
    save(outfile, fig)

    # Crop image to fit Planet
    #composite = load(outfile)
    #img_size = size(composite)
    #img_cropped = @view composite[73:874,63:864]
    #save(outfile, img_cropped)

end

function plot_dbz_composite(file, date, plot_dir, moment_dict)

    # Read in the gridded data
    x, y, lat, lon, start_time, stop_time, radardata = Daisho.read_gridded_ppi(file, moment_dict)

    x_center = Int((long_xdim-1)/2 + 1)
    y_center = Int((long_ydim-1)/2 + 1)
    # Mask out the blanking sector using SQI
    sqi = reshape(radardata[moment_dict["SQI"],:],long_xdim,long_ydim)
    sqiraster = nomissing(sqi[:,:],-32768.0)
    blanking = ifelse.(sqiraster .> -32768.0, NaN, 0.0)

    dbz = reshape(radardata[moment_dict["DBZ"],:],long_xdim,long_ydim)
    dbzmax = nomissing(dbz[:,:],-32768.0)
    replace!(dbzmax, -32768.0 => NaN)

    start = Dates.format(DateTime(start_time[1]), "HHMM")
    stop = Dates.format(DateTime(stop_time[1]), "HHMM")
    timestr = date * " " * start * "-" * stop * " UTC"

    fig = Figure()
    ax = CairoMakie.Axis(fig[1,1],
        width=400,
        height=400,
        title = "SEA-POL $timestr Composite Reflectivity",
        xlabel = "Longitude", ylabel = "Latitude")
    center_lon = lon[x_center,y_center]
    center_lat = lat[x_center,y_center]
    xlims!(ax, lon[1,y_center], lon[long_xdim,y_center])
    ylims!(ax, lat[x_center,1], lat[x_center,long_ydim])

    # Define color bar
    dbz_cbar = [:peachpuff, :aqua, :dodgerblue, :mediumblue, :lime,
        :limegreen, :green, :yellow, :orange, :orangered,
        :red, :crimson, :fuchsia, :indigo, :darkcyan, :white]
    blanking_cbar = [(:gray, 0.5)]

    range_ring = poly!(fig[1, 1], Circle(Point2f(center_lon, center_lat), 2.21),
    color= :transparent,
    strokecolor = (:gray, 0.5), strokewidth = 0.5)
    contourf!(ax, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
        colormap = blanking_cbar, extendlow = (:gray, 0.5))
    composite = contourf!(ax, lon[:,y_center], lat[x_center,:], dbzmax[:,:], levels = range(-4, 60, step=4),
        colormap = colorschemes[:chaseSpectral])
    #scatter!(ax, center_lon, center_lat, markersize = 5, color = :black)
    poly!(Circle(Point2f(center_lon, center_lat), 1.08), color= :transparent,
        strokecolor = (:gray, 0.5), strokewidth = 0.5)
    text!(fig[1, 1], Point2f(center_lon, center_lat-1.1), text = "120 km", color = (:gray, 0.5),
        fontsize = :12, align = (:center, :baseline))
    text!(fig[1, 1], Point2f(center_lon, center_lat-2.23), text = "245 km", color = (:gray, 0.5),
        fontsize = :12, align = (:center, :baseline))

    #arc!(ax, Point2f(center_lon, center_lat), 0, -π, π, color= (:gray, 0.5), linewidth = 0.5)
    #text!(fig[1, 1], Point2f(center_lon, center_lat-1.1), text = "120 km", color = (:gray, 0.5),
    #    fontsize = :12, align = (:center, :baseline))
    #hidedecorations!(ax, minorgrid = false)
    colsize!(fig.layout, 1, Aspect(1, 1.0))
    Colorbar(fig[1,2],composite, ticks = 0:10:60, label = "dBZ")
    resize_to_layout!(fig)
    outfile = plot_dir * "/SEAPOL_composite_" * date * "_" * start * "-" * stop * ".png"
    save(outfile, fig)

end

function plot_composite(file, date, plot_dir, moment_dict)

    # Read in the gridded data
    x, y, lat, lon, start_time, stop_time, radardata = Daisho.read_gridded_ppi(file, moment_dict)

    # Mask out the blanking sector using SQI
    sqi = reshape(radardata[moment_dict["SQI"],:],501,501)
    sqiraster = nomissing(sqi[:,:],-32768.0)
    blanking = ifelse.(sqiraster .> -32768.0, NaN, 0.0)

    dbz = reshape(radardata[moment_dict["DBZ"],:],501,501)
    dbzmax = nomissing(dbz[:,:],-32768.0)
    replace!(dbzmax, -32768.0 => NaN)

    start = Dates.format(DateTime(start_time[1]), "HHMM")
    stop = Dates.format(DateTime(stop_time[1]), "HHMM")
    timestr = date * " " * start * "-" * stop * " UTC"

    fig = Figure()
    ax = CairoMakie.Axis(fig[1,1],
        width=400,
        height=400,
        title = "SEA-POL $timestr Composite Reflectivity",
        xlabel = "Longitude", ylabel = "Latitude")
    center_lon = lon[251,251]
    center_lat = lat[251,251]
    xlims!(ax, lon[1,251], lon[501,251])
    ylims!(ax, lat[251,1], lat[251,501])

    # Define color bar
    dbz_cbar = [:peachpuff, :aqua, :dodgerblue, :mediumblue, :lime,
        :limegreen, :green, :yellow, :orange, :orangered,
        :red, :crimson, :fuchsia, :indigo, :darkcyan, :white]
    blanking_cbar = [(:gray, 0.5)]

    #Box(fig[1, 1], color = (:blue, 0.1), strokewidth = 0)
    #poly!(ax, Rect(center_lon - 2.5, center_lat - 2.5, 5.0, 5.0),
    #    color = (:gray, 0.5))
    range_ring = poly!(fig[1, 1], Circle(Point2f(center_lon, center_lat), 2.21),
        color= :transparent,
        strokecolor = (:gray, 0.5), strokewidth = 0.5)
    contourf!(ax, lon[:,251], lat[251,:], blanking[:,:], levels = range(-5, 5, step=10),
        colormap = blanking_cbar, extendlow = (:gray, 0.5))
    composite = contourf!(ax, lon[:,251], lat[251,:], dbzmax[:,:], levels = range(-4, 60, step=4),
        colormap = dbz_cbar, extendlow = (:skyblue, 0.1))
    scatter!(ax, center_lon, center_lat, markersize = 10, color = :black)
    poly!(Circle(Point2f(center_lon, center_lat), 1.08), color= :transparent,
        strokecolor = (:gray, 0.5), strokewidth = 0.5)
    text!(fig[1, 1], Point2f(center_lon, center_lat-1.1), text = "120 km", color = (:gray, 0.5),
        fontsize = :12, align = (:center, :baseline))
    text!(fig[1, 1], Point2f(center_lon, center_lat-2.23), text = "245 km", color = (:gray, 0.5),
        fontsize = :12, align = (:center, :baseline))
    #hidedecorations!(ax, grid = false)
    colsize!(fig.layout, 1, Aspect(1, 1.0))
    Colorbar(fig[1,2],composite, ticks = 0:10:60, label = "dBZ")
    resize_to_layout!(fig)
    outfile = plot_dir * "/SEAPOL_composite_" * date * "_" * start * "-" * stop * ".png"
    save(outfile, fig)

end

function plot_dbz_vel(file, date, plot_dir, moment_dict)

    # Read in the gridded data
    x, y, lat, lon, start_time, stop_time, radardata = Daisho.read_gridded_ppi(file, moment_dict)

    x_center = Int((xdim-1)/2 + 1)
    y_center = Int((ydim-1)/2 + 1)

    # Mask out the blanking sector using SQI
    sqi = reshape(radardata[moment_dict["SQI"],:],xdim,ydim)
    sqiraster = nomissing(sqi[:,:],-32768.0)
    blanking = ifelse.(sqiraster .> -32768.0, NaN, 0.0)

    dbz = reshape(radardata[moment_dict["DBZ"],:],xdim,ydim)
    dbz = nomissing(dbz[:,:],-32768.0)
    replace!(dbz, -32768.0 => NaN)
    replace!(dbz, -9999.0 => NaN)

    vel = reshape(radardata[moment_dict["VEL"],:],xdim,ydim)
    vel = nomissing(vel[:,:],-32768.0)
    replace!(vel, -32768.0 => NaN)
    replace!(vel, -9999.0 => NaN)

    start = Dates.format(DateTime(start_time[1]), "HHMM")
    stop = Dates.format(DateTime(stop_time[1]), "HHMM")
    timestr = date * " " * start * "-" * stop * " UTC"

    # Elevation angle from filename
    elevation = chop(split(file, "_")[end], tail=3)

    fig = Figure()
    ax1 = CairoMakie.Axis(fig[1,1],
        width=400,
        height=400,
        title = "SEA-POL $timestr Reflectivity at $(elevation)°",
        xlabel = "Longitude", ylabel = "Latitude")

    center_lon = lon[x_center,y_center]
    center_lat = lat[x_center,y_center]
    xlims!(ax1, lon[1,y_center], lon[xdim,y_center])
    ylims!(ax1, lat[x_center,1], lat[x_center,ydim])

    # Define color bar
    dbz_cbar = [:peachpuff, :aqua, :dodgerblue, :mediumblue, :lime,
        :limegreen, :green, :yellow, :orange, :orangered,
        :red, :crimson, :fuchsia, :indigo, :darkcyan, :white]
    blanking_cbar = [(:gray, 0.5)]

    contourf!(ax1, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
        colormap = blanking_cbar, extendlow = (:gray, 0.5))
    composite = contourf!(ax1, lon[:,y_center], lat[x_center,:], dbz[:,:], levels = range(-10, 45),
        colormap = colorschemes[:chaseSpectral])
    composite = contourf!(ax1, lon[:,126], lat[126,:], dbz[:,:], levels = range(-10, 45),
        colormap = colorschemes[:chaseSpectral])
    #scatter!(ax1, center_lon, center_lat, markersize = 5, color = :black)
    scatter!(ax1, -106.744,40.455, marker=:diamond, markersize = 5, color = :black)
    #arc!(ax, Point2f(center_lon, center_lat), 0, -π, π, color= (:gray, 0.5), linewidth = 0.5)
    #text!(fig[1, 1], Point2f(center_lon, center_lat-1.1), text = "120 km", color = (:gray, 0.5),
    #    fontsize = :12, align = (:center, :baseline))
    #hidedecorations!(ax, grid = false)
    colsize!(fig.layout, 1, Aspect(1, 1.0))
    Colorbar(fig[1,2],composite, ticks = -10:5:45, label = "dBZ")

    ax2 = CairoMakie.Axis(fig[1,3],
        width=400,
        height=400,
        title = "SEA-POL $timestr Velocity at $(elevation)°",
        xlabel = "Longitude", ylabel = "Latitude")

    center_lon = lon[x_center,y_center]
    center_lat = lat[x_center,y_center]
    xlims!(ax2, lon[1,y_center], lon[xdim,y_center])
    ylims!(ax2, lat[x_center,1], lat[x_center,ydim])

    # Define color bar
    blanking_cbar = [(:gray, 0.5)]

    contourf!(ax2, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
        colormap = blanking_cbar, extendlow = (:gray, 0.5))
    velocity = contourf!(ax2, lon[:,y_center], lat[x_center,:], vel[:,:], levels = range(-32, 32, step=4),
        colormap = :balance)
    #scatter!(ax2, center_lon, center_lat, markersize = 5, color = :black)
    scatter!(ax2, -106.744,40.455, marker=:diamond, markersize = 5, color = :black)
    #arc!(ax, Point2f(center_lon, center_lat), 0, -π, π, color= (:gray, 0.5), linewidth = 0.5)
    #text!(fig[1, 1], Point2f(center_lon, center_lat-1.1), text = "120 km", color = (:gray, 0.5),
    #    fontsize = :12, align = (:center, :baseline))
    #hidedecorations!(ax, grid = false)
    colsize!(fig.layout, 1, Aspect(1, 1.0))
    Colorbar(fig[1,4],velocity, ticks = -32:4:32, label = "Velocity m/s")

    resize_to_layout!(fig)
    outfile = plot_dir * "/SEAPOL_PPI_" * date * "_" * start * "-" * stop * "_" * elevation * "_deg.png"
    save(outfile, fig)

end

function plot_dbz_rainrate(file, date, plot_dir, moment_dict)

    # Read in the gridded data
    x, y, lat, lon, start_time, stop_time, radardata = Daisho.read_gridded_ppi(file, moment_dict)

    x_center = Int((long_xdim-1)/2 + 1)
    y_center = Int((long_ydim-1)/2 + 1)

    # Mask out the blanking sector using SQI
    sqi = reshape(radardata[moment_dict["SQI"],:],long_xdim,long_ydim)
    sqiraster = nomissing(sqi[:,:],-32768.0)
    blanking = ifelse.(sqiraster .> -32768.0, NaN, 0.0)

    dbz = reshape(radardata[moment_dict["DBZ"],:],long_xdim,long_ydim)
    dbz = nomissing(dbz[:,:],-32768.0)
    replace!(dbz, -32768.0 => NaN)
    replace!(dbz, -9999.0 => NaN)

    rr = reshape(radardata[moment_dict["RATE_CSU_BLENDED"],:],long_xdim,long_ydim)
    rr = nomissing(rr[:,:],-32768.0)
    replace!(rr, -32768.0 => NaN)
    replace!(rr, -9999.0 => NaN)

    start = Dates.format(DateTime(start_time[1]), "HHMM")
    stop = Dates.format(DateTime(stop_time[1]), "HHMM")
    timestr = date * " " * start * "-" * stop * " UTC"

    # Elevation angle from filename
    elevation = chop(split(file, "_")[end], tail=3)

    fig = Figure()
    ax1 = CairoMakie.Axis(fig[1,1],
        width=400,
        height=400,
        title = "SEA-POL $timestr Reflectivity at $(elevation)°",
        xlabel = "Longitude", ylabel = "Latitude")

    center_lon = lon[x_center,y_center]
    center_lat = lat[x_center,y_center]
    xlims!(ax1, lon[1,y_center], lon[long_xdim,y_center])
    ylims!(ax1, lat[x_center,1], lat[x_center,long_ydim])

    # Define color bar
    dbz_cbar = [:peachpuff, :aqua, :dodgerblue, :mediumblue, :lime,
        :limegreen, :green, :yellow, :orange, :orangered,
        :red, :crimson, :fuchsia, :indigo, :darkcyan, :white]
    blanking_cbar = [(:gray, 0.5)]

    contourf!(ax1, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
        colormap = blanking_cbar, extendlow = (:gray, 0.5))
    composite = contourf!(ax1, lon[:,y_center], lat[x_center,:], dbz[:,:], levels = range(-4, 60, step=4),
        colormap = colorschemes[:chaseSpectral])
    #scatter!(ax1, center_lon, center_lat, markersize = 5, color = :black)
    #scatter!(ax1, -106.744,40.455, marker=:diamond, markersize = 5, color = :black)
    #arc!(ax, Point2f(center_lon, center_lat), 0, -π, π, color= (:gray, 0.5), linewidth = 0.5)
    #text!(fig[1, 1], Point2f(center_lon, center_lat-1.1), text = "120 km", color = (:gray, 0.5),
    #    fontsize = :12, align = (:center, :baseline))
    #hidedecorations!(ax, grid = false)
    colsize!(fig.layout, 1, Aspect(1, 1.0))
    Colorbar(fig[1,2],composite, ticks = ticks = 0:10:60, label = "dBZ")

    ax2 = CairoMakie.Axis(fig[1,3],
        width=400,
        height=400,
        title = "SEA-POL $timestr Rain rate at $(elevation)°",
        xlabel = "Longitude", ylabel = "Latitude")

    center_lon = lon[x_center,y_center]
    center_lat = lat[x_center,y_center]
    xlims!(ax2, lon[1,y_center], lon[xdim,y_center])
    ylims!(ax2, lat[x_center,1], lat[x_center,ydim])

    # Define color bar
    blanking_cbar = [(:gray, 0.5)]

    contourf!(ax2, lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
        colormap = blanking_cbar, extendlow = (:gray, 0.5))
    rainrate = contourf!(ax2, lon[:,y_center], lat[x_center,:], rr[:,:], levels = range(0, 150, step=10),
        colormap = :Paired_6)
    #scatter!(ax2, center_lon, center_lat, markersize = 5, color = :black)
    scatter!(ax2, -106.744,40.455, marker=:diamond, markersize = 5, color = :black)
    #arc!(ax, Point2f(center_lon, center_lat), 0, -π, π, color= (:gray, 0.5), linewidth = 0.5)
    #text!(fig[1, 1], Point2f(center_lon, center_lat-1.1), text = "120 km", color = (:gray, 0.5),
    #    fontsize = :12, align = (:center, :baseline))
    #hidedecorations!(ax, grid = false)
    colsize!(fig.layout, 1, Aspect(1, 1.0))
    Colorbar(fig[1,4],rainrate, ticks = 0:10:150, label = "Rain rate mm/hr")

    resize_to_layout!(fig)
    outfile = plot_dir * "/SEAPOL_PPI_" * date * "_" * start * "-" * stop * "_" * elevation * "_deg.png"
    save(outfile, fig)

end

function plot_rhi(file, date, plot_dir, moment_dict)

    # Read in the gridded data
    r, z, lat, lon, start_time, stop_time, radardata = Daisho.read_gridded_rhi(file, moment_dict)

    # Convert to km
    r = r ./ 1000.0
    z = z ./ 1000.0

    # Mask out the blanking sector using SQI
    sqi = reshape(radardata[moment_dict["SQI"],:],rdim,rhi_zdim)
    sqiraster = nomissing(sqi[:,:],-32768.0)
    blanking = ifelse.(sqiraster .> -32768.0, NaN, 0.0)

    dbz = reshape(radardata[moment_dict["DBZ"],:],rdim,rhi_zdim)
    dbz = nomissing(dbz[:,:],-32768.0)
    replace!(dbz, -32768.0 => NaN)

    vel = reshape(radardata[moment_dict["VEL"],:],rdim,rhi_zdim)
    vel = nomissing(vel[:,:],-32768.0)
    replace!(vel, -32768.0 => NaN)

    zdr = reshape(radardata[moment_dict["ZDR"],:],rdim,rhi_zdim)
    zdr = nomissing(zdr[:,:],-32768.0)
    replace!(zdr, -32768.0 => NaN)

    kdp = reshape(radardata[moment_dict["KDP"],:],rdim,rhi_zdim)
    kdp = nomissing(kdp[:,:],-32768.0)
    replace!(kdp, -32768.0 => NaN)

    phidp = reshape(radardata[moment_dict["PHIDP"],:],rdim,rhi_zdim)
    phidp = nomissing(phidp[:,:],-32768.0)
    replace!(phidp, -32768.0 => NaN)

    rhohv = reshape(radardata[moment_dict["RHOHV"],:],rdim,rhi_zdim)
    rhohv = nomissing(rhohv[:,:],-32768.0)
    replace!(rhohv, -32768.0 => NaN)

    start = Dates.format(DateTime(start_time[1]), "HHMM")
    stop = Dates.format(DateTime(stop_time[1]), "HHMM")
    timestr = date * " " * start * "-" * stop * " UTC"

    # Get angle from filename
    angle = chop(split(file, "_")[end], tail=3)

    fig = Figure(size = (1500, 1200))
    ax1 = CairoMakie.Axis(fig[1,1], aspect = 7.5, title = "SEA-POL $timestr RHI at $(angle)°\n Reflectivity", ylabel = "Height")
    xlims!(ax1, 0.0, 120.0)
    ylims!(ax1, 0.0, 16.0)

    ax2 = CairoMakie.Axis(fig[2,1], aspect = 7.5, title = "Doppler Velocity", ylabel = "Height")
    xlims!(ax2, 0.0, 120.0)
    ylims!(ax2, 0.0, 16.0)

    ax3 = CairoMakie.Axis(fig[3,1], aspect = 7.5, title = "Differential Reflectivity (ZDR)", ylabel = "Height")
    xlims!(ax3, 0.0, 120.0)
    ylims!(ax3, 0.0, 16.0)

    ax4 = CairoMakie.Axis(fig[4,1], aspect = 7.5, title = "Correlation Coefficient (RhoHV)", ylabel = "Height")
    xlims!(ax4, 0.0, 120.0)
    ylims!(ax4, 0.0, 16.0)

    ax5 = CairoMakie.Axis(fig[5,1], aspect = 7.5, title = "Specific Differential Phase (KDP)", ylabel = "Height")
    xlims!(ax5, 0.0, 120.0)
    ylims!(ax5, 0.0, 16.0)

    ax6 = CairoMakie.Axis(fig[6,1], aspect = 7.5, title = "Differential Phase (PhiDP)", ylabel = "Height",
        xlabel = "Range")
    xlims!(ax6, 0.0, 120.0)
    ylims!(ax6, 0.0, 16.0)

    # Define color bar
    dbz_cbar = [:peachpuff, :aqua, :dodgerblue, :mediumblue, :lime,
        :limegreen, :green, :yellow, :orange, :orangered,
        :red, :crimson, :fuchsia, :indigo, :darkcyan, :white]
    blanking_cbar = [(:gray, 0.5)]

    dbz_plot = contourf!(ax1, r[:], z[:], dbz[:,:] , levels = range(-4, 60, step=4),
        colormap = colorschemes[:chaseSpectral])
    vel_plot = contourf!(ax2, r[:], z[:], vel[:,:], levels = range(-32, 32, step=4),
        colormap = :balance)
    zdr_plot = contourf!(ax3, r[:], z[:], zdr[:,:], levels = range(-0.5, 3.5, step=0.2),
        colormap = :PRGn) #:oleron)
    rhohv_plot = contourf!(ax4, r[:], z[:], rhohv[:,:], levels = range(0.8, 1.0, step=0.01),
        colormap = Reverse(colorschemes[:romaRhoHV]))
    kdp_plot = contourf!(ax5, r[:], z[:], kdp[:,:], levels = range(-1, 4, step=0.1),
        colormap = Reverse(:RdYlGn))
    phidp_plot = contourf!(ax6, r[:], z[:], phidp[:,:], levels = range(0, 360),
        colormap = :davos)

    #contourf!(ax1, r[:], z[:], blanking[:,:], levels = range(-5, 5, step=10),
    #    colormap = blanking_cbar, extendlow = (:gray, 0.5))
    #contourf!(ax2, r[:], z[:], blanking[:,:], levels = range(-5, 5, step=10),
    #    colormap = blanking_cbar, extendlow = (:gray, 0.5))
    #contourf!(ax3, r[:], z[:], blanking[:,:], levels = range(-5, 5, step=10),
    #    colormap = blanking_cbar, extendlow = (:gray, 0.5))
    #contourf!(ax4, r[:], z[:], blanking[:,:], levels = range(-5, 5, step=10),
    #    colormap = blanking_cbar, extendlow = (:gray, 0.5))
    #contourf!(ax5, r[:], z[:], blanking[:,:], levels = range(-5, 5, step=10),
    #    colormap = blanking_cbar, extendlow = (:gray, 0.5))
    #contourf!(ax6, r[:], z[:], blanking[:,:], levels = range(-5, 5, step=10),
    #    colormap = blanking_cbar, extendlow = (:gray, 0.5))

    #rowsize!(fig.layout, 1, [1,1,1,1,1,1])
    colsize!(fig.layout, 1, Aspect(1, 6.0))
    Colorbar(fig[1,2], dbz_plot, ticks = 0:10:60, label = "dBZ")
    Colorbar(fig[2,2], vel_plot, ticks = -32:8:32, label = "m/s")
    Colorbar(fig[3,2], zdr_plot, ticks = -0.5:0.5:3.5, label = "dB")
    Colorbar(fig[4,2], rhohv_plot, ticks = 0.8:0.05:1.0)
    Colorbar(fig[5,2], kdp_plot, ticks = -1:1:4,label = "Deg/km")
    Colorbar(fig[6,2], phidp_plot, ticks = 0:45:360, label = "Deg")
    resize_to_layout!(fig)
    trim!(fig.layout)
    outfile = plot_dir * "/SEAPOL_RHI_" * date * "_" * start * "-" * stop * "_" * angle * "_deg.png"
    save(outfile, fig)

end

function plot_ppi_vol(files, date, plot_dir, moment_dict)

    fig = Figure()
    num_columns = 2
    if length(files) > 2
        num_columns = 3
    end
    ax = Array{CairoMakie.Axis}(undef,length(files))

    # Read in the gridded data
    row = 1
    col = 0
    for f in 1:length(files)
        x, y, lat, lon, start_time, stop_time, radardata = Daisho.read_gridded_ppi(files[f], moment_dict)

        x_center = Int((xdim-1)/2 + 1)
        y_center = Int((ydim-1)/2 + 1)

        # Mask out the blanking sector using SQI
        sqi = reshape(radardata[moment_dict["SQI"],:],xdim,ydim)
        sqiraster = nomissing(sqi[:,:],-32768.0)
        blanking = ifelse.(sqiraster .> -32768.0, NaN, 0.0)

        dbz = reshape(radardata[moment_dict["DBZ"],:],xdim,ydim)
        dbz = nomissing(dbz[:,:],-32768.0)
        replace!(dbz, -32768.0 => NaN)
        replace!(dbz, -9999.0 => NaN)

        start = Dates.format(DateTime(start_time[1]), "HHMM")
        stop = Dates.format(DateTime(stop_time[1]), "HHMM")
        timestr = date * " " * start * "-" * stop * " UTC"

        # Elevation angle from filename
        elevation = chop(split(files[f], "_")[end], tail=3)

        if num_columns == 2
            col = col + 1
            if col > 2
                col = 1
                row = row + 1
            end
        else
            col = col + 1
            if col > 3
                col = 1
                row = row + 1
            end
        end

        ax[f] = CairoMakie.Axis(fig[row,col],
            width=400,
            height=400,
            title = "SEA-POL $timestr Reflectivity at $(elevation)°",
            xlabel = "Longitude", ylabel = "Latitude")

        center_lon = lon[x_center,y_center]
        center_lat = lat[x_center,y_center]
        xlims!(ax[f], lon[1,y_center], lon[xdim,y_center])
        ylims!(ax[f], lat[x_center,1], lat[x_center,ydim])

        # Define color bar
        dbz_cbar = [:peachpuff, :aqua, :dodgerblue, :mediumblue, :lime,
            :limegreen, :green, :yellow, :orange, :orangered,
            :red, :crimson, :fuchsia, :indigo, :darkcyan, :white]
        blanking_cbar = [(:gray, 0.5)]

        contourf!(ax[f], lon[:,y_center], lat[x_center,:], blanking[:,:], levels = range(-5, 5, step=10),
            colormap = blanking_cbar, extendlow = (:gray, 0.5))
        composite = contourf!(ax[f], lon[:,y_center], lat[x_center,:], dbz[:,:], levels = range(-10, 45),
            colormap = colorschemes[:chaseSpectral])
        composite = contourf!(ax[f], lon[:,126], lat[126,:], dbz[:,:], levels = range(-10, 45),
            colormap = colorschemes[:chaseSpectral])
        #scatter!(ax1, center_lon, center_lat, markersize = 5, color = :black)
        scatter!(ax[f], -106.744,40.455, marker=:diamond, markersize = 5, color = :black)
        #arc!(ax, Point2f(center_lon, center_lat), 0, -π, π, color= (:gray, 0.5), linewidth = 0.5)
        #text!(fig[1, 1], Point2f(center_lon, center_lat-1.1), text = "120 km", color = (:gray, 0.5),
        #    fontsize = :12, align = (:center, :baseline))
        #hidedecorations!(ax, grid = false)
        colsize!(fig.layout, 1, Aspect(1, 1.0))
        if num_columns == 2 && col == 2
            Colorbar(fig[row,3],composite, ticks = -10:5:45, label = "dBZ")
        elseif num_columns == 3 && col == 3
            Colorbar(fig[row,4],composite, ticks = -10:5:45, label = "dBZ")
        end
    end

    resize_to_layout!(fig)
    x, y, lat, lon, start_vol, stop_time, radardata = Daisho.read_gridded_ppi(files[1], moment_dict)
    x, y, lat, lon, start_time, stop_vol, radardata = Daisho.read_gridded_ppi(files[end], moment_dict)
    start = Dates.format(DateTime(start_vol[1]), "HHMM")
    stop = Dates.format(DateTime(stop_vol[1]), "HHMM")

    outfile = plot_dir * "/SEAPOL_VOL_" * date * "_" * start * "-" * stop * ".png"
    save(outfile, fig)

end

function define_colorschemes()

    colorschemes[:chaseSpectral] = loadcolorscheme(:chaseSpectral , [
        RGB(2.491587318630544227e-03, 0.000000000000000000e+00, 1.238497574313402773e-02),
        RGB(0.03658093634274969, 0.028054239833639998, 0.05381675386098778),
        RGB(0.05294470009390365, 0.04244028154055208, 0.07213062231236242),
        RGB(0.06658209706708043, 0.05494952540396814, 0.08788848915960604),
        RGB(0.07828532464084167, 0.06569663206458462, 0.10191334732637991),
        RGB(0.08774627903391646, 0.07532763064627765, 0.11603662838305168),
        RGB(0.09608542813730694, 0.0838823226614803, 0.1305319484336847),
        RGB(0.10519906000616333, 0.09139766310160755, 0.14533666113501592),
        RGB(0.1143925332853242, 0.09895719929230179, 0.16035654554120207),
        RGB(0.1236459743440021, 0.10658676959498997, 0.17558104337578956),
        RGB(0.13295940567709563, 0.11428464678392375, 0.1910026176979828),
        RGB(0.1423326780515856, 0.12204918809971516, 0.20661430538507652),
        RGB(0.15176551148761097, 0.12987883051086024, 0.2224096588254607),
        RGB(0.16125752647128078, 0.13777208601081994, 0.23838269363022035),
        RGB(0.17080826795454293, 0.14572753705631736, 0.25452784216510033),
        RGB(0.18041722395923285, 0.1537438322082816, 0.27083991244121586),
        RGB(0.19008384009771045, 0.16181968200806704, 0.2873140518120347),
        RGB(0.19980753097126575, 0.16995385510293815, 0.30394571491863803),
        RGB(0.20958768915915027, 0.17814517462286908, 0.32073063535963053),
        RGB(0.21942369233296966, 0.18639251480322644, 0.3376648006126895),
        RGB(0.229314908901726, 0.19469479784338192, 0.3547444297895381),
        RGB(0.23926070249758158, 0.20305099098874413, 0.37196595385915493),
        RGB(0.2492604355416123, 0.21146010382244096, 0.3893259980226194),
        RGB(0.25931347207563205, 0.21992118575247493, 0.4068213659661921),
        RGB(0.26941918000585097, 0.22843332368030173, 0.42444902575695725),
        RGB(0.27957693287328533, 0.23699563983726068, 0.442206097177961),
        RGB(0.28978611124208525, 0.24560728977595703, 0.4600898403277725),
        RGB(0.30004610377848004, 0.25426746050447113, 0.4780976453333535),
        RGB(0.31035630807862913, 0.2629753687521055, 0.4962270230455848),
        RGB(0.3207161312923116, 0.2717302593562055, 0.5144755966042727),
        RGB(0.3311249905804125, 0.28053140376040597, 0.5328410937743833),
        RGB(0.3415823584034798, 0.28937818783558124, 0.5513208663517171),
        RGB(0.35208646988467956, 0.2982709895139585, 0.5699100705078144),
        RGB(0.3626292452733528, 0.30721497007958726, 0.5885931009906794),
        RGB(0.37317251268837997, 0.3162349022923335, 0.6073166391422907),
        RGB(0.3835684996112459, 0.32541781729653146, 0.6259301309289748),
        RGB(0.3933843749267976, 0.3349944088647704, 0.6441067607805429),
        RGB(0.4016713180922428, 0.34542223318753285, 0.6613179588797128),
        RGB(0.4069156093882403, 0.3573463785025636, 0.6769567442797976),
        RGB(0.4074599054729932, 0.37132742930864043, 0.6905909806936888),
        RGB(0.4022968399432315, 0.3874670617414102, 0.7021598000653095),
        RGB(0.3916190272313545, 0.405288231006769, 0.7119412504953325),
        RGB(0.37660765489444875, 0.42401770965357366, 0.7203375941837565),
        RGB(0.35868791680516796, 0.44298053254038267, 0.7276780477656283),
        RGB(0.33896849505266413, 0.4617722727676919, 0.7341484532598764),
        RGB(0.3182701330608626, 0.4801975992804505, 0.7397743004894358),
        RGB(0.29753807775604063, 0.4981643586862719, 0.7443189423745032),
        RGB(0.27823563430973564, 0.5156450695105298, 0.7470997393591877),
        RGB(0.26243698091245304, 0.5326711207928083, 0.7469866546910617),
        RGB(0.25233166701799553, 0.5493025406502459, 0.7428566828712679),
        RGB(0.2491179225414517, 0.5655840527839966, 0.7343172939531252),
        RGB(0.2522199829625309, 0.5815309105792504, 0.7220388721983574),
        RGB(0.2597984989666126, 0.597152029096929, 0.7073314124740867),
        RGB(0.2699418598131884, 0.6124761563034992, 0.6913968891923088),
        RGB(0.2813751612175089, 0.6275493875453179, 0.6749240519450622),
        RGB(0.2935126820811936, 0.6424053926032058, 0.6582127377035207),
        RGB(0.3063185037098662, 0.6570224289209322, 0.6415967764035395),
        RGB(0.3202520046229441, 0.6712877289433464, 0.6258365919199179),
        RGB(0.3361767323789121, 0.6850088089981187, 0.6121319301833816),
        RGB(0.35497707458200606, 0.6979979864067665, 0.6015997055370958),
        RGB(0.37697466444423516, 0.7101849199617357, 0.5945972934672993),
        RGB(0.4016592555188411, 0.7216625973555056, 0.5905427889573092),
        RGB(0.42799277834604854, 0.7326300747025514, 0.5883846980218588),
        RGB(0.4549589537484719, 0.7432906607111363, 0.5872050838318994),
        RGB(0.4819169604718663, 0.7537845486656257, 0.5864561680492162),
        RGB(0.5086265718380801, 0.7641818771945084, 0.5858423203908761),
        RGB(0.5350793431627744, 0.7745114539811094, 0.5851363495209893),
        RGB(0.5613104434757933, 0.7847933147539455, 0.5840978365069859),
        RGB(0.587284910577184, 0.7950573993163036, 0.5825078415106638),
        RGB(0.6128844828768119, 0.8053428878825712, 0.5802646269966033),
        RGB(0.6379939021096188, 0.8156801806197339, 0.5774330409641608),
        RGB(0.6626184816022166, 0.8260702180199759, 0.5741948745714632),
        RGB(0.6869079831407115, 0.8364827703370801, 0.5705948745714632),
        RGB(0.7110428610159713, 0.8468792024067447, 0.5667905704270348),
        RGB(0.7350865447037018, 0.8572398237629604, 0.5629180508629931),
        RGB(0.7589321151074746, 0.8675724108554084, 0.5593878412660628),
        RGB(0.7823504956513494, 0.8779001029436256, 0.5569777403249802),
        RGB(0.8050554698778819, 0.8882474809582022, 0.5568616413755243),
        RGB(0.8267512092510693, 0.8986387786400021, 0.5604108141197536),
        RGB(0.8472095149843595, 0.9091006838255575, 0.5686604283247991),
        RGB(0.866381114586076, 0.9196556199980889, 0.5817274532333131),
        RGB(0.884452682503417, 0.9303074257189875, 0.5987181648235023),
        RGB(0.9017752049790235, 0.9410357991358146, 0.6182485505649489),
        RGB(0.9187153956842157, 0.9518062481845423, 0.6390932676023294),
        RGB(0.9355553305055087, 0.9625851523600569, 0.6604473764758707),
        RGB(0.9524981387722576, 0.9733495708555574, 0.681731468379263),
        RGB(0.9697427075190795, 0.9840891707348572, 0.7022161781556219),
        RGB(0.9875564727577292, 0.9947988126567285, 0.7208193646517077),
        RGB(0.9980407582045668, 0.9973360522701887, 0.7285604345804712),
        RGB(0.9901081341662908, 0.9805280486371985, 0.7139421557523695),
        RGB(0.9832921183557174, 0.9636719697773511, 0.6953632580311194),
        RGB(0.9773247105504667, 0.9467720315871103, 0.6736725338087443),
        RGB(0.9718012632191854, 0.9298537865135398, 0.6500943381243378),
        RGB(0.9663890021662357, 0.912941478302525, 0.6256850968508929),
        RGB(0.9609540913422064, 0.8960319858754917, 0.6010808973083388),
        RGB(0.9555703321549603, 0.8790785433496511, 0.5765990298015855),
        RGB(0.9504686901658378, 0.8619848588841477, 0.5524940776715515),
        RGB(0.9459565461927416, 0.8446168450986672, 0.5291397436626922),
        RGB(0.9422938604457962, 0.8268438187355671, 0.5070074252916694),
        RGB(0.9395729615486617, 0.8085927166950098, 0.4864503172310807),
        RGB(0.9376981768110149, 0.7898713125314274, 0.4674718760614884),
        RGB(0.9364676752058404, 0.7707444542112941, 0.4497070119696765),
        RGB(0.9356527829986327, 0.7512973497424082, 0.4326419511471316),
        RGB(0.9350195740872602, 0.7316173915660021, 0.4158722656183817),
        RGB(0.9343573494980812, 0.7117791695881326, 0.3992230218226498),
        RGB(0.9335648756142448, 0.6918074664813865, 0.3827490810251898),
        RGB(0.9327101603754453, 0.6716444449334502, 0.3667140568017911),
        RGB(0.9319595477552292, 0.6511713889089449, 0.3515520705284562),
        RGB(0.9314169854435216, 0.6302839565213184, 0.3377209433706352),
        RGB(0.9310296827682809, 0.6089545159356072, 0.3254539980932858),
        RGB(0.9306432638093524, 0.5872242187691006, 0.3145970957378832),
        RGB(0.9301245783303129, 0.5651424372654756, 0.3046934957439262),
        RGB(0.9294267649644918, 0.5427160958250945, 0.2952352339035277),
        RGB(0.9285558487843163, 0.5199094507764838, 0.2858706783655494),
        RGB(0.9274643902597414, 0.4967005378030533, 0.2764880193747088),
        RGB(0.9259240389407738, 0.4731756982138288, 0.2672639230506011),
        RGB(0.9234711163596824, 0.4496035876395664, 0.2587595802102953),
        RGB(0.9195129965638398, 0.426409949494608, 0.251859380154075),
        RGB(0.9135736866352893, 0.4040267237927211, 0.247598128701105),
        RGB(0.9055280333993522, 0.3826919211952166, 0.2464654113583632),
        RGB(0.8956528296047865, 0.3623437102019935, 0.2480965004984163),
        RGB(0.884457764474428, 0.3426902787839809, 0.2514863799218179),
        RGB(0.8724404890113568, 0.3233794743789057, 0.2555998932478791),
        RGB(0.859941054992959, 0.3041242778043479, 0.2598006529424506),
        RGB(0.8471298230752027, 0.2847363627062785, 0.2638605711868699),
        RGB(0.8340532096652388, 0.265117231304337, 0.2677304454377097),
        RGB(0.8206709470780188, 0.2452608083507071, 0.2713113994435089),
        RGB(0.8068823812198758, 0.2252642569365564, 0.2743528736776508),
        RGB(0.7925681574071997, 0.2052990065432801, 0.2765327557716384),
        RGB(0.7776437086548245, 0.1855231800585573, 0.2766209307266459),
        RGB(0.7620881787474552, 0.1659938811053616, 0.2778098473048807),
        RGB(0.74592520405293, 0.14666215075194897, 0.2772148588299371),
        RGB(0.7291837579643043, 0.12744029957433484, 0.2760954516834965),
        RGB(0.7118643606327573, 0.10827362082100705, 0.2746220501928834),
        RGB(0.6939114128763002, 0.08917323459852672, 0.2731619874805619),
        RGB(0.6751925157681596, 0.07018975339513076, 0.2726604632714439),
        RGB(0.6555544703778219, 0.05112188655540586, 0.2747104787145965),
        RGB(0.6350589782820527, 0.030821925003199253, 0.2807508245877506),
        RGB(0.6143394151378339, 0.009946609770185135, 0.2905377427866415),
        RGB(6.096174471715584131e-01, 1.689067352390654503e-02, 3.132536812924263114e-01),
        RGB(6.304362302694949127e-01, 6.415999880604145167e-02, 3.523023872285024338e-01),
        RGB(6.545332720619715383e-01, 9.240290591553368404e-02, 3.867931688005283863e-01),
        RGB(6.816771386719749914e-01, 1.121795130427629683e-01, 4.165734585630757048e-01),
        RGB(7.106931461283616525e-01, 1.285922649813384111e-01, 4.432172748824148578e-01),
        RGB(7.401742431623169471e-01, 1.447501537429476681e-01, 4.684441576756514514e-01),
        RGB(7.687478120884442268e-01, 1.630208970332134855e-01, 4.933201793214440634e-01),
        RGB(7.950315753590273538e-01, 1.853358302944488334e-01, 5.182632140904128715e-01),
        RGB(8.177791370615994371e-01, 2.127627953382852377e-01, 5.432386337435157753e-01),
        RGB(8.362698416153079295e-01, 2.450086989067829513e-01, 5.678838319976026172e-01),
        RGB(8.505563725418664456e-01, 2.806737230285537565e-01, 5.916628811036308555e-01),
        RGB(8.613070089309564636e-01, 3.180749603252363000e-01, 6.141010127652497541e-01),
        RGB(8.694116302737093793e-01, 3.558810711006659688e-01, 6.350145273064313756e-01),
        RGB(8.757161388545896541e-01, 3.932313368152108302e-01, 6.546177707919846878e-01),
        RGB(8.809154887212219398e-01, 4.296236382495501882e-01, 6.735307717661165317e-01),
        RGB(8.853268404597925967e-01, 4.649163816409356831e-01, 6.927624045682388987e-01),
        RGB(8.884310704284409388e-01, 4.994546810769878165e-01, 7.137490323869131181e-01),
        RGB(8.887111971501618912e-01, 5.339646188625030154e-01, 7.383284867848654009e-01),
        RGB(8.846323716875585941e-01, 5.689236616662907142e-01, 7.682007948833130540e-01),
        RGB(8.767267275991816877e-01, 6.037553329925489098e-01, 8.037105842040241921e-01),
        RGB(8.463768910989423189e-01, 6.154197987084349952e-01, 8.207155904920702127e-01),
        RGB(7.884451339599858333e-01, 5.910998057946171835e-01, 8.040760682356380418e-01),
        RGB(7.414676382011815559e-01, 5.625639310187692255e-01, 7.851649477259431409e-01),
        RGB(7.050881789462218885e-01, 5.302805297690829089e-01, 7.636124721626524892e-01),
        RGB(6.762693114550958340e-01, 4.953415569730459933e-01, 7.404207375243810896e-01),
        RGB(6.517912360501287861e-01, 4.587593976723408074e-01, 7.166589548313024860e-01),
        RGB(6.294171674813368034e-01, 4.212253612177472295e-01, 6.928095728598714365e-01),
        RGB(6.077882060069819126e-01, 3.831868627309770736e-01, 6.688349720194523007e-01),
        RGB(5.860059395082031219e-01, 3.449961231831933373e-01, 6.444254002678728721e-01),
        RGB(5.633019127215219690e-01, 3.070716971501701309e-01, 6.191087573569722391e-01),
        RGB(5.388922630410429848e-01, 2.700276638574735100e-01, 5.923009006765995732e-01),
        RGB(5.121182005529967274e-01, 2.346165576727894941e-01, 5.634752525056647698e-01),
        RGB(4.827461836049378729e-01, 2.014304616321936914e-01, 5.324428187371255117e-01),
        RGB(4.511233066836186079e-01, 1.705617177957048647e-01, 4.995004888153025679e-01),
        RGB(4.180000933862609291e-01, 1.415324018359887526e-01, 4.652975085785351905e-01),
        RGB(3.841911983452363510e-01, 1.134918877382977420e-01, 4.305617096124739196e-01),
        RGB(3.503684772212236065e-01, 8.531603060917344883e-02, 3.959457343993016964e-01),
        RGB(3.170584348590873569e-01, 5.515718708797005126e-02, 3.620573876341695585e-01),
        RGB(2.846879783788356377e-01, 2.120036336828947862e-02, 3.295099346165862864e-01),
        RGB(2.535503873992720481e-01, 0.000000000000000000e+00, 2.988424429514020542e-01),
        ],
        "radar", # the category
        "Chase Spectral scheme for dBZ" # some descriptive keywords
        )

    colorschemes[:romaRhoHV] = loadcolorscheme(:romaRhoHV , [
            RGB(0.501412, 0.111589, 0.003827),
            RGB(0.510490, 0.133620, 0.011176),
            RGB(0.519529, 0.153965, 0.017936),
            RGB(0.528514, 0.173192, 0.023941),
            RGB(0.537418, 0.191589, 0.029740),
            RGB(0.546205, 0.209380, 0.036371),
            RGB(0.554865, 0.226705, 0.043275),
            RGB(0.563416, 0.243617, 0.050381),
            RGB(0.571835, 0.260262, 0.057332),
            RGB(0.580145, 0.276650, 0.064287),
            RGB(0.588325, 0.292810, 0.071178),
            RGB(0.596410, 0.308833, 0.077891),
            RGB(0.604386, 0.324676, 0.084709),
            RGB(0.612252, 0.340432, 0.091425),
            RGB(0.620044, 0.356084, 0.098071),
            RGB(0.627742, 0.371641, 0.104624),
            RGB(0.635369, 0.387155, 0.111286),
            RGB(0.642941, 0.402629, 0.117860),
            RGB(0.650464, 0.418074, 0.124428),
            RGB(0.657953, 0.433508, 0.131082),
            RGB(0.665412, 0.448963, 0.137762),
            RGB(0.672873, 0.464433, 0.144496),
            RGB(0.680329, 0.479939, 0.151340),
            RGB(0.687827, 0.495507, 0.158398),
            RGB(0.695366, 0.511166, 0.165603),
            RGB(0.702975, 0.526947, 0.173152),
            RGB(0.710674, 0.542854, 0.181032),
            RGB(0.718485, 0.558920, 0.189387),
            RGB(0.726444, 0.575192, 0.198261),
            RGB(0.734572, 0.591684, 0.207814),
            RGB(0.742889, 0.608418, 0.218131),
            RGB(0.751418, 0.625398, 0.229326),
            RGB(0.760163, 0.642647, 0.241558),
            RGB(0.769138, 0.660138, 0.254901),
            RGB(0.778335, 0.677840, 0.269434),
            RGB(0.787711, 0.695680, 0.285203),
            RGB(0.797224, 0.713566, 0.302268),
            RGB(0.806806, 0.731375, 0.320593),
            RGB(0.816353, 0.748957, 0.340035),
            RGB(0.825755, 0.766142, 0.360474),
            RGB(0.834903, 0.782742, 0.381762),
            RGB(0.843655, 0.798596, 0.403654),
            RGB(0.851905, 0.813544, 0.425906),
            RGB(0.859527, 0.827476, 0.448313),
            RGB(0.866428, 0.840307, 0.470649),
            RGB(0.872531, 0.851993, 0.492717),
            RGB(0.877767, 0.862540, 0.514408),
            RGB(0.882089, 0.871973, 0.535567),
            RGB(0.885456, 0.880350, 0.556154),
            RGB(0.887829, 0.887752, 0.576132),
            RGB(0.889183, 0.894257, 0.595438),
            RGB(0.889474, 0.899939, 0.614094),
            RGB(0.888675, 0.904879, 0.632101),
            RGB(0.886743, 0.909141, 0.649445),
            RGB(0.883645, 0.912793, 0.666117),
            RGB(0.879342, 0.915870, 0.682122),
            RGB(0.873812, 0.918420, 0.697447),
            RGB(0.867026, 0.920459, 0.712073),
            RGB(0.858974, 0.922011, 0.725980),
            RGB(0.849654, 0.923073, 0.739148),
            RGB(0.839064, 0.923648, 0.751554),
            RGB(0.827233, 0.923728, 0.763181),
            RGB(0.814185, 0.923298, 0.774030),
            RGB(0.799970, 0.922340, 0.784100),
            RGB(0.799970, 0.922340, 0.784100),
            RGB(0.792431, 0.921655, 0.788832),
            RGB(0.792431, 0.921655, 0.788832),
            RGB(0.784623, 0.920824, 0.793371),
            RGB(0.776542, 0.919856, 0.797707),
            RGB(0.776542, 0.919856, 0.797707),
            RGB(0.768196, 0.918734, 0.801854),
            RGB(0.759602, 0.917467, 0.805806),
            RGB(0.759602, 0.917467, 0.805806),
            RGB(0.750772, 0.916029, 0.809568),
            RGB(0.741691, 0.914442, 0.813132),
            RGB(0.741691, 0.914442, 0.813132),
            RGB(0.732395, 0.912681, 0.816514),
            RGB(0.722868, 0.910753, 0.819696),
            RGB(0.722868, 0.910753, 0.819696),
            RGB(0.713142, 0.908647, 0.822701),
            RGB(0.703222, 0.906364, 0.825512),
            RGB(0.703222, 0.906364, 0.825512),
            RGB(0.693114, 0.903893, 0.828140),
            RGB(0.682827, 0.901238, 0.830587),
            RGB(0.682827, 0.901238, 0.830587),
            RGB(0.672388, 0.898390, 0.832843),
            RGB(0.661799, 0.895352, 0.834922),
            RGB(0.661799, 0.895352, 0.834922),
            RGB(0.651074, 0.892115, 0.836817),
            RGB(0.640238, 0.888678, 0.838527),
            RGB(0.640238, 0.888678, 0.838527),
            RGB(0.629296, 0.885038, 0.840063),
            RGB(0.618282, 0.881200, 0.841411),
            RGB(0.618282, 0.881200, 0.841411),
            RGB(0.607206, 0.877157, 0.842583),
            RGB(0.596077, 0.872922, 0.843568),
            RGB(0.596077, 0.872922, 0.843568),
            RGB(0.584937, 0.868490, 0.844384),
            RGB(0.573789, 0.863858, 0.845020),
            RGB(0.573789, 0.863858, 0.845020),
            RGB(0.562674, 0.859031, 0.845478),
            RGB(0.551593, 0.854022, 0.845762),
            RGB(0.551593, 0.854022, 0.845762),
            RGB(0.540580, 0.848838, 0.845876),
            RGB(0.529662, 0.843474, 0.845820),
            RGB(0.529662, 0.843474, 0.845820),
            RGB(0.518858, 0.837953, 0.845599),
            RGB(0.508186, 0.832268, 0.845215),
            RGB(0.508186, 0.832268, 0.845215),
            RGB(0.497670, 0.826435, 0.844672),
            RGB(0.487327, 0.820459, 0.843969),
            RGB(0.487327, 0.820459, 0.843969),
            RGB(0.477178, 0.814357, 0.843121),
            RGB(0.467254, 0.808137, 0.842130),
            RGB(0.467254, 0.808137, 0.842130),
            RGB(0.457548, 0.801802, 0.840993),
            RGB(0.448093, 0.795369, 0.839727),
            RGB(0.448093, 0.795369, 0.839727),
            RGB(0.438894, 0.788850, 0.838326),
            RGB(0.429973, 0.782245, 0.836809),
            RGB(0.429973, 0.782245, 0.836809),
            RGB(0.421314, 0.775567, 0.835174),
            RGB(0.412960, 0.768827, 0.833431),
            RGB(0.412960, 0.768827, 0.833431),
            RGB(0.404865, 0.762037, 0.831588),
            RGB(0.397070, 0.755206, 0.829645),
            RGB(0.397070, 0.755206, 0.829645),
            RGB(0.389570, 0.748331, 0.827608),
            RGB(0.382350, 0.741419, 0.825492),
            RGB(0.382350, 0.741419, 0.825492),
            RGB(0.375417, 0.734495, 0.823301),
            RGB(0.368773, 0.727543, 0.821037),
            RGB(0.368773, 0.727543, 0.821037),
            RGB(0.362383, 0.720579, 0.818704),
            RGB(0.356266, 0.713610, 0.816321),
            RGB(0.356266, 0.713610, 0.816321),
            RGB(0.350401, 0.706638, 0.813871),
            RGB(0.344767, 0.699655, 0.811381),
            RGB(0.344767, 0.699655, 0.811381),
            RGB(0.339388, 0.692690, 0.808842),
            RGB(0.334215, 0.685718, 0.806262),
            RGB(0.334215, 0.685718, 0.806262),
            RGB(0.329259, 0.678754, 0.803644),
            RGB(0.324478, 0.671805, 0.800996),
            RGB(0.324478, 0.671805, 0.800996),
            RGB(0.319917, 0.664865, 0.798319),
            RGB(0.315514, 0.657949, 0.795616),
            RGB(0.315514, 0.657949, 0.795616),
            RGB(0.311269, 0.651037, 0.792896),
            RGB(0.307176, 0.644139, 0.790151),
            RGB(0.307176, 0.644139, 0.790151),
            RGB(0.303223, 0.637270, 0.787394),
            RGB(0.299421, 0.630415, 0.784624),
            RGB(0.299421, 0.630415, 0.784624),
            RGB(0.295709, 0.623578, 0.781839),
            RGB(0.292126, 0.616757, 0.779042),
            RGB(0.292126, 0.616757, 0.779042),
            RGB(0.288637, 0.609952, 0.776243),
            RGB(0.285227, 0.603177, 0.773433),
            RGB(0.285227, 0.603177, 0.773433),
            RGB(0.281932, 0.596418, 0.770627),
            RGB(0.278695, 0.589674, 0.767809),
            RGB(0.278695, 0.589674, 0.767809),
            RGB(0.275536, 0.582959, 0.765001),
            RGB(0.272407, 0.576276, 0.762181),
            RGB(0.272407, 0.576276, 0.762181),
            RGB(0.269386, 0.569588, 0.759366),
            RGB(0.266385, 0.562945, 0.756558),
            RGB(0.266385, 0.562945, 0.756558),
            RGB(0.263447, 0.556303, 0.753748),
            RGB(0.260532, 0.549699, 0.750948),
            RGB(0.260532, 0.549699, 0.750948),
            RGB(0.257663, 0.543111, 0.748143),
            RGB(0.254858, 0.536546, 0.745342),
            RGB(0.254858, 0.536546, 0.745342),
            RGB(0.252055, 0.529996, 0.742553),
            RGB(0.249280, 0.523472, 0.739769),
            RGB(0.249280, 0.523472, 0.739769),
            RGB(0.246538, 0.516968, 0.736982),
            RGB(0.243816, 0.510478, 0.734207),
            RGB(0.243816, 0.510478, 0.734207),
            RGB(0.241139, 0.504023, 0.731435),
            RGB(0.238460, 0.497585, 0.728673),
            RGB(0.238460, 0.497585, 0.728673),
            RGB(0.235832, 0.491168, 0.725921),
            RGB(0.233172, 0.484751, 0.723166),
            RGB(0.233172, 0.484751, 0.723166),
            RGB(0.230563, 0.478376, 0.720425),
            RGB(0.227981, 0.472024, 0.717696),
            RGB(0.227981, 0.472024, 0.717696),
            RGB(0.225380, 0.465671, 0.714962),
            RGB(0.222818, 0.459363, 0.712240),
            RGB(0.222818, 0.459363, 0.712240),
            RGB(0.220261, 0.453062, 0.709531),
            RGB(0.217698, 0.446780, 0.706824),
            RGB(0.217698, 0.446780, 0.706824),
            RGB(0.215140, 0.440515, 0.704119),
            RGB(0.212618, 0.434272, 0.701424),
            RGB(0.212618, 0.434272, 0.701424),
            RGB(0.210094, 0.428057, 0.698736),
            RGB(0.207584, 0.421842, 0.696062),
            RGB(0.207584, 0.421842, 0.696062),
            RGB(0.205069, 0.415662, 0.693386),
            RGB(0.202559, 0.409496, 0.690714),
            RGB(0.202559, 0.409496, 0.690714),
            RGB(0.200048, 0.403347, 0.688058),
            RGB(0.197574, 0.397204, 0.685404),
            RGB(0.197574, 0.397204, 0.685404),
            RGB(0.195089, 0.391098, 0.682752),
            RGB(0.192594, 0.384984, 0.680105),
            RGB(0.192594, 0.384984, 0.680105),
            RGB(0.190104, 0.378904, 0.677478),
            RGB(0.187646, 0.372830, 0.674840),
            RGB(0.187646, 0.372830, 0.674840),
            RGB(0.185147, 0.366784, 0.672216),
            RGB(0.182620, 0.360728, 0.669595),
            RGB(0.182620, 0.360728, 0.669595),
            RGB(0.180129, 0.354723, 0.666972),
            RGB(0.177660, 0.348701, 0.664362),
            RGB(0.177660, 0.348701, 0.664362),
            RGB(0.175131, 0.342707, 0.661761),
            RGB(0.172593, 0.336706, 0.659150),
            RGB(0.172593, 0.336706, 0.659150),
            RGB(0.170075, 0.330723, 0.656558),
            RGB(0.167525, 0.324753, 0.653958),
            RGB(0.167525, 0.324753, 0.653958),
            RGB(0.164939, 0.318804, 0.651369),
            RGB(0.162384, 0.312849, 0.648780),
            RGB(0.162384, 0.312849, 0.648780),
            RGB(0.159737, 0.306914, 0.646193),
            RGB(0.157120, 0.300970, 0.643609),
            RGB(0.157120, 0.300970, 0.643609),
            RGB(0.154458, 0.295044, 0.641030),
            RGB(0.151760, 0.289137, 0.638458),
            RGB(0.151760, 0.289137, 0.638458),
            RGB(0.149038, 0.283217, 0.635885),
            RGB(0.146267, 0.277303, 0.633315),
            RGB(0.146267, 0.277303, 0.633315),
            RGB(0.143460, 0.271380, 0.630749),
            RGB(0.140601, 0.265474, 0.628180),
            RGB(0.140601, 0.265474, 0.628180),
            RGB(0.137689, 0.259574, 0.625609),
            RGB(0.134704, 0.253654, 0.623048),
            RGB(0.134704, 0.253654, 0.623048),
            RGB(0.131632, 0.247744, 0.620488),
            RGB(0.128492, 0.241818, 0.617918),
            RGB(0.128492, 0.241818, 0.617918),
            RGB(0.125280, 0.235896, 0.615354),
            RGB(0.121937, 0.229930, 0.612792),
            RGB(0.121937, 0.229930, 0.612792),
            RGB(0.118594, 0.223993, 0.610234),
            RGB(0.115017, 0.218053, 0.607680),
            RGB(0.115017, 0.218053, 0.607680),
            RGB(0.111419, 0.212093, 0.605113),
            RGB(0.107611, 0.206110, 0.602552),
            RGB(0.107611, 0.206110, 0.602552),
        ],
        "radar", # the category
        "crameri-michelson-roma-rhohv" # some descriptive keywords
        )

end
