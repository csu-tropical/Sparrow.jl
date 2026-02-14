# IO helper functions and workflow steps

function initialize_working_dirs(workflow::SparrowWorkflow, date)

    # Set up the working directories
    base_data_dir = workflow["base_data_dir"]
    base_working_dir = workflow["base_working_dir"]
    steps = length(workflow["steps"])

    temp_dir = base_working_dir * "/" * randstring(6)
    mkpath(temp_dir)

    # This directory holds raw data from the base_data_dir, which may be in SIGMET format or already converted to CfRadial
    raw_dir = temp_dir * "/raw_data/" * date
    mkpath(raw_dir)
    link_base_data(date, base_data_dir, raw_dir)

    for (step_num, (step_name, step_type)) in enumerate(workflow["steps"])
        step_dir = temp_dir * step_name * "/" * date
        mkpath(step_dir)
    end

    return temp_dir
end

function archive_workflow(workflow::SparrowWorkflow, temp_dir)

    println("Archiving the processed data...")
    flush(stdout)

    processed_files = String[]
    # Get the date from the end of the temp_dir path
    date = temp_dir[end-7:end]
    archive_dir = workflow["base_archive_dir"]

    # Make sure the archive directory exists
    mkpath(archive_dir)
    mkpath(archive_dir * "/.sparrow/")

    archive_flag = workflow["archive"]
    for (step_num, (step_name, step_type)) in enumerate(workflow["steps"])
        if archive_flag[step_num] == true
            step_dir = temp_dir * "/" * step_name * "/" * date
            data_files = readdir(step_dir; join=true)
            step_files = filter!(!isdir,data_files)
            append!(processed_files, step_files)
            mkpath(archive_dir * "/" * step_name * "/" * date)
            archive_files(temp_dir, archive_dir, step_files)
        end
    end

    # Touch the hidden files to indicate that these have been processed and archived
    for file in processed_files
        hidden_file = archive_dir * "/.sparrow/" * basename(file)
        touch(hidden_file)
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

function archive_files(temp_dir, archive_dir, files)
    for file in files
        newfile = replace(file, temp_dir => archive_dir)
        println("Archiving $file -> $newfile")
        mv(file, newfile, force=true)
    end
end
