# Gridding helper functions and workflow steps
#
# All grid geometry, interpolation, and field configuration comes from the
# Daisho TOML configuration referenced by the workflow's `daisho_config`
# parameter (see `get_daisho_params`). The steps here only select files and
# sweeps, name the output products, and dispatch to Daisho.

# Workflow parameters that configured the old positional-argument Daisho API.
# They are ignored now that grid configuration lives in the Daisho TOML.
const LEGACY_GRID_PARAMS = ["rmin", "rincr", "rdim", "rhi_zmin", "rhi_zincr", "rhi_zdim",
    "long_xmin", "long_xincr", "long_xdim", "long_ymin", "long_yincr", "long_ydim",
    "vol_xmin", "vol_xincr", "vol_xdim", "vol_ymin", "vol_yincr", "vol_ydim",
    "latmin", "latdim", "lonmin", "londim", "degincr", "zmin", "zincr", "zdim",
    "beam_inflation", "power_threshold", "ppi_power_threshold",
    "rhi_power_threshold", "qvp_power_threshold", "missing_key", "valid_key",
    "grid_type_dict", "moment_grid_type"]

function warn_legacy_grid_params(workflow::SparrowWorkflow)
    found = filter(k -> haskey(workflow.params, k), LEGACY_GRID_PARAMS)
    isempty(found) || msg_warning("Ignoring legacy grid parameters: $(join(found, ", ")). " *
        "Grid configuration now comes from the Daisho TOML file (`daisho_config`).")
end

"""
    single_sweep_volume(vol::Volume, i::Integer) → Volume

Copy of `vol` containing only sweep `i`, with all volume-level metadata
carried over. Used to grid RHI/PPI sweeps as individual products.
"""
single_sweep_volume(vol::Volume, i::Integer) =
    Volume((f === :sweeps ? [vol.sweeps[i]] : getfield(vol, f)
            for f in fieldnames(Volume))...)

# CfRadial `sweep_mode` values whose `fixed_angle` is not an elevation angle.
# The full enumeration is the one Daisho writes as the `options` attribute of the
# sweep_mode variable: sector, coplane, rhi, vertical_pointing, idle,
# azimuth_surveillance, elevation_surveillance, sunscan, pointing, calibration,
# manual_ppi, manual_rhi, sunscan_rhi, doppler_beam_swinging, complex_trajectory,
# electronic_steering. The elevation-scanning modes below hold the sweep azimuth
# in `fixed_angle`; `coplane` holds the coplane rotation angle about the
# baseline. Either way the value is not an elevation, so the PPI/QVP thresholds
# cannot be applied to it.
const NON_ELEVATION_SWEEP_MODES = ("rhi", "manual_rhi", "sunscan_rhi",
    "elevation_surveillance", "coplane")

"""
    is_rhi_sweep(sweep) → Bool

True when `sweep`'s `fixed_angle` is not an elevation angle: the elevation-
scanning modes (`rhi`, `manual_rhi`, `sunscan_rhi`, `elevation_surveillance`),
which store the sweep azimuth there, and `coplane`, which stores the coplane
rotation angle. An elevation threshold (`max_ppi_angle`, `min_qvp_angle`) must
never be compared against those values.
"""
is_rhi_sweep(sweep) = lowercase(strip(sweep.sweep_mode)) in NON_ELEVATION_SWEEP_MODES

"""
    sweep_elevation_angle(sweep, product, file, i) → Union{Float64,Nothing}

Elevation angle of sweep `i` for the elevation-thresholded products (PPI, QVP),
or `nothing` when the sweep has no usable elevation and must be skipped.

Two cases are rejected, both with a warning naming the file and sweep, since
either would otherwise pass or fail the threshold silently:

- a sweep whose `fixed_angle` is not an elevation (see [`is_rhi_sweep`]). The
  step's filename check only catches RHI *volumes* named "RHI"; this catches RHI
  sweeps embedded in a volume whose name does not say so.
- a missing `fixed_angle`, read back as `NaN`. Every comparison with `NaN` is
  false, so the sweep would be dropped with no explanation.
"""
function sweep_elevation_angle(sweep, product::String, file::String, i::Integer)
    if is_rhi_sweep(sweep)
        msg_warning("Skipping $(product) for sweep $i of $(basename(file)): " *
            "sweep_mode is \"$(sweep.sweep_mode)\", so fixed_angle " *
            "($(sweep.fixed_angle)) is not an elevation angle.")
        return nothing
    end
    angle = sweep.fixed_angle
    if isnan(angle)
        msg_warning("Skipping $(product) for sweep $i of $(basename(file)): " *
            "fixed_angle is missing (NaN), so its elevation cannot be checked.")
        return nothing
    end
    return angle
end

"""
    mean_volume_heading(vol::Volume) → Float64

Mean platform heading across all rays of all sweeps, from the per-sweep
georeference. Returns Daisho's `-9999.0` missing sentinel when no heading
information is present (fixed platforms).
"""
function mean_volume_heading(vol::Volume)
    headings = Float64[]
    for sweep in vol.sweeps
        georef = sweep.georeference
        if georef !== nothing && georef.heading !== nothing
            append!(headings, georef.heading)
        end
    end
    return isempty(headings) ? -9999.0 : mean(headings)
end

# Output product name: per-scan time with second precision so scans that fall
# within the same processing chunk (or same minute) do not overwrite each other
grid_output_name(kind::String, scan_start::DateTime) =
    "gridded_$(kind)_" * Dates.format(scan_start, "YYYYmmdd_HHMMSS") * ".nc"
grid_output_name(kind::String, scan_start::DateTime, angle::Real) =
    "gridded_$(kind)_" * Dates.format(scan_start, "YYYYmmdd_HHMMSS") *
    "_" * @sprintf("%.1f", angle) * ".nc"

# Files within the step's time window, non-directories only
function grid_input_files(input_dir::String, start_time::DateTime, stop_time::DateTime)
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    selected = Tuple{String,DateTime}[]
    for file in input_files
        scan_start = get_scan_start(file)
        msg_debug("Checking $file at $(Dates.format(scan_start, "YYYYmmdd HHMMSS"))")
        if scan_start < start_time || scan_start >= stop_time
            msg_debug("Skipping $file")
            continue
        end
        push!(selected, (file, scan_start))
    end
    return selected
end

# Time coordinate written into the gridded product, selected by the workflow's
# `index_time` parameter (see `resolve_index_time`). The output filename always
# uses `scan_start` regardless, so scans sharing an analysis increment do not
# collide.
grid_index_time(mode::Symbol, scan_start::DateTime, start_time::DateTime, stop_time::DateTime) =
    mode === :scan_start ? scan_start :
    mode === :start_time ? start_time : stop_time

@workflow_step GridRHIStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridRHIStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)
    warn_legacy_grid_params(workflow)
    index_mode = resolve_index_time(workflow)

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            grid_time = grid_index_time(index_mode, scan_start, start_time, stop_time)
            for i in eachindex(volume.sweeps)
                output_file = joinpath(output_dir,
                    grid_output_name("rhi", scan_start, volume.sweeps[i].fixed_angle))
                msg_info("Gridding RHI $output_file")
                flush(stdout)
                @time Daisho.grid_radar_rhi(single_sweep_volume(volume, i),
                    output_file, grid_time, daisho_params)
            end
        end
    end
end

@workflow_step GridCompositeStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridCompositeStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)
    warn_legacy_grid_params(workflow)
    index_mode = resolve_index_time(workflow)

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if !contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            grid_time = grid_index_time(index_mode, scan_start, start_time, stop_time)
            output_file = joinpath(output_dir, grid_output_name("composite", scan_start))
            msg_info("Gridding composite $output_file")
            flush(stdout)
            @time Daisho.grid_radar_composite(volume, output_file, grid_time,
                daisho_params; mean_heading=mean_volume_heading(volume))
        end
    end
end

@workflow_step GridVolumeStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridVolumeStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)
    warn_legacy_grid_params(workflow)
    index_mode = resolve_index_time(workflow)

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if !contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            grid_time = grid_index_time(index_mode, scan_start, start_time, stop_time)
            output_file = joinpath(output_dir, grid_output_name("volume", scan_start))
            msg_info("Gridding volume $output_file")
            flush(stdout)
            @time Daisho.grid_radar_volume(volume, output_file, grid_time,
                daisho_params; heading=mean_volume_heading(volume))
        end
    end
end

@workflow_step GridLatlonStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridLatlonStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)
    warn_legacy_grid_params(workflow)
    index_mode = resolve_index_time(workflow)

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if !contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            grid_time = grid_index_time(index_mode, scan_start, start_time, stop_time)
            output_file = joinpath(output_dir, grid_output_name("latlon", scan_start))
            msg_info("Gridding lat-lon volume $output_file")
            flush(stdout)
            @time Daisho.grid_radar_latlon_volume(volume, output_file, grid_time,
                daisho_params; heading=mean_volume_heading(volume))
        end
    end
end

@workflow_step GridPPIStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridPPIStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)
    warn_legacy_grid_params(workflow)
    index_mode = resolve_index_time(workflow)
    max_ppi_angle = workflow["max_ppi_angle"]

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if !contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            heading = mean_volume_heading(volume)
            grid_time = grid_index_time(index_mode, scan_start, start_time, stop_time)
            for i in eachindex(volume.sweeps)
                angle = sweep_elevation_angle(volume.sweeps[i], "PPI", file, i)
                angle === nothing && continue
                if angle <= max_ppi_angle
                    output_file = joinpath(output_dir,
                        grid_output_name("ppi", scan_start, angle))
                    msg_info("Gridding PPI $output_file")
                    @time Daisho.grid_radar_ppi(single_sweep_volume(volume, i),
                        output_file, grid_time, daisho_params; heading=heading)
                end
            end
        end
    end
end

@workflow_step GridQVPStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridQVPStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)
    warn_legacy_grid_params(workflow)
    index_mode = resolve_index_time(workflow)
    min_qvp_angle = workflow["min_qvp_angle"]

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if !contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            grid_time = grid_index_time(index_mode, scan_start, start_time, stop_time)
            for i in eachindex(volume.sweeps)
                angle = sweep_elevation_angle(volume.sweeps[i], "QVP", file, i)
                angle === nothing && continue
                if angle >= min_qvp_angle
                    output_file = joinpath(output_dir,
                        grid_output_name("qvp", scan_start, angle))
                    msg_info("Gridding QVP $output_file")
                    @time Daisho.grid_radar_column(single_sweep_volume(volume, i),
                        output_file, grid_time, daisho_params)
                end
            end
        end
    end
end
