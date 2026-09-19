# Data source types for local and remote radar data

"""
    DataSource

Abstract type for radar data sources.

All data sources must implement:
- `discover_files(source, date) → Vector{String}`
- `fetch_file(source, filename, dest_dir, date) → String`
- `is_remote(source) → Bool`
- `has_data(source, date) → Bool`

The `date` parameter is a string of variable length:
- `"YYYYMMDD"` — day-level
- `"YYYYMMDDhh"` — hour-level
- `"YYYYMMDDhhmm"` — minute-level
"""
abstract type DataSource end

# --- Date placeholder substitution ---

"""
    LEGACY_PLACEHOLDER_ALIASES

Older spellings of two placeholder tokens, kept working for good: they were
public `prefix_template`/`base_url` syntax before the tokens moved to ISO 8601
notation. Each maps to its canonical form, which is what documentation and
error messages use. See [`_canonical_placeholders`](@ref).
"""
const LEGACY_PLACEHOLDER_ALIASES = ("{YYYYmmdd}" => "{YYYYMMDD}", "{HH}" => "{hh}")

"""
    _canonical_placeholders(template) → String

`template` with every [legacy placeholder spelling](@ref
LEGACY_PLACEHOLDER_ALIASES) rewritten to its canonical form, so the rest of the
placeholder machinery only ever sees `{YYYYMMDD}` and `{hh}`.
"""
function _canonical_placeholders(template::AbstractString)
    out = String(template)
    for (legacy, canonical) in LEGACY_PLACEHOLDER_ALIASES
        out = replace(out, legacy => canonical)
    end
    return out
end

"""
    substitute_date_placeholders(template, date) → String

Replace date/time placeholders in `template` with the corresponding fields of
`date`. Shared by the remote sources' `prefix_template`/`base_url` and by the
date-aware base directories (`base_data_dir`, `base_archive_dir`,
`base_plot_dir`, see [`dated_dir`](@ref)).

`date` is either a `DateTime` or a date string of variable length, as used
throughout the [`DataSource`](@ref) interface. The substitutions performed
depend on how much of the date string is present:

- `length(date) >= 8`: `{YYYY}`, `{MM}`, `{DD}`, `{YYYYMMDD}`
- `length(date) >= 10`: `{hh}`, `{YYYYMMDD_hh}`
- `length(date) >= 12`: `{mm}`, `{YYYYMMDD_hhmm}`

Placeholders with no available value are left untouched. A `DateTime` is
formatted as `"YYYYMMDDhhmm"` first, so every placeholder is substituted.

The [legacy spellings](@ref LEGACY_PLACEHOLDER_ALIASES) `{YYYYmmdd}` and `{HH}`
are still accepted silently as aliases of `{YYYYMMDD}` and `{hh}`.

# Example
```julia
substitute_date_placeholders("/archive/{YYYY}/{MM}/{DD}", "20240101")  # "/archive/2024/01/01"
substitute_date_placeholders("/data/{YYYYMMDD_hh}", "2024010113")      # "/data/20240101_13"
```
"""
function substitute_date_placeholders(template::AbstractString, date::AbstractString)
    out = _canonical_placeholders(template)
    # The combined tokens are replaced first so their leading "{YYYYMMDD" is
    # never consumed by the shorter tokens.
    if length(date) >= 12
        out = replace(out, "{YYYYMMDD_hhmm}" => date[1:8] * "_" * date[9:12])
    end
    if length(date) >= 10
        out = replace(out, "{YYYYMMDD_hh}" => date[1:8] * "_" * date[9:10])
    end
    if length(date) >= 8
        out = replace(out, "{YYYY}" => date[1:4])
        out = replace(out, "{MM}" => date[5:6])
        out = replace(out, "{DD}" => date[7:8])
        out = replace(out, "{YYYYMMDD}" => date[1:8])
    end
    if length(date) >= 10
        out = replace(out, "{hh}" => date[9:10])
    end
    if length(date) >= 12
        out = replace(out, "{mm}" => date[11:12])
    end
    return out
end

substitute_date_placeholders(template::AbstractString, date::DateTime) =
    substitute_date_placeholders(template, Dates.format(date, "YYYYmmddHHMM"))

substitute_date_placeholders(template::AbstractString, date::Date) =
    substitute_date_placeholders(template, Dates.format(date, "YYYYmmdd"))

# --- LocalDirSource ---

"""
    LocalDirSource(base_dir; date_subdir=true) <: DataSource

Data source backed by a local directory. Default and backward-compatible.

The directory actually read for a given time is resolved by [`dated_dir`](@ref):

- `base_dir` contains a [date placeholder](@ref DATE_PLACEHOLDERS) → the
  placeholders are substituted and nothing is appended. The finest token present
  sets the directory unit: `{YYYYMMDD}` is a day, `{YYYYMMDD}/{hh}` an hour,
  `{YYYYMMDD_hhmm}` a minute.
- otherwise, with `date_subdir = true` (the default) → `base_dir/YYYYMMDD`.
- otherwise, with `date_subdir = false` → `base_dir` itself, a flat directory
  holding every date's files.

The `date` of the [`DataSource`](@ref) interface names a window: 8 digits are
one day, 10 one hour and 12 one minute. `discover_files` and `has_data` read
every unit directory that window overlaps, so `has_data(source, "20240101")`
still answers "is there data that day" whatever the directory unit is.

# Fields
- `base_dir::String`: Base directory, optionally containing date placeholders
- `date_subdir::Bool`: Append a `YYYYMMDD` directory level when `base_dir` has
  no placeholder (default `true`)
"""
struct LocalDirSource <: DataSource
    base_dir::String
    date_subdir::Bool
    function LocalDirSource(base_dir::AbstractString, date_subdir::Bool)
        # Reject typos such as {yyyy} up front; otherwise every day would just
        # report "no data" against a literal directory name.
        validate_date_placeholders(base_dir, "LocalDirSource base_dir")
        return new(String(base_dir), date_subdir)
    end
end

LocalDirSource(base_dir::AbstractString; date_subdir::Bool = true) =
    LocalDirSource(base_dir, date_subdir)

"""
    _is_flat(source::LocalDirSource) → Bool

True when the source reads one flat directory holding every date's files
(no date placeholder in `base_dir` and `date_subdir = false`).
"""
_is_flat(source::LocalDirSource) = !has_date_placeholder(source.base_dir) && !source.date_subdir

"""
    source_resolution(source::LocalDirSource) → Symbol

Time organization unit of the source's directory tree: the
[`placeholder_resolution`](@ref) of `base_dir` if it has any placeholder, else
`:day` when `date_subdir` appends a `YYYYMMDD` level, else `:none` for a flat
directory.
"""
function source_resolution(source::LocalDirSource)
    resolution = placeholder_resolution(source.base_dir)
    resolution === :none || return resolution
    return source.date_subdir ? :day : :none
end

"""
    unit_dirs(source::LocalDirSource, start_time, stop_time) → Vector{String}

Every distinct directory of `source` that the window `[start_time, stop_time)`
overlaps, in chronological order. A flat source has a single directory; a dated
one is walked from `floor_to_unit(start_time, ...)` in steps of one unit.

A window shorter than one unit yields one directory, and a window spanning a
boundary yields all the directories it touches — a rapid-scan chunk crossing the
top of the hour reads both hours rather than being split.
"""
function unit_dirs(source::LocalDirSource, start_time::DateTime, stop_time::DateTime)
    resolution = source_resolution(source)
    resolution === :none && return String[source.base_dir]
    period = unit_period(resolution)
    dirs = String[]
    t = floor_to_unit(start_time, resolution)
    while t < stop_time
        dir = _local_dir(source, t)
        dir in dirs || push!(dirs, dir)
        t += period
    end
    # An empty or inverted window still names the directory it starts in
    isempty(dirs) && push!(dirs, _local_dir(source, floor_to_unit(start_time, resolution)))
    return dirs
end

"""
    _filter_names_by_window(files, start_time, stop_time) → Vector{String}

Keep the files whose filename timestamp (see [`_parse_filename_time`](@ref))
falls in `[start_time, stop_time)`. Files whose names carry no recognizable
timestamp are kept, since they could belong to any window. Used to pick one
window's files out of a flat directory.
"""
function _filter_names_by_window(files::AbstractVector{<:AbstractString},
                                 start_time::DateTime, stop_time::DateTime)
    return filter(files) do f
        scan_start = _parse_filename_time(basename(f))
        scan_start === nothing || (scan_start >= start_time && scan_start < stop_time)
    end
end

"""
    _filter_names_by_day(files, date) → Vector{String}

[`_filter_names_by_window`](@ref) over the whole day of `date` (`"YYYYMMDD"`,
longer strings are truncated to the day).
"""
function _filter_names_by_day(files::AbstractVector{<:AbstractString}, date::AbstractString)
    day_start = DateTime(String(date)[1:8], dateformat"YYYYmmdd")
    return _filter_names_by_window(files, day_start, day_start + Dates.Day(1))
end

"""
    _date_window(date) → (DateTime, DateTime)

The window a [`DataSource`](@ref) `date` string names: 8 digits are one day,
10 one hour and 12 one minute (longer strings are truncated to the minute).
"""
function _date_window(date::AbstractString)
    s = String(date)
    if length(s) >= 12
        t = DateTime(s[1:12], dateformat"YYYYmmddHHMM")
        return (t, t + Dates.Minute(1))
    elseif length(s) >= 10
        t = DateTime(s[1:10], dateformat"YYYYmmddHH")
        return (t, t + Dates.Hour(1))
    elseif length(s) >= 8
        t = DateTime(s[1:8], dateformat"YYYYmmdd")
        return (t, t + Dates.Day(1))
    end
    msg_error("Date string \"$date\" is too short. Expected YYYYMMDD (a day), " *
              "YYYYMMDDhh (an hour) or YYYYMMDDhhmm (a minute).")
end

"""
    _local_dir(source::LocalDirSource, date) → String

Directory this source reads for `date`, honouring date placeholders in
`base_dir` and the `date_subdir` flag.
"""
_local_dir(source::LocalDirSource, date) = dated_dir(source.base_dir, date, source.date_subdir)

"""
    _coarse_prefix(source::LocalDirSource, t::DateTime) → String

The deepest directory of `source`'s tree that is fixed once the *day* of `t` is
known: the template with only its day-level tokens substituted, cut before the
first component that still holds an hour or minute token. For a day-level
layout this is the day directory itself; for `/data/{YYYYMMDD}/{hh}` it is
`/data/20240101`. Checking it first lets a day with no data at all be rejected
with one `isdir` instead of one per hour or minute directory.
"""
function _coarse_prefix(source::LocalDirSource, t::DateTime)
    _is_flat(source) && return source.base_dir
    # `has_date_placeholder` and `substitute_date_placeholders` both canonicalize
    # the legacy token spellings first, so this reads either spelling as it is.
    has_date_placeholder(source.base_dir) || return _local_dir(source, t)
    # An 8-digit date substitutes only the day-level tokens
    partial = substitute_date_placeholders(source.base_dir, Dates.format(t, "YYYYmmdd"))
    occursin('{', partial) || return partial
    kept = String[]
    for part in splitpath(partial)
        occursin('{', part) && break
        push!(kept, part)
    end
    return isempty(kept) ? partial : joinpath(kept...)
end

"""
    _existing_unit_dirs(source::LocalDirSource, start_time, stop_time) → Vector{String}

The unit directories of `source` that the window overlaps *and* exist on disk,
in chronological order. Days whose coarse prefix is missing are skipped without
probing their hour or minute directories. With `first_only` the walk stops at
the first existing directory, for existence checks.
"""
function _existing_unit_dirs(source::LocalDirSource, start_time::DateTime, stop_time::DateTime;
                             first_only::Bool=false)
    dirs = String[]
    _is_flat(source) && return isdir(source.base_dir) ? push!(dirs, source.base_dir) : dirs
    # Walk one day at a time so a day whose tree is absent costs a single stat
    # rather than one per hour or minute directory.
    day = Dates.Date(start_time)
    stop_time = max(stop_time, start_time)
    while true
        day_start = max(DateTime(day), start_time)
        day_stop = min(DateTime(day) + Dates.Day(1), stop_time)
        if isdir(_coarse_prefix(source, day_start))
            for dir in unit_dirs(source, day_start, day_stop)
                isdir(dir) || continue
                push!(dirs, dir)
                first_only && return dirs
            end
        end
        day += Dates.Day(1)
        DateTime(day) < stop_time || break
    end
    return dirs
end

"""
    _list_unit_files(source::LocalDirSource, start_time, stop_time) → (Vector{String}, Bool)

Regular, non-hidden files across every unit directory of `source` that the
window `[start_time, stop_time)` overlaps, de-duplicated and in directory order,
plus whether any of those directories existed. A flat directory is narrowed to
the window by filename timestamp. Shared by `discover_files` and the local
branch of `link_base_data` so the two never drift.
"""
function _list_unit_files(source::LocalDirSource, start_time::DateTime, stop_time::DateTime)
    files = String[]
    dirs = _existing_unit_dirs(source, start_time, stop_time)
    for dir in dirs
        try
            entries = readdir(dir; join=true)
            filter!(f -> !isdir(f) && !startswith(basename(f), "."), entries)
            append!(files, entries)
        catch e
            msg_warning("Error reading directory $dir: $e")
        end
    end
    # A flat directory holds every date, so select this window by name
    _is_flat(source) && (files = _filter_names_by_window(files, start_time, stop_time))
    unique!(files)
    return files, !isempty(dirs)
end

function discover_files(source::LocalDirSource, date::String)
    window_start, window_stop = _date_window(date)
    files, _ = _list_unit_files(source, window_start, window_stop)
    # Newest first, as the realtime poller and the chunked runs expect
    return reverse(files)
end

function fetch_file(source::LocalDirSource, filename::String, dest_dir::String, date::String)
    window_start, window_stop = _date_window(date)
    # The file may live in any unit directory of the window (an hour-resolution
    # layout queried by day, say); return the one that has it, else the window
    # start's directory so the caller gets a sensible path for a missing file.
    for dir in _existing_unit_dirs(source, window_start, window_stop)
        candidate = joinpath(dir, filename)
        isfile(candidate) && return candidate
    end
    return joinpath(_local_dir(source, window_start), filename)
end

is_remote(::LocalDirSource) = false

function has_data(source::LocalDirSource, date::String)
    window_start, window_stop = _date_window(date)
    # A dated directory (placeholder or `YYYYMMDD` subdirectory) covers a known
    # slice of time by construction, so the existence of any unit directory the
    # window touches is the answer. A flat directory holds every date at once, so
    # look at the filenames instead — otherwise a month or year run would think
    # every day had data and iterate over empty chunks.
    if !_is_flat(source)
        return !isempty(_existing_unit_dirs(source, window_start, window_stop; first_only=true))
    end
    dir = source.base_dir
    isdir(dir) || return false
    any_parseable = false
    any_unparseable = false
    for entry in readdir(dir)
        startswith(entry, ".") && continue
        isdir(joinpath(dir, entry)) && continue
        scan_start = _parse_filename_time(entry)
        if scan_start === nothing
            any_unparseable = true
        else
            any_parseable = true
            (scan_start >= window_start && scan_start < window_stop) && return true
        end
    end
    # When the filenames carry timestamps, trust them: a stray README or similar
    # must not make every day of a year run look populated. Only when nothing in
    # the directory is parseable do we have to assume the day may have data.
    return any_unparseable && !any_parseable
end

supports_streaming(::DataSource) = false
fetch_stream(::DataSource, ::String, ::String) = error("Streaming not supported for this data source")

# --- S3BucketSource ---

"""
    S3BucketSource <: DataSource

Data source for S3 buckets (e.g., NEXRAD Level 2, NOAA RTMA, MRMS, NBM).

Supports public/anonymous-access buckets directly via HTTPS (no AWS CLI or
credentials required). For private buckets, consider using AWSS3.jl for
full AWS Signature V4 authentication.

# Fields
- `bucket::String`: S3 bucket name (e.g., "unidata-nexrad-level2")
- `prefix_template::String`: Template for S3 key prefix with placeholders:
  `{YYYY}`, `{MM}`, `{DD}`, `{YYYYMMDD}`, `{hh}`, `{mm}` (the legacy spellings
  `{YYYYmmdd}` and `{HH}` still work).
  Additional placeholders can be defined via `extras`.
- `extras::Dict{String,String}`: Additional template variables. Keys become
  `{key}` placeholders in the prefix template.
  Examples: `Dict("station" => "KFTG")`, `Dict("region" => "CONUS", "product" => "QPE")`
- `region::String`: AWS region (default: "us-east-1")
- `endpoint::String`: S3 endpoint URL (auto-generated if empty)
- `aws_access_key_id::String`: AWS access key (empty for public buckets)
- `aws_secret_access_key::String`: AWS secret key (empty for public buckets)
- `file_pattern::Regex`: Pattern to filter files
"""
struct S3BucketSource <: DataSource
    bucket::String
    prefix_template::String
    extras::Dict{String,String}
    region::String
    endpoint::String
    aws_access_key_id::String
    aws_secret_access_key::String
    file_pattern::Regex
end

function S3BucketSource(;
    bucket::String,
    prefix_template::String = "{YYYY}/{MM}/{DD}/",
    extras::Dict{String,String} = Dict{String,String}(),
    region::String = "us-east-1",
    endpoint::String = "",
    aws_access_key_id::String = "",
    aws_secret_access_key::String = "",
    file_pattern::Regex = r".*"
)
    if isempty(endpoint)
        endpoint = "https://$(bucket).s3.$(region).amazonaws.com"
    end
    S3BucketSource(bucket, prefix_template, extras, region, endpoint,
                   aws_access_key_id, aws_secret_access_key, file_pattern)
end

"""Resolve an S3 prefix template with date/time and extras values."""
function _s3_resolve_prefix(source::S3BucketSource, date::String)
    prefix = substitute_date_placeholders(source.prefix_template, date)
    # Resolve extras placeholders
    for (key, val) in source.extras
        prefix = replace(prefix, "{$(key)}" => val)
    end
    return prefix
end

"""
    _s3_parse_list_response(xml::AbstractString, file_pattern::Regex)
        -> (filenames::Vector{String}, next_token::Union{String,Nothing})

Pure helper: parse a single ListObjectsV2 XML response. Returns matching filenames
and the next continuation token (or `nothing` if the listing is complete or the
truncated response is missing its token).
"""
function _s3_parse_list_response(xml::AbstractString, file_pattern::Regex)
    filenames = String[]
    for m in eachmatch(r"<Key>([^<]+)</Key>", xml)
        filename = basename(m.captures[1])
        if occursin(file_pattern, filename)
            push!(filenames, filename)
        end
    end
    next_token = nothing
    if occursin(r"<IsTruncated>true</IsTruncated>", xml)
        token_match = match(r"<NextContinuationToken>([^<]+)</NextContinuationToken>", xml)
        if token_match !== nothing
            next_token = String(token_match.captures[1])
        end
    end
    return filenames, next_token
end

"""
    _s3_list_prefix(source::S3BucketSource, prefix::String)

List all files under an S3 prefix, handling pagination for large result sets.
"""
function _s3_list_prefix(source::S3BucketSource, prefix::String)
    if !isempty(source.aws_access_key_id)
        msg_warning("AWS Signature V4 not implemented for private buckets. Use AWSS3.jl for authenticated access.")
    end
    all_keys = String[]
    continuation_token = ""
    while true
        url = "$(source.endpoint)?list-type=2&prefix=$(prefix)"
        if !isempty(continuation_token)
            url *= "&continuation-token=$(continuation_token)"
        end
        try
            buf = IOBuffer()
            Downloads.download(url, buf)
            xml = String(take!(buf))
            page_keys, next_token = _s3_parse_list_response(xml, source.file_pattern)
            append!(all_keys, page_keys)
            isnothing(next_token) && break
            continuation_token = next_token
        catch e
            msg_warning("Error listing S3 bucket $(source.bucket) with prefix $(prefix): $e")
            break
        end
    end
    return all_keys
end

"""
    _s3_needs_hour_iteration(source::S3BucketSource, date::String)

Check if the prefix template contains `{hh}` (or its legacy alias `{HH}`) but
the date string doesn't include an hour.
"""
function _s3_needs_hour_iteration(source::S3BucketSource, date::String)
    return occursin("{hh}", _canonical_placeholders(source.prefix_template)) && length(date) < 10
end

function discover_files(source::S3BucketSource, date::String)
    if _s3_needs_hour_iteration(source, date)
        msg_warning("Prefix template contains {hh} but only a day-level date was provided. " *
                    "Iterating over all 24 hours — this may be slow for large datasets. " *
                    "Pass a 10-character date string (YYYYMMDDhh) to select a specific hour.")
        all_files = String[]
        for hh in 0:23
            hour_date = date * lpad(hh, 2, '0')
            prefix = _s3_resolve_prefix(source, hour_date)
            append!(all_files, _s3_list_prefix(source, prefix))
        end
        return all_files
    else
        prefix = _s3_resolve_prefix(source, date)
        return _s3_list_prefix(source, prefix)
    end
end

function fetch_file(source::S3BucketSource, filename::String, dest_dir::String, date::String)
    # If hour iteration is needed, try each hour to find the file
    if _s3_needs_hour_iteration(source, date)
        for hh in 0:23
            hour_date = date * lpad(hh, 2, '0')
            prefix = _s3_resolve_prefix(source, hour_date)
            key = "$(prefix)$(filename)"
            url = "$(source.endpoint)/$(key)"
            local_path = joinpath(dest_dir, filename)
            if isfile(local_path)
                return local_path
            end
            mkpath(dest_dir)
            try
                Downloads.download(url, local_path)
                msg_debug("Downloaded $filename from S3 to $local_path")
                return local_path
            catch
                # Try next hour
                continue
            end
        end
        error("File $filename not found under any hour prefix for date $date")
    else
        prefix = _s3_resolve_prefix(source, date)
        key = "$(prefix)$(filename)"
        url = "$(source.endpoint)/$(key)"
        local_path = joinpath(dest_dir, filename)
        if isfile(local_path)
            return local_path
        end
        mkpath(dest_dir)
        try
            Downloads.download(url, local_path)
            msg_debug("Downloaded $filename from S3 to $local_path")
            return local_path
        catch e
            msg_warning("Error downloading $filename from S3: $e")
            rethrow(e)
        end
    end
end

is_remote(::S3BucketSource) = true

function has_data(source::S3BucketSource, date::String)
    return !isempty(discover_files(source, date))
end

# --- Convenience constructors for NOAA public datasets ---

"""
    NEXRADSource(station; file_pattern=r".*")

Create an S3BucketSource for the Unidata NEXRAD Level 2 public archive.

# Arguments
- `station::String`: Radar station ID (e.g., "KFTG", "KEVX")
- `file_pattern::Regex`: Optional file filter (e.g., `r"_V06\$"` for V06 format only)

# Example
```julia
source = NEXRADSource("KFTG")
files = discover_files(source, "20240101")
```
"""
function NEXRADSource(station::String; file_pattern::Regex = r".*")
    S3BucketSource(
        bucket = "unidata-nexrad-level2",
        prefix_template = "{YYYY}/{MM}/{DD}/{station}/",
        extras = Dict("station" => station),
        file_pattern = file_pattern,
    )
end

"""
    RTMASource(; station="rtma2p5", file_pattern=r"\\.grb2(_wexp)?\$")

Create an S3BucketSource for the NOAA RTMA (Real-Time Mesoscale Analysis) public archive.

Available stations include "rtma2p5" (CONUS 2.5km), "akrtma" (Alaska), etc.
Files are hourly GRIB2 products. Analysis files use the `_wexp` (westward expanded) suffix.

# Example
```julia
source = RTMASource()
files = discover_files(source, "20250101")
```
"""
function RTMASource(; station::String = "rtma2p5", file_pattern::Regex = r"\.grb2(_wexp)?$")
    S3BucketSource(
        bucket = "noaa-rtma-pds",
        prefix_template = "{station}.{YYYYMMDD}/",
        extras = Dict("station" => station),
        file_pattern = file_pattern,
    )
end

"""
    NBMSource(; region="co", file_pattern=r"\\.grib2\$")

Create an S3BucketSource for the NOAA NBM (National Blend of Models) GRIB2 public archive.

Requires an hour-level date (YYYYMMDDhh) for efficient access, since files are organized
by forecast cycle hour. If only a day is given, all 24 hours will be iterated.

# Regions
- `"co"` — CONUS
- `"ak"` — Alaska
- `"hi"` — Hawaii
- `"gu"` — Guam
- `"pr"` — Puerto Rico

# Example
```julia
source = NBMSource(region="co")
files = discover_files(source, "2025010100")  # 00Z cycle
```
"""
function NBMSource(; region::String = "co", file_pattern::Regex = r"\.grib2$")
    S3BucketSource(
        bucket = "noaa-nbm-grib2-pds",
        prefix_template = "blend.{YYYYMMDD}/{hh}/core/",
        extras = Dict("region" => region),
        file_pattern = file_pattern,
    )
end

"""
    MRMSSource(; region="CONUS", product="MergedBaseReflectivity_00.50",
                 file_pattern=r"\\.grib2\\.gz\$")

Create an S3BucketSource for the NOAA MRMS (Multi-Radar Multi-Sensor) public archive.

Files are organized by region, product, and date. Sub-hourly products (e.g.,
reflectivity at ~2-minute intervals) may have hundreds of files per day.

# Regions
- `"CONUS"`, `"ALASKA"`, `"HAWAII"`, `"GUAM"`, `"CARIB"`

# Common products
- `"MergedBaseReflectivity_00.50"` — Base reflectivity (~2 min)
- `"MultiSensor_QPE_01H_Pass2_00.00"` — 1-hour QPE (hourly)
- `"PrecipRate_00.00"` — Precipitation rate

# Example
```julia
source = MRMSSource(product="MultiSensor_QPE_01H_Pass2_00.00")
files = discover_files(source, "20201014")
```
"""
function MRMSSource(; region::String = "CONUS",
                      product::String = "MergedBaseReflectivity_00.50",
                      file_pattern::Regex = r"\.grib2\.gz$")
    S3BucketSource(
        bucket = "noaa-mrms-pds",
        prefix_template = "{region}/{product}/{YYYYMMDD}/",
        extras = Dict("region" => region, "product" => product),
        file_pattern = file_pattern,
    )
end

# --- HTTPDirSource ---

"""
    HTTPDirSource <: DataSource

Data source for HTTP directory listings.

URL supports date placeholders: `{YYYY}`, `{MM}`, `{DD}`, `{YYYYMMDD}`, and —
when an hour/minute-level date string is supplied — `{hh}` and `{mm}`
(see [`substitute_date_placeholders`](@ref), which also accepts the legacy
spellings `{YYYYmmdd}` and `{HH}`).

# Fields
- `base_url::String`: URL template with optional date placeholders
- `file_pattern::Regex`: Pattern to filter files from directory listing
- `auth_type::Symbol`: Authentication type (`:none`, `:basic`, `:bearer`, `:api_key`)
- `auth_username::String`: Username for basic auth
- `auth_password::String`: Password for basic auth
- `api_key::String`: API key value
- `api_key_header::String`: Header name for API key (default: "X-API-Key")
"""
struct HTTPDirSource <: DataSource
    base_url::String
    file_pattern::Regex
    auth_type::Symbol
    auth_username::String
    auth_password::String
    api_key::String
    api_key_header::String
end

function HTTPDirSource(;
    base_url::String,
    file_pattern::Regex = r".*",
    auth_type::Symbol = :none,
    auth_username::String = "",
    auth_password::String = "",
    api_key::String = "",
    api_key_header::String = "X-API-Key"
)
    HTTPDirSource(base_url, file_pattern, auth_type, auth_username, auth_password, api_key, api_key_header)
end

function _http_resolve_url(source::HTTPDirSource, date::String)
    return substitute_date_placeholders(source.base_url, date)
end

function _http_auth_headers(source::HTTPDirSource)
    headers = Pair{String,String}[]
    if source.auth_type == :basic
        creds = Base64.base64encode("$(source.auth_username):$(source.auth_password)")
        push!(headers, "Authorization" => "Basic $creds")
    elseif source.auth_type == :bearer
        push!(headers, "Authorization" => "Bearer $(source.api_key)")
    elseif source.auth_type == :api_key
        push!(headers, source.api_key_header => source.api_key)
    end
    return headers
end

function discover_files(source::HTTPDirSource, date::String)
    url = _http_resolve_url(source, date)
    headers = _http_auth_headers(source)
    try
        buf = IOBuffer()
        Downloads.download(url, buf; headers=headers)
        html = String(take!(buf))
        # Parse <a href="..."> links from HTML directory listing
        files = String[]
        for m in eachmatch(r"<a\s+[^>]*href=\"([^\"]+)\"", html)
            href = m.captures[1]
            filename = basename(href)
            if !isempty(filename) && !startswith(filename, ".") && occursin(source.file_pattern, filename)
                push!(files, filename)
            end
        end
        return files
    catch e
        msg_warning("Error listing HTTP directory $url: $e")
        return String[]
    end
end

function fetch_file(source::HTTPDirSource, filename::String, dest_dir::String, date::String)
    base_url = _http_resolve_url(source, date)
    # Ensure trailing slash
    if !endswith(base_url, "/")
        base_url *= "/"
    end
    url = base_url * filename
    local_path = joinpath(dest_dir, filename)
    if isfile(local_path)
        return local_path
    end
    mkpath(dest_dir)
    headers = _http_auth_headers(source)
    try
        Downloads.download(url, local_path; headers=headers)
        msg_debug("Downloaded $filename from HTTP to $local_path")
        return local_path
    catch e
        msg_warning("Error downloading $filename from HTTP: $e")
        rethrow(e)
    end
end

is_remote(::HTTPDirSource) = true

function has_data(source::HTTPDirSource, date::String)
    return !isempty(discover_files(source, date))
end
