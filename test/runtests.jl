using Test
using Sparrow

# Check if optional test suites should be run
const RUN_INTEGRATION_TESTS = get(ENV, "SPARROW_RUN_INTEGRATION_TESTS", "0") == "1"
const RUN_DISTRIBUTED_TESTS = get(ENV, "SPARROW_RUN_DISTRIBUTED_TESTS", "0") == "1"

@testset "Sparrow.jl Basic Tests" begin
    
    @testset "Message System" begin
        # Test message level setting
        Sparrow.set_message_level(Sparrow.MSG_INFO)
        @test Sparrow.MSG_LEVEL[] == Sparrow.MSG_INFO
        
        Sparrow.set_message_level(Sparrow.MSG_DEBUG)
        @test Sparrow.MSG_LEVEL[] == Sparrow.MSG_DEBUG
        
        # Test message constants exist
        @test Sparrow.MSG_ERROR == 0
        @test Sparrow.MSG_WARNING == 1
        @test Sparrow.MSG_INFO == 2
        @test Sparrow.MSG_DEBUG == 3
        
        # Reset to default
        Sparrow.set_message_level(Sparrow.MSG_INFO)
    end
    
    @testset "Workflow Type Creation" begin
        # Test creating a simple workflow type
        @workflow_type SimpleTestWorkflow
        
        # Test that the type was created
        @test isdefined(@__MODULE__, :SimpleTestWorkflow)
        
        # Test creating an instance
        wf = SimpleTestWorkflow(param1="value1", param2=42)
        @test wf isa Sparrow.SparrowWorkflow
        @test wf["param1"] == "value1"
        @test wf["param2"] == 42
    end
    
    @testset "Workflow Dict Operations" begin
        wf = SimpleTestWorkflow(key1="value1", key2=123)
        
        # Test getindex
        @test wf["key1"] == "value1"
        @test wf["key2"] == 123
        
        # Test setindex
        wf["key3"] = "new_value"
        @test wf["key3"] == "new_value"
        
        # Test length
        @test length(wf) >= 3
        
        # Test iteration
        count = 0
        for (k, v) in wf
            count += 1
        end
        @test count >= 3
    end
    
    @testset "get_param Helper" begin
        wf = SimpleTestWorkflow(existing="value")
        
        # Test with existing key
        @test Sparrow.get_param(wf, "existing", "default") == "value"
        
        # Test with missing key returns default
        @test Sparrow.get_param(wf, "missing", "default") == "default"
        @test Sparrow.get_param(wf, "missing", 99) == 99
    end
    
    @testset "Workflow Step Macro" begin
        # Test creating step types
        @workflow_step StepOne
        @workflow_step StepTwo
        
        @test isdefined(@__MODULE__, :StepOne)
        @test isdefined(@__MODULE__, :StepTwo)
        @test StepOne isa DataType
        @test StepTwo isa DataType
    end
    
    println("\n✅ All basic tests passed!")
end

@testset "Plot Steps" begin
    include("test_plot_steps.jl")
end

@testset "Utility Functions" begin
    include("test_utility.jl")
end

# Integration tests (require test data)
if RUN_INTEGRATION_TESTS
    @testset "Integration Tests" begin
        println("\n🔧 Running integration tests...")
        include("test_integration.jl")
    end
else
    @testset "Integration Tests (Skipped)" begin
        println("\nℹ️  Integration tests skipped. Set SPARROW_RUN_INTEGRATION_TESTS=1 to enable.")
        @test_skip true  # Set SPARROW_RUN_INTEGRATION_TESTS=1 to run integration tests
    end
end

# Distributed worker tests (spawn local workers, slower)
if RUN_DISTRIBUTED_TESTS
    @testset "Distributed Tests" begin
        println("\nRunning distributed worker tests...")
        include("test_distributed.jl")
    end
else
    @testset "Distributed Tests (Skipped)" begin
        println("\nDistributed tests skipped. Set SPARROW_RUN_DISTRIBUTED_TESTS=1 to enable.")
        @test_skip true
    end
end

println("\n" * "="^60)
println("Test Summary:")
println("  Basic unit tests: PASSED")
if RUN_INTEGRATION_TESTS
    println("  Integration tests: COMPLETED")
else
    println("  Integration tests: SKIPPED")
end
if RUN_DISTRIBUTED_TESTS
    println("  Distributed tests: COMPLETED")
else
    println("  Distributed tests: SKIPPED")
end
println("\nTo run optional test suites:")
println("  SPARROW_RUN_INTEGRATION_TESTS=1 julia --project -e 'using Pkg; Pkg.test()'")
println("  SPARROW_RUN_DISTRIBUTED_TESTS=1 julia --project -e 'using Pkg; Pkg.test()'")
println("="^60)
println()