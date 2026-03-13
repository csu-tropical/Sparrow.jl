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
- `"YYYYMMDDHH"` — hour-level
- `"YYYYMMDDHHmm"` — minute-level
"""
abstract type DataSource end

# --- LocalDirSource ---

"""
    LocalDirSource <: DataSource

Data source backed by a local directory. Default and backward-compatible.

# Fields
- `base_dir::String`: Base directory containing date-organized subdirectories
"""
struct LocalDirSource <: DataSource
    base_dir::String
end

function discover_files(source::LocalDirSource, date::String)
    dir = joinpath(source.base_dir, date)
    isdir(dir) || return String[]
    try
        files = readdir(dir; join=true)
        filter!(f -> !isdir(f) && !startswith(basename(f), "."), files)
        return reverse(files)
    catch e
        msg_warning("Error reading directory $dir: $e")
        return String[]
    end
end

function fetch_file(source::LocalDirSource, filename::String, dest_dir::String, date::String)
    return joinpath(source.base_dir, date, filename)
end

is_remote(::LocalDirSource) = false

function has_data(source::LocalDirSource, date::String)
    return isdir(joinpath(source.base_dir, date))
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
  `{YYYY}`, `{MM}`, `{DD}`, `{YYYYmmdd}`, `{HH}`, `{mm}`.
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
    prefix = source.prefix_template
    if length(date) >= 8
        prefix = replace(prefix, "{YYYY}" => date[1:4])
        prefix = replace(prefix, "{MM}" => date[5:6])
        prefix = replace(prefix, "{DD}" => date[7:8])
        prefix = replace(prefix, "{YYYYmmdd}" => date[1:8])
    end
    if length(date) >= 10
        prefix = replace(prefix, "{HH}" => date[9:10])
    end
    if length(date) >= 12
        prefix = replace(prefix, "{mm}" => date[11:12])
    end
    # Resolve extras placeholders
    for (key, val) in source.extras
        prefix = replace(prefix, "{$(key)}" => val)
    end
    return prefix
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
            # Parse <Key> elements from XML response
            for m in eachmatch(r"<Key>([^<]+)</Key>", xml)
                key = m.captures[1]
                filename = basename(key)
                if occursin(source.file_pattern, filename)
                    push!(all_keys, filename)
                end
            end
            # Check for pagination
            is_truncated = occursin(r"<IsTruncated>true</IsTruncated>", xml)
            if is_truncated
                token_match = match(r"<NextContinuationToken>([^<]+)</NextContinuationToken>", xml)
                if token_match !== nothing
                    continuation_token = token_match.captures[1]
                else
                    break
                end
            else
                break
            end
        catch e
            msg_warning("Error listing S3 bucket $(source.bucket) with prefix $(prefix): $e")
            break
        end
    end
    return all_keys
end

"""
    _s3_needs_hour_iteration(source::S3BucketSource, date::String)

Check if the prefix template contains `{HH}` but the date string doesn't include an hour.
"""
function _s3_needs_hour_iteration(source::S3BucketSource, date::String)
    return occursin("{HH}", source.prefix_template) && length(date) < 10
end

function discover_files(source::S3BucketSource, date::String)
    if _s3_needs_hour_iteration(source, date)
        msg_warning("Prefix template contains {HH} but only a day-level date was provided. " *
                    "Iterating over all 24 hours — this may be slow for large datasets. " *
                    "Pass a 10-character date string (YYYYMMDDHH) to select a specific hour.")
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
    RTMASource(; station="rtma2p5", file_pattern=r"\\.grb2\$")

Create an S3BucketSource for the NOAA RTMA (Real-Time Mesoscale Analysis) public archive.

Available stations include "rtma2p5" (CONUS 2.5km), "akrtma" (Alaska), etc.
Files are hourly GRIB2 products.

# Example
```julia
source = RTMASource()
files = discover_files(source, "20250101")
```
"""
function RTMASource(; station::String = "rtma2p5", file_pattern::Regex = r"\.grb2$")
    S3BucketSource(
        bucket = "noaa-rtma-pds",
        prefix_template = "{station}.{YYYYmmdd}/",
        extras = Dict("station" => station),
        file_pattern = file_pattern,
    )
end

"""
    NBMSource(; region="co", file_pattern=r"\\.grib2\$")

Create an S3BucketSource for the NOAA NBM (National Blend of Models) GRIB2 public archive.

Requires an hour-level date (YYYYMMDDHH) for efficient access, since files are organized
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
        prefix_template = "blend.{YYYYmmdd}/{HH}/core/",
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
        prefix_template = "{region}/{product}/{YYYYmmdd}/",
        extras = Dict("region" => region, "product" => product),
        file_pattern = file_pattern,
    )
end

# --- HTTPDirSource ---

"""
    HTTPDirSource <: DataSource

Data source for HTTP directory listings.

URL supports date placeholders: `{YYYY}`, `{MM}`, `{DD}`, `{YYYYmmdd}`.

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
    url = source.base_url
    if length(date) >= 8
        url = replace(url, "{YYYY}" => date[1:4])
        url = replace(url, "{MM}" => date[5:6])
        url = replace(url, "{DD}" => date[7:8])
        url = replace(url, "{YYYYmmdd}" => date[1:8])
    end
    return url
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
