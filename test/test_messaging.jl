using Test
using Sparrow
using Dates

@testset "Messaging System" begin
    
    @testset "Message Level Setting" begin
        # Test default level
        Sparrow.set_message_level(Sparrow.MSG_INFO)
        @test Sparrow.MSG_LEVEL[] == Sparrow.MSG_INFO
        
        # Test changing levels
        Sparrow.set_message_level(Sparrow.MSG_DEBUG)
        @test Sparrow.MSG_LEVEL[] == Sparrow.MSG_DEBUG
        
        Sparrow.set_message_level(Sparrow.MSG_ERROR)
        @test Sparrow.MSG_LEVEL[] == Sparrow.MSG_ERROR
    end
    
    @testset "Message Filtering" begin
        # Capture stdout
        original_stdout = stdout
        (rd, wr) = redirect_stdout()
        
        # Set to INFO level - should show INFO, WARNING, ERROR
        Sparrow.set_message_level(Sparrow.MSG_INFO)
        
        Sparrow.msg_info("Info message")
        Sparrow.msg_warning("Warning message")
        Sparrow.msg_debug("Debug message")  # Should NOT appear
        
        redirect_stdout(original_stdout)
        output = String(read(rd))
        close(rd)
        close(wr)
        
        @test occursin("Info message", output)
        @test occursin("Warning message", output)
        @test !occursin("Debug message", output)
    end
    
    @testset "Message with Debug Level" begin
        original_stdout = stdout
        (rd, wr) = redirect_stdout()
        
        # Set to DEBUG level - should show everything except TRACE
        Sparrow.set_message_level(Sparrow.MSG_DEBUG)
        
        Sparrow.msg_info("Info message")
        Sparrow.msg_debug("Debug message")
        Sparrow.msg_trace("Trace message")  # Should NOT appear
        
        redirect_stdout(original_stdout)
        output = String(read(rd))
        close(rd)
        close(wr)
        
        @test occursin("Info message", output)
        @test occursin("Debug message", output)
        @test !occursin("Trace message", output)
    end
    
    @testset "Error Messages Throw" begin
        Sparrow.set_message_level(Sparrow.MSG_INFO)
        
        # ERROR level should throw
        @test_throws ErrorException Sparrow.msg_error("Fatal error")
    end
    
    @testset "Warning Messages Don't Throw" begin
        original_stdout = stdout
        (rd, wr) = redirect_stdout()
        
        Sparrow.set_message_level(Sparrow.MSG_INFO)
        
        # WARNING level should NOT throw
        @test_nowarn Sparrow.msg_warning("Warning message")
        
        redirect_stdout(original_stdout)
        close(rd)
        close(wr)
    end
    
    @testset "Message Prefixes" begin
        original_stdout = stdout
        (rd, wr) = redirect_stdout()
        
        Sparrow.set_message_level(Sparrow.MSG_TRACE)
        
        Sparrow.msg_info("Test info")
        Sparrow.msg_warning("Test warning")
        Sparrow.msg_debug("Test debug")
        Sparrow.msg_trace("Test trace")
        
        redirect_stdout(original_stdout)
        output = String(read(rd))
        close(rd)
        close(wr)
        
        @test occursin("INFO", output)
        @test occursin("WARNING", output)
        @test occursin("DEBUG", output)
        @test occursin("TRACE", output)
    end
    
    @testset "Timestamp in Messages" begin
        original_stdout = stdout
        (rd, wr) = redirect_stdout()
        
        Sparrow.set_message_level(Sparrow.MSG_INFO)
        Sparrow.msg_info("Timestamped message")
        
        redirect_stdout(original_stdout)
        output = String(read(rd))
        close(rd)
        close(wr)
        
        # Check for timestamp format [YYYY-mm-dd HH:MM:SS]
        @test occursin(r"\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]", output)
    end
    
    # Reset to default after tests
    Sparrow.set_message_level(Sparrow.MSG_INFO)
end