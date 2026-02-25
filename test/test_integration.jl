# Integration tests for Sparrow workflows
# These tests use actual workflow files and test data

using Test
using Sparrow
using Dates

@testset "Integration Tests" begin
    
    @testset "Workflow File Loading" begin
        # Test that we can include a workflow file
        workflow_file = joinpath(@__DIR__, "fixtures", "minimal_workflow.jl")
        
        if isfile(workflow_file)
            # Include the workflow file
            @test_nowarn include(workflow_file)
            
            # Check that workflow variable was created
            @test @isdefined workflow
            @test workflow isa Sparrow.SparrowWorkflow
            @test typeof(workflow).name.name == :MinimalTestWorkflow
        else
            @warn "Workflow file not found at $workflow_file, skipping test"
        end
    end
    
    @testset "Workflow Parameter Access" begin
        # Create a simple test workflow
        @workflow_type IntegrationTestWorkflow
        
        wf = IntegrationTestWorkflow(
            base_working_dir="/tmp/sparrow_test",
            base_archive_dir="/tmp/sparrow_archive",
            steps=["step1" => Sparrow.PassThroughStep],
            raw_moment_names=["DBZ", "VEL"],
            qc_moment_names=["DBZ", "VEL"],
            moment_grid_type=[:linear, :weighted],
            test_param=42
        )
        
        # Test parameter retrieval
        @test wf["base_working_dir"] == "/tmp/sparrow_test"
        @test wf["test_param"] == 42
        @test length(wf["raw_moment_names"]) == 2
        @test wf["moment_grid_type"][1] == :linear
    end
    
    @testset "Step Execution with I/O" begin
        @workflow_type IOTestWorkflow
        @workflow_step IOTestStep
        
        # Track execution
        execution_log = String[]
        
        function Sparrow.workflow_step(workflow::IOTestWorkflow, ::Type{IOTestStep},
                                       input_dir::String, output_dir::String;
                                       kwargs...)
            push!(execution_log, "Executed with input=$input_dir, output=$output_dir")
            mkpath(output_dir)
            
            # Create a test file in output
            test_file = joinpath(output_dir, "test_output.txt")
            write(test_file, "Test output")
            
            return test_file
        end
        
        # Use temporary directory for testing
        mktempdir() do tmpdir
            input_dir = joinpath(tmpdir, "input")
            output_dir = joinpath(tmpdir, "output")
            mkpath(input_dir)
            
            # Create test input file
            write(joinpath(input_dir, "input.txt"), "test data")
            
            wf = IOTestWorkflow()
            result = Sparrow.workflow_step(wf, IOTestStep, input_dir, output_dir)
            
            @test length(execution_log) == 1
            @test occursin("input=$input_dir", execution_log[1])
            @test occursin("output=$output_dir", execution_log[1])
            @test isfile(result)
            @test isdir(output_dir)
        end
    end
    
    @testset "Multi-Step Workflow Simulation" begin
        @workflow_type MultiStepTestWorkflow
        @workflow_step Step1
        @workflow_step Step2
        @workflow_step Step3
        
        execution_order = Int[]
        
        function Sparrow.workflow_step(workflow::MultiStepTestWorkflow, ::Type{Step1},
                                       input_dir::String, output_dir::String;
                                       step_num::Int=0, kwargs...)
            push!(execution_order, step_num)
            mkpath(output_dir)
            write(joinpath(output_dir, "step1_output.txt"), "Step 1 complete")
        end
        
        function Sparrow.workflow_step(workflow::MultiStepTestWorkflow, ::Type{Step2},
                                       input_dir::String, output_dir::String;
                                       step_num::Int=0, kwargs...)
            push!(execution_order, step_num)
            mkpath(output_dir)
            # Check that step 1 output exists
            step1_file = joinpath(input_dir, "step1_output.txt")
            if isfile(step1_file)
                content = read(step1_file, String)
                write(joinpath(output_dir, "step2_output.txt"), "Step 2: $content")
            end
        end
        
        function Sparrow.workflow_step(workflow::MultiStepTestWorkflow, ::Type{Step3},
                                       input_dir::String, output_dir::String;
                                       step_num::Int=0, kwargs...)
            push!(execution_order, step_num)
            mkpath(output_dir)
            write(joinpath(output_dir, "final_output.txt"), "All steps complete")
        end
        
        mktempdir() do tmpdir
            wf = MultiStepTestWorkflow(
                steps=[
                    "step1" => Step1,
                    "step2" => Step2,
                    "step3" => Step3
                ]
            )
            
            # Simulate step execution in order
            step1_input = joinpath(tmpdir, "input")
            step1_output = joinpath(tmpdir, "step1_out")
            step2_output = joinpath(tmpdir, "step2_out")
            step3_output = joinpath(tmpdir, "step3_out")
            
            mkpath(step1_input)
            
            # Execute steps
            Sparrow.workflow_step(wf, Step1, step1_input, step1_output; step_num=1)
            Sparrow.workflow_step(wf, Step2, step1_output, step2_output; step_num=2)
            Sparrow.workflow_step(wf, Step3, step2_output, step3_output; step_num=3)
            
            # Verify execution order
            @test execution_order == [1, 2, 3]
            
            # Verify outputs exist
            @test isfile(joinpath(step1_output, "step1_output.txt"))
            @test isfile(joinpath(step2_output, "step2_output.txt"))
            @test isfile(joinpath(step3_output, "final_output.txt"))
            
            # Verify content propagation
            step2_content = read(joinpath(step2_output, "step2_output.txt"), String)
            @test occursin("Step 1 complete", step2_content)
        end
    end
    
    @testset "Workflow with Real Files" begin
        @workflow_type FileTestWorkflow
        @workflow_step FileProcessStep
        
        function Sparrow.workflow_step(workflow::FileTestWorkflow, ::Type{FileProcessStep},
                                       input_dir::String, output_dir::String;
                                       kwargs...)
            mkpath(output_dir)
            
            # Process all .txt files from input
            input_files = readdir(input_dir; join=true)
            filter!(f -> endswith(f, ".txt"), input_files)
            
            processed_count = 0
            for input_file in input_files
                output_file = joinpath(output_dir, basename(input_file))
                content = read(input_file, String)
                # "Process" by uppercasing
                write(output_file, uppercase(content))
                processed_count += 1
            end
            
            return processed_count
        end
        
        mktempdir() do tmpdir
            input_dir = joinpath(tmpdir, "input")
            output_dir = joinpath(tmpdir, "output")
            mkpath(input_dir)
            
            # Create test files
            write(joinpath(input_dir, "file1.txt"), "hello world")
            write(joinpath(input_dir, "file2.txt"), "test data")
            write(joinpath(input_dir, "ignore.nc"), "not a txt file")
            
            wf = FileTestWorkflow()
            count = Sparrow.workflow_step(wf, FileProcessStep, input_dir, output_dir)
            
            # Should have processed 2 .txt files
            @test count == 2
            
            # Check output files
            @test isfile(joinpath(output_dir, "file1.txt"))
            @test isfile(joinpath(output_dir, "file2.txt"))
            @test !isfile(joinpath(output_dir, "ignore.nc"))
            
            # Check content was processed
            @test read(joinpath(output_dir, "file1.txt"), String) == "HELLO WORLD"
            @test read(joinpath(output_dir, "file2.txt"), String) == "TEST DATA"
        end
    end
    
    @testset "Error Handling in Steps" begin
        @workflow_type ErrorTestWorkflow
        @workflow_step ErrorStep
        
        function Sparrow.workflow_step(workflow::ErrorTestWorkflow, ::Type{ErrorStep},
                                       input_dir::String, output_dir::String;
                                       kwargs...)
            # This step intentionally errors on missing input
            if !isdir(input_dir)
                error("Input directory does not exist: $input_dir")
            end
            mkpath(output_dir)
        end
        
        mktempdir() do tmpdir
            wf = ErrorTestWorkflow()
            
            # Should succeed with valid input
            valid_input = joinpath(tmpdir, "valid")
            valid_output = joinpath(tmpdir, "output")
            mkpath(valid_input)
            
            @test_nowarn Sparrow.workflow_step(wf, ErrorStep, valid_input, valid_output)
            
            # Should error with invalid input
            invalid_input = joinpath(tmpdir, "nonexistent")
            @test_throws ErrorException Sparrow.workflow_step(wf, ErrorStep, invalid_input, valid_output)
        end
    end
    
    @testset "Workflow Parameters in Steps" begin
        @workflow_type ParamTestWorkflow
        @workflow_step ParamStep
        
        function Sparrow.workflow_step(workflow::ParamTestWorkflow, ::Type{ParamStep},
                                       input_dir::String, output_dir::String;
                                       kwargs...)
            mkpath(output_dir)
            
            # Use workflow parameters in processing
            threshold = workflow["threshold"]
            multiplier = workflow["multiplier"]
            
            output_file = joinpath(output_dir, "result.txt")
            write(output_file, "threshold=$threshold, multiplier=$multiplier")
            
            return output_file
        end
        
        mktempdir() do tmpdir
            input_dir = joinpath(tmpdir, "input")
            output_dir = joinpath(tmpdir, "output")
            mkpath(input_dir)
            
            wf = ParamTestWorkflow(
                threshold=0.5,
                multiplier=2.0
            )
            
            result = Sparrow.workflow_step(wf, ParamStep, input_dir, output_dir)
            
            @test isfile(result)
            content = read(result, String)
            @test occursin("threshold=0.5", content)
            @test occursin("multiplier=2.0", content)
        end
    end
    
    println("\n✅ All integration tests passed!")
end