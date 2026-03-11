# Test workflow for world-age testing
# This file is loaded via Base.include(Sparrow, ...) to test that:
# 1. New types defined here can be constructed and used after include
# 2. New workflow_step methods defined here can be dispatched on workers
# 3. hasmethod sees the new methods on workers
# 4. Workflow objects with new types serialize correctly across processes

@workflow_type WorldAgeTestWorkflow

@workflow_step WorldAgeCustomStep

workflow = WorldAgeTestWorkflow(
    base_working_dir = tempdir(),
    base_archive_dir = joinpath(tempdir(), "archive"),
    base_plot_dir = joinpath(tempdir(), "plots"),
    base_data_dir = joinpath(tempdir(), "data"),
    minute_span = 5,
    reverse = false,
    steps = [
        ("builtin_pass", PassThroughStep, "raw_data", false),
        ("custom", WorldAgeCustomStep, "raw_data", false),
    ],
    raw_moment_names = ["DBZ"],
    qc_moment_names = ["DBZ"],
    moment_grid_type = [:linear],
    test_marker = "world_age_test"
)

# Custom workflow_step method — must be visible to hasmethod and dispatch on workers
function workflow_step(workflow::WorldAgeTestWorkflow, ::Type{WorldAgeCustomStep},
                       input_dir::String, output_dir::String; kwargs...)
    mkpath(output_dir)
    return "world_age_custom_step_executed"
end
