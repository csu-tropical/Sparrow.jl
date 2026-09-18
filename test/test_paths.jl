# Tests for the date-aware output path helpers: placeholder substitution in the
# base directories, the `date_subdir` opt-out, and how `LocalDirSource` resolves
# the directory it reads for a given date.

using Test
using Sparrow
using Dates

@workflow_type PathTestWorkflow

# Minimal parsed_args as produced by Sparrow.parse_arguments
function _path_parsed_args(; datetime = "now", start = "none", stop = "none",
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

# Write a cfrad-style file whose embedded timestamp `_parse_filename_time` reads
function _touch_cfrad(dir, stamp)
    touch(joinpath(dir, "cfrad.$(stamp).000_to_$(stamp).000_TEST_SUR.nc"))
end

@testset "substitute_date_placeholders" begin

    @testset "day-level date fills the date tokens" begin
        @test Sparrow.substitute_date_placeholders("/archive/{YYYYmmdd}/chivo", "20240101") ==
              "/archive/20240101/chivo"
        @test Sparrow.substitute_date_placeholders("/archive/{YYYY}/{MM}/{DD}", "20240101") ==
              "/archive/2024/01/01"
        @test Sparrow.substitute_date_placeholders("{YYYY}-{MM}-{DD}", "20241231") == "2024-12-31"
        # Nothing to substitute is a no-op
        @test Sparrow.substitute_date_placeholders("/archive/chivo", "20240101") == "/archive/chivo"
    end

    @testset "hour and minute tokens need a longer date string" begin
        # A day-level date leaves {HH}/{mm} alone
        @test Sparrow.substitute_date_placeholders("blend.{YYYYmmdd}/{HH}/core/", "20240101") ==
              "blend.20240101/{HH}/core/"
        @test Sparrow.substitute_date_placeholders("blend.{YYYYmmdd}/{HH}/core/", "2024010106") ==
              "blend.20240101/06/core/"
        @test Sparrow.substitute_date_placeholders("{YYYYmmdd}_{HH}{mm}", "202401010615") ==
              "20240101_0615"
        # Too short to resolve anything
        @test Sparrow.substitute_date_placeholders("{YYYY}/{MM}", "2024") == "{YYYY}/{MM}"
    end

    @testset "DateTime and Date inputs are formatted first" begin
        @test Sparrow.substitute_date_placeholders("/archive/{YYYY}/{MM}/{DD}",
                                                   DateTime(2024, 3, 5, 6, 7, 8)) ==
              "/archive/2024/03/05"
        @test Sparrow.substitute_date_placeholders("{YYYYmmdd}_{HH}{mm}",
                                                   DateTime(2024, 3, 5, 6, 7)) == "20240305_0607"
        @test Sparrow.substitute_date_placeholders("{YYYYmmdd}", Date(2024, 3, 5)) == "20240305"
    end

    @testset "the remote sources resolve through the shared helper" begin
        s3 = NEXRADSource("KFTG")
        @test Sparrow._s3_resolve_prefix(s3, "20240101") == "2024/01/01/KFTG/"
        nbm = NBMSource()
        @test Sparrow._s3_resolve_prefix(nbm, "2024010106") == "blend.20240101/06/core/"
        http = HTTPDirSource(base_url="https://example.com/{YYYY}/{MM}/{DD}/")
        @test Sparrow._http_resolve_url(http, "20240101") == "https://example.com/2024/01/01/"
    end
end

@testset "has_date_placeholder and validate_date_placeholders" begin

    @test Sparrow.has_date_placeholder("/archive/{YYYYmmdd}/chivo")
    @test Sparrow.has_date_placeholder("/archive/{YYYY}/{MM}/{DD}")
    @test !Sparrow.has_date_placeholder("/archive/chivo")
    # Hour and minute tokens organize the tree just as the day tokens do
    @test Sparrow.has_date_placeholder("/archive/{YYYYmmdd}/{HH}")
    @test Sparrow.has_date_placeholder("/archive/{YYYYmmdd_HHMM}")
    # {step} carries no time information
    @test !Sparrow.has_date_placeholder("/archive/{step}")
    @test Sparrow.has_step_placeholder("/archive/{step}/{YYYYmmdd}")
    @test !Sparrow.has_step_placeholder("/archive/{YYYYmmdd}")

    @test Sparrow.validate_date_placeholders("/archive/{YYYY}/{MM}/{DD}", "base_archive_dir") ==
          "/archive/{YYYY}/{MM}/{DD}"
    @test Sparrow.validate_date_placeholders("/archive/chivo", "base_archive_dir") == "/archive/chivo"

    @test Sparrow.validate_date_placeholders("/archive/{YYYYmmdd}/{HH}", "base_archive_dir") ==
          "/archive/{YYYYmmdd}/{HH}"
    @test Sparrow.validate_date_placeholders("/archive/{YYYYmmdd_HHMM}", "base_plot_dir") ==
          "/archive/{YYYYmmdd_HHMM}"

    for bad in ["/archive/{yyyy}", "/archive/{date}", "/archive/{YYYYMMDD}", "/archive/{hh}"]
        @test_throws ErrorException Sparrow.validate_date_placeholders(bad, "base_archive_dir")
    end

    # {step} is only valid where a step directory exists
    @test Sparrow.validate_date_placeholders("/archive/{step}/{YYYYmmdd}", "base_archive_dir";
                                             allow_step=true) == "/archive/{step}/{YYYYmmdd}"
    @test_throws ErrorException Sparrow.validate_date_placeholders("/data/{step}", "base_data_dir")

    # The message names the offending token and lists the valid ones
    err = try
        Sparrow.validate_date_placeholders("/archive/{date}", "base_archive_dir")
        nothing
    catch e
        e
    end
    @test err isa ErrorException
    @test occursin("{date}", err.msg)
    @test occursin("base_archive_dir", err.msg)
    @test occursin("{YYYYmmdd}", err.msg)
end

@testset "dated_dir and step_dated_dir" begin

    @testset "default layout appends YYYYmmdd" begin
        @test Sparrow.dated_dir("/data", "20240101", true) == joinpath("/data", "20240101")
        @test Sparrow.step_dated_dir("/archive", "grid", "20240101", true) ==
              joinpath("/archive", "grid", "20240101")
    end

    @testset "date_subdir = false drops the date level" begin
        @test Sparrow.dated_dir("/data/chivo", "20240101", false) == "/data/chivo"
        @test Sparrow.step_dated_dir("/archive", "grid", "20240101", false) ==
              joinpath("/archive", "grid")
    end

    @testset "a placeholder puts the date where the user asked for it" begin
        @test Sparrow.dated_dir("/data/{YYYYmmdd}/chivo", "20240101", true) ==
              "/data/20240101/chivo"
        @test Sparrow.step_dated_dir("/archive/{YYYYmmdd}/chivo", "grid", "20240101", true) ==
              joinpath("/archive/20240101/chivo", "grid")
        @test Sparrow.step_dated_dir("/archive/{YYYY}/{MM}/{DD}", "grid", "20240101", true) ==
              joinpath("/archive/2024/01/01", "grid")
        # date_subdir is ignored once a placeholder is present
        @test Sparrow.step_dated_dir("/archive/{YYYYmmdd}/chivo", "grid", "20240101", false) ==
              joinpath("/archive/20240101/chivo", "grid")
    end

    @testset "DateTime dates use the day component" begin
        t = DateTime(2024, 1, 1, 13, 45, 0)
        @test Sparrow.dated_dir("/data", t, true) == joinpath("/data", "20240101")
        @test Sparrow.step_dated_dir("/archive/{YYYY}/{MM}/{DD}", "grid", t, true) ==
              joinpath("/archive/2024/01/01", "grid")
    end
end

@testset "data_dir, archive_step_dir and plot_output_dir" begin

    t = DateTime(2024, 1, 1, 13, 45, 0)

    @testset "default layout" begin
        wf = PathTestWorkflow(base_data_dir = "/data",
                              base_archive_dir = "/archive",
                              base_plot_dir = "/figs")
        @test Sparrow.use_date_subdir(wf) == true
        @test Sparrow.data_dir(wf, "20240101") == joinpath("/data", "20240101")
        @test Sparrow.archive_root_dir(wf) == "/archive"
        @test Sparrow.archive_step_dir(wf, "grid", "20240101") ==
              joinpath("/archive", "grid", "20240101")
        @test Sparrow.plot_output_dir(wf, "plot_rhi", t, "/tmp/fallback") ==
              joinpath("/figs", "plot_rhi", "20240101")
    end

    @testset "date_subdir = false" begin
        wf = PathTestWorkflow(base_data_dir = "/data/chivo",
                              base_archive_dir = "/archive",
                              base_plot_dir = "/figs",
                              date_subdir = false)
        @test Sparrow.use_date_subdir(wf) == false
        @test Sparrow.data_dir(wf, "20240101") == "/data/chivo"
        @test Sparrow.archive_step_dir(wf, "grid", "20240101") == joinpath("/archive", "grid")
        @test Sparrow.plot_output_dir(wf, "plot_rhi", t, "/tmp/fallback") ==
              joinpath("/figs", "plot_rhi")
    end

    @testset "placeholders put the date above the step" begin
        wf = PathTestWorkflow(base_data_dir = "/data/{YYYYmmdd}/chivo",
                              base_archive_dir = "/archive/{YYYYmmdd}/chivo",
                              base_plot_dir = "/figs/{YYYY}/{MM}/{DD}")
        @test Sparrow.data_dir(wf, "20240101") == "/data/20240101/chivo"
        # The marker root keeps every literal component, dropping the placeholders
        @test Sparrow.archive_root_dir(wf) == joinpath("/archive", "chivo")
        @test Sparrow.archive_step_dir(wf, "grid", "20240101") ==
              joinpath("/archive/20240101/chivo", "grid")
        @test Sparrow.plot_output_dir(wf, "plot_rhi", t, "/tmp/fallback") ==
              joinpath("/figs/2024/01/01", "plot_rhi")
    end

    @testset "plot fallback and a bad date_subdir" begin
        wf = PathTestWorkflow(base_archive_dir = "/archive")
        @test Sparrow.plot_output_dir(wf, "plot_rhi", t, "/tmp/fallback") == "/tmp/fallback"

        bad = PathTestWorkflow(base_archive_dir = "/archive", date_subdir = "yes")
        @test_throws ErrorException Sparrow.use_date_subdir(bad)
        @test_throws ErrorException Sparrow.archive_step_dir(bad, "grid", "20240101")
    end
end

@testset "LocalDirSource layouts" begin

    @testset "default date subdirectory" begin
        tmp = mktempdir()
        date_dir = joinpath(tmp, "20240903")
        mkpath(date_dir)
        _touch_cfrad(date_dir, "20240903_120000")

        source = LocalDirSource(tmp)
        @test source.date_subdir == true
        @test Sparrow._local_dir(source, "20240903") == joinpath(tmp, "20240903")
        @test has_data(source, "20240903") == true
        @test has_data(source, "20240904") == false
        @test length(discover_files(source, "20240903")) == 1
        @test fetch_file(source, "a.nc", "/tmp/dest", "20240903") ==
              joinpath(tmp, "20240903", "a.nc")

        rm(tmp, recursive=true)
    end

    @testset "placeholder base directory" begin
        tmp = mktempdir()
        real_dir = joinpath(tmp, "2024", "09")
        mkpath(real_dir)
        _touch_cfrad(real_dir, "20240903_120000")

        source = LocalDirSource(joinpath(tmp, "{YYYY}", "{MM}"))
        @test Sparrow._local_dir(source, "20240903") == real_dir
        @test has_data(source, "20240903") == true
        @test has_data(source, "20241003") == false
        @test length(discover_files(source, "20240903")) == 1
        @test fetch_file(source, "a.nc", "/tmp/dest", "20240903") == joinpath(real_dir, "a.nc")

        # A placeholder wins over date_subdir
        flat_source = LocalDirSource(joinpath(tmp, "{YYYY}", "{MM}"); date_subdir=false)
        @test Sparrow._local_dir(flat_source, "20240903") == real_dir

        rm(tmp, recursive=true)
    end

    @testset "flat directory with date_subdir = false" begin
        tmp = mktempdir()
        _touch_cfrad(tmp, "20240903_120000")
        _touch_cfrad(tmp, "20240903_120500")
        _touch_cfrad(tmp, "20240905_120000")
        touch(joinpath(tmp, ".hidden_file"))
        mkdir(joinpath(tmp, "subdir"))

        source = LocalDirSource(tmp; date_subdir=false)
        @test source.date_subdir == false
        @test Sparrow._local_dir(source, "20240903") == tmp

        # has_data keys off the filenames, so a day with no files is skipped
        @test has_data(source, "20240903") == true
        @test has_data(source, "20240905") == true
        @test has_data(source, "20240904") == false

        # discover_files reads the flat directory, keeping only this day's files
        # and dropping hidden files and dirs
        files = discover_files(source, "20240903")
        @test length(files) == 2
        @test all(f -> occursin("20240903", basename(f)), files)
        @test all(f -> !startswith(basename(f), "."), files)
        @test all(f -> !isdir(f), files)
        @test length(discover_files(source, "20240905")) == 1
        @test isempty(discover_files(source, "20240904"))

        @test fetch_file(source, "a.nc", "/tmp/dest", "20240903") == joinpath(tmp, "a.nc")

        # A stray file without a timestamp does not make an empty day look
        # populated while timestamped files are present, but it is still
        # offered to every day's discovery since it could belong to any of them
        touch(joinpath(tmp, "README.txt"))
        @test has_data(source, "20240904") == false
        @test has_data(source, "20240903") == true
        @test length(discover_files(source, "20240904")) == 1
        @test length(discover_files(source, "20240903")) == 3

        rm(tmp, recursive=true)
    end

    @testset "flat directory holding only unparseable names" begin
        tmp = mktempdir()
        touch(joinpath(tmp, "radar_data.nc"))
        source = LocalDirSource(tmp; date_subdir=false)
        @test has_data(source, "20240903") == true
        rm(tmp, recursive=true)
    end

    @testset "an empty flat directory has no data" begin
        tmp = mktempdir()
        source = LocalDirSource(tmp; date_subdir=false)
        @test has_data(source, "20240903") == false
        rm(tmp, recursive=true)
    end
end

@testset "_filter_names_by_day" begin
    names = ["cfrad.20240903_120000.000_to_20240903_120500.000_TEST_SUR.nc",
             "cfrad.20240905_120000.000_to_20240905_120500.000_TEST_SUR.nc",
             "KFTG20240903_130000_V06",
             "unparseable.nc"]
    kept = Sparrow._filter_names_by_day(names, "20240903")
    @test kept == [names[1], names[3], names[4]]
    # Longer date strings are truncated to the day
    @test Sparrow._filter_names_by_day(names, "2024090312") == kept
    @test Sparrow._filter_names_by_day(names, "20240904") == [names[4]]
end

@testset "LocalDirSource rejects unknown placeholders" begin
    @test_throws ErrorException LocalDirSource("/data/{yyyy}/{MM}")
    @test_throws ErrorException LocalDirSource("/data/{date}"; date_subdir=false)
    @test LocalDirSource("/data/{YYYY}/{MM}").base_dir == "/data/{YYYY}/{MM}"
end

@testset "get_data_source honours date_subdir" begin

    wf = PathTestWorkflow(base_data_dir = "/data")
    source = get_data_source(wf)
    @test source isa LocalDirSource
    @test source.base_dir == "/data"
    @test source.date_subdir == true

    wf_flat = PathTestWorkflow(base_data_dir = "/data/chivo", date_subdir = false)
    flat = get_data_source(wf_flat)
    @test flat.base_dir == "/data/chivo"
    @test flat.date_subdir == false
    @test Sparrow._local_dir(flat, "20240903") == "/data/chivo"

    # An explicit data_source is returned untouched
    explicit = LocalDirSource("/elsewhere"; date_subdir=false)
    wf_explicit = PathTestWorkflow(base_data_dir = "/data", data_source = explicit)
    @test get_data_source(wf_explicit) === explicit
end

@testset "setup_workflow_params validates the directory layout" begin

    @testset "valid placeholders and date_subdir pass" begin
        wf = PathTestWorkflow(base_data_dir = "/data/{YYYYmmdd}/chivo",
                              base_archive_dir = "/archive/{YYYY}/{MM}/{DD}",
                              base_plot_dir = "/figs",
                              date_subdir = false)
        Sparrow.setup_workflow_params(wf, _path_parsed_args())
        @test wf["base_data_dir"] == "/data/{YYYYmmdd}/chivo"
        @test Sparrow.data_dir(wf, "20240101") == "/data/20240101/chivo"
    end

    @testset "an unknown token fails at startup" begin
        for (key, value) in (("base_data_dir", "/data/{yyyy}"),
                             ("base_archive_dir", "/archive/{date}/chivo"),
                             ("base_plot_dir", "/figs/{YYYYMMDD}"))
            wf = PathTestWorkflow(; Symbol(key) => value)
            @test_throws ErrorException Sparrow.setup_workflow_params(wf, _path_parsed_args())
        end
    end

    @testset "placeholders in base_working_dir fail at startup" begin
        wf = PathTestWorkflow(base_data_dir = "/data", base_working_dir = "/work/{YYYYmmdd}")
        @test_throws ErrorException Sparrow.setup_workflow_params(wf, _path_parsed_args())
    end

    @testset "a non-Bool date_subdir fails at startup" begin
        wf = PathTestWorkflow(base_data_dir = "/data", date_subdir = "true")
        @test_throws ErrorException Sparrow.setup_workflow_params(wf, _path_parsed_args())
    end
end

@testset "hour and minute placeholders" begin

    @testset "substitution of the hour, minute and combined tokens" begin
        @test Sparrow.substitute_date_placeholders("/data/{YYYYmmdd}/{HH}", "2024010113") ==
              "/data/20240101/13"
        @test Sparrow.substitute_date_placeholders("/data/{YYYYmmdd}/{HH}{mm}", "202401011305") ==
              "/data/20240101/1305"
        @test Sparrow.substitute_date_placeholders("/data/{YYYYmmdd_HH}", "2024010113") ==
              "/data/20240101_13"
        @test Sparrow.substitute_date_placeholders("/data/{YYYYmmdd_HHMM}", "202401011305") ==
              "/data/20240101_1305"
        # The combined tokens are not clobbered by the shorter {YYYYmmdd}
        @test Sparrow.substitute_date_placeholders("{YYYYmmdd}/{YYYYmmdd_HH}/{YYYYmmdd_HHMM}",
                                                   "202401011305") ==
              "20240101/20240101_13/20240101_1305"
        # A day-level date cannot resolve the combined tokens, and leaves them alone
        @test Sparrow.substitute_date_placeholders("{YYYYmmdd_HH}", "20240101") == "{YYYYmmdd_HH}"
        @test Sparrow.substitute_date_placeholders("{YYYYmmdd_HHMM}", "2024010113") ==
              "{YYYYmmdd_HHMM}"
        # A DateTime resolves everything
        @test Sparrow.substitute_date_placeholders("{YYYYmmdd_HHMM}", DateTime(2024, 1, 1, 13, 5)) ==
              "20240101_1305"
    end

    @testset "{step} substitution" begin
        @test Sparrow.step_dated_dir("/archive/{step}/{YYYYmmdd}/{HH}", "grid",
                                     DateTime(2024, 1, 1, 13, 5), true) ==
              "/archive/grid/20240101/13"
        # Without {step} the step name is appended after the resolved base
        @test Sparrow.step_dated_dir("/archive/{YYYYmmdd}/{HH}", "grid",
                                     DateTime(2024, 1, 1, 13, 5), true) ==
              joinpath("/archive/20240101/13", "grid")
        # {step} without any date placeholder still honours date_subdir
        @test Sparrow.step_dated_dir("/archive/{step}/products", "grid", "20240101", true) ==
              joinpath("/archive/grid/products", "20240101")
        @test Sparrow.step_dated_dir("/archive/{step}/products", "grid", "20240101", false) ==
              "/archive/grid/products"
    end

    @testset "dated_dir resolves the full time" begin
        t = DateTime(2024, 1, 1, 13, 5, 30)
        @test Sparrow.dated_dir("/data/{YYYYmmdd}/{HH}", t, true) == "/data/20240101/13"
        @test Sparrow.dated_dir("/data/{YYYYmmdd_HHMM}", t, true) == "/data/20240101_1305"
        # A day string means midnight, so the hour and minute are zero
        @test Sparrow.dated_dir("/data/{YYYYmmdd}/{HH}{mm}", "20240101", true) ==
              "/data/20240101/0000"
        # An hour string leaves the minute at zero
        @test Sparrow.dated_dir("/data/{YYYYmmdd}/{HH}{mm}", "2024010113", true) ==
              "/data/20240101/1300"
    end
end

@testset "placeholder_resolution, unit_period and floor_to_unit" begin

    @test Sparrow.placeholder_resolution("/data/chivo") === :none
    @test Sparrow.placeholder_resolution("/data/{step}") === :none
    @test Sparrow.placeholder_resolution("/data/{YYYYmmdd}") === :day
    @test Sparrow.placeholder_resolution("/data/{YYYY}/{MM}/{DD}") === :day
    @test Sparrow.placeholder_resolution("/data/{YYYYmmdd}/{HH}") === :hour
    @test Sparrow.placeholder_resolution("/data/{YYYYmmdd_HH}") === :hour
    @test Sparrow.placeholder_resolution("/data/{YYYYmmdd}/{HH}{mm}") === :minute
    @test Sparrow.placeholder_resolution("/data/{YYYYmmdd_HHMM}") === :minute

    @test Sparrow.unit_period(:day) == Dates.Day(1)
    @test Sparrow.unit_period(:hour) == Dates.Hour(1)
    @test Sparrow.unit_period(:minute) == Dates.Minute(1)
    @test_throws ErrorException Sparrow.unit_period(:none)

    t = DateTime(2024, 1, 1, 13, 5, 30)
    @test Sparrow.floor_to_unit(t, :day) == DateTime(2024, 1, 1)
    @test Sparrow.floor_to_unit(t, :hour) == DateTime(2024, 1, 1, 13)
    @test Sparrow.floor_to_unit(t, :minute) == DateTime(2024, 1, 1, 13, 5)
    @test Sparrow.floor_to_unit(t, :none) == t

    @test Sparrow.source_resolution(LocalDirSource("/data")) === :day
    @test Sparrow.source_resolution(LocalDirSource("/data"; date_subdir=false)) === :none
    @test Sparrow.source_resolution(LocalDirSource("/data/{YYYYmmdd}/{HH}")) === :hour
    # A placeholder wins over date_subdir
    @test Sparrow.source_resolution(LocalDirSource("/data/{YYYYmmdd_HHMM}"; date_subdir=false)) ===
          :minute
end

@testset "unit_dirs over a processing window" begin

    @testset "a window inside one unit yields one directory" begin
        hourly = LocalDirSource("/data/{YYYYmmdd}/{HH}")
        @test Sparrow.unit_dirs(hourly, DateTime(2024, 1, 1, 13, 5),
                                DateTime(2024, 1, 1, 13, 15)) == ["/data/20240101/13"]
    end

    @testset "a window crossing a boundary yields every directory it touches" begin
        hourly = LocalDirSource("/data/{YYYYmmdd}/{HH}")
        @test Sparrow.unit_dirs(hourly, DateTime(2024, 1, 1, 13, 55),
                                DateTime(2024, 1, 1, 14, 5)) ==
              ["/data/20240101/13", "/data/20240101/14"]

        daily = LocalDirSource("/data")
        @test Sparrow.unit_dirs(daily, DateTime(2024, 1, 1, 23, 55),
                                DateTime(2024, 1, 2, 0, 5)) ==
              [joinpath("/data", "20240101"), joinpath("/data", "20240102")]

        minutely = LocalDirSource("/data/{YYYYmmdd_HHMM}")
        @test Sparrow.unit_dirs(minutely, DateTime(2024, 1, 1, 13, 5, 30),
                                DateTime(2024, 1, 1, 13, 8)) ==
              ["/data/20240101_1305", "/data/20240101_1306",
               "/data/20240101_1307"]
    end

    @testset "a flat source has a single directory" begin
        flat = LocalDirSource("/data/chivo"; date_subdir=false)
        @test Sparrow.unit_dirs(flat, DateTime(2024, 1, 1), DateTime(2024, 1, 3)) ==
              ["/data/chivo"]
    end

    @testset "an empty window still names its own directory" begin
        hourly = LocalDirSource("/data/{YYYYmmdd}/{HH}")
        t = DateTime(2024, 1, 1, 13, 5)
        @test Sparrow.unit_dirs(hourly, t, t) == ["/data/20240101/13"]
    end

end

@testset "_date_window" begin
    @test Sparrow._date_window("20240101") ==
          (DateTime(2024, 1, 1), DateTime(2024, 1, 2))
    @test Sparrow._date_window("2024010113") ==
          (DateTime(2024, 1, 1, 13), DateTime(2024, 1, 1, 14))
    @test Sparrow._date_window("202401011305") ==
          (DateTime(2024, 1, 1, 13, 5), DateTime(2024, 1, 1, 13, 6))
    @test_throws ErrorException Sparrow._date_window("2024")
end

@testset "LocalDirSource with hour and minute layouts" begin

    @testset "{YYYYmmdd}/{HH} layout" begin
        tmp = mktempdir()
        mkpath(joinpath(tmp, "20240101", "13"))
        mkpath(joinpath(tmp, "20240101", "14"))
        _touch_cfrad(joinpath(tmp, "20240101", "13"), "20240101_130500")
        _touch_cfrad(joinpath(tmp, "20240101", "13"), "20240101_135500")
        _touch_cfrad(joinpath(tmp, "20240101", "14"), "20240101_140500")

        source = LocalDirSource(joinpath(tmp, "{YYYYmmdd}", "{HH}"))
        @test Sparrow.source_resolution(source) === :hour

        # An 8-digit date is the whole day: every hour directory is read
        @test length(discover_files(source, "20240101")) == 3
        @test has_data(source, "20240101") == true
        @test has_data(source, "20240102") == false

        # A 10-digit date is one hour
        @test length(discover_files(source, "2024010113")) == 2
        @test length(discover_files(source, "2024010114")) == 1
        @test isempty(discover_files(source, "2024010115"))
        @test has_data(source, "2024010113") == true
        @test has_data(source, "2024010115") == false

        # A 12-digit date is one minute, which still lives in the hour directory
        @test length(discover_files(source, "202401011305")) == 2
        @test has_data(source, "202401011305") == true

        # fetch_file finds a file in whichever unit directory of the window holds
        # it, so the discover_files -> fetch_file round trip works at day level
        found = first(discover_files(source, "2024010114"))
        @test fetch_file(source, basename(found), "/tmp/dest", "20240101") == found
        @test fetch_file(source, basename(found), "/tmp/dest", "2024010114") == found
        # A file that exists nowhere resolves to the window start's directory
        @test fetch_file(source, "missing.nc", "/tmp/dest", "2024010114") ==
              joinpath(tmp, "20240101", "14", "missing.nc")

        rm(tmp, recursive=true)
    end

    @testset "{YYYYmmdd_HHMM} layout" begin
        tmp = mktempdir()
        for stamp in ("20240101_1305", "20240101_1306")
            mkpath(joinpath(tmp, stamp))
        end
        _touch_cfrad(joinpath(tmp, "20240101_1305"), "20240101_130510")
        _touch_cfrad(joinpath(tmp, "20240101_1306"), "20240101_130610")

        source = LocalDirSource(joinpath(tmp, "{YYYYmmdd_HHMM}"))
        @test Sparrow.source_resolution(source) === :minute
        @test Sparrow._local_dir(source, DateTime(2024, 1, 1, 13, 5, 30)) ==
              joinpath(tmp, "20240101_1305")

        @test length(discover_files(source, "202401011305")) == 1
        @test isempty(discover_files(source, "202401011307"))
        # An hour or a day scans every minute directory it covers
        @test length(discover_files(source, "2024010113")) == 2
        @test length(discover_files(source, "20240101")) == 2
        @test has_data(source, "202401011305") == true
        @test has_data(source, "202401011307") == false
        @test has_data(source, "20240101") == true
        @test has_data(source, "20240102") == false

        rm(tmp, recursive=true)
    end

    @testset "flat layout filters by the window, not just the day" begin
        tmp = mktempdir()
        _touch_cfrad(tmp, "20240101_130500")
        _touch_cfrad(tmp, "20240101_140500")
        _touch_cfrad(tmp, "20240102_130500")

        source = LocalDirSource(tmp; date_subdir=false)
        @test length(discover_files(source, "20240101")) == 2
        @test length(discover_files(source, "2024010113")) == 1
        @test isempty(discover_files(source, "2024010115"))
        @test has_data(source, "2024010113") == true
        @test has_data(source, "2024010115") == false

        rm(tmp, recursive=true)
    end
end

@testset "_filter_names_by_window" begin
    names = ["cfrad.20240101_130500.000_to_20240101_130500.000_TEST_SUR.nc",
             "cfrad.20240101_140500.000_to_20240101_140500.000_TEST_SUR.nc",
             "unparseable.nc"]
    kept = Sparrow._filter_names_by_window(names, DateTime(2024, 1, 1, 13),
                                           DateTime(2024, 1, 1, 14))
    @test kept == [names[1], names[3]]
    # Unparseable names are always kept, since they could belong to any window
    @test Sparrow._filter_names_by_window(names, DateTime(2024, 2, 1),
                                          DateTime(2024, 2, 2)) == [names[3]]
end

@testset "archive_root_dir keeps a stable root" begin

    @test Sparrow.stable_root("/archive/chivo", "base_archive_dir") == "/archive/chivo"
    @test Sparrow.stable_root("/archive/{YYYYmmdd}/chivo", "base_archive_dir") ==
          joinpath("/archive", "chivo")
    # Two trees that differ only below a placeholder keep distinct marker roots
    @test Sparrow.stable_root("/archive/{YYYYmmdd}/seapol", "base_archive_dir") ==
          joinpath("/archive", "seapol")
    @test Sparrow.stable_root("/archive/chivo/{YYYY}/{MM}", "base_archive_dir") ==
          joinpath("/archive", "chivo")
    @test Sparrow.stable_root("/archive/{step}/{YYYYmmdd}/{HH}", "base_archive_dir") == "/archive"
    @test Sparrow.stable_root("/archive/{YYYYmmdd}/{HH}/grid", "base_archive_dir") ==
          joinpath("/archive", "grid")
    # A relative path works the same way
    @test Sparrow.stable_root("archive/{YYYYmmdd}", "base_archive_dir") == "archive"
    # There must be a literal directory to anchor the markers to
    @test_throws ErrorException Sparrow.stable_root("/{YYYYmmdd}/archive", "base_archive_dir")
    @test_throws ErrorException Sparrow.stable_root("{step}/archive", "base_archive_dir")

    for (base, root) in (("/archive", "/archive"),
                         ("/archive/{YYYYmmdd}/chivo", joinpath("/archive", "chivo")),
                         ("/archive/{step}/{YYYYmmdd}/{HH}", "/archive"))
        wf = PathTestWorkflow(base_archive_dir = base)
        @test Sparrow.archive_root_dir(wf) == root
    end
end

@testset "plot_output_dir_for_file" begin

    wf = PathTestWorkflow(base_plot_dir = "/figs/{YYYYmmdd}/{HH}")
    start_time = DateTime(2024, 1, 1, 13, 0)

    # The file's own timestamp decides the hour, even across a chunk boundary
    @test Sparrow.plot_output_dir_for_file(wf, "plot_rhi",
                                           "/work/gridded_rhi_20240101_140500.nc",
                                           start_time, "/tmp/fallback") ==
          joinpath("/figs/20240101/14", "plot_rhi")
    @test Sparrow.plot_output_dir_for_file(wf, "plot_rhi",
                                           "/work/gridded_rhi_20240101_130500.nc",
                                           start_time, "/tmp/fallback") ==
          joinpath("/figs/20240101/13", "plot_rhi")
    # An unparseable name falls back to the chunk start
    @test Sparrow.plot_output_dir_for_file(wf, "plot_rhi", "/work/unparseable.nc",
                                           start_time, "/tmp/fallback") ==
          joinpath("/figs/20240101/13", "plot_rhi")

    # Without base_plot_dir the figures stay in the step's working directory
    no_plot_dir = PathTestWorkflow(base_archive_dir = "/archive")
    @test Sparrow.plot_output_dir_for_file(no_plot_dir, "plot_rhi",
                                           "/work/gridded_rhi_20240101_140500.nc",
                                           start_time, "/tmp/fallback") == "/tmp/fallback"
end

@testset "archive_workflow files each product by its own time" begin

    @testset "an hour-resolution layout splits a chunk across hours" begin
        tmp = mktempdir()
        date = "20240101"
        step_dir = joinpath(tmp, "work", "grid", date)
        mkpath(step_dir)
        touch(joinpath(step_dir, "gridded_ppi_20240101_135500.nc"))
        touch(joinpath(step_dir, "gridded_ppi_20240101_140500.nc"))

        archive_base = joinpath(tmp, "archive")
        wf = PathTestWorkflow(base_archive_dir = joinpath(archive_base, "{step}", "{YYYYmmdd}", "{HH}"),
                              steps = [("grid", PassThroughStep, "base_data", true)],
                              force_reprocess = true)
        archived = Sparrow.archive_workflow(wf, joinpath(tmp, "work"), date;
                                            start_time = DateTime(2024, 1, 1, 13, 55))
        @test length(archived) == 2
        @test isfile(joinpath(archive_base, "grid", "20240101", "13",
                              "gridded_ppi_20240101_135500.nc"))
        @test isfile(joinpath(archive_base, "grid", "20240101", "14",
                              "gridded_ppi_20240101_140500.nc"))

        rm(tmp, recursive=true)
    end

    @testset "the default layout still lands in <archive>/<step>/YYYYmmdd" begin
        tmp = mktempdir()
        date = "20240101"
        step_dir = joinpath(tmp, "work", "grid", date)
        mkpath(step_dir)
        touch(joinpath(step_dir, "gridded_ppi_20240101_135500.nc"))
        touch(joinpath(step_dir, "gridded_ppi_20240101_140500.nc"))

        archive_base = joinpath(tmp, "archive")
        wf = PathTestWorkflow(base_archive_dir = archive_base,
                              steps = [("grid", PassThroughStep, "base_data", true)],
                              force_reprocess = true)
        Sparrow.archive_workflow(wf, joinpath(tmp, "work"), date;
                                 start_time = DateTime(2024, 1, 1, 13, 55))
        @test isfile(joinpath(archive_base, "grid", date, "gridded_ppi_20240101_135500.nc"))
        @test isfile(joinpath(archive_base, "grid", date, "gridded_ppi_20240101_140500.nc"))

        rm(tmp, recursive=true)
    end

    @testset "an unparseable product name falls back to the chunk start" begin
        tmp = mktempdir()
        date = "20240101"
        step_dir = joinpath(tmp, "work", "grid", date)
        mkpath(step_dir)
        touch(joinpath(step_dir, "summary.txt"))

        archive_base = joinpath(tmp, "archive")
        wf = PathTestWorkflow(base_archive_dir = joinpath(archive_base, "{YYYYmmdd}", "{HH}"),
                              steps = [("grid", PassThroughStep, "base_data", true)],
                              force_reprocess = true)
        Sparrow.archive_workflow(wf, joinpath(tmp, "work"), date;
                                 start_time = DateTime(2024, 1, 1, 13, 55))
        @test isfile(joinpath(archive_base, "20240101", "13", "grid", "summary.txt"))

        rm(tmp, recursive=true)
    end
end

@testset "setup_workflow_params validates the generalized layout" begin

    @testset "hour and minute layouts pass" begin
        wf = PathTestWorkflow(base_data_dir = "/data/{YYYYmmdd}/{HH}{mm}",
                              base_archive_dir = "/archive/{step}/{YYYYmmdd}/{HH}",
                              base_plot_dir = "/figs/{YYYYmmdd_HH}")
        Sparrow.setup_workflow_params(wf, _path_parsed_args())
        @test Sparrow.data_dir(wf, DateTime(2024, 1, 1, 13, 5)) == "/data/20240101/1305"
        @test Sparrow.archive_step_dir(wf, "grid", DateTime(2024, 1, 1, 13, 5)) ==
              "/archive/grid/20240101/13"
        @test Sparrow.plot_output_dir(wf, "plot_rhi", DateTime(2024, 1, 1, 13, 5), "/tmp/f") ==
              joinpath("/figs/20240101_13", "plot_rhi")
    end

    @testset "{step} in base_data_dir fails at startup" begin
        wf = PathTestWorkflow(base_data_dir = "/data/{step}/{YYYYmmdd}")
        @test_throws ErrorException Sparrow.setup_workflow_params(wf, _path_parsed_args())
    end

    @testset "a leading placeholder in base_archive_dir fails at startup" begin
        wf = PathTestWorkflow(base_data_dir = "/data",
                              base_archive_dir = "/{YYYYmmdd}/archive")
        @test_throws ErrorException Sparrow.setup_workflow_params(wf, _path_parsed_args())
    end
end
