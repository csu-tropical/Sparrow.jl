# Test workflow types and basic workflow functionality

using Test
using Sparrow
using Dates

@testset "Workflow Types" begin
    
    @testset "Workflow Type Creation" begin
        # Test creating a workflow type
        @workflow_type TestWorkflow1
        
        # Test that the type exists and is a subtype of SparrowWorkflow
        @test TestWorkflow1 <: Sparrow.SparrowWorkflow
        
        # Test creating an instance
        wf = TestWorkflow1(param1="value1", param2=42)
        @test wf isa Sparrow.SparrowWorkflow
        @test wf["param1"] == "value1"
        @test wf["param2"] == 42
    end
    
    @testset "Workflow Dict Access" begin
        wf = TestWorkflow1(key1="value1", key2=123, key3=true)
        
        # Test getindex
        @test wf["key1"] == "value1"
        @test wf["key2"] == 123
        @test wf["key3"] == true
        
        # Test setindex
        wf["key4"] = "new_value"
        @test wf["key4"] == "new_value"
        
        # Test that accessing non-existent key throws error
        @test_throws ErrorException wf["nonexistent_key"]
    end
    
    @testset "Workflow get_param" begin
        wf = TestWorkflow1(existing="value")
        
        # Test get_param with existing key
        @test Sparrow.get_param(wf, "existing", "default") == "value"
        
        # Test get_param with default value
        @test Sparrow.get_param(wf, "missing", "default") == "default"
        @test Sparrow.get_param(wf, "missing", 99) == 99
    end
    
    @testset "Workflow Iteration" begin
        wf = TestWorkflow1(a=1, b=2, c=3)
        
        # Test that workflow can be iterated
        count = 0
        for (k, v) in wf
            count += 1
            @test k isa String
        end
        @test count == 3
        
        # Test length
        @test length(wf) == 3
    end
    
    @testset "Multiple Workflow Types" begin
        @workflow_type WorkflowA
        @workflow_type WorkflowB
        
        wf_a = WorkflowA(type="A")
        wf_b = WorkflowB(type="B")
        
        @test typeof(wf_a) != typeof(wf_b)
        @test wf_a["type"] == "A"
        @test wf_b["type"] == "B"
    end
end

@testset "Workflow Steps" begin
    
    @testset "Step Type Creation" begin
        @workflow_step TestStep1
        @workflow_step TestStep2
        
        # Test that step types are created
        @test TestStep1 isa DataType
        @test TestStep2 isa DataType
    end
    
    @testset "Step Dispatch" begin
        @workflow_type TestWorkflow2
        @workflow_step StepA
        @workflow_step StepB
        
        # Track which steps were called
        called_steps = String[]
        
        # Define step implementations
        function Sparrow.workflow_step(workflow::TestWorkflow2, ::Type{StepA}, 
                                       input_dir::String, output_dir::String; kwargs...)
            push!(called_steps, "StepA")
        end
        
        function Sparrow.workflow_step(workflow::TestWorkflow2, ::Type{StepB}, 
                                       input_dir::String, output_dir::String; kwargs...)
            push!(called_steps, "StepB")
        end
        
        wf = TestWorkflow2()
        
        # Call steps
        Sparrow.workflow_step(wf, StepA, "/in", "/out")
        Sparrow.workflow_step(wf, StepB, "/in", "/out")
        
        @test called_steps == ["StepA", "StepB"]
    end
    
    @testset "Step with kwargs" begin
        @workflow_type TestWorkflow3
        @workflow_step StepWithKwargs
        
        received_kwargs = Dict()
        
        function Sparrow.workflow_step(workflow::TestWorkflow3, ::Type{StepWithKwargs},
                                       input_dir::String, output_dir::String;
                                       step_name::String="", step_num::Int=0, kwargs...)
            received_kwargs[:step_name] = step_name
            received_kwargs[:step_num] = step_num
        end
        
        wf = TestWorkflow3()
        Sparrow.workflow_step(wf, StepWithKwargs, "/in", "/out"; 
                             step_name="test", step_num=5)
        
        @test received_kwargs[:step_name] == "test"
        @test received_kwargs[:step_num] == 5
    end
end

@testset "Workflow Parameters" begin
    
    @testset "Parameter Storage" begin
        wf = TestWorkflow1(
            base_dir="/path/to/data",
            threshold=0.5,
            enabled=true,
            count=10
        )
        
        @test wf["base_dir"] == "/path/to/data"
        @test wf["threshold"] == 0.5
        @test wf["enabled"] == true
        @test wf["count"] == 10
    end
    
    @testset "Parameter Modification" begin
        wf = TestWorkflow1(original=1)
        
        # Modify existing parameter
        wf["original"] = 2
        @test wf["original"] == 2
        
        # Add new parameter
        wf["new_param"] = "added"
        @test wf["new_param"] == "added"
    end
    
    @testset "Mixed Type Parameters" begin
        wf = TestWorkflow1(
            string_val="test",
            int_val=42,
            float_val=3.14,
            bool_val=true,
            array_val=[1, 2, 3],
            dict_val=Dict("nested" => "value")
        )
        
        @test wf["string_val"] isa String
        @test wf["int_val"] isa Int
        @test wf["float_val"] isa Float64
        @test wf["bool_val"] isa Bool
        @test wf["array_val"] isa Vector
        @test wf["dict_val"] isa Dict
    end
end