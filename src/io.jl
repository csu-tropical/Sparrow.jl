# IO helper functions and workflow steps

function initialize_working_dirs(workflow::SparrowWorkflow, date)

    # Set up the working directories
    base_working_dir = workflow["base_working_dir"]
    steps = length(workflow["steps"])
    force_reprocess = workflow["force_reprocess"]
    temp_dir = joinpath(base_working_dir, randstring(6))
    mkpath(temp_dir)

    # This directory holds raw data from the base_data_dir, which may be in SIGMET format or already converted to CfRadial
    working_dir = joinpath(temp_dir, "base_data", date)
    mkpath(working_dir)
    link_base_data(date, workflow, working_dir, force_reprocess)

    for (step_name, step_type, input_name, archive) in workflow["steps"]
        step_dir = joinpath(temp_dir, step_name, date)
        mkpath(step_dir)
    end

    return temp_dir
end

function archive_workflow(workflow::SparrowWorkflow, temp_dir, date)

    println("Archiving the processed data...")
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
            #println("Archiving $(step_files) to $(step_archive_dir)...")
            archive_files(step_files, step_archive_dir, force)
        end
    end

    return processed_files
end

function link_base_data(date, workflow, raw_working_dir, force_reprocess)

    base_data_dir = workflow["base_data_dir"]
    base_archive_dir = workflow["base_archive_dir"]
    data_files = readdir("$(base_data_dir)/$(date)"; join=true)
    filter!(!isdir,data_files)
    for file in data_files
        if force_reprocess || !check_processed(workflow, file, base_archive_dir)
            target = file
            link = raw_working_dir * "/" * basename(file)
            symlink(target,link)
        else
            println("File $(basename(file)) already processed by $(typeof(workflow)), skipping...")
            flush(stdout)
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
        println("Archiving $file -> $newfile")
        if force
            mv(file, newfile, force=true)
        else
            try
                mv(file, newfile)
            catch e
                println("Error archiving $file, may need '--force_reprocess' flag: $e")
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
