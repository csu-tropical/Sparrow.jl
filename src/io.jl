# IO helper functions and workflow steps

function initialize_working_dirs(workflow::SparrowWorkflow, date)

    # Set up the working directories
    base_working_dir = workflow["base_working_dir"]
    steps = length(workflow["steps"])
    temp_dir = joinpath(base_working_dir, randstring(6))
    mkpath(temp_dir)

    # This directory holds raw data from the base_data_dir, which may be in SIGMET format or already converted to CfRadial
    working_dir = joinpath(temp_dir, "base_data", date)
    mkpath(working_dir)
    link_base_data(date, workflow, working_dir)

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

function link_base_data(date, workflow, raw_working_dir)

    base_archive_dir = workflow["base_archive_dir"]
    force_reprocess = workflow["force_reprocess"]
    source = get_data_source(workflow)

    if is_remote(source)
        # Remote source: download files into working directory
        remote_files = discover_files(source, date)
        for filename in remote_files
            fname = basename(filename)
            if force_reprocess || !check_processed(workflow, fname, base_archive_dir)
                try
                    fetch_file(source, fname, raw_working_dir, date)
                catch e
                    msg_warning("Failed to fetch $fname: $e")
                end
            else
                msg_debug("File $fname already processed by $(typeof(workflow)), skipping...")
            end
        end
    else
        # Local source: symlink files
        base_data_dir = source.base_dir
        data_files = readdir("$(base_data_dir)/$(date)"; join=true)
        filter!(!isdir, data_files)
        for file in data_files
            if force_reprocess || !check_processed(workflow, file, base_archive_dir)
                target = file
                link = raw_working_dir * "/" * basename(file)
                symlink(target, link)
            else
                msg_debug("File $(basename(file)) already processed by $(typeof(workflow)), skipping...")
            end
        end
    end
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
        else
            try
                mv(file, newfile)
            catch e
                msg_warning("Error archiving $file, may need '--force_reprocess' flag: $e")
                return false
            end
        end
    end
    return true
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
        println("[$timestamp] $prefix: $msg")

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
