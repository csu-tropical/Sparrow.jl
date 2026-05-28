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
    filter!(!isdir, input_files)
    # RadxConvert adds the YYYYmmdd automatically, so we have to remove it from output_dir
    radx_output_dir = output_dir[1:end-9]
    for file in input_files
        scan_start = get_scan_start(file)
        if scan_start < start_time || scan_start >= stop_time
            msg_debug("Skipping $file")
            continue
        end
        try
            run(`RadxConvert -sort_rays_by_time -outdir $radx_output_dir -const_ngates -f $file`)
        catch e
            msg_warning("Error converting $file with RadxConvert: $e")
            continue
        end
    end
end

# Per-worker cache for Ronin config + loaded models. Workers stay alive for the
# whole run, so the cache amortizes the JLD2 load (≈45s per call) across every
# chunk that worker handles. Keyed by absolute config path so two workflows
# pointing at different configs don't share an entry.
const RONIN_CACHE = Dict{String,NamedTuple}()

function _get_ronin_resources(config_path::String)
    key = abspath(config_path)
    cached = get(RONIN_CACHE, key, nothing)
    cached === nothing || return cached
    msg_info("Loading Ronin config and models from $config_path (one-time per worker)...")
    config = load_config(config_path)
    models = [Ronin.load_model(m, config.task_mode) for m in config.model_output_paths]
    cached = (config=config, models=models)
    RONIN_CACHE[key] = cached
    return cached
end

@workflow_step RoninQCStep
function workflow_step(workflow::SparrowWorkflow, ::Type{RoninQCStep}, input_dir::String, output_dir::String; start_time::DateTime, stop_time::DateTime, step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")

    msg_info("Processing with Ronin...")
    input_files = filter(!isdir, readdir(input_dir; join=true))
    filter!(input_files) do file
        scan_start = get_scan_start(file)
        scan_start >= start_time && scan_start < stop_time
    end
    if length(input_files) > 0
        output_files = [replace(f, input_dir => output_dir) for f in input_files]
        for (src, dst) in zip(input_files, output_files)
            cp(src, dst; follow_symlinks=true)
        end
        cached = _get_ronin_resources(workflow["ronin_config"])
        composite_QC(cached.config, output_files, cached.models)
    end
end
