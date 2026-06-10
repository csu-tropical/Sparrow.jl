# Tests for chunk-span resolution and time-window chunking helpers.
#
# These cover the rename of `minute_span` → `span_seconds`, the deprecation
# alias for the old name, and the offset range used by `process_day_chunks`.

using Test
using Sparrow

@workflow_type ChunkingTestWorkflow

# Run `f()` while capturing anything written to stdout. Returns (result, output).
# `redirect_stdout` on Julia 1.12 requires a `Pipe`, not an `IOBuffer`.
function _capture_stdout(f)
    pipe = Pipe()
    Base.link_pipe!(pipe; reader_supports_async = true, writer_supports_async = true)
    result = redirect_stdout(pipe) do
        try
            f()
        finally
            flush(stdout)
        end
    end
    close(pipe.in)
    output = read(pipe, String)
    return result, output
end

@testset "parse_span_seconds" begin

    @testset "integers pass through as seconds" begin
        @test Sparrow.parse_span_seconds(600) == 600
        @test Sparrow.parse_span_seconds(20) == 20
    end

    @testset "strings with unit codes" begin
        @test Sparrow.parse_span_seconds("90") == 90
        @test Sparrow.parse_span_seconds("20S") == 20
        @test Sparrow.parse_span_seconds("20s") == 20
        @test Sparrow.parse_span_seconds("5M") == 300
        @test Sparrow.parse_span_seconds("5m") == 300
        @test Sparrow.parse_span_seconds("10H") == 36000
        @test Sparrow.parse_span_seconds("1D") == 86400
        @test Sparrow.parse_span_seconds(" 15 M ") == 900
    end

    @testset "Dates.Period values" begin
        @test Sparrow.parse_span_seconds(Sparrow.Dates.Minute(5)) == 300
        @test Sparrow.parse_span_seconds(Sparrow.Dates.Hour(10)) == 36000
        @test Sparrow.parse_span_seconds(Sparrow.Dates.Second(20)) == 20
    end

    @testset "invalid specifications throw" begin
        @test_throws ErrorException Sparrow.parse_span_seconds("5X")
        @test_throws ErrorException Sparrow.parse_span_seconds("M5")
        @test_throws ErrorException Sparrow.parse_span_seconds("")
        @test_throws ErrorException Sparrow.parse_span_seconds(5.5)
    end
end

@testset "resolve_span_seconds" begin

    @testset "string span codes resolve and cache as Int" begin
        wf = ChunkingTestWorkflow(span_seconds = "5M")
        @test Sparrow.resolve_span_seconds(wf) == 300
        @test wf["span_seconds"] === 300
    end

    @testset "non-positive spans throw" begin
        wf = ChunkingTestWorkflow(span_seconds = 0)
        @test_throws ErrorException Sparrow.resolve_span_seconds(wf)
    end

    @testset "returns span_seconds when set" begin
        wf = ChunkingTestWorkflow(span_seconds = 30)
        @test Sparrow.resolve_span_seconds(wf) == 30
        @test wf["span_seconds"] == 30
        @test !haskey(wf.params, "minute_span")
    end

    @testset "converts deprecated minute_span and warns" begin
        wf = ChunkingTestWorkflow(minute_span = 5)

        result, output = _capture_stdout() do
            Sparrow.resolve_span_seconds(wf)
        end

        @test result == 300
        # Side effect: minute_span is removed and span_seconds is set.
        @test wf["span_seconds"] == 300
        @test !haskey(wf.params, "minute_span")
        # Warning text mentions both names so users know what to change.
        @test occursin("minute_span", output)
        @test occursin("span_seconds", output)
    end

    @testset "subsequent calls do not re-warn" begin
        wf = ChunkingTestWorkflow(minute_span = 2)

        # First call triggers the conversion + warning.
        Sparrow.resolve_span_seconds(wf)

        # Second call should be silent (no minute_span left to deprecate).
        result, output = _capture_stdout() do
            Sparrow.resolve_span_seconds(wf)
        end
        @test result == 120
        @test !occursin("minute_span", output)
    end

    @testset "defaults to 600 when neither key is present" begin
        wf = ChunkingTestWorkflow(other = "value")
        @test Sparrow.resolve_span_seconds(wf) == 600
        @test !haskey(wf.params, "span_seconds")
    end

    @testset "span_seconds wins if both keys are present" begin
        wf = ChunkingTestWorkflow(span_seconds = 45, minute_span = 10)
        @test Sparrow.resolve_span_seconds(wf) == 45
    end
end

@testset "chunk_offsets" begin

    @testset "default day-long range with 10-minute chunks" begin
        offsets = Sparrow.chunk_offsets(600, 86400)
        @test first(offsets) == 0
        @test last(offsets) == 85800
        @test step(offsets) == 600
        @test length(offsets) == 144
    end

    @testset "one-hour range with 1-minute chunks" begin
        offsets = Sparrow.chunk_offsets(60, 3600)
        @test length(offsets) == 60
        @test last(offsets) == 3540
    end

    @testset "second-precision chunks" begin
        offsets = Sparrow.chunk_offsets(1, 10)
        @test collect(offsets) == collect(0:1:9)
    end

    @testset "reverse=true reverses the iteration order" begin
        offsets = Sparrow.chunk_offsets(600, 86400; reverse = true)
        @test first(offsets) == 85800
        @test last(offsets) == 0
        @test length(offsets) == 144
    end

    @testset "span equal to range produces a single chunk at 0" begin
        offsets = Sparrow.chunk_offsets(86400, 86400)
        @test collect(offsets) == [0]
    end

    @testset "span larger than range produces an empty range" begin
        offsets = Sparrow.chunk_offsets(120, 60)
        @test isempty(offsets)
    end
end
