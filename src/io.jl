# IO helper functions and workflow steps

function initialize_working_dirs(workflow::SparrowWorkflow, date)

    # Set up the working directories
    base_data_dir = workflow["base_data_dir"]
    base_working_dir = workflow["base_working_dir"]
    steps = length(workflow["steps"])

    temp_dir = joinpath(base_working_dir, randstring(6))
    mkpath(temp_dir)

    # This directory holds raw data from the base_data_dir, which may be in SIGMET format or already converted to CfRadial
    raw_dir = joinpath(temp_dir, "raw_data", date)
    mkpath(raw_dir)
    link_base_data(date, base_data_dir, raw_dir)

    for (step_num, (step_name, step_type)) in enumerate(workflow["steps"])
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

    archive = workflow["archive"]
    force = workflow["force_reprocess"]
    for (step_num, (step_name, step_type)) in enumerate(workflow["steps"])
        if archive[step_num].second
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

function link_base_data(date, base_dir, raw_dir)

    data_files = readdir("$(base_dir)/$(date)"; join=true)
    filter!(!isdir,data_files)
    for file in data_files
        target = file
        link = raw_dir * "/" * basename(file)
        symlink(target,link)
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
            mv(file, newfile)
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
