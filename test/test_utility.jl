using Test
using Sparrow
using Dates

@testset "Utility Functions" begin
    
    @testset "Message System" begin
        # Test message level setting
        Sparrow.set_message_level(Sparrow.MSG_DEBUG)
        @test Sparrow.MSG_LEVEL[] == Sparrow.MSG_DEBUG
        
        Sparrow.set_message_level(Sparrow.MSG_INFO)
        @test Sparrow.MSG_LEVEL[] == Sparrow.MSG_INFO
        
        # Test that messages don't crash
        @test_nowarn Sparrow.msg_info("Test info message")
        @test_nowarn Sparrow.msg_warning("Test warning message")
        @test_nowarn Sparrow.msg_debug("Test debug message")
        @test_nowarn Sparrow.msg_trace("Test trace message")
        
        # Test that error messages throw
        @test_throws Exception Sparrow.msg_error("Test error message")
    end
    
    @testset "get_scan_start" begin
        # Test CfRadial filename parsing
        cfrad_file = "cfrad.20240816_081147.897_to_20240816_082005.026_SEAPOL_SUR.nc"
        expected_time = DateTime(2024, 8, 16, 8, 11)
        @test Sparrow.get_scan_start(cfrad_file) == expected_time
        
        # Test SEAPOL filename parsing
        seapol_file = "SEA20240816_081147"
        expected_time = DateTime(2024, 8, 16, 8, 11)
        @test Sparrow.get_scan_start(seapol_file) == expected_time
        
        # Test unknown format throws error
        @test_throws Exception Sparrow.get_scan_start("unknown_format.nc")
    end
    
    @testset "Workflow Step Macro" begin
        # Test that workflow step macro creates a struct
        @workflow_step TestStep
        @test isdefined(Main, :TestStep)
        @test TestStep isa DataType
        
        # Test that the step type can be instantiated (it's an empty struct)
        @test TestStep() isa TestStep
    end
    
end