# Test workflow for distributed scope testing
# This file is loaded via Base.include(Sparrow, ...) on both main and workers.
# It tests that:
# 1. Built-in step types (GridRHIStep, etc.) are accessible
# 2. User-defined custom step types work
# 3. Re-declaring a built-in step via @workflow_step is a no-op (no error)

@workflow_type DistributedScopeTestWorkflow

# Re-declare a built-in step (should be a no-op due to idempotent macro)
@workflow_step PassThroughStep

# Define a custom step unique to this workflow
@workflow_step CustomDistTestStep

workflow = DistributedScopeTestWorkflow(
    base_working_dir = tempdir(),
    base_archive_dir = joinpath(tempdir(), "archive"),
    base_plot_dir = joinpath(tempdir(), "plots"),
    base_data_dir = joinpath(tempdir(), "data"),

    minute_span = 5,
    reverse = false,

    # Mix built-in and custom steps
    steps = [
        ("passthrough", PassThroughStep, "raw_data", false),
        ("custom", CustomDistTestStep, "raw_data", false),
        ("grid_rhi", GridRHIStep, "raw_data", false),
    ],

    raw_moment_names = ["DBZ"],
    qc_moment_names = ["DBZ"],
    moment_grid_type = [:linear],

    test_mode = true
)

# Define behavior for the custom step
function workflow_step(workflow::DistributedScopeTestWorkflow, ::Type{CustomDistTestStep},
                       input_dir::String, output_dir::String; kwargs...)
    msg_debug("Custom step executed")
    mkpath(output_dir)
end
