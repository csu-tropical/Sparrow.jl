# IO helper functions and workflow steps

function initialize_working_dirs(workflow::SparrowWorkflow, date;
                                  start_time::DateTime=DateTime(1970), stop_time::DateTime=DateTime(2100))

    # Set up the working directories
    base_working_dir = workflow["base_working_dir"]
    steps = length(workflow["steps"])
    temp_dir = joinpath(base_working_dir, randstring(6))
    mkpath(temp_dir)

    # This directory holds raw data from the base_data_dir, which may be in SIGMET format or already converted to CfRadial
    working_dir = joinpath(temp_dir, "base_data", date)
    mkpath(working_dir)
    link_base_data(date, workflow, working_dir; start_time=start_time, stop_time=stop_time)

    for (step_name, step_type, input_name, archive) in workflow["steps"]
        step_dir = joinpath(temp_dir, step_name, date)
        mkpath(step_dir)
    end

    return temp_dir
end

function archive_workflow(workflow::SparrowWorkflow, temp_dir, date)

    msg_info("Archiving the processed data...")
    flush(stdout)

    processed_files = String[]
    archive_dir = workflow["base_archive_dir"]

    # Make sure the archive directory exists
    mkpath(archive_dir)

    force = workflow["force_reprocess"]
    for (step_name, step_type, input_name, archive) in workflow["steps"]
        if archive
            step_dir = joinpath(temp_dir, step_name, date)
            step_files = readdir(step_dir; join=true)
            filter!(!isdir,step_files)
            append!(processed_files, step_files)
            step_archive_dir = joinpath(archive_dir, step_name, date)
            mkpath(step_archive_dir)
            msg_debug("Archiving $(step_files) to $(step_archive_dir)...")
            archive_files(step_files, step_archive_dir, force)
        end
    end

    return processed_files
end

function link_base_data(date, workflow, raw_working_dir;
                        start_time::DateTime=DateTime(1970), stop_time::DateTime=DateTime(2100))

    base_archive_dir = workflow["base_archive_dir"]
    force_reprocess = workflow["force_reprocess"]
    # When set, a missing .sparrow marker is reconciled against existing archived
    # products (see `archived_output_exists`): if every archive step already has
    # output for this scan, write the marker and skip. Default false, consistent
    # with the conservative abort mode — recovers pre-marker broken runs without
    # reprocessing already-finished volumes.
    reconcile = get_param(workflow, "reconcile_markers", false)
    source = get_data_source(workflow)

    if is_remote(source)
        # Remote source: discover files, filter by time window, download into
        # base_data_dir as a local cache, then symlink into the working directory
        base_data_dir = workflow["base_data_dir"]
        cache_dir = joinpath(base_data_dir, date)
        mkpath(cache_dir)
        remote_files = discover_files(source, date)
        # Filter by time window to avoid downloading the entire day
        if start_time > DateTime(1970) && stop_time < DateTime(2100)
            remote_files = _filter_files_by_time(remote_files, start_time, stop_time)
            msg_info("Filtered to $(length(remote_files)) files in time window $(start_time) to $(stop_time)")
        end
        for filename in remote_files
            fname = basename(filename)
            if !force_reprocess
                if check_processed(workflow, fname, base_archive_dir)
                    msg_debug("File $fname already processed by $(typeof(workflow)), skipping...")
                    continue
                elseif reconcile
                    # File not downloaded yet; key reconcile off the filename time.
                    scan_start = _parse_filename_time(fname)
                    if scan_start !== nothing && archived_output_exists(workflow, scan_start, date)
                        mark_processed(workflow, [fname], base_archive_dir)
                        msg_info("Reconciled $fname: products already archived, marking processed and skipping")
                        continue
                    end
                end
            end
            cached_file = joinpath(cache_dir, fname)
            if !isfile(cached_file)
                try
                    fetch_file(source, fname, cache_dir, date)
                catch e
                    msg_warning("Failed to fetch $fname: $(safe_exception_string(e))")
                    continue
                end
            else
                msg_debug("File $fname already cached in $cache_dir")
            end
            # Symlink cached file into working directory
            link = joinpath(raw_working_dir, fname)
            if !islink(link) && !isfile(link)
                symlink(cached_file, link)
            end
        end
    else
        # Local source: symlink files
        base_data_dir = source.base_dir
        data_dir = joinpath(base_data_dir, date)
        if !isdir(data_dir)
            msg_warning("Local data directory $data_dir does not exist")
            return
        end
        data_files = readdir(data_dir; join=true)
        filter!(!isdir, data_files)
        # Filter by time window so chunked runs only see their own files
        if start_time > DateTime(1970) && stop_time < DateTime(2100)
            data_files = _filter_files_by_time(data_files, start_time, stop_time)
        end
        for file in data_files
            if !force_reprocess
                if check_processed(workflow, file, base_archive_dir)
                    msg_debug("File $(basename(file)) already processed by $(typeof(workflow)), skipping...")
                    continue
                elseif reconcile
                    scan_start = get_scan_start(file)
                    if scan_start > DateTime(1970) && archived_output_exists(workflow, scan_start, date)
                        mark_processed(workflow, [file], base_archive_dir)
                        msg_info("Reconciled $(basename(file)): products already archived, marking processed and skipping")
                        continue
                    end
                end
            end
            link = joinpath(raw_working_dir, basename(file))
            symlink(file, link)
        end
    end
end

"""
    archived_output_exists(workflow, scan_start::DateTime, date) -> Bool

True if **any** archive step already has an output product for the scan at
`scan_start` on `date`. Gridded products embed the scan time as
`..._<YYYYmmdd_HHMMSS>...` (see `grid_output_name`), so a file in an archive
step's dir whose name contains that timestamp marks that scan as archived.

"Any" rather than "all" because a single scan only produces a subset of the
configured archive products (a PPI scan yields ppi/composite/volume/latlon but
no rhi; an RHI scan yields only rhi), so requiring every archive step would
almost never match. Archiving is per-chunk and atomic-ish — all of a completed
chunk's products move together at the end of `process_volume` — so the presence
of any product for a scan reliably means that scan's chunk finished. (The only
gap is a crash *during* the archive move itself, a narrow window; force-reprocess
a suspect date if needed.) Returns false if no archive step has matching output.
"""
function archived_output_exists(workflow::SparrowWorkflow, scan_start::DateTime, date)
    archive_dir = workflow["base_archive_dir"]
    stamp = Dates.format(scan_start, "YYYYmmdd_HHMMSS")
    for (step_name, step_type, input_name, archive) in workflow["steps"]
        archive || continue
        step_dir = joinpath(archive_dir, step_name, date)
        isdir(step_dir) || continue
        any(f -> occursin(stamp, f), readdir(step_dir)) && return true
    end
    return false
end

"""
    _parse_filename_time(filename) → DateTime or nothing

Extract a datetime from common meteorological data filename patterns:
- NEXRAD: `KEVX20181010_142033_V06` → 2018-10-10T14:20:33
- MRMS:   `MRMS_..._20201014-210000.grib2.gz` → 2020-10-14T21:00:00
- CfRadial: `cfrad.20181010_142033...` → 2018-10-10T14:20:33
- Generic: any `YYYYmmdd_HHMMSS` or `YYYYmmdd-HHMMSS` pattern in the filename
"""
function _parse_filename_time(filename::String)
    # Try NEXRAD pattern: 4-letter station + YYYYmmdd_HHMMSS
    m = match(r"[A-Z]{4}(\d{8})_(\d{6})", filename)
    if m !== nothing
        return DateTime(m.captures[1] * m.captures[2], dateformat"YYYYmmddHHMMSS")
    end
    # Try MRMS/generic pattern: YYYYmmdd-HHMMSS
    m = match(r"(\d{8})-(\d{6})", filename)
    if m !== nothing
        return DateTime(m.captures[1] * m.captures[2], dateformat"YYYYmmddHHMMSS")
    end
    # Try CfRadial/generic pattern: YYYYmmdd_HHMMSS
    m = match(r"(\d{8})_(\d{6})", filename)
    if m !== nothing
        return DateTime(m.captures[1] * m.captures[2], dateformat"YYYYmmddHHMMSS")
    end
    return nothing
end

"""
    _filter_files_by_time(files, start_time, stop_time) → Vector{String}

Filter a list of filenames to those whose embedded timestamp falls within
[start_time, stop_time). Files without a parseable timestamp are included
(to avoid silently dropping data with unexpected naming).
"""
function _filter_files_by_time(files::Vector{String}, start_time::DateTime, stop_time::DateTime)
    filtered = String[]
    for f in files
        t = _parse_filename_time(f)
        if t === nothing
            # Can't parse time — include to be safe
            push!(filtered, f)
        elseif t >= start_time && t < stop_time
            push!(filtered, f)
        end
    end
    return filtered
end

function clean_links(files)
   for file in files
       rm(file)
   end
end

function archive_files(files, archive_dir, force)
    for file in files
        newfile = joinpath(archive_dir, basename(file))
        msg_debug("Archiving $file -> $newfile")
        if force
            mv(file, newfile, force=true)
        elseif isfile(newfile)
            # Product already archived and we're not forcing: skip this one and
            # leave the existing copy in place (the un-moved temp file is removed
            # with the working dir). Continue archiving the rest rather than
            # aborting the whole step. Use '--force_reprocess' to overwrite, or
            # `reconcile_markers = true` to skip already-finished volumes entirely.
            msg_warning("Archived product already exists, skipping: $newfile " *
                        "(use '--force_reprocess' to overwrite)")
        else
            try
                mv(file, newfile)
            catch e
                msg_warning("Error archiving $file: $(safe_exception_string(e))")
            end
        end
    end
    return true
end

"""
    remove_working_dir(temp_dir)

Remove a disposable working directory. On networked/parallel filesystems
(Lustre/NFS) a recursive delete can transiently fail with `ENOTEMPTY` while
async unlinks settle, so retry a few times. A persistent failure is logged but
never aborts the run — the directory is scratch.
"""
function remove_working_dir(temp_dir)
    for attempt in 1:3
        try
            rm(temp_dir; recursive=true, force=true)
            return
        catch e
            if attempt < 3
                msg_debug("Cleanup of $temp_dir failed (attempt $attempt), retrying: " *
                          safe_exception_string(e))
                sleep(0.5)
            else
                msg_warning("Could not fully remove working dir $temp_dir: " *
                            safe_exception_string(e))
            end
        end
    end
end

function find_SeaPol_sigmet_data(date, time)

    file_expr = "SEA" * date * "_" * time
    sigmet_original = sigmet_base * "/" * date
    sigmet_file = filter(contains(file_expr),readdir(sigmet_original))
    if length(sigmet_file) > 0
        return sigmet_file[1]
    end
end

function find_SeaPol_sigmet_data(date)

    file_expr = "SEA" * date
    sigmet_original = sigmet_base * "/" * date
    sigmet_files = filter(contains(file_expr),readdir(sigmet_original))
    if length(sigmet_files) > 0
        file = sigmet_files[end]
        return file
    end
end

"""
    MSG_ERROR

Message severity level 0: Fatal errors that halt program execution.
"""
const MSG_ERROR = 0

"""
    MSG_WARNING

Message severity level 1: Warnings for non-fatal issues.
"""
const MSG_WARNING = 1

"""
    MSG_INFO

Message severity level 2: Informational messages (default level).
"""
const MSG_INFO = 2

"""
    MSG_DEBUG

Message severity level 3: Detailed debugging information.
"""
const MSG_DEBUG = 3

"""
    MSG_TRACE

Message severity level 4: Very verbose trace information.
"""
const MSG_TRACE = 4

# Global message level (can be set by user)
const DEFAULT_MSG_LEVEL = MSG_INFO
MSG_LEVEL = Ref(DEFAULT_MSG_LEVEL)

"""
    set_message_level(level::Int)

Set the global message verbosity level.

# Arguments
- `level`: Message level (0-4)

# Message Levels
- `0` (`MSG_ERROR`): Only errors
- `1` (`MSG_WARNING`): Errors and warnings
- `2` (`MSG_INFO`): Errors, warnings, and informational (default)
- `3` (`MSG_DEBUG`): Include debug messages
- `4` (`MSG_TRACE`): Include trace messages (very verbose)

# Example
```julia
set_message_level(MSG_DEBUG)  # Show debug messages
set_message_level(3)          # Same as above
```
"""
set_message_level(level::Int) = (MSG_LEVEL[] = level)

"""
    message(msg::String, level::Int=MSG_INFO; flush_output::Bool=true)

Output a message with the specified severity level.

Messages are only displayed if their severity is at or below the current message
level (set via [`set_message_level`](@ref)).

# Arguments
- `msg`: Message text to display
- `level`: Message severity level (0-4, default: MSG_INFO)
- `flush_output`: Whether to flush stdout/stderr after printing (default: true)

# Description
Messages at MSG_ERROR level will throw an error after printing.

# Example
```julia
message("Processing started", MSG_INFO)
message("Debug value: \$(x)", MSG_DEBUG)
```

# See Also
- [`msg_error`](@ref), [`msg_warning`](@ref), [`msg_info`](@ref), [`msg_debug`](@ref), [`msg_trace`](@ref)
"""
function message(msg::String, level::Int=MSG_INFO; flush_output::Bool=true)
    if level <= MSG_LEVEL[]
        prefix = if level == MSG_ERROR
            "⚠️ ERROR"
        elseif level == MSG_WARNING
            "WARNING"
        elseif level == MSG_INFO
            "𓅪"
        elseif level == MSG_DEBUG
            "DEBUG"
        else
            "TRACE"
        end

        timestamp = Dates.format(now(UTC), "yyyy-mm-dd HH:MM:SS")
        println("[$timestamp] $prefix : $msg")

        if flush_output
            flush(stdout)
            flush(stderr)
        end
    end

    # Halt on fatal error
    if level == MSG_ERROR
        error(msg)
    end
end

"""
    msg_error(msg::String)

Output an error message and halt program execution.

Equivalent to `message(msg, MSG_ERROR)`.
"""
msg_error(msg::String) = message(msg, MSG_ERROR)

"""
    msg_warning(msg::String)

Output a warning message.

Equivalent to `message(msg, MSG_WARNING)`.
"""
msg_warning(msg::String) = message(msg, MSG_WARNING)

"""
    msg_info(msg::String)

Output an informational message.

Equivalent to `message(msg, MSG_INFO)`.
"""
msg_info(msg::String) = message(msg, MSG_INFO)

"""
    msg_debug(msg::String)

Output a debug message (only shown when message level ≥ 3).

Equivalent to `message(msg, MSG_DEBUG)`.
"""
msg_debug(msg::String) = message(msg, MSG_DEBUG)

"""
    msg_trace(msg::String)

Output a trace message (only shown when message level = 4).

Equivalent to `message(msg, MSG_TRACE)`.
"""
msg_trace(msg::String) = message(msg, MSG_TRACE)
