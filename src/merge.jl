# Volume merge workflow steps

@workflow_step MergeVolumesStep
@workflow_step PiccoloMergeStep

"""
    MergeVolumesStep

Merge all scans within the time window into aggregated volumes using RadxConvert.

Reads radar files from `input_dir`, filters by time range using `get_scan_start`,
and merges them into a single aggregated volume written to `output_dir`.
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{MergeVolumesStep},
                       input_dir::String, output_dir::String;
                       start_time::DateTime, stop_time::DateTime,
                       step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")

    mkpath(output_dir)
    volume = Set{String}()

    msg_info("Reading files in $(input_dir)...")
    qc_files = readdir(input_dir; join=true)
    filter!(!isdir, qc_files)

    for file in qc_files
        scan_start = get_scan_start(file)
        if scan_start < start_time || scan_start >= stop_time
            continue
        end
        push!(volume, file)
    end

    msg_info("Merging $(length(volume)) files...")
    if !isempty(volume)
        run(`RadxConvert -ag_all -sort_rays_by_time -outdir $output_dir -const_ngates -f $volume`)
    end
    flush(stdout)
end

"""
    PiccoloMergeStep

Merge Piccolo radar scans into separate volume groups using RadxConvert.

Sorts scans by scan name into up to two PPI volumes and an RHI group,
then merges each group separately. Scan name classification:
- RHI scans → merged together
- PICCOLO_LONG, CIRL, CIRC, PICO_LONGVOL, VOL1, NEAR, FAR, HILO → volume 1
- VOL2 → volume 2

# Configurable parameters (via workflow dict)
- `qc_moment_dict`: Moment dictionary (required, set by workflow setup)
"""
function workflow_step(workflow::SparrowWorkflow, ::Type{PiccoloMergeStep},
                       input_dir::String, output_dir::String;
                       start_time::DateTime, stop_time::DateTime,
                       step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")

    qc_moment_dict = workflow["qc_moment_dict"]

    mkpath(output_dir)
    volume1 = Set{String}()
    volume2 = Set{String}()
    rhis = Set{String}()

    msg_info("Reading files in $(input_dir)...")
    qc_files = readdir(input_dir; join=true)
    filter!(!isdir, qc_files)

    for file in qc_files
        scan_start = get_scan_start(file)
        if scan_start < start_time || scan_start >= stop_time
            continue
        end

        radar_volume = Daisho.read_cfradial(file, qc_moment_dict)
        scan_name = radar_volume.scan_name

        if contains(scan_name, "RHI")
            push!(rhis, file)
        elseif contains(scan_name, "PICCOLO_LONG")
            push!(volume1, file)
        elseif contains(scan_name, "CIRL")
            push!(volume1, file)
        elseif contains(scan_name, "CIRC")
            push!(volume1, file)
        elseif contains(scan_name, "PICO_LONGVOL")
            push!(volume1, file)
        elseif contains(scan_name, "VOL2")
            push!(volume2, file)
        else # VOL1, NEAR, FAR, HILO
            push!(volume1, file)
        end
    end

    msg_info("Merging volumes...")
    if !isempty(volume1)
        run(`RadxConvert -ag_all -sort_rays_by_time -outdir $output_dir -const_ngates -f $volume1`)
    end

    if !isempty(volume2)
        run(`RadxConvert -ag_all -sort_rays_by_time -outdir $output_dir -const_ngates -f $volume2`)
    end

    if !isempty(rhis)
        run(`RadxConvert -ag_all -sort_rays_by_time -outdir $output_dir -const_ngates -f $rhis`)
    end
    flush(stdout)
end
