# Data source types for local and remote radar data

"""
    DataSource

Abstract type for radar data sources.

All data sources must implement:
- `discover_files(source, date) → Vector{String}`
- `fetch_file(source, filename, dest_dir, date) → String`
- `is_remote(source) → Bool`
- `has_data(source, date) → Bool`
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

Data source for S3 buckets (e.g., NEXRAD Level 2, NOAA RTMA).

Supports public/anonymous-access buckets directly via HTTPS (no AWS CLI or
credentials required). For private buckets, consider using AWSS3.jl for
full AWS Signature V4 authentication.

# Fields
- `bucket::String`: S3 bucket name (e.g., "unidata-nexrad-level2")
- `station::String`: Station or product identifier used in the S3 prefix
- `prefix_template::String`: Template for S3 key prefix with placeholders:
  `{YYYY}`, `{MM}`, `{DD}`, `{YYYYmmdd}`, `{station}`.
  Default: `"{YYYY}/{MM}/{DD}/{station}/"` (NEXRAD convention).
  RTMA example: `"{station}.{YYYYmmdd}/"`
- `region::String`: AWS region (default: "us-east-1")
- `endpoint::String`: S3 endpoint URL (auto-generated if empty)
- `aws_access_key_id::String`: AWS access key (empty for public buckets)
- `aws_secret_access_key::String`: AWS secret key (empty for public buckets)
- `file_pattern::Regex`: Pattern to filter files
"""
struct S3BucketSource <: DataSource
    bucket::String
    station::String
    prefix_template::String
    region::String
    endpoint::String
    aws_access_key_id::String
    aws_secret_access_key::String
    file_pattern::Regex
end

function S3BucketSource(;
    bucket::String,
    station::String,
    prefix_template::String = "{YYYY}/{MM}/{DD}/{station}/",
    region::String = "us-east-1",
    endpoint::String = "",
    aws_access_key_id::String = "",
    aws_secret_access_key::String = "",
    file_pattern::Regex = r".*"
)
    if isempty(endpoint)
        endpoint = "https://$(bucket).s3.$(region).amazonaws.com"
    end
    S3BucketSource(bucket, station, prefix_template, region, endpoint,
                   aws_access_key_id, aws_secret_access_key, file_pattern)
end

"""Resolve an S3 prefix template with date and station values."""
function _s3_resolve_prefix(source::S3BucketSource, date::String)
    prefix = source.prefix_template
    if length(date) >= 8
        prefix = replace(prefix, "{YYYY}" => date[1:4])
        prefix = replace(prefix, "{MM}" => date[5:6])
        prefix = replace(prefix, "{DD}" => date[7:8])
        prefix = replace(prefix, "{YYYYmmdd}" => date[1:8])
    end
    prefix = replace(prefix, "{station}" => source.station)
    return prefix
end

function _s3_list_prefix(source::S3BucketSource, prefix::String)
    url = "$(source.endpoint)?list-type=2&prefix=$(prefix)"
    headers = Pair{String,String}[]
    if !isempty(source.aws_access_key_id)
        msg_warning("AWS Signature V4 not implemented for private buckets. Use AWSS3.jl for authenticated access.")
    end
    try
        buf = IOBuffer()
        Downloads.download(url, buf; headers=headers)
        xml = String(take!(buf))
        # Parse <Key> elements from XML response
        keys = String[]
        for m in eachmatch(r"<Key>([^<]+)</Key>", xml)
            key = m.captures[1]
            filename = basename(key)
            if occursin(source.file_pattern, filename)
                push!(keys, filename)
            end
        end
        return keys
    catch e
        msg_warning("Error listing S3 bucket $(source.bucket) with prefix $(prefix): $e")
        return String[]
    end
end

function discover_files(source::S3BucketSource, date::String)
    prefix = _s3_resolve_prefix(source, date)
    return _s3_list_prefix(source, prefix)
end

function fetch_file(source::S3BucketSource, filename::String, dest_dir::String, date::String)
    prefix = _s3_resolve_prefix(source, date)
    key = "$(prefix)$(filename)"
    url = "$(source.endpoint)/$(key)"
    local_path = joinpath(dest_dir, filename)
    if isfile(local_path)
        return local_path
    end
    mkpath(dest_dir)
    headers = Pair{String,String}[]
    try
        Downloads.download(url, local_path; headers=headers)
        msg_debug("Downloaded $filename from S3 to $local_path")
        return local_path
    catch e
        msg_warning("Error downloading $filename from S3: $e")
        rethrow(e)
    end
end

is_remote(::S3BucketSource) = true

function has_data(source::S3BucketSource, date::String)
    return !isempty(discover_files(source, date))
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

