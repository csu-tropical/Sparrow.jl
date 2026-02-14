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

function run_workflow(parsed_args)

    # Load the workflow file
    workflow_file = parsed_args["workflow"]
    include(workflow_file)

    # Set up the distributed environment
    # Send the workflow file path to all workers and have them include it
    # This defines the type on each worker
    @everywhere workers() begin
        Base.include(Sparrow, $workflow_file)
    end

    # Store type name and params in the workflow dict for workers to reconstruct
    workflow_type_name = typeof(workflow).name.name
    workflow["workflow_type_name"] = String(workflow_type_name)
    num_workers = length(workers())
    workflow["num_workers"] = num_workers

    # Override the log_prefix if provided in the arguments, otherwise use a default based on the workflow type and current time
    log_prefix = "$(typeof(workflow))_$(Dates.format(now(UTC), "YYYYmmdd_HHMMSS"))"
    if parsed_args["log_prefix"] != "default"
        log_prefix = parsed_args["log_prefix"]
    end

    # Override the paths if a paths file is provided, otherwise assume the workflow file has set the paths in the workflow dict
    if parsed_args["paths"] != "none"
        paths_file = parsed_args["paths"]
        include(paths_file)
        workflow["base_data_dir"] = base_data_dir
        workflow["base_working_dir"] = base_working_dir
        workflow["base_archive_dir"] = base_archive_dir
        workflow["base_plot_dir"] = base_plot_dir
    end

    if parsed_args["realtime"] && parsed_args["datetime"] != "now"
        error("Cannot specify a datetime when running in realtime mode. Please remove the --datetime argument or remove the --realtime flag.")
    end

    if (haskey(workflow.params, "realtime") && workflow["realtime"]) || parsed_args["realtime"]
        println("Running in realtime mode")
        workflow["realtime"] = true
    else
        workflow["realtime"] = false
    end

    datetime = parsed_args["datetime"]
    if haskey(workflow.params, "datetime") && datetime != "now"
        println("Overriding datetime in workflow file with $datetime datetime provided in arguments")
    end
    workflow["datetime"] = datetime

    # Change "now" to the current datetime in the format YYYYmmdd_HHMMSS
    if datetime == "now"
        workflow["datetime"] = Dates.format(now(UTC), "YYYYmmdd_HHMMSS")
    end

    # Fix if user mistakenly put "SEA" in front of the datetime
    if (startswith(datetime, "SEA"))
        workflow["datetime"] = datetime[4:end]
    end

    println("Running in archive mode on data from $(workflow["datetime"])")

    if parsed_args["force_reprocess"]
        workflow["force"] = parsed_args["force_reprocess"]
    else
        workflow["force"] = get_param(workflow, "force", false)
    end

    # Add the moment names and grid types to the workflow dict so they can be accessed by the worker processes
    raw_moment_dict, qc_moment_dict, grid_type_dict = Daisho.initialize_moment_dictionaries(workflow["raw_moment_names"], workflow["qc_moment_names"], workflow["moment_grid_type"])
    workflow["raw_moment_dict"] = raw_moment_dict
    workflow["qc_moment_dict"] = qc_moment_dict
    workflow["grid_type_dict"] = grid_type_dict

    # Set up the log files and redirect the output
    outfile = log_prefix * "_out.log"
    errfile = log_prefix * "_err.log"
    out = open(outfile, "w")
    err = open(errfile, "w")
    redirect_stdout(out)
    redirect_stderr(err)

    # Redirect the output on each worker process to a separate log file if more than one worker
    if num_workers > 1
        for i in 1:num_workers
            local outfile = log_prefix * "_out_$(i).log"
            local errfile = log_prefix * "_err_$(i).log"
            wait(save_at(workers()[i], :out, :(open($(outfile), "w"))))
            wait(save_at(workers()[i], :err, :(open($(errfile), "w"))))
            wait(get_from(workers()[i], :(redirect_stdout(out))))
            wait(get_from(workers()[i], :(redirect_stderr(err))))
        end
    else
        wait(save_at(workers()[1], :out, :(open($(outfile), "w"))))
        wait(save_at(workers()[1], :err, :(open($(errfile), "w"))))
        wait(get_from(workers()[1], :(redirect_stdout(out))))
        wait(get_from(workers()[1], :(redirect_stderr(err))))
    end

    # Run the main processing loop
    assign_workers(workflow)

    # Close the output files
    close(out)
    close(err)
    for i in 1:num_workers
        wait(get_from(workers()[i], :(close(out))))
        wait(get_from(workers()[i], :(close(err))))
    end
end

# Main function to process radar data
function assign_workers(workflow::SparrowWorkflow)

    println("Processing data with $(typeof(workflow))...")

    # Process a time period of radar data
    if workflow["realtime"]
        println("Watching for real time data...")
        flush(stdout)
        status = "Starting"
        # Allow up to num_workers parallel processes to occur simultaneously
        tasks = Array{Distributed.Future}(undef, num_workers)
        filequeue = fill("none", length(tasks))
        while true
            radar_date = Dates.format(now(UTC), "YYYYmmdd")
            sigmet_raw = base_data_dir * "/" * radar_date
            mkpath(sigmet_raw)
            raw_files = readdir(sigmet_raw)
            filter!(!isdir, raw_files)
            #println("Checking for new data at $(now(UTC))...")
            flush(stdout)
            for file in reverse(raw_files)
                #println("Checking $file...")
                flush(stdout)
                # Skip if it is hidden file, which means rsync is still writing, or if it is already in the queue
                if startswith(file, ".")
                    continue
                end
                radar_date = Dates.format(now(UTC), "YYYYmmdd")
                radar_time = file[end-5:end] #HHMMSS

                # Check if the file is already processed
                status = check_processed(file, base_archive_dir)
                if status == "processed"
                    #println("$file already processed, skipping...")
                    #flush(stdout)
                    continue
                end
                # File is not hidden and has not been processed
                if !(file in filequeue)
                    # Found some data to process
                    println("Current queue: $filequeue")
                    flush(stdout)
                    # Find an open task slot
                    for t in 1:length(tasks)
                        if !isassigned(tasks, t) || filequeue[t] == "none"
                            # Found an open task slot so start processing
                            filequeue[t] = file
                            #tasks[t] = get_from(workers()[t], :(process_workflow($workflow)))
                            # Reconstruct workflow on worker instead of serializing it
                            tasks[t] = get_from(workers()[t], :(process_workflow($(workflow))))

                            println("$file being processed in empty task slot $t at $(now(UTC))")
                            flush(stdout)
                            break
                        elseif isassigned(tasks, t) && filequeue[t] != "none"
                            if check_processed(filequeue[t], base_archive_dir) == "processed"
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

                # Check if the queue is full
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
                            if check_processed(filequeue[t], base_archive_dir) == "processed"
                                println("Fetching status on task $t at $(now(UTC))")
                                try
                                    status = fetch(tasks[t])
                                catch e
                                    println("Error $e fetching $status at $(now(UTC))")
                                    flush(stdout)
                                end
                                println("Task $t $status at $(now(UTC))")
                                filequeue[t] = file
                                free_task = t
                                flush(stdout)
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
                if check_processed(filequeue[t], base_archive_dir) == "processed"
                    println("Fetching status on task $t at $(now(UTC))")
                    try
                        status = fetch(tasks[t])
                    catch e
                        println("Error $e fetching $status at $(now(UTC))")
                        flush(stdout)
                    end
                    println("Task $t $status at $(now(UTC))")
                    filequeue[t] = "none"
                    flush(stdout)
                end
            end

            # Wait for a bit before checking again
            sleep(5)
        end
    else
        # Process using the datetime provided in the arguments
        wait(get_from(workers()[1], :(process_workflow($(workflow)))))
    end

    return true
end

function process_workflow(workflow::SparrowWorkflow)

    # Set the local variables from thw workflow
    datetime = workflow["datetime"]
    minute_span = workflow["minute_span"]
    force = workflow["force"]
    reverse = workflow["reverse"]
    base_archive_dir = workflow["base_archive_dir"]

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
            processed_files = process_volume(workflow, start_time, stop_time)
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
            processed_files = process_volume(workflow, start_time, stop_time)
        end
    else
        hr = datetime[10:11]
        min = datetime[12:13]
        start_time = DateTime(parse(Int64, year), parse(Int64, month), parse(Int64, day), parse(Int64, hr), parse(Int64, min))
        stop_time = start_time + Dates.Minute(minute_span)
        processed_files = process_volume(workflow, start_time, stop_time)
    end

    flush(stdout)
end

function process_volume(workflow::SparrowWorkflow, start_time, stop_time)

    date = Dates.format(start_time, "YYYYmmdd")
    processed_files = []

    # Set up the working directories
    temp_dir = initialize_working_dirs(workflow, date)

    # Run the workflow steps
    for (step_num, (step_name, step_type)) in enumerate(workflow["steps"])
        println("Running step $(step_num): $(step_name)...")
        flush(stdout)
        run_workflow_step(workflow, step_num, start_time, stop_time, temp_dir)
    end

    # Clean up and move to archive
    processed_files = archive_workflow(workflow, temp_dir)

    # Remove the temporary directories
    rm(temp_dir, recursive=true)

    return processed_files

end

# Main QC workflow dispatcher - takes a workflow type as argument
function run_workflow_step(workflow::SparrowWorkflow, step_num, start_time, stop_time, temp_dir)

    # Common preprocessing that applies to all workflows
    date = Dates.format(start_time, "YYYYmmdd")
    steps = workflow["steps"]
    step_name, step_type = steps[step_num]
    if step_num == 1
        input_dir = joinpath(temp_dir, "raw_data", date)
    else step_num > 1
        prev_step_name, prev_step_type = steps[step_num-1]
        input_dir = joinpath(temp_dir, prev_step_name, date)
    end
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

function check_processed(date, time, archive_dir)

    # Make sure the hidden processed directory exists
    processed_dir = archive_dir * "/.sparrow/"
    mkpath(processed_dir)

    # Check to see if the data is already processed
    sigmet_file = ""
    if time == "now"
        sigmet_file = find_sigmet_data(date)
    else
        sigmet_file = find_sigmet_data(date, time)
    end
    if sigmet_file == nothing
        return "none"
    end

    processed_file = processed_dir * basename(sigmet_file)
    if isfile(processed_file)
        return "processed"
    else
        return "ready"
    end
end

#function check_processed(workflow::SparrowWorkflow)
#    processed_composite_dir = base_archive_dir * "/gridded_data/composite/" * date
#    processed_composite = processed_composite_dir * "/gridded_composite_" * Dates.format(starttime, "YYYYmmdd_HHMM") * ".nc"
#    processed_rhi_dir = base_archive_dir * "/gridded_data/rhi/" * date
#    rhi_files = readdir(processed_rhi_dir)
#    processed_rhi = "gridded_rhi_" * Dates.format(starttime, "YYYYmmdd_HHMM")
#    rhi_files = any(f -> occursin(processed_rhi, f), rhi_files)
#    if isfile(processed_composite) || rhi_files
#        println("Data already processed! To reprocess use '--force_reprocess true'")
#        continue
#    end
#end

# QC the data
#run_qc_workflow(workflow, date, start_time, stop_time, temp_dir, qc_base, raw_moment_dict, qc_moment_dict, dbz_threshold, vel_threshold, sw_threshold)
#run_qc_workflow(workflow)
#flush(stdout)

# Merge volumes together if needed
#run_merge_workflow(workflow, qc_moment_dict, cfrad_qc, cfrad_merge_dir)
#run_merge_workflow(workflow)
#flush(stdout)

# Grid the volumes
#run_grid_workflow(workflow, qc_moment_dict, cfrad_merge_dir, composite_grid_dir, ppi_grid_dir, rhi_grid_dir, qvp_grid_dir)
#run_grid_workflow(workflow)
#flush(stdout)

# Plot the data
#run_plot_workflow(workflow, qc_moment_dict, qc_moment_dict, cfrad_merge_dir, composite_grid_dir, ppi_grid_dir, rhi_grid_dir, qvp_grid_dir)
#run_plot_workflow(workflow)
#flush(stdout)
