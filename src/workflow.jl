# Workflow functions and definitions

# Abstract type for Sparrow Workflow
abstract type SparrowWorkflow <: AbstractDict{String,Any} end

# Implement dict interface (same for all subtypes)
#Base.getindex(p::SparrowWorkflow, key) = getindex(p.params, key)
function Base.getindex(workflow::SparrowWorkflow, key::String)
    if !haskey(workflow.params, key)
        error("Required parameter '$key' not found in $(typeof(workflow)). Available parameters: $(sort(collect(keys(workflow.params))))")
    end
    return workflow.params[key]
end
Base.setindex!(p::SparrowWorkflow, value, key) = setindex!(p.params, value, key)
Base.iterate(p::SparrowWorkflow) = iterate(p.params)
Base.iterate(p::SparrowWorkflow, state) = iterate(p.params, state)
Base.length(p::SparrowWorkflow) = length(p.params)

# Helper for default values (since workflow["key", default] isn't valid syntax)
function get_param(workflow::SparrowWorkflow, key::String, default)
    return get(workflow.params, key, default)
end

# Helper version with type assertion
function get_param(workflow::SparrowWorkflow, key::String, ::Type{T}) where {T}
    if !haskey(workflow.params, key)
        error("Required parameter '$key' not found in $(typeof(workflow)). Available parameters: $(keys(workflow.params))")
    end
    value = workflow.params[key]
    if !(value isa T)
        error("Parameter '$key' has type $(typeof(value)), expected $T")
    end
    return value::T
end

# Macro to define a workflow type with constructor
macro workflow_type(name)
    return quote
        struct $(esc(name)) <: SparrowWorkflow
            params::Dict{String,Any}
        end

        $(esc(name))(; kwargs...) = $(esc(name))(Dict{String,Any}(string(k) => v for (k, v) in kwargs))
    end
end

# Define multiple workflow types at once
macro workflow_types(names...)
    exprs = []
    for name in names
        push!(exprs, quote
            struct $(esc(name)) <: SparrowWorkflow
                params::Dict{String,Any}
            end
            $(esc(name))(; kwargs...) = $(esc(name))(Dict{String,Any}(string(k) => v for (k, v) in kwargs))
        end)
    end
    return Expr(:block, exprs...)
end

# Macro to define a workflow step type
macro workflow_step(name)
    return quote
        struct $(esc(name)) end
    end
end

function run_workflow(workflow::SparrowWorkflow, parsed_args)

    # Override the log_prefix if provided in the arguments, otherwise use a default based on the workflow type and current time
    log_prefix = "$(typeof(workflow))_$(Dates.format(now(UTC), "YYYYmmdd_HHMMSS"))"
    if parsed_args["log_prefix"] != "default"
        log_prefix = parsed_args["log_prefix"]
    end

    # Set all the parameters from the provided workflow file or command line arguments
    setup_workflow_params(workflow, parsed_args)

    # Save the original stdout/stderr before redirection
    original_stdout = stdout
    original_stderr = stderr

    # Set up the log files and redirect the output
    outfile = log_prefix * ".log"
    out = open(outfile, "w")
    redirect_stdout(out)
    redirect_stderr(out)

    # Redirect the output on each worker process to a separate log file if more than one worker
    num_workers = length(workers())
    if num_workers > 1
        for i in 1:num_workers
            local outfile = log_prefix * "_worker_$(i).log"
            wait(save_at(workers()[i], :out, :(open($(outfile), "w"))))
            wait(get_from(workers()[i], :(redirect_stdout(out))))
            wait(get_from(workers()[i], :(redirect_stderr(out))))
        end
    else
        wait(save_at(workers()[1], :out, :(open($(outfile), "w"))))
        wait(get_from(workers()[1], :(redirect_stdout(out))))
        wait(get_from(workers()[1], :(redirect_stderr(out))))
    end

    # Run the main processing loop
    status = assign_workers(workflow)

    # Close the output files
    close(out)
    for i in 1:num_workers
        wait(get_from(workers()[i], :(close(out))))
    end

    # Restore original stdout/stderr
    redirect_stdout(original_stdout)
    redirect_stderr(original_stderr)

    return status
end

function setup_workflow_params(workflow::SparrowWorkflow, parsed_args)
    # This function can be used to set up any workflow specific parameters or directories before processing starts

    # Store type name and params in the workflow dict for workers to reconstruct
    workflow_type_name = typeof(workflow).name.name
    workflow["workflow_type_name"] = String(workflow_type_name)
    num_workers = length(workers())
    workflow["num_workers"] = num_workers

    if parsed_args["realtime"] && parsed_args["datetime"] != "now"
        error("𓅪 Cannot specify a datetime when running in realtime mode. Please remove the --datetime argument or remove the --realtime flag.")
    end

    if (haskey(workflow.params, "realtime") && workflow["realtime"]) || parsed_args["realtime"]
        println("𓅪 Running in realtime mode")
        workflow["realtime"] = true
        workflow["datetime"] = "now"
    else
        workflow["realtime"] = false
        datetime = parsed_args["datetime"]
        if haskey(workflow.params, "datetime") && datetime != "now"
            println("𓅪 Overriding datetime in workflow file with $datetime datetime provided in arguments")
        end
        workflow["datetime"] = datetime

        # Fix if user mistakenly put "SEA" in front of the datetime
        if (startswith(datetime, "SEA"))
            workflow["datetime"] = datetime[4:end]
        end

        println("𓅪 Running in archive mode on $(workflow["datetime"])")
    end

    if parsed_args["force_reprocess"]
        workflow["force_reprocess"] = parsed_args["force_reprocess"]
    else
        workflow["force_reprocess"] = get_param(workflow, "force_reprocess", false)
    end

    # Add the moment names and grid types to the workflow dict so they can be accessed by the worker processes
    raw_moment_dict, qc_moment_dict, grid_type_dict = Daisho.initialize_moment_dictionaries(workflow["raw_moment_names"], workflow["qc_moment_names"], workflow["moment_grid_type"])
    workflow["raw_moment_dict"] = raw_moment_dict
    workflow["qc_moment_dict"] = qc_moment_dict
    workflow["grid_type_dict"] = grid_type_dict

    return workflow
end

# Main function to process radar data
function assign_workers(workflow::SparrowWorkflow)

    println("Processing data with $(typeof(workflow))...")
    base_data_dir = workflow["base_data_dir"]
    base_archive_dir = workflow["base_archive_dir"]

    # Process a time period of radar data
    if !workflow["realtime"]
        # Process using the datetime provided in the arguments
        try
            wait(get_from(workers()[1], :(process_workflow($(workflow)))))
        catch e
            println("Error processing workflow: $e")
            flush(stdout)
            return false
        end
    else
        # Process realtime loop
        println("Watching for real time data...")
        flush(stdout)
        status = "Starting"
        # Allow up to num_workers parallel processes to occur simultaneously
        num_workers = length(workers())
        tasks = Array{Distributed.Future}(undef, num_workers)
        filequeue = fill("none", length(tasks))
        # Implement some time limits on tasks to check on them
        timequeue = fill(now(UTC), length(tasks))
        while true
            radar_date = Dates.format(now(UTC), "YYYYmmdd")
            raw_dir = joinpath(base_data_dir, radar_date)
            # Check to make sure directory exists
            mkpath(raw_dir)
            raw_files = readdir(raw_dir)
            filter!(!isdir, raw_files)
            #println("Checking for new data at $(now(UTC))...")
            #flush(stdout)
            for file in reverse(raw_files)
                #println("Checking $file...")
                #flush(stdout)
                # Skip if it is hidden file, which means rsync is still writing, or if it is already in the queue
                if startswith(file, ".")
                    continue
                end

                # Check if the file is already processed
                if check_processed(workflow, file, base_archive_dir)
                    #println("$file already processed, skipping...")
                    #flush(stdout)
                    continue
                elseif (file in filequeue)
                    #println("$file is in the queue and being processed...")
                    #flush(stdout)
                    continue
                end

                # File is not hidden and has not been processed so try to schedule it
                if !(file in filequeue)
                    # Found some data to process
                    println("Current queue: $filequeue")
                    flush(stdout)
                    # Find an open task slot
                    for t in 1:length(tasks)
                        if !isassigned(tasks, t) || filequeue[t] == "none"
                            # Found an open task slot so start processing
                            filequeue[t] = file
                            tasks[t] = get_from(workers()[t], :(process_workflow($(workflow))))
                            println("$file being processed in empty task slot $t at $(now(UTC))")
                            flush(stdout)
                            break
                        elseif isassigned(tasks, t) && filequeue[t] != "none"
                            # Non-blocking check if the task errored
                            if isready(tasks[t])
                                try
                                    status = fetch(tasks[t])
                                    println("Task $t $status at $(now(UTC))")
                                catch e
                                    println("Task $t errored: $e at $(now(UTC))")
                                end
                                flush(stdout)
                                filequeue[t] = file
                                tasks[t] = get_from(workers()[t], :(process_workflow($(workflow))))
                                println("$file took over task slot $t at $(now(UTC))")
                                flush(stdout)
                                break
                            elseif check_processed(workflow, filequeue[t], base_archive_dir)
                                # Check if the previous task is done processing, and if so clear it from the filequeue and assign new file
                                println("Clearing task $t at $(now(UTC))")
                                try
                                    status = fetch(tasks[t])
                                catch e
                                    println("Error $e fetching task $t status at $(now(UTC))")
                                    flush(stdout)
                                end
                                println("Task $t $status at $(now(UTC))")
                                filequeue[t] = file
                                tasks[t] = get_from(workers()[t], :(process_workflow($(workflow))))
                                println("$file took over task slot $t at $(now(UTC))")
                                flush(stdout)
                                break
                            end
                        end
                    end
                end

                # Check if the file was successfully queued or queue is full
                if !(file in filequeue)
                    # Queue is full, wait for the first task to finish
                    println("Queue full, waiting to schedule $file")
                    flush(stdout)
                    free_task = -1
                    waiting_time = 0
                    while free_task == -1 && waiting_time < 600
                        if waiting_time % 60 == 0
                            println("Waited $waiting_time seconds...")
                            flush(stdout)
                        end
                        for t in 1:length(tasks)
                            # Non-blocking check if task errored
                            if isready(tasks[t])
                                try
                                    status = fetch(tasks[t])
                                    println("Task $t completed: $status at $(now(UTC))")
                                catch e
                                    println("Task $t errored: $e at $(now(UTC))")
                                end
                                flush(stdout)
                                filequeue[t] = file
                                free_task = t
                                break
                            elseif check_processed(workflow, filequeue[t], base_archive_dir)
                                println("Fetching status on task $t at $(now(UTC))")
                                try
                                    status = fetch(tasks[t])
                                catch e
                                    println("Error $e fetching task $t at $(now(UTC))")
                                    flush(stdout)
                                end
                                println("Task $t $status at $(now(UTC))")
                                flush(stdout)
                                filequeue[t] = file
                                free_task = t
                                break
                            end
                        end
                        if free_task == -1
                            # Wait for a bit for things to finish
                            sleep(1)
                            waiting_time += 1
                        end
                    end
                    if free_task != -1
                        tasks[free_task] = get_from(workers()[free_task], :(process_workflow($(workflow))))
                        println("Task slot $free_task opened up for $file at $(now(UTC)), processing...")
                        break
                    else
                        println("No task slots opened up in 10 minutes! Skipping $file and moving on")
                    end
                end
            end

            # Made it to the end of the file checking loop, clear the queue if we can
            for t in 1:length(tasks)
                if !isassigned(tasks, t) || filequeue[t] == "none"
                    continue
                end

                # Non-blocking check if the task has completed or errored
                if isready(tasks[t])
                    try
                        status = fetch(tasks[t])
                        println("Task $t completed with status: $status at $(now(UTC))")
                        flush(stdout)
                    catch e
                        println("Task $t errored: $e at $(now(UTC))")
                        flush(stdout)
                    end
                    # Either way, clear the slot
                    filequeue[t] = "none"
                elseif check_processed(workflow, filequeue[t], base_archive_dir)
                    # Task isn't ready yet but file shows as processed
                    println("Fetching status on task $t at $(now(UTC))")
                    flush(stdout)
                    try
                        status = fetch(tasks[t])
                    catch e
                        println("Error $e fetching task $t at $(now(UTC))")
                        flush(stdout)
                    end
                    println("Task $t $status at $(now(UTC))")
                    flush(stdout)
                    filequeue[t] = "none"
                end
            end

            # Wait for a bit before checking again
            sleep(5)
        end
    end

    return true
end

function process_workflow(workflow::SparrowWorkflow)

    # Set the local variables from the workflow
    datetime = workflow["datetime"]
    minute_span = workflow["minute_span"]
    force_reprocess = workflow["force_reprocess"]
    reverse = workflow["reverse"]
    base_archive_dir = workflow["base_archive_dir"]

    # Change "now" to the current datetime in the format YYYYmmdd_HHMMSS
    if datetime == "now"
        datetime = Dates.format(now(UTC), "YYYYmmdd_HHMMSS")
    end

    if length(datetime) < 8
        error("Invalid datetime format $(datetime), needs to be at least YYYYmmdd")
    end

    date = datetime[1:8] #YYYYmmdd
    year = datetime[1:4]
    month = datetime[5:6]
    day = datetime[7:8]

    processed_files = []
    if length(datetime) == 8
        base_datetime = DateTime(parse(Int64, year), parse(Int64, month), parse(Int64, day))
        # Process the whole day in 5 minute chunks
        println("Processing the whole day...")
        flush(stdout)
        max_minute = 1440 - minute_span
        timerange = 0:minute_span:max_minute
        if reverse
            timerange = reverse(timerange)
        end
        for t in timerange
            start_time = base_datetime + Dates.Minute(t)
            stop_time = start_time + Dates.Minute(minute_span)
            println("Processing $(Dates.format(start_time, "HHMM"))...")
            volume_files = process_volume(workflow, start_time, stop_time)
            append!(processed_files, volume_files)
        end
    elseif length(datetime) == 11
        hr = datetime[10:11]
        base_datetime = DateTime(parse(Int64, year), parse(Int64, month), parse(Int64, day), parse(Int64, hr))
        println("Processing one hour...")
        flush(stdout)
        max_minute = 60 - minute_span
        timerange = 0:minute_span:max_minute
        if reverse
            timerange = reverse(timerange)
        end
        for t in timerange
            start_time = base_datetime + Dates.Minute(t)
            stop_time = start_time + Dates.Minute(minute_span)
            println("Processing $(Dates.format(start_time, "HHMM"))...")
            volume_files = process_volume(workflow, start_time, stop_time)
            append!(processed_files, volume_files)
        end
    else
        hr = datetime[10:11]
        min = datetime[12:13]
        start_time = DateTime(parse(Int64, year), parse(Int64, month), parse(Int64, day), parse(Int64, hr), parse(Int64, min))
        stop_time = start_time + Dates.Minute(minute_span)
        println("Processing $(Dates.format(start_time, "HHMM"))...")
        processed_files = process_volume(workflow, start_time, stop_time)
    end

    # Mark files as processed by touching a hidden file in the archive directory
    mkpath(base_archive_dir * "/.sparrow/")
    for file in processed_files
        hidden_file = "$(base_archive_dir)/.sparrow/$(typeof(workflow))_$(basename(file))"
        touch(hidden_file)
    end

    flush(stdout)
    return "processed successfully"
end

function process_volume(workflow::SparrowWorkflow, start_time, stop_time)

    date = Dates.format(start_time, "YYYYmmdd")
    processed_files = []

    # Set up the working directories
    temp_dir = initialize_working_dirs(workflow, date)

    # Run the workflow steps
    for (step_num, (step_name, step_type, input_name, archive)) in enumerate(workflow["steps"])
        if archive
            println("Running archive step $(step_num): $(step_name) using $(step_type) from $(input_name)...")
            flush(stdout)
        else
            println("Running temporary step $(step_num): $(step_name) using $(step_type) from $(input_name)...")
            flush(stdout)
        end

        run_workflow_step(workflow, step_num, start_time, stop_time, temp_dir)
    end

    # Clean up and move to archive
    processed_files = archive_workflow(workflow, temp_dir, date)

    # Remove the temporary directories
    rm(temp_dir, recursive=true)

    return processed_files

end

# Main QC workflow dispatcher - takes a workflow type as argument
function run_workflow_step(workflow::SparrowWorkflow, step_num, start_time, stop_time, temp_dir)

    # Common preprocessing that applies to all workflows
    date = Dates.format(start_time, "YYYYmmdd")
    steps = workflow["steps"]
    step_name, step_type, input_name, archive = steps[step_num]
    input_dir = joinpath(temp_dir, input_name, date)
    output_dir = joinpath(temp_dir, step_name, date)

    if hasmethod(workflow_step, (typeof(workflow), Type{step_type}, String, String))
        println("Running $(typeof(workflow)) workflow step $(step_num): $(step_name)")
        flush(stdout)
        workflow_step(workflow, step_type, input_dir, output_dir;
                     step_name=step_name, step_num=step_num, start_time=start_time, stop_time=stop_time)
    elseif hasmethod(workflow_step, (workflow::SparrowWorkflow, Type{step_type}, String, String))
        println("Running Sparrow provided step $(step_num): $(step_name)")
        flush(stdout)
        workflow_step(workflow, step_type, input_dir, output_dir;
                     step_name=step_name, step_num=step_num, start_time=start_time, stop_time=stop_time)
    else
        error("Workflow step $(step_name) is not implemented by $(typeof(workflow)) or Sparrow provided functions. Please implement workflow_step(workflow::$(typeof(workflow)), step_type::$(step_type), input_dir::String, output_dir::String) to run this workflow step.")
    end
end

function check_processed(workflow::SparrowWorkflow, file::String, archive_dir::String)

    # Make sure the hidden processed directory exists
    processed_dir = joinpath(archive_dir,".sparrow")
    mkpath(processed_dir)
    processed_file = "$(processed_dir)/$(typeof(workflow))_$(basename(file))"
    if isfile(processed_file)
        return true
    else
        return false
    end
end
