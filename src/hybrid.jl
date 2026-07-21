# Hybrid-scan workflow step
#
# Collapses one time chunk's gridded PPI tilts into a single near-surface 2-D
# product via `Daisho.build_hybrid_scan`. All of the science configuration —
# which fields to carry, the base tilt, the beam-height limit, the sentinel
# policy — lives in the `[hybrid_scan]` block of the workflow's Daisho TOML.

"""
    hybrid_output_name(start_time::DateTime) → String

Output filename for a hybrid scan covering the chunk beginning `start_time`.
Carries the same `YYYYmmdd_HHMMSS` stamp as the gridded products, which
`archived_output_exists` relies on to reconcile archived files.
"""
hybrid_output_name(start_time::DateTime) =
    "gridded_hybrid_" * Dates.format(start_time, "YYYYmmdd_HHMMSS") * ".nc"

"""
    HybridScanStep

Build a near-surface hybrid scan from a set of gridded PPI tilts.

Point this step's `input_directory` at a preceding PPI grid step; steps run in
declaration order within a time chunk, so that step's output for this chunk is
already on disk. Every file in the input directory is treated as one tilt of the
same volume — the PPI step has already scoped them to the chunk — and each one's
elevation angle comes from the `fixed_angle` Daisho writes into gridded PPI files
(with the `[hybrid_scan] angle_pattern` filename fallback for older archives).

Requires `daisho_config` with an enabled `[hybrid_scan]` block. Because the
product usually carries rain rate and hydrometeor ID, `[echo]` should be enabled
too so those fields exist in the PPI grids.

Writes one `gridded_hybrid_<YYYYmmdd_HHMMSS>.nc` per chunk, in the same layout as
a gridded PPI — so the plotting steps (e.g. `PlotDBZRainrateStep`) read it back
unchanged.
"""
@workflow_step HybridScanStep
function workflow_step(workflow::SparrowWorkflow, ::Type{HybridScanStep},
                       input_dir::String, output_dir::String;
                       start_time::DateTime, stop_time::DateTime,
                       step_name::String, kwargs...)

    msg_info("Executing Step $(step_name) for $(typeof(workflow)) ...")
    daisho_params = get_daisho_params(workflow)

    if !daisho_params.hybrid_scan.enabled
        msg_warning("Step $(step_name): [hybrid_scan] is not enabled in the Daisho " *
                    "configuration; skipping.")
        return
    end

    input_files = readdir(input_dir; join=true)
    filter!(!isdir, input_files)
    if isempty(input_files)
        msg_info("Step $(step_name): no gridded PPI tilts in $(input_dir); skipping.")
        return
    end

    output_file = joinpath(output_dir, hybrid_output_name(start_time))
    msg_info("Building hybrid scan $output_file from $(length(input_files)) tilt(s)")
    @time written = Daisho.build_hybrid_scan(input_files, output_file, daisho_params)
    msg_debug("Wrote $(join(written, ", ")) to $output_file")
end
