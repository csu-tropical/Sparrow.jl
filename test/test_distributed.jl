# Distributed worker tests for Sparrow
# Tests the distributed infrastructure: worker lifecycle, remote execution,
# task queue patterns, log redirection, and Slurm configuration.
#
# These tests use local workers (addprocs) so they can run on any machine.
# Set SPARROW_RUN_DISTRIBUTED_TESTS=1 to enable (disabled by default since
# they spawn processes and are slower than unit tests).

using Test
using Sparrow
using Distributed
using DistributedData
using SlurmClusterManager

@testset "Distributed Worker Tests" begin

    @testset "Argument Parsing" begin
        # Test basic argument parsing
        args = Sparrow.parse_arguments(["test_workflow.jl", "--num_workers", "4", "--threads", "2"])
        @test args["num_workers"] == 4
        @test args["threads"] == 2
        @test args["workflow"] == "test_workflow.jl"
        @test args["slurm"] == false
        @test args["sge"] == false
        @test args["datetime"] == "now"
        @test args["verbose"] == 2

        # Test slurm flag
        args_slurm = Sparrow.parse_arguments(["workflow.jl", "--slurm", "--verbose", "3"])
        @test args_slurm["slurm"] == true
        @test args_slurm["verbose"] == 3

        # Test realtime flag
        args_rt = Sparrow.parse_arguments(["workflow.jl", "--realtime"])
        @test args_rt["realtime"] == true

        # Test datetime override
        args_dt = Sparrow.parse_arguments(["workflow.jl", "--datetime", "20250101_120000"])
        @test args_dt["datetime"] == "20250101_120000"

        # Test log prefix
        args_log = Sparrow.parse_arguments(["workflow.jl", "--log_prefix", "myrun"])
        @test args_log["log_prefix"] == "myrun"

        # Test force reprocess
        args_force = Sparrow.parse_arguments(["workflow.jl", "--force_reprocess"])
        @test args_force["force_reprocess"] == true

        # Test defaults
        args_default = Sparrow.parse_arguments(["workflow.jl"])
        @test args_default["num_workers"] == 1
        @test args_default["threads"] == 1
        @test args_default["email"] == "none"
        @test args_default["paths_file"] == "none"
        @test args_default["log_prefix"] == "default"
        @test args_default["force_reprocess"] == false
    end

    @testset "Local Worker Lifecycle" begin
        # Start with only the main process
        initial_workers = workers()

        # Add 2 local workers
        new_pids = addprocs(2)
        @test length(new_pids) == 2
        @test length(workers()) == length(initial_workers) + 2 || length(workers()) == 2

        # Workers should be reachable
        for w in new_pids
            @test remotecall_fetch(() -> myid(), w) == w
        end

        # Clean up
        rmprocs(new_pids)
        # Give workers time to shut down
        sleep(0.5)
        @test length(workers()) <= length(initial_workers) || workers() == [1]
    end

    @testset "Module Loading on Workers" begin
        # Add workers and load Sparrow on them
        new_pids = addprocs(2)

        @everywhere new_pids using Sparrow

        # Verify Sparrow is available on each worker
        for w in new_pids
            @test remotecall_fetch(() -> isdefined(Main, :Sparrow), w)
            @test remotecall_fetch(() -> Sparrow.MSG_INFO, w) == 2
        end

        # Set message level on workers
        for w in new_pids
            remotecall_fetch(() -> Sparrow.set_message_level(Sparrow.MSG_DEBUG), w)
            level = remotecall_fetch(() -> Sparrow.MSG_LEVEL[], w)
            @test level == Sparrow.MSG_DEBUG
        end

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "Remote Execution with get_from/save_at" begin
        new_pids = addprocs(2)
        @everywhere new_pids using DistributedData

        # Test save_at: store a value on a remote worker
        wait(save_at(new_pids[1], :test_val, 42))
        result = fetch(get_from(new_pids[1], :test_val))
        @test result == 42

        # Test save_at with an expression
        wait(save_at(new_pids[2], :computed_val, :(2 + 3)))
        result2 = fetch(get_from(new_pids[2], :computed_val))
        @test result2 == 5

        # Test overwriting a value
        wait(save_at(new_pids[1], :test_val, 100))
        result3 = fetch(get_from(new_pids[1], :test_val))
        @test result3 == 100

        # Test get_from with expression evaluation
        result4 = fetch(get_from(new_pids[1], :(test_val * 2)))
        @test result4 == 200

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "Future-based Task Management" begin
        new_pids = addprocs(2)

        # Create futures like assign_workers does
        num_workers = length(new_pids)
        tasks = Array{Distributed.Future}(undef, num_workers)
        filequeue = fill("none", num_workers)

        # Simulate task assignment pattern from workflow.jl
        for (i, w) in enumerate(new_pids)
            filequeue[i] = "file_$(i).nc"
            tasks[i] = remotecall(() -> begin
                sleep(0.1)
                return "processed"
            end, w)
        end

        # Verify task queue state
        @test all(f -> f != "none", filequeue)

        # Wait for all tasks and check results
        for i in 1:num_workers
            result = fetch(tasks[i])
            @test result == "processed"
            # Clear the slot like assign_workers does
            filequeue[i] = "none"
        end
        @test all(f -> f == "none", filequeue)

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "Non-blocking Task Status Checks" begin
        new_pids = addprocs(2)

        # Launch a slow task and a fast task
        slow_task = remotecall(() -> begin
            sleep(2.0)
            return "slow_done"
        end, new_pids[1])

        fast_task = remotecall(() -> begin
            return "fast_done"
        end, new_pids[2])

        # Fast task should complete quickly
        sleep(0.2)
        @test isready(fast_task)
        @test fetch(fast_task) == "fast_done"

        # Slow task should still be running
        @test !isready(slow_task)

        # Wait for slow task to finish
        result = fetch(slow_task)
        @test result == "slow_done"
        @test isready(slow_task)

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "Worker Error Handling" begin
        new_pids = addprocs(1)

        # Test that errors on workers propagate correctly
        error_task = remotecall(() -> error("test error from worker"), new_pids[1])

        @test_throws Distributed.RemoteException fetch(error_task)

        # Worker should still be alive after an error in a task
        @test remotecall_fetch(() -> myid(), new_pids[1]) == new_pids[1]

        # Test error handling pattern used in assign_workers
        task = remotecall(() -> error("simulated failure"), new_pids[1])
        caught = false
        try
            fetch(task)
        catch e
            caught = true
            @test e isa Distributed.RemoteException
        end
        @test caught

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "Per-Worker Log Redirection" begin
        new_pids = addprocs(2)
        @everywhere new_pids using DistributedData

        mktempdir() do tmpdir
            log_prefix = joinpath(tmpdir, "test_log")

            # Redirect stdout/stderr on each worker to separate log files
            # (mirrors run_workflow logic in workflow.jl)
            num_workers = length(new_pids)
            for i in 1:num_workers
                outfile = log_prefix * "_worker_$(i).log"
                wait(save_at(new_pids[i], :out, :(open($(outfile), "w"))))
                wait(get_from(new_pids[i], :(redirect_stdout(out))))
                wait(get_from(new_pids[i], :(redirect_stderr(out))))
            end

            # Write something on each worker
            for (i, w) in enumerate(new_pids)
                remotecall_fetch(() -> begin
                    println("Worker $(myid()) log message")
                    flush(stdout)
                end, w)
            end

            # Close log files and restore stdout/stderr on workers
            for i in 1:num_workers
                wait(get_from(new_pids[i], :(begin
                    flush(out)
                    close(out)
                    redirect_stdout()
                    redirect_stderr()
                end)))
            end

            # Verify log files were created with content
            for i in 1:num_workers
                logfile = log_prefix * "_worker_$(i).log"
                @test isfile(logfile)
                content = read(logfile, String)
                @test occursin("log message", content)
            end
        end

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "Workflow Serialization to Workers" begin
        # Test that workflow objects can be sent to workers and used there
        new_pids = addprocs(1)
        @everywhere new_pids using Sparrow

        # Define type on all processes for serialization
        @everywhere new_pids @eval Sparrow.@workflow_type DistributedTestWorkflow
        @eval Sparrow.@workflow_type DistributedTestWorkflow

        wf = DistributedTestWorkflow(
            base_working_dir="/tmp/test",
            base_archive_dir="/tmp/archive",
            base_data_dir="/tmp/data",
            num_workers=2,
            minute_span=10,
            force_reprocess=false,
            reverse=false,
            datetime="20250101",
            realtime=false,
            raw_moment_names=["DBZ", "VEL"],
            qc_moment_names=["DBZ_QC", "VEL_QC"],
            moment_grid_type=[:linear, :linear]
        )

        # Send workflow to worker and verify parameters
        result = remotecall_fetch((w) -> begin
            @assert w isa Sparrow.SparrowWorkflow
            @assert w["minute_span"] == 10
            @assert w["base_working_dir"] == "/tmp/test"
            @assert length(w["raw_moment_names"]) == 2
            return "workflow_received"
        end, new_pids[1], wf)

        @test result == "workflow_received"

        # Test get_param on worker
        result2 = remotecall_fetch((w) -> begin
            return Sparrow.get_param(w, "minute_span", 5)
        end, new_pids[1], wf)
        @test result2 == 10

        # Test missing param with default on worker
        result3 = remotecall_fetch((w) -> begin
            return Sparrow.get_param(w, "nonexistent", "default_val")
        end, new_pids[1], wf)
        @test result3 == "default_val"

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "setup_workers Local Mode" begin
        # Test that setup_workers creates the right number of local workers
        parsed_args = Sparrow.parse_arguments(["workflow.jl", "--num_workers", "2"])

        # Suppress info messages during test
        prev_level = Sparrow.MSG_LEVEL[]
        Sparrow.set_message_level(Sparrow.MSG_ERROR + 1)  # Warnings only

        Sparrow.setup_workers(parsed_args)

        Sparrow.set_message_level(prev_level)

        # Should have 2 workers
        w = workers()
        @test length(w) >= 2

        # Sparrow should be loaded on workers (setup_workers does @everywhere using Sparrow)
        for wid in w
            @test remotecall_fetch(() -> isdefined(Main, :Sparrow), wid)
        end

        # Clean up
        rmprocs(w)
        sleep(0.5)
    end

    @testset "SlurmManager Environment Validation" begin
        # SlurmManager requires SLURM_JOB_ID and SLURM_NTASKS env vars.
        # Without them, construction should fail.

        # Make sure env vars are NOT set (we're on a laptop)
        for var in ["SLURM_JOB_ID", "SLURM_JOBID", "SLURM_NTASKS"]
            delete!(ENV, var)
        end

        @test_throws ErrorException SlurmManager()

        # Test that setting only SLURM_JOB_ID without SLURM_NTASKS also fails
        ENV["SLURM_JOB_ID"] = "12345"
        @test_throws ErrorException SlurmManager()

        # Test that setting both env vars allows construction
        ENV["SLURM_NTASKS"] = "4"
        mgr = SlurmManager()
        @test mgr.jobid == 12345
        @test mgr.ntasks == 4
        @test mgr.launch_timeout == 60.0

        # Test SLURM_JOBID alternative
        delete!(ENV, "SLURM_JOB_ID")
        ENV["SLURM_JOBID"] = "67890"
        mgr2 = SlurmManager()
        @test mgr2.jobid == 67890

        # Test custom launch_timeout
        mgr3 = SlurmManager(launch_timeout=120.0)
        @test mgr3.launch_timeout == 120.0

        # Clean up env vars
        for var in ["SLURM_JOB_ID", "SLURM_JOBID", "SLURM_NTASKS"]
            delete!(ENV, var)
        end
    end

    @testset "Task Queue Overflow Pattern" begin
        # Test the queue-full waiting pattern from assign_workers realtime mode
        new_pids = addprocs(2)

        num_workers = length(new_pids)
        tasks = Array{Distributed.Future}(undef, num_workers)
        filequeue = fill("none", num_workers)

        # Fill all task slots
        for (i, w) in enumerate(new_pids)
            filequeue[i] = "file_$(i).nc"
            tasks[i] = remotecall(() -> begin
                sleep(0.5)
                return "done"
            end, w)
        end

        # Queue should be full — no "none" slots
        @test !any(f -> f == "none", filequeue)

        # Simulate waiting for a free slot (like the inner loop in assign_workers)
        free_task = -1
        for t in 1:num_workers
            if isready(tasks[t])
                status = fetch(tasks[t])
                @test status == "done"
                filequeue[t] = "waiting_file.nc"
                free_task = t
                break
            end
        end

        # If no task was immediately ready, wait for one
        if free_task == -1
            # Wait for any task to complete
            for t in 1:num_workers
                wait(tasks[t])
                status = fetch(tasks[t])
                @test status == "done"
                filequeue[t] = "waiting_file.nc"
                free_task = t
                break
            end
        end

        @test free_task != -1
        @test filequeue[free_task] == "waiting_file.nc"

        # Wait for remaining tasks
        for t in 1:num_workers
            if filequeue[t] != "waiting_file.nc" && filequeue[t] != "none"
                wait(tasks[t])
                fetch(tasks[t])
                filequeue[t] = "none"
            end
        end

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "check_processed with Workers" begin
        new_pids = addprocs(1)
        @everywhere new_pids using Sparrow

        # Define the workflow type on all processes so it can be serialized
        @everywhere new_pids @eval Sparrow.@workflow_type ProcessCheckWorkflow
        @eval Sparrow.@workflow_type ProcessCheckWorkflow

        mktempdir() do tmpdir
            archive_dir = joinpath(tmpdir, "archive")
            mkpath(archive_dir)

            wf = ProcessCheckWorkflow(
                base_archive_dir=archive_dir
            )

            # File should not be processed initially
            @test !Sparrow.check_processed(wf, "test_file.nc", archive_dir)

            # check_processed should also work on a worker
            result = remotecall_fetch((w, f, d) -> Sparrow.check_processed(w, f, d),
                                       new_pids[1], wf, "test_file.nc", archive_dir)
            @test !result

            # Mark file as processed
            processed_dir = joinpath(archive_dir, ".sparrow")
            mkpath(processed_dir)
            touch(joinpath(processed_dir, "ProcessCheckWorkflow_test_file.nc"))

            # Now it should show as processed
            @test Sparrow.check_processed(wf, "test_file.nc", archive_dir)

            # Worker should also see it as processed
            result2 = remotecall_fetch((w, f, d) -> Sparrow.check_processed(w, f, d),
                                        new_pids[1], wf, "test_file.nc", archive_dir)
            @test result2
        end

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "Multiple Workers Processing Concurrently" begin
        # Simulate the core pattern: multiple workers processing different files
        new_pids = addprocs(3)

        results = Dict{Int, String}()
        tasks = Dict{Int, Future}()

        # Launch concurrent tasks on all workers
        for (i, w) in enumerate(new_pids)
            tasks[i] = remotecall((file_id) -> begin
                # Simulate some processing work
                sleep(0.1 * file_id)
                return "processed_file_$(file_id)"
            end, w, i)
        end

        # Collect results as they complete (non-blocking polling)
        completed = Set{Int}()
        max_iterations = 100
        iteration = 0
        while length(completed) < length(new_pids) && iteration < max_iterations
            for (i, task) in tasks
                if i in completed
                    continue
                end
                if isready(task)
                    results[i] = fetch(task)
                    push!(completed, i)
                end
            end
            if length(completed) < length(new_pids)
                sleep(0.05)
            end
            iteration += 1
        end

        # All tasks should have completed
        @test length(completed) == length(new_pids)
        @test results[1] == "processed_file_1"
        @test results[2] == "processed_file_2"
        @test results[3] == "processed_file_3"

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "Built-in Step Types Exported to Workers" begin
        # Test that built-in workflow step types are accessible on workers
        # This is the core fix: these types must be available after `using Sparrow`
        new_pids = addprocs(2)
        @everywhere new_pids using Sparrow

        built_in_steps = [
            :GridRHIStep, :GridCompositeStep, :GridVolumeStep,
            :GridLatlonStep, :GridPPIStep, :GridQVPStep,
            :RadxConvertStep, :RoninQCStep,
            :PassThroughStep, :filterByTimeStep
        ]

        for step_name in built_in_steps
            for w in new_pids
                is_defined = remotecall_fetch((s) -> isdefined(Sparrow, s), w, step_name)
                @test is_defined
            end
        end

        # Also verify they are usable as types (not just defined)
        for w in new_pids
            result = remotecall_fetch(() -> begin
                GridRHIStep isa DataType &&
                PassThroughStep isa DataType &&
                RoninQCStep isa DataType
            end, w)
            @test result
        end

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "Workflow File Loading in Sparrow Scope" begin
        # Test that loading a workflow file via Base.include(Sparrow, ...) works
        # on both main process and workers, and that types are consistent
        new_pids = addprocs(2)
        @everywhere new_pids using Sparrow

        workflow_file = joinpath(@__DIR__, "fixtures", "distributed_test_workflow.jl")

        # Load on main process in Sparrow scope
        Base.include(Sparrow, workflow_file)

        # The workflow variable should be defined in Sparrow
        @test isdefined(Sparrow, :workflow)
        @test Sparrow.workflow isa Sparrow.SparrowWorkflow

        # Custom step type should be defined in Sparrow
        @test isdefined(Sparrow, :CustomDistTestStep)
        @test isdefined(Sparrow, :DistributedScopeTestWorkflow)

        # The steps should reference the correct types
        wf = Sparrow.workflow
        steps = wf["steps"]
        @test steps[1][2] === Sparrow.PassThroughStep
        @test steps[2][2] === Sparrow.CustomDistTestStep
        @test steps[3][2] === Sparrow.GridRHIStep

        # Load on workers (same as main() does)
        @everywhere new_pids begin
            Base.include(Sparrow, $workflow_file)
        end

        # Verify types are consistent between main and workers
        for w in new_pids
            result = remotecall_fetch(() -> begin
                # Custom type should exist in Sparrow scope
                isdefined(Sparrow, :CustomDistTestStep) &&
                isdefined(Sparrow, :DistributedScopeTestWorkflow) &&
                # Built-in types should still work
                isdefined(Sparrow, :GridRHIStep) &&
                isdefined(Sparrow, :PassThroughStep)
            end, w)
            @test result
        end

        # Verify the workflow can be serialized to workers with correct types
        for w in new_pids
            result = remotecall_fetch((wf) -> begin
                steps = wf["steps"]
                # Types should match the ones in Sparrow module on this worker
                steps[1][2] === Sparrow.PassThroughStep &&
                steps[2][2] === Sparrow.CustomDistTestStep &&
                steps[3][2] === Sparrow.GridRHIStep
            end, w, wf)
            @test result
        end

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "World Age: include from function then access bindings" begin
        # Reproduces the exact pattern in main(): Base.include called from within
        # a compiled function, then accessing newly created bindings.
        # invokelatest is used for safety to cross any world-age barriers.
        new_pids = addprocs(1)
        @everywhere new_pids using Sparrow

        workflow_file = joinpath(@__DIR__, "fixtures", "world_age_test_workflow.jl")

        # Simulate main()'s pattern: include from a function, then access bindings
        function test_include_from_function()
            Base.include(Sparrow, workflow_file)

            # invokelatest safely crosses the world-age boundary
            invokelatest_result = Base.invokelatest(isdefined, Sparrow, :WorldAgeTestWorkflow)

            # getfield via invokelatest should work
            wf = Base.invokelatest(getfield, Sparrow, :workflow)
            wf_valid = wf isa Sparrow.SparrowWorkflow

            return (invokelatest_result, wf_valid)
        end

        via_invokelatest, wf_valid = test_include_from_function()

        @test via_invokelatest  # invokelatest sees the new binding
        @test wf_valid  # Workflow object is valid

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "World Age: worker hasmethod sees workflow_step after include" begin
        # The critical path: after @everywhere Base.include(Sparrow, workflow_file),
        # workers must see user-defined workflow_step methods via hasmethod.
        # This is what run_workflow_step uses for dispatch.
        new_pids = addprocs(2)
        @everywhere new_pids using Sparrow

        workflow_file = joinpath(@__DIR__, "fixtures", "world_age_test_workflow.jl")

        # Load on workers via @everywhere (same pattern as main())
        @everywhere new_pids begin
            Base.include(Sparrow, $workflow_file)
        end

        for w in new_pids
            # hasmethod should see the user-defined workflow_step for the custom step
            result = remotecall_fetch(() -> begin
                hasmethod(Sparrow.workflow_step,
                    (Sparrow.WorldAgeTestWorkflow, Type{Sparrow.WorldAgeCustomStep}, String, String))
            end, w)
            @test result

            # hasmethod should also see built-in steps with the new workflow type
            # (PassThroughStep is defined for SparrowWorkflow, which WorldAgeTestWorkflow subtypes)
            result2 = remotecall_fetch(() -> begin
                hasmethod(Sparrow.workflow_step,
                    (Sparrow.SparrowWorkflow, Type{Sparrow.PassThroughStep}, String, String))
            end, w)
            @test result2
        end

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "World Age: worker dispatches user-defined workflow_step" begin
        # End-to-end test: load workflow file on worker, then actually call
        # the user-defined workflow_step method and verify it executes.
        new_pids = addprocs(2)
        @everywhere new_pids using Sparrow, Dates

        workflow_file = joinpath(@__DIR__, "fixtures", "world_age_test_workflow.jl")

        # Load on main (with invokelatest to get the workflow)
        Base.include(Sparrow, workflow_file)
        wf = Base.invokelatest(getfield, Sparrow, :workflow)

        # Load on workers
        @everywhere new_pids begin
            Base.include(Sparrow, $workflow_file)
        end

        # Call the custom workflow_step on each worker
        for w in new_pids
            result = remotecall_fetch((wf) -> begin
                outdir = mktempdir()
                ret = Sparrow.workflow_step(wf, Sparrow.WorldAgeCustomStep,
                    tempdir(), outdir;
                    step_name="test", step_num=1,
                    start_time=DateTime(2024,1,1),
                    stop_time=DateTime(2024,1,2))
                return ret
            end, w, wf)
            @test result == "world_age_custom_step_executed"
        end

        # Also verify built-in step dispatch works with the new workflow type
        for w in new_pids
            result = remotecall_fetch((wf) -> begin
                indir = mktempdir()
                outdir = mktempdir()
                # PassThroughStep is defined for SparrowWorkflow — should work
                # with WorldAgeTestWorkflow since it's a subtype
                Sparrow.workflow_step(wf, Sparrow.PassThroughStep,
                    indir, outdir;
                    step_name="test_pass", step_num=1,
                    start_time=DateTime(2024,1,1),
                    stop_time=DateTime(2024,1,2))
                return true
            end, w, wf)
            @test result
        end

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "World Age: workflow type serialization across processes" begin
        # Test that workflow objects with types defined at runtime serialize
        # correctly to workers and maintain type identity.
        new_pids = addprocs(2)
        @everywhere new_pids using Sparrow

        workflow_file = joinpath(@__DIR__, "fixtures", "world_age_test_workflow.jl")

        # Load on main and workers
        Base.include(Sparrow, workflow_file)
        wf = Base.invokelatest(getfield, Sparrow, :workflow)

        @everywhere new_pids begin
            Base.include(Sparrow, $workflow_file)
        end

        for w in new_pids
            # Verify the deserialized workflow has the correct concrete type
            result = remotecall_fetch((wf) -> begin
                type_name = string(typeof(wf))
                is_sparrow = wf isa Sparrow.SparrowWorkflow
                has_marker = wf["test_marker"] == "world_age_test"
                # Step types must be identical (===) to those on this worker
                steps = wf["steps"]
                types_match = steps[1][2] === Sparrow.PassThroughStep &&
                              steps[2][2] === Sparrow.WorldAgeCustomStep
                return (type_name, is_sparrow, has_marker, types_match)
            end, w, wf)

            type_name, is_sparrow, has_marker, types_match = result
            @test occursin("WorldAgeTestWorkflow", type_name)
            @test is_sparrow
            @test has_marker
            @test types_match
        end

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "World Age: run_workflow_step dispatch chain on worker" begin
        # Test the actual dispatch chain used in production:
        # run_workflow_step → hasmethod → workflow_step
        # This must work on workers after loading a workflow file at runtime.
        new_pids = addprocs(1)
        @everywhere new_pids using Sparrow, Dates

        workflow_file = joinpath(@__DIR__, "fixtures", "world_age_test_workflow.jl")

        # Load on main and worker
        Base.include(Sparrow, workflow_file)
        wf = Base.invokelatest(getfield, Sparrow, :workflow)

        @everywhere new_pids begin
            Base.include(Sparrow, $workflow_file)
        end

        # Simulate what process_volume does: call run_workflow_step on a worker
        # for both built-in and custom steps
        for step_num in 1:2
            result = remotecall_fetch((wf, sn) -> begin
                temp_dir = mktempdir()
                steps = wf["steps"]
                step_name, step_type, input_name, archive = steps[sn]

                # Create the directories that run_workflow_step expects
                date = "20240101"
                input_dir = joinpath(temp_dir, input_name, date)
                output_dir = joinpath(temp_dir, step_name, date)
                mkpath(input_dir)
                mkpath(output_dir)

                # Test hasmethod (same check as run_workflow_step)
                has_specific = hasmethod(Sparrow.workflow_step,
                    (typeof(wf), Type{step_type}, String, String))
                has_generic = hasmethod(Sparrow.workflow_step,
                    (Sparrow.SparrowWorkflow, Type{step_type}, String, String))

                # Actually call workflow_step
                Sparrow.workflow_step(wf, step_type, input_dir, output_dir;
                    step_name=step_name, step_num=sn,
                    start_time=DateTime(2024,1,1),
                    stop_time=DateTime(2024,1,2))

                rm(temp_dir; recursive=true)
                return (has_specific || has_generic, step_name)
            end, new_pids[1], wf, step_num)

            dispatched, name = result
            @test dispatched
        end

        rmprocs(new_pids)
        sleep(0.5)
    end

    @testset "Idempotent @workflow_step Macro" begin
        # Test that re-declaring an existing step type doesn't error
        # This is important for workflow files that include @workflow_step for built-in steps
        new_pids = addprocs(1)
        @everywhere new_pids using Sparrow

        # Re-declaring built-in steps on a worker should not error
        result = remotecall_fetch(() -> begin
            try
                # These are already defined in Sparrow, re-declaring should be a no-op
                @eval Sparrow begin
                    @workflow_step PassThroughStep
                    @workflow_step GridRHIStep
                    @workflow_step RoninQCStep
                end
                return true
            catch e
                return false
            end
        end, new_pids[1])
        @test result

        # Verify the types are still the same (not replaced)
        result2 = remotecall_fetch(() -> begin
            Sparrow.PassThroughStep isa DataType &&
            Sparrow.GridRHIStep isa DataType &&
            Sparrow.RoninQCStep isa DataType
        end, new_pids[1])
        @test result2

        rmprocs(new_pids)
        sleep(0.5)
    end

end
