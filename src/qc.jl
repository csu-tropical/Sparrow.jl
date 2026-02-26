# QC helper functions and workflow steps

function seapol_level_one()

   # Get the sigmet data from the SEA-POL server
   sigmet_raw = temp_dir * "/sigmet_raw/" * date
   if time == "now"
       link_latest_sigmet_data(date, sigmet_raw)
   else
       link_sigmet_data(date, time, sigmet_raw)
   end

   # Convert the Sigmet files to CfRadial
   msg_info("Converting Sigmet data to CfRadial...")
   sigmet_files = readdir(sigmet_raw; join=true)
   filter!(!isdir,sigmet_files)

   cfrad_raw = temp_dir * "/cfrad_raw"
   for file in sigmet_files
       scan_name = String(readchomp(pipeline(`RadxPrint -f $file`, `grep scanName`)))
       outdir = cfrad_raw
       if contains(scan_name, "VOL") || contains(scan_name, "SUR")
           outdir = outdir * "/sur"
       else
           outdir = outdir * "/rhi"
       end

       # Need to sort and force the number of gates to get time, range dimension instead of n_points
       run(`RadxConvert -sort_rays_by_time -outdir $outdir -const_ngates -f $file`)
   end
end

@workflow_step RadxConvertStep
function workflow_step(workflow::SparrowWorkflow, ::Type{RadxConvertStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")

    # Convert the input files to CfRadial
    msg_info("Converting data to CfRadial...")
    input_files = readdir(input_dir; join=true)
    filter!(!isdir,input_files)
    files = join(input_files, " ")
    # RadxConvert adds the YYYYmmdd automatically, so we have to remove it from output_dir
    radx_output_dir = output_dir[1:end-9]
    # Save the date
    start_date = Dates.format(start_time, "YYYYmmdd")
    for file in input_files
        # Get the scan start time
        scan_start = get_scan_start(file)
         if haskey(workflow.params, "process_all") && !workflow["process_all"]
             if scan_start < start_time || scan_start >= stop_time
                msg_debug("Skipping $file")
                continue
            end
        end
        try
            run(`RadxConvert -sort_rays_by_time -outdir $radx_output_dir -const_ngates -f $file`)
        catch e
            msg_warning("Error converting $file with RadxConvert: $e")
            continue
        end
        if haskey(workflow.params, "process_all") && workflow["process_all"]
            scan_date = Dates.format(scan_start, "YYYYmmdd")
            if scan_date != start_date
                # RadxConvert will have put it in a subdirectory with the date of the actual file, so we need to move it back to the output directory
                radx_output_dir = joinpath(radx_output_dir, date)
                msg_debug("Ignoring $date and moving files from $radx_output_dir to $output_dir")
                for cfrad_file in readdir(radx_output_dir; join=true)
                    output_file = replace(cfrad_file, radx_output_dir => output_dir)
                    mv(cfrad_file, output_file)
                end
            end
        end
    end
end

@workflow_step RoninQCStep
function workflow_step(workflow::SparrowWorkflow, ::Type{RoninQCStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")

   # Convert the input files to CfRadial
   msg_info("Processing with Ronin...")
   ronin_config = load_object(workflow["ronin_config"])
   models = [load_object(model) for model in ronin_config.model_output_paths]
   input_files = readdir(input_dir; join=true)
   filter!(!isdir,input_files)
   for input_file in input_files
       output_file = replace(input_file, input_dir => output_dir)
       cp(input_file, output_file, follow_symlinks=true)
   end
   output_files = readdir(output_dir; join=true)
   filter!(!isdir,output_files)
   composite_QC(ronin_config, output_files, models)
end
