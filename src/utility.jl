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

Get the start time of a radar scan file using RadxPrint.

Works with any file format supported by RadxPrint (CfRadial, Sigmet, DORADE,
UF, and 30+ other radar formats). Requires `RadxPrint` to be available on PATH.

# Arguments
- `file`: Path to a radar data file

# Returns
- `DateTime` of the scan start time

# Example
```julia
scan_time = get_scan_start("/path/to/cfrad.20240101_120000.nc")
```
"""
function get_scan_start(file)
    try
        cmd_output = readchomp(pipeline(`RadxPrint -meta_only -f $file`, `grep startTimeSecs`))
        if length(cmd_output) >= 18
            return DateTime(cmd_output[18:end], dateformat"YYYY/mm/dd HH:MM:SS")
        else
            msg_warning("RadxPrint output too short for $file: '$cmd_output'")
        end
    catch e
        msg_warning("Error running RadxPrint on $file: $e")
    end
    # Return a far-past date so callers' time-window filters skip this file
    return DateTime(1970, 1, 1)
end
