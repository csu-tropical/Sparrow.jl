@workflow_step PassThroughStep
function workflow_step(workflow::SparrowWorkflow, ::Type{PassThroughStep}, input_dir::String, output_dir::String;
    step_name="PassThroughStep", start_time::DateTime, stop_time::DateTime, kwargs...)

    # Pass through to next step regardless of time
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for input_file in input_files
        output_file = replace(input_file, input_dir => output_dir)
        cp(input_file, output_file, follow_symlinks=true)
    end
end

@workflow_step filterByTimeStep
function workflow_step(workflow::SparrowWorkflow, ::Type{filterByTimeStep}, input_dir::String, output_dir::String;
    step_name="filterByTimeStep", start_time::DateTime, stop_time::DateTime, kwargs...)

    # Pass through if within the time limit
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for input_file in input_files
        scan_start = get_scan_start(input_file)
        msg_debug("Checking $(input_file) at $(Dates.format(scan_start, "YYYYmmdd HHMM"))")
        if scan_start < start_time || scan_start >= stop_time
            msg_debug("Skipping $(input_file)")
            continue
        else
            output_file = replace(input_file, input_dir => output_dir)
            cp(input_file, output_file, follow_symlinks=true)
        end
    end
end

"""
    get_scan_start(file) → DateTime

Get the start time of a radar scan file.

The primary path uses RadxPrint, which works with any format it supports
(CfRadial-1, Sigmet, DORADE, UF, and 30+ others); requires `RadxPrint` on PATH.
When RadxPrint cannot supply the volume start time — notably for CfRadial 2.0
(`cfrad2.*`) files, where lrose leaves it unset — the canonical
`time_coverage_start` global attribute is read directly via NCDatasets.

# Arguments
- `file`: Path to a radar data file

# Returns
- `DateTime` of the scan start time, or `DateTime(1970, 1, 1)` if it cannot be
  determined (so callers' time-window filters skip the file).

# Example
```julia
scan_time = get_scan_start("/path/to/cfrad.20240101_120000.nc")
```
"""
function get_scan_start(file)
    # Primary: RadxPrint reads many radar formats and reports the volume start as
    # `startTimeSecs: YYYY/mm/dd HH:MM:SS`.
    radxprint_err = nothing
    try
        meta = readchomp(`RadxPrint -meta_only -f $file`)
        m = match(r"startTimeSecs:\s*(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2})", meta)
        m === nothing || return DateTime(m.captures[1], dateformat"YYYY/mm/dd HH:MM:SS")
    catch e
        radxprint_err = e
    end
    # Fallback for CfRadial 2.0 (cfrad2.*): lrose leaves the volume start unset
    # ("===== NOT SET ====="), so read the standard `time_coverage_start` global
    # attribute (ISO 8601). CfRadial 2.0 files are always NetCDF, so this is only
    # attempted when RadxPrint itself ran but did not report a start time.
    if radxprint_err === nothing
        try
            iso = NCDataset(file) do ds
                get(ds.attrib, "time_coverage_start", nothing)
            end
            if iso isa AbstractString
                m = match(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}", iso)
                m === nothing || return DateTime(m.match)
            end
        catch
            # fall through to the warning below
        end
    end
    msg_warning("Could not determine scan start time for $file" *
                (radxprint_err === nothing ? "" : "; RadxPrint failed: $radxprint_err"))
    # Return a far-past date so callers' time-window filters skip this file
    return DateTime(1970, 1, 1)
end

"""
    get_scan_name(file) → String

Read the `scan_name` global attribute from a CfRadial file without loading the
full volume. Returns an empty string if the attribute is missing or the file
cannot be read.
"""
function get_scan_name(file)
    try
        name = NCDataset(file) do ds
            get(ds.attrib, "scan_name", "")
        end
        return strip(String(name))
    catch e
        msg_warning("Could not read scan_name from $file: $e")
        return ""
    end
end

"""
    safe_exception_string(e) -> String

Stringify an exception for logging without letting the formatting itself throw.
Some errors raised on workers embed objects (e.g. Makie/ComputePipeline
internals) whose own `show` method throws, so naively interpolating `\$e` would
crash the error-handling path and mask the original failure. Falls back to the
captured exception's type (and worker pid) when the full message is unprintable.
"""
function safe_exception_string(e)
    try
        return sprint(showerror, e)
    catch
    end
    try
        if e isa RemoteException
            cap = e.captured.ex
            return "remote $(typeof(cap)) on worker $(e.pid) (full message unprintable)"
        end
    catch
    end
    return string(typeof(e))
end
