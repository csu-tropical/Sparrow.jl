function copy_each_file(input_dir, output_dir, start_time::DateTime, stop_time::DateTime)
    # Pass through if within the time limit
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for file in input_files
        scan_start = get_scan_start(file)
        #println("Checking $file at $(Dates.format(scan_start, "YYYYmmdd HHMM"))")
        if scan_start < start_time || scan_start >= stop_time
            #println("Skipping $file")
            continue
        else
            output_file = replace(input_file, input_dir => output_dir)
            cp(input_file, output_file)
        end
    end
end

function workflow_step(workflow::SparrowWorkflow, filterByTime, input_dir::String, output_dir::String;
    step_name="filterByTime", start_time::DateTime, stop_time::DateTime)

    # Pass through if within the time limit
    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    for file in input_files
        scan_start = get_scan_start(file)
        #println("Checking $file at $(Dates.format(scan_start, "YYYYmmdd HHMM"))")
        if scan_start < start_time || scan_start >= stop_time
            #println("Skipping $file")
            continue
        else
            output_file = replace(input_file, input_dir => output_dir)
            cp(input_file, output_file)
        end
    end
end

function get_scan_start(file)
    if basename(file)[1:6] == "cfrad."
        # Assumes CfRadial files with names like "cfrad.YYYYmmdd_HHMMSS.ms_to_YYYYmmdd_HHMMSS.ms_radar_scantype.nc"
        return DateTime(parse(Int64, basename(file)[7:10]),
            parse(Int64, basename(file)[11:12]),
            parse(Int64, basename(file)[13:14]),
            parse(Int64, basename(file)[16:17]),
            parse(Int64, basename(file)[18:19]))
    elseif basename(file)[1:3] == "SEA"
        # Assumes Sigmet files with names like "SEAYYYYmmdd_HHMMSS"
        return DateTime(parse(Int64, basename(file)[4:7]),
            parse(Int64, basename(file)[8:9]),
            parse(Int64, basename(file)[10:11]),
            parse(Int64, basename(file)[13:14]),
            parse(Int64, basename(file)[15:16]))
    elseif match(r"RAW", basename(file))
        # Assumes P3 files with names like "2TS220918150850.RAWEHHV"
        # Have to use RadxPrint
        # TBD
    else
        error("Unknown file format for $(basename(file))")
    end
end
