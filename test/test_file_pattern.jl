# Tests for the `file_pattern` workflow parameter (GitHub issue #8): filtering
# input files by a regular expression matched against the file's basename, so a
# directory holding files from several radars can be restricted to just one.
#
# Fixture filenames are the exact example from the issue: a directory mixing
# CHIVO, CSAPR2 and KHGX cfrad files.

using Test
using Sparrow
using Dates

@workflow_type FilePatternTestWorkflow

# The nine filenames from the issue: 3 chivo, 5 CSAPR2, 1 KHGX.
const ISSUE_FILES = [
    "cfrad.20220917_141754.000_to_20220917_141756.177_CSAPR2_RHI.nc",
    "cfrad.20220917_141807.137_to_20220917_141827.972_chivo_RHI.nc",
    "cfrad.20220917_141808.387_to_20220917_142238.578_KHGX_SUR.nc",
    "cfrad.20220917_141810.000_to_20220917_141827.005_CSAPR2_PPI.nc",
    "cfrad.20220917_141830.763_to_20220917_141841.811_chivo_RHI.nc",
    "cfrad.20220917_141835.000_to_20220917_141837.177_CSAPR2_RHI.nc",
    "cfrad.20220917_141851.000_to_20220917_141853.176_CSAPR2_RHI.nc",
    "cfrad.20220917_141906.000_to_20220917_141908.176_CSAPR2_RHI.nc",
    "cfrad.20220917_141917.989_to_20220917_141940.470_chivo_RHI.nc",
]

@testset "resolve_file_pattern" begin

    @testset "absent parameter returns nothing" begin
        wf = FilePatternTestWorkflow()
        @test Sparrow.resolve_file_pattern(wf) === nothing
    end

    @testset "a Regex is returned as is" begin
        wf = FilePatternTestWorkflow(file_pattern = r"chivo")
        @test Sparrow.resolve_file_pattern(wf) === wf["file_pattern"]
    end

    @testset "a String is compiled into a Regex" begin
        wf = FilePatternTestWorkflow(file_pattern = "chivo")
        pattern = Sparrow.resolve_file_pattern(wf)
        @test pattern isa Regex
        @test occursin(pattern, "cfrad.20220917_141807.137_to_20220917_141827.972_chivo_RHI.nc")
        @test !occursin(pattern, "cfrad.20220917_141754.000_to_20220917_141756.177_CSAPR2_RHI.nc")
    end

    @testset "an invalid regex string errors" begin
        wf = FilePatternTestWorkflow(file_pattern = "(unclosed")
        @test_throws ErrorException Sparrow.resolve_file_pattern(wf)
    end

    @testset "a non-Regex, non-String value errors" begin
        wf = FilePatternTestWorkflow(file_pattern = 42)
        @test_throws ErrorException Sparrow.resolve_file_pattern(wf)
    end

    @testset "setup_workflow_params rejects an invalid file_pattern at startup" begin
        wf = FilePatternTestWorkflow(file_pattern = "(unclosed")
        parsed_args = Dict{String,Any}(
            "datetime" => "now",
            "start" => "none",
            "stop" => "none",
            "realtime" => false,
            "force_reprocess" => false,
            "log_prefix" => "default",
        )
        @test_throws ErrorException Sparrow.setup_workflow_params(wf, parsed_args)
    end
end

@testset "matches_file_pattern / filter_by_file_pattern" begin

    @testset "\"chivo\" keeps the 3 chivo files" begin
        kept = Sparrow.filter_by_file_pattern(Regex("chivo"), ISSUE_FILES)
        @test length(kept) == 3
        @test all(f -> occursin("chivo", f), kept)
    end

    @testset "\"CSAPR2\" keeps the 5 CSAPR2 files" begin
        kept = Sparrow.filter_by_file_pattern(Regex("CSAPR2"), ISSUE_FILES)
        @test length(kept) == 5
        @test all(f -> occursin("CSAPR2", f), kept)
    end

    @testset "nothing keeps all 9 files" begin
        kept = Sparrow.filter_by_file_pattern(nothing, ISSUE_FILES)
        @test length(kept) == 9
        @test kept == ISSUE_FILES
    end

    @testset "a case-insensitive pattern matches a differently-cased input" begin
        chivo_upper = [replace(f, "chivo" => "CHIVO") for f in ISSUE_FILES if occursin("chivo", f)]
        @test length(chivo_upper) == 3
        @test length(Sparrow.filter_by_file_pattern(r"chivo"i, chivo_upper)) == 3
        # The plain (case-sensitive) pattern must not match the uppercase names
        @test length(Sparrow.filter_by_file_pattern(Regex("chivo"), chivo_upper)) == 0
    end

    @testset "matches basename, not directory" begin
        # A CSAPR2 file sitting in a directory literally named "chivo" must not
        # match file_pattern = "chivo": only the basename is checked.
        path_in_chivo_dir = joinpath("/data", "chivo",
                                     "cfrad.20220917_141754.000_to_20220917_141756.177_CSAPR2_RHI.nc")
        @test Sparrow.matches_file_pattern(Regex("chivo"), path_in_chivo_dir) == false
        @test Sparrow.matches_file_pattern(nothing, path_in_chivo_dir) == true
    end
end

@testset "LocalDirSource file_pattern" begin
    tmp = mktempdir()
    date_dir = joinpath(tmp, "20220917")
    mkpath(date_dir)
    for f in ISSUE_FILES
        touch(joinpath(date_dir, f))
    end

    @testset "a source with file_pattern only sees matching files" begin
        chivo_source = LocalDirSource(tmp; file_pattern = r"chivo")
        @test chivo_source.file_pattern == r"chivo"
        chivo_files = discover_files(chivo_source, "20220917")
        @test length(chivo_files) == 3
        @test all(f -> occursin("chivo", basename(f)), chivo_files)
    end

    @testset "the default source (no pattern) sees every file" begin
        default_source = LocalDirSource(tmp)
        @test default_source.file_pattern == r".*"
        @test length(discover_files(default_source, "20220917")) == 9
    end

    @testset "get_data_source honours the workflow's file_pattern" begin
        wf = FilePatternTestWorkflow(base_data_dir = tmp, file_pattern = "CSAPR2")
        source = Sparrow.get_data_source(wf)
        @test source isa LocalDirSource
        @test source.file_pattern == Regex("CSAPR2")
        files = discover_files(source, "20220917")
        @test length(files) == 5
    end

    rm(tmp, recursive=true)
end

@testset "link_base_data applies the workflow's file_pattern" begin

    @testset "default LocalDirSource picks up the workflow's file_pattern" begin
        tmp = mktempdir()
        data_root = joinpath(tmp, "data")
        date_dir = joinpath(data_root, "20220917")
        mkpath(date_dir)
        for f in ISSUE_FILES
            touch(joinpath(date_dir, f))
        end
        working_dir = joinpath(tmp, "working")
        mkpath(working_dir)

        wf = FilePatternTestWorkflow(base_data_dir = data_root,
                                     base_archive_dir = joinpath(tmp, "archive"),
                                     force_reprocess = true,
                                     file_pattern = "chivo")
        Sparrow.link_base_data("20220917", wf, working_dir;
                               start_time = DateTime(2022, 9, 17, 14, 15),
                               stop_time = DateTime(2022, 9, 17, 14, 25))

        linked = readdir(working_dir)
        @test length(linked) == 3
        @test all(f -> occursin("chivo", f), linked)

        rm(tmp, recursive=true)
    end

    @testset "an explicit data_source with no pattern of its own still gets filtered" begin
        tmp = mktempdir()
        data_root = joinpath(tmp, "data")
        date_dir = joinpath(data_root, "20220917")
        mkpath(date_dir)
        for f in ISSUE_FILES
            touch(joinpath(date_dir, f))
        end
        working_dir = joinpath(tmp, "working")
        mkpath(working_dir)

        wf = FilePatternTestWorkflow(data_source = LocalDirSource(data_root),
                                     base_archive_dir = joinpath(tmp, "archive"),
                                     force_reprocess = true,
                                     file_pattern = "CSAPR2")
        Sparrow.link_base_data("20220917", wf, working_dir;
                               start_time = DateTime(2022, 9, 17, 14, 15),
                               stop_time = DateTime(2022, 9, 17, 14, 25))

        linked = readdir(working_dir)
        @test length(linked) == 5
        @test all(f -> occursin("CSAPR2", f), linked)

        rm(tmp, recursive=true)
    end
end

@testset "_apply_source_pattern (shared by archive listing and realtime polling)" begin
    names = ["cfrad.20220917_141807.137_to_20220917_141827.972_chivo_RHI.nc",
             "cfrad.20220917_141754.000_to_20220917_141756.177_CSAPR2_RHI.nc",
             "cfrad.20220917_141808.387_to_20220917_142238.578_KHGX_SUR.nc"]
    default_source = LocalDirSource("/data")
    @test Sparrow._apply_source_pattern(default_source, names) === names
    chivo_source = LocalDirSource("/data"; file_pattern = r"chivo")
    @test Sparrow._apply_source_pattern(chivo_source, names) == names[1:1]
    # Matches the basename even when full paths are given
    paths = joinpath.("/data/20220917", names)
    @test Sparrow._apply_source_pattern(chivo_source, paths) == paths[1:1]
    # No debug log path is exercised when logging is off
    @test Sparrow.filter_by_file_pattern(r"chivo", names; log = false) == names[1:1]
end
