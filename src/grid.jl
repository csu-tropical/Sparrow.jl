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

@workflow_step GridRHIStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridRHIStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)
    warn_legacy_grid_params(workflow)

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            for i in eachindex(volume.sweeps)
                output_file = joinpath(output_dir,
                    grid_output_name("rhi", scan_start, volume.sweeps[i].fixed_angle))
                msg_info("Gridding RHI $output_file")
                flush(stdout)
                @time Daisho.grid_radar_rhi(single_sweep_volume(volume, i),
                    output_file, scan_start, daisho_params)
            end
        end
    end
end

@workflow_step GridCompositeStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridCompositeStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)
    warn_legacy_grid_params(workflow)

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if !contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            output_file = joinpath(output_dir, grid_output_name("composite", scan_start))
            msg_info("Gridding composite $output_file")
            flush(stdout)
            @time Daisho.grid_radar_composite(volume, output_file, scan_start,
                daisho_params; mean_heading=mean_volume_heading(volume))
        end
    end
end

@workflow_step GridVolumeStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridVolumeStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)
    warn_legacy_grid_params(workflow)

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if !contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            output_file = joinpath(output_dir, grid_output_name("volume", scan_start))
            msg_info("Gridding volume $output_file")
            flush(stdout)
            @time Daisho.grid_radar_volume(volume, output_file, scan_start,
                daisho_params; heading=mean_volume_heading(volume))
        end
    end
end

@workflow_step GridLatlonStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridLatlonStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)
    warn_legacy_grid_params(workflow)

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if !contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            output_file = joinpath(output_dir, grid_output_name("latlon", scan_start))
            msg_info("Gridding lat-lon volume $output_file")
            flush(stdout)
            @time Daisho.grid_radar_latlon_volume(volume, output_file, scan_start,
                daisho_params; heading=mean_volume_heading(volume))
        end
    end
end

@workflow_step GridPPIStep
function workflow_step(workflow::SparrowWorkflow, ::Type{GridPPIStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)
    warn_legacy_grid_params(workflow)
    max_ppi_angle = workflow["max_ppi_angle"]

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if !contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            heading = mean_volume_heading(volume)
            for i in eachindex(volume.sweeps)
                angle = volume.sweeps[i].fixed_angle
                if angle <= max_ppi_angle
                    output_file = joinpath(output_dir,
                        grid_output_name("ppi", scan_start, angle))
                    msg_info("Gridding PPI $output_file")
                    @time Daisho.grid_radar_ppi(single_sweep_volume(volume, i),
                        output_file, scan_start, daisho_params; heading=heading)
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
    min_qvp_angle = workflow["min_qvp_angle"]

    for (file, scan_start) in grid_input_files(input_dir, start_time, stop_time)
        if !contains(file, "RHI")
            volume = Daisho.read_cfradial(file)
            for i in eachindex(volume.sweeps)
                angle = volume.sweeps[i].fixed_angle
                if angle >= min_qvp_angle
                    output_file = joinpath(output_dir,
                        grid_output_name("qvp", scan_start, angle))
                    msg_info("Gridding QVP $output_file")
                    @time Daisho.grid_radar_column(single_sweep_volume(volume, i),
                        output_file, scan_start, daisho_params)
                end
            end
        end
    end
end
