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
    # {HH}/{mm} are for remote prefix templates, not for the base directories
    @test !Sparrow.has_date_placeholder("/archive/{HH}")

    @test Sparrow.validate_date_placeholders("/archive/{YYYY}/{MM}/{DD}", "base_archive_dir") ==
          "/archive/{YYYY}/{MM}/{DD}"
    @test Sparrow.validate_date_placeholders("/archive/chivo", "base_archive_dir") == "/archive/chivo"

    for bad in ["/archive/{yyyy}", "/archive/{date}", "/archive/{YYYYMMDD}", "/archive/{HH}"]
        @test_throws ErrorException Sparrow.validate_date_placeholders(bad, "base_archive_dir")
    end

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
        @test Sparrow.archive_root_dir(wf, "20240101") == "/archive"
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
        @test Sparrow.archive_root_dir(wf, "20240101") == "/archive/20240101/chivo"
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
