# Tests for the processing-period helpers: datetime parsing, start/stop window
# chunking, the --start/--stop command-line options, and the precedence rules
# `setup_workflow_params` applies when resolving the period to process.

using Test
using Sparrow
using Dates

@workflow_type TimeWindowTestWorkflow

# Minimal parsed_args as produced by Sparrow.parse_arguments
function _window_parsed_args(; datetime = "now", start = "none", stop = "none",
                             realtime = false, force_reprocess = false)
    return Dict{String,Any}(
        "datetime" => datetime,
        "start" => start,
        "stop" => stop,
        "realtime" => realtime,
        "force_reprocess" => force_reprocess,
        "log_prefix" => "default",
    )
end

@testset "parse_datetime_string" begin

    @testset "each accepted format returns its start and kind" begin
        @test Sparrow.parse_datetime_string("2024") == (DateTime(2024, 1, 1), :year)
        @test Sparrow.parse_datetime_string("202402") == (DateTime(2024, 2, 1), :month)
        @test Sparrow.parse_datetime_string("20240215") == (DateTime(2024, 2, 15), :day)
        @test Sparrow.parse_datetime_string("20240215_14") == (DateTime(2024, 2, 15, 14), :hour)
        @test Sparrow.parse_datetime_string("20240215_1418") == (DateTime(2024, 2, 15, 14, 18), :minute)
        @test Sparrow.parse_datetime_string("20240215_141820") ==
              (DateTime(2024, 2, 15, 14, 18, 20), :second)
    end

    @testset "invalid lengths throw and list the accepted formats" begin
        for bad in ["202401011", "2024010112", "20240101_1234_", "20240101_12345",
                    "20240101_1234567"]
            err = try
                Sparrow.parse_datetime_string(bad)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("YYYYMMDD_hhmmss", err.msg)
        end
    end

    @testset "non-digits and out-of-range fields throw" begin
        @test_throws ErrorException Sparrow.parse_datetime_string("20xx")
        @test_throws ErrorException Sparrow.parse_datetime_string("2024010x")
        @test_throws ErrorException Sparrow.parse_datetime_string("20240101_xx")
        @test_throws ErrorException Sparrow.parse_datetime_string("20241301")
        @test_throws ErrorException Sparrow.parse_datetime_string("20240101_99")
        @test_throws ErrorException Sparrow.parse_datetime_string("")
        # Non-ASCII digits and separators other than "_" are rejected with the format list
        for bad in ["\u0662\u0660\u0662\u0664", "20240101-14", "20240101T1418", "20240101 141820"]
            err = try
                Sparrow.parse_datetime_string(bad)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("YYYYMMDD_hhmmss", err.msg)
        end
    end

    @testset "Dates values pass through" begin
        @test Sparrow.parse_datetime_string(DateTime(2024, 2, 15, 14, 18, 20)) ==
              (DateTime(2024, 2, 15, 14, 18, 20), :second)
        @test Sparrow.parse_datetime_string(Date(2024, 2, 15)) == (DateTime(2024, 2, 15), :day)
        @test_throws ErrorException Sparrow.parse_datetime_string(20240215)
    end
end

@testset "time_window_chunks" begin

    @testset "exact fit splits into equal chunks" begin
        chunks = Sparrow.time_window_chunks(DateTime(2024, 1, 1, 14),
                                            DateTime(2024, 1, 1, 14, 30), 600)
        @test length(chunks) == 3
        @test chunks[1] == (DateTime(2024, 1, 1, 14), DateTime(2024, 1, 1, 14, 10))
        @test chunks[end] == (DateTime(2024, 1, 1, 14, 20), DateTime(2024, 1, 1, 14, 30))
    end

    @testset "trailing partial chunk is clipped, not dropped" begin
        chunks = Sparrow.time_window_chunks(DateTime(2024, 1, 1, 14),
                                            DateTime(2024, 1, 1, 14, 25), 600)
        @test length(chunks) == 3
        @test chunks[end] == (DateTime(2024, 1, 1, 14, 20), DateTime(2024, 1, 1, 14, 25))
        # The whole window is covered with no gaps
        @test first(chunks[1]) == DateTime(2024, 1, 1, 14)
        @test all(chunks[i][2] == chunks[i + 1][1] for i in 1:(length(chunks) - 1))
    end

    @testset "span longer than the window yields one clipped chunk" begin
        chunks = Sparrow.time_window_chunks(DateTime(2024, 1, 1), DateTime(2024, 1, 1, 0, 5), 600)
        @test chunks == [(DateTime(2024, 1, 1), DateTime(2024, 1, 1, 0, 5))]
    end

    @testset "reverse=true reverses the chunk order" begin
        chunks = Sparrow.time_window_chunks(DateTime(2024, 1, 1, 14),
                                            DateTime(2024, 1, 1, 14, 25), 600; reverse = true)
        @test length(chunks) == 3
        @test chunks[1] == (DateTime(2024, 1, 1, 14, 20), DateTime(2024, 1, 1, 14, 25))
        @test chunks[end] == (DateTime(2024, 1, 1, 14), DateTime(2024, 1, 1, 14, 10))
    end

    @testset "chunks are split at midnight" begin
        chunks = Sparrow.time_window_chunks(DateTime(2024, 1, 1, 23, 55),
                                            DateTime(2024, 1, 2, 0, 15), 600)
        @test chunks == [(DateTime(2024, 1, 1, 23, 55), DateTime(2024, 1, 2)),
                         (DateTime(2024, 1, 2), DateTime(2024, 1, 2, 0, 10)),
                         (DateTime(2024, 1, 2, 0, 10), DateTime(2024, 1, 2, 0, 15))]
        # No chunk crosses a day boundary
        @test all(Dates.Date(c[1]) == Dates.Date(c[2] - Dates.Millisecond(1)) for c in chunks)
    end

    @testset "empty when stop is not after start" begin
        @test isempty(Sparrow.time_window_chunks(DateTime(2024, 1, 1), DateTime(2024, 1, 1), 600))
        @test isempty(Sparrow.time_window_chunks(DateTime(2024, 1, 1, 2), DateTime(2024, 1, 1), 600))
    end

    @testset "non-positive spans throw" begin
        @test_throws ErrorException Sparrow.time_window_chunks(DateTime(2024, 1, 1),
                                                              DateTime(2024, 1, 2), 0)
    end
end

@testset "resolve_time_window" begin

    @testset "returns nothing without start_time/stop_time" begin
        @test Sparrow.resolve_time_window(TimeWindowTestWorkflow(datetime = "20240101")) === nothing
    end

    @testset "parses strings and DateTimes" begin
        wf = TimeWindowTestWorkflow(start_time = "20240101_1400", stop_time = "20240101_1500")
        @test Sparrow.resolve_time_window(wf) ==
              (DateTime(2024, 1, 1, 14), DateTime(2024, 1, 1, 15))

        wf2 = TimeWindowTestWorkflow(start_time = DateTime(2024, 1, 1),
                                     stop_time = DateTime(2024, 1, 2))
        @test Sparrow.resolve_time_window(wf2) == (DateTime(2024, 1, 1), DateTime(2024, 1, 2))
    end

    @testset "half a window, or a backwards window, throws" begin
        @test_throws ErrorException Sparrow.resolve_time_window(
            TimeWindowTestWorkflow(start_time = "20240101_1400"))
        @test_throws ErrorException Sparrow.resolve_time_window(
            TimeWindowTestWorkflow(stop_time = "20240101_1400"))
        @test_throws ErrorException Sparrow.resolve_time_window(
            TimeWindowTestWorkflow(start_time = "20240101_1500", stop_time = "20240101_1400"))
    end
end

@testset "parse_arguments start/stop options" begin

    args = Sparrow.parse_arguments(["workflow.jl"])
    @test args["start"] == "none"
    @test args["stop"] == "none"
    @test args["datetime"] == "now"

    args_window = Sparrow.parse_arguments(["workflow.jl", "--start", "20240101_1400",
                                           "--stop", "20240101_1500"])
    @test args_window["start"] == "20240101_1400"
    @test args_window["stop"] == "20240101_1500"
    @test args_window["datetime"] == "now"
end

@testset "setup_workflow_params processing period" begin

    @testset "command-line datetime overrides a config window" begin
        wf = TimeWindowTestWorkflow(start_time = "20240101_1400", stop_time = "20240101_1500")
        Sparrow.setup_workflow_params(wf, _window_parsed_args(datetime = "20240301_120000"))
        @test wf["datetime"] == "20240301_120000"
        @test !haskey(wf.params, "start_time")
        @test !haskey(wf.params, "stop_time")
        @test Sparrow.resolve_time_window(wf) === nothing
    end

    @testset "command-line start/stop are stored as DateTimes" begin
        wf = TimeWindowTestWorkflow()
        Sparrow.setup_workflow_params(wf, _window_parsed_args(start = "20240101_1400",
                                                              stop = "20240101_1500"))
        @test wf["start_time"] == DateTime(2024, 1, 1, 14)
        @test wf["stop_time"] == DateTime(2024, 1, 1, 15)
        # datetime tracks the window start so log names stay sensible
        @test wf["datetime"] == "20240101_140000"
        @test Sparrow.resolve_time_window(wf) ==
              (DateTime(2024, 1, 1, 14), DateTime(2024, 1, 1, 15))
    end

    @testset "command-line start/stop override a config datetime" begin
        wf = TimeWindowTestWorkflow(datetime = "20231225")
        Sparrow.setup_workflow_params(wf, _window_parsed_args(start = "20240101",
                                                              stop = "20240102"))
        @test wf["datetime"] == "20240101_000000"
        @test Sparrow.resolve_time_window(wf) == (DateTime(2024, 1, 1), DateTime(2024, 1, 2))
    end

    @testset "--start without --stop errors" begin
        wf = TimeWindowTestWorkflow()
        @test_throws ErrorException Sparrow.setup_workflow_params(
            wf, _window_parsed_args(start = "20240101_1400"))

        wf2 = TimeWindowTestWorkflow()
        @test_throws ErrorException Sparrow.setup_workflow_params(
            wf2, _window_parsed_args(stop = "20240101_1500"))
    end

    @testset "--stop must be after --start" begin
        wf = TimeWindowTestWorkflow()
        @test_throws ErrorException Sparrow.setup_workflow_params(
            wf, _window_parsed_args(start = "20240101_1500", stop = "20240101_1400"))
    end

    @testset "--datetime cannot be combined with --start/--stop" begin
        wf = TimeWindowTestWorkflow()
        @test_throws ErrorException Sparrow.setup_workflow_params(
            wf, _window_parsed_args(datetime = "20240101_140000",
                                    start = "20240101_1400", stop = "20240101_1500"))
    end

    @testset "config start_time/stop_time are stored as DateTimes" begin
        wf = TimeWindowTestWorkflow(start_time = "20240101_1400", stop_time = "20240101_1500")
        Sparrow.setup_workflow_params(wf, _window_parsed_args())
        @test wf["start_time"] == DateTime(2024, 1, 1, 14)
        @test wf["stop_time"] == DateTime(2024, 1, 1, 15)
        @test wf["datetime"] == "20240101_140000"
    end

    @testset "config datetime survives the \"now\" command-line default" begin
        wf = TimeWindowTestWorkflow(datetime = "20240101_14")
        Sparrow.setup_workflow_params(wf, _window_parsed_args())
        @test wf["datetime"] == "20240101_14"
    end

    @testset "a Date config datetime keeps whole-day precision" begin
        wf = TimeWindowTestWorkflow(datetime = Date(2024, 1, 1))
        Sparrow.setup_workflow_params(wf, _window_parsed_args())
        @test wf["datetime"] == "20240101"
        wf2 = TimeWindowTestWorkflow(datetime = DateTime(2024, 1, 1, 14, 18, 20))
        Sparrow.setup_workflow_params(wf2, _window_parsed_args())
        @test wf2["datetime"] == "20240101_141820"
    end

    @testset "malformed datetimes fail at setup, not on a worker" begin
        wf = TimeWindowTestWorkflow()
        @test_throws ErrorException Sparrow.setup_workflow_params(
            wf, _window_parsed_args(datetime = "2024-01-01"))
        wf2 = TimeWindowTestWorkflow(datetime = "202401011")
        @test_throws ErrorException Sparrow.setup_workflow_params(wf2, _window_parsed_args())
    end

    @testset "config with both datetime and start_time is ambiguous" begin
        wf = TimeWindowTestWorkflow(datetime = "20240101_14", start_time = "20240101_1400",
                                    stop_time = "20240101_1500")
        @test_throws ErrorException Sparrow.setup_workflow_params(wf, _window_parsed_args())
    end

    @testset "a config window missing one end errors" begin
        wf = TimeWindowTestWorkflow(start_time = "20240101_1400")
        @test_throws ErrorException Sparrow.setup_workflow_params(wf, _window_parsed_args())
    end

    @testset "stop_time must be after start_time" begin
        wf = TimeWindowTestWorkflow(start_time = "20240101_1500", stop_time = "20240101_1400")
        @test_throws ErrorException Sparrow.setup_workflow_params(wf, _window_parsed_args())
    end

    @testset "realtime mode rejects any processing period" begin
        wf = TimeWindowTestWorkflow()
        @test_throws ErrorException Sparrow.setup_workflow_params(
            wf, _window_parsed_args(realtime = true, start = "20240101_1400",
                                    stop = "20240101_1500"))

        wf2 = TimeWindowTestWorkflow(start_time = "20240101_1400", stop_time = "20240101_1500")
        @test_throws ErrorException Sparrow.setup_workflow_params(
            wf2, _window_parsed_args(realtime = true))

        wf3 = TimeWindowTestWorkflow()
        @test_throws ErrorException Sparrow.setup_workflow_params(
            wf3, _window_parsed_args(realtime = true, datetime = "20240101_140000"))
    end

    @testset "realtime mode still resolves to now" begin
        wf = TimeWindowTestWorkflow()
        Sparrow.setup_workflow_params(wf, _window_parsed_args(realtime = true))
        @test wf["realtime"] == true
        @test wf["datetime"] == "now"
    end

    @testset "no period anywhere resolves to now" begin
        wf = TimeWindowTestWorkflow()
        Sparrow.setup_workflow_params(wf, _window_parsed_args())
        @test wf["datetime"] == "now"
    end

    @testset "parsed_args without start/stop keys still works" begin
        # Backward compatibility with callers building their own parsed_args
        wf = TimeWindowTestWorkflow()
        legacy_args = Dict{String,Any}("datetime" => "20240101_000000", "realtime" => false,
                                       "force_reprocess" => false, "log_prefix" => "default")
        Sparrow.setup_workflow_params(wf, legacy_args)
        @test wf["datetime"] == "20240101_000000"
    end

    @testset "a leading SEA prefix is stripped" begin
        wf = TimeWindowTestWorkflow()
        Sparrow.setup_workflow_params(wf, _window_parsed_args(datetime = "SEA20240101_000000"))
        @test wf["datetime"] == "20240101_000000"
    end
end
