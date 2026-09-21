# Workflow functions and definitions

"""
    SparrowWorkflow <: AbstractDict{String,Any}

Abstract base type for all Sparrow workflows.

All workflow types created with [`@workflow_type`](@ref) inherit from `SparrowWorkflow`.
This type subtypes `AbstractDict{String,Any}` to provide a dictionary interface for
accessing workflow parameters.

# Dictionary Interface

Workflows support standard dictionary operations:
- `workflow["key"]` - Get parameter (throws error if not found)
- `workflow["key"] = value` - Set parameter
- `haskey(workflow.params, "key")` - Check if parameter exists
- `keys(workflow.params)` - Get all parameter names
- `length(workflow)` - Number of parameters

# See Also
- [`@workflow_type`](@ref)
- [`get_param`](@ref)
"""
abstract type SparrowWorkflow <: AbstractDict{String,Any} end

# Implement dict interface (same for all subtypes)
#Base.getindex(p::SparrowWorkflow, key) = getindex(p.params, key)
function Base.getindex(workflow::SparrowWorkflow, key::String)
    if !haskey(workflow.params, key)
        msg_error("Required parameter '$key' not found in $(typeof(workflow)). Available parameters: $(sort(collect(keys(workflow.params))))")
    end
    return workflow.params[key]
end
Base.setindex!(p::SparrowWorkflow, value, key) = setindex!(p.params, value, key)
Base.iterate(p::SparrowWorkflow) = iterate(p.params)
Base.iterate(p::SparrowWorkflow, state) = iterate(p.params, state)
Base.length(p::SparrowWorkflow) = length(p.params)

"""
    get_param(workflow::SparrowWorkflow, key::String, default) → Any

Get a workflow parameter with a default value if not found.

# Arguments
- `workflow`: Workflow instance
- `key`: Parameter name
- `default`: Default value to return if parameter not found

# Returns
Parameter value if found, otherwise `default`

# Example
```julia
span = get_param(workflow, "span_seconds", 600)
threshold = get_param(workflow, "threshold", 5.0)
```
"""
function get_param(workflow::SparrowWorkflow, key::String, default)
    return get(workflow.params, key, default)
end

"""
    get_param(workflow::SparrowWorkflow, key::String, ::Type{T}) → T

Get a workflow parameter with type checking.

# Arguments
- `workflow`: Workflow instance
- `key`: Parameter name
- `T`: Expected type

# Returns
Parameter value (type-asserted to `T`)

# Throws
- Error if parameter not found
- Error if parameter type doesn't match `T`

# Example
```julia
moments = get_param(workflow, "raw_moment_names", Vector{String})
```
"""
function get_param(workflow::SparrowWorkflow, key::String, ::Type{T}) where {T}
    if !haskey(workflow.params, key)
        msg_error("Required parameter '$key' not found in $(typeof(workflow)). Available parameters: $(keys(workflow.params))")
    end
    value = workflow.params[key]
    if !(value isa T)
        msg_error("Parameter '$key' has type $(typeof(value)), expected $T")
    end
    return value::T
end

"""
    get_daisho_params(workflow::SparrowWorkflow) → DaishoParameters

Get the Daisho parameters built from the workflow's `daisho_config` TOML file.

Throws an error with setup instructions if the workflow has no `daisho_config`
parameter. Steps that grid or otherwise call into Daisho should use this
accessor rather than reading `workflow["daisho_params"]` directly.
"""
function get_daisho_params(workflow::SparrowWorkflow)
    if haskey(workflow.params, "daisho_params")
        return workflow["daisho_params"]::DaishoParameters
    end
    error("This workflow step requires a Daisho TOML configuration. Add " *
          "`daisho_config = \"/path/to/daisho.toml\"` to your workflow parameters. " *
          "Generate a template with `using Daisho; print_config(\"daisho.toml\")` " *
          "and edit it for your radar.")
end

"""
    DATE_PLACEHOLDERS

Date/time placeholders accepted in `base_data_dir`, `base_archive_dir` and
`base_plot_dir`. A base directory containing any of them has the time
substituted in place, and no extra date directory level is appended.

| Token             | Unit   | 2024-01-01 13:05 |
| ----------------- | ------ | ---------------- |
| `{YYYY}`          | day    | `2024`           |
| `{MM}`            | day    | `01`             |
| `{DD}`            | day    | `01`             |
| `{YYYYMMDD}`      | day    | `20240101`       |
| `{hh}`            | hour   | `13`             |
| `{YYYYMMDD_hh}`   | hour   | `20240101_13`    |
| `{mm}`            | minute | `05`             |
| `{YYYYMMDD_hhmm}` | minute | `20240101_1305`  |

Tokens follow ISO 8601 notation: uppercase letters for the date fields and
lowercase for the time fields. The [legacy spellings](@ref
LEGACY_PLACEHOLDER_ALIASES) `{YYYYmmdd}` and `{HH}` are still accepted silently
as aliases of `{YYYYMMDD}` and `{hh}`.

The finest token present sets the directory's *time organization unit*, day,
hour or minute (see [`placeholder_resolution`](@ref)). That unit is independent
of the processing granularity: a chunk is always `span_seconds` long and may
overlap several unit directories.

See [`dated_dir`](@ref) and [`substitute_date_placeholders`](@ref).
"""
const DATE_PLACEHOLDERS = ("{YYYYMMDD_hhmm}", "{YYYYMMDD_hh}", "{YYYYMMDD}",
                           "{YYYY}", "{MM}", "{DD}", "{hh}", "{mm}")

"""
    STEP_PLACEHOLDER

The `{step}` token. Valid in `base_archive_dir` and `base_plot_dir` only, where
it marks the level at which the step name is inserted; without it the step name
is appended after the resolved base. `base_data_dir` has no step, so `{step}`
there is rejected at startup.
"""
const STEP_PLACEHOLDER = "{step}"

"""
Tokens of [`DATE_PLACEHOLDERS`](@ref) that resolve only to a day, an hour and a
minute respectively. Used by [`placeholder_resolution`](@ref).
"""
const DAY_PLACEHOLDERS = ("{YYYY}", "{MM}", "{DD}", "{YYYYMMDD}")
const HOUR_PLACEHOLDERS = ("{hh}", "{YYYYMMDD_hh}")
const MINUTE_PLACEHOLDERS = ("{mm}", "{YYYYMMDD_hhmm}")

"""
    has_date_placeholder(path) → Bool

True if `path` contains one of the [`DATE_PLACEHOLDERS`](@ref), or one of their
[legacy spellings](@ref LEGACY_PLACEHOLDER_ALIASES). `{step}` alone does not
count, since it carries no time information.
"""
function has_date_placeholder(path::AbstractString)
    canonical = _canonical_placeholders(path)
    return any(p -> occursin(p, canonical), DATE_PLACEHOLDERS)
end

"""
    has_step_placeholder(path) → Bool

True if `path` contains the [`STEP_PLACEHOLDER`](@ref).
"""
has_step_placeholder(path::AbstractString) = occursin(STEP_PLACEHOLDER, path)

"""
    validate_date_placeholders(path, param_name; allow_step=false) → path

Check that every `{...}` token in `path` is one of the
[`DATE_PLACEHOLDERS`](@ref) or their
[legacy spellings](@ref LEGACY_PLACEHOLDER_ALIASES), plus
[`STEP_PLACEHOLDER`](@ref) when `allow_step` is set. Called from
[`setup_workflow_params`](@ref) so a typo such as `{yyyy}`, or a `{step}` in
`base_data_dir`, fails at startup rather than silently creating a literal
directory of that name.
"""
function validate_date_placeholders(path::AbstractString, param_name::AbstractString;
                                    allow_step::Bool = false)
    allowed = allow_step ? (DATE_PLACEHOLDERS..., STEP_PLACEHOLDER) : DATE_PLACEHOLDERS
    for m in eachmatch(r"\{[^}]*\}", _canonical_placeholders(path))
        token = String(m.match)
        if !(token in allowed)
            hint = (!allow_step && token == STEP_PLACEHOLDER) ?
                " The {step} placeholder is only valid in base_archive_dir and base_plot_dir." : ""
            msg_error("Unrecognized date placeholder \"$token\" in $param_name = \"$path\". " *
                      "Valid placeholders are $(join(allowed, ", "))." * hint)
        end
    end
    return path
end

"""
    placeholder_resolution(template) → Symbol

The time organization unit of a base directory: the finest
[date placeholder](@ref DATE_PLACEHOLDERS) it contains. One of `:minute`,
`:hour`, `:day`, or `:none` when the template carries no date placeholder at all.

```julia
placeholder_resolution("/data/{YYYYMMDD}")        # :day
placeholder_resolution("/data/{YYYYMMDD}/{hh}")   # :hour
placeholder_resolution("/data/{YYYYMMDD_hhmm}")   # :minute
placeholder_resolution("/data/chivo")             # :none
```
"""
function placeholder_resolution(template::AbstractString)
    canonical = _canonical_placeholders(template)
    any(p -> occursin(p, canonical), MINUTE_PLACEHOLDERS) && return :minute
    any(p -> occursin(p, canonical), HOUR_PLACEHOLDERS) && return :hour
    any(p -> occursin(p, canonical), DAY_PLACEHOLDERS) && return :day
    return :none
end

"""
    unit_period(resolution::Symbol) → Dates.Period

The length of one directory of a `:day`, `:hour` or `:minute` layout.
"""
function unit_period(resolution::Symbol)
    resolution === :day && return Dates.Day(1)
    resolution === :hour && return Dates.Hour(1)
    resolution === :minute && return Dates.Minute(1)
    msg_error("No directory unit for resolution $(repr(resolution)); " *
              "expected :day, :hour or :minute.")
end

"""
    floor_to_unit(t::DateTime, resolution::Symbol) → DateTime

Start of the directory `t` falls in. `:none` returns `t` unchanged, since a flat
directory has no time boundaries.
"""
function floor_to_unit(t::DateTime, resolution::Symbol)
    resolution === :none && return t
    return floor(t, unit_period(resolution))
end

"""
    use_date_subdir(workflow) → Bool

Whether the output layout appends a `YYYYMMDD` directory level to base
directories that contain no date placeholder. Set by the optional workflow
parameter `date_subdir` (default `true`).
"""
function use_date_subdir(workflow::SparrowWorkflow)
    value = get_param(workflow, "date_subdir", true)
    value isa Bool || msg_error("date_subdir must be true or false, got $(repr(value)).")
    return value
end

# The appended `YYYYMMDD` directory level is always day-resolution.
_date_string(date::AbstractString) = String(date)
_date_string(date::DateTime) = Dates.format(date, "YYYYmmdd")
_date_string(date::Date) = Dates.format(date, "YYYYmmdd")

# Placeholder substitution uses the full time so {hh}/{mm} resolve. A date given
# as a string shorter than YYYYMMDDhhmm names the start of its window, so the
# missing hour/minute fields are zero.
_placeholder_date_string(date::DateTime) = Dates.format(date, "YYYYmmddHHMM")
_placeholder_date_string(date::Date) = Dates.format(date, "YYYYmmdd") * "0000"
function _placeholder_date_string(date::AbstractString)
    s = String(date)
    length(s) >= 12 && return s[1:12]
    length(s) >= 8 && return rpad(s, 12, '0')
    return s
end

"""
    dated_dir(base, date, date_subdir::Bool) → String

Resolve a base directory for `date` (a `DateTime`, or a date string of 8, 10 or
12 digits naming the start of a day, hour or minute):

- `base` contains a [date placeholder](@ref DATE_PLACEHOLDERS) → substitute it
  and append nothing, so the date can sit at any level of the path and the
  directory unit can be day, hour or minute.
- otherwise, `date_subdir = true` → `base/YYYYMMDD` (the default layout).
- otherwise, `date_subdir = false` → `base` itself, a flat directory.
"""
function dated_dir(base::AbstractString, date, date_subdir::Bool)
    has_date_placeholder(base) &&
        return substitute_date_placeholders(base, _placeholder_date_string(date))
    return date_subdir ? joinpath(base, _date_string(date)) : String(base)
end

"""
    step_dated_dir(base, step_name, date, date_subdir::Bool) → String

Per-step variant of [`dated_dir`](@ref), used for the archive and plot trees.
A [`{step}`](@ref STEP_PLACEHOLDER) token in `base` is replaced by the step name
wherever it sits; without one the step name is appended after the resolved base:
`base/<step>/YYYYMMDD` by default, `<substituted base>/<step>` when `base`
carries a date placeholder, and `base/<step>` when `date_subdir = false`.
"""
function step_dated_dir(base::AbstractString, step_name, date, date_subdir::Bool)
    step = String(step_name)
    if has_date_placeholder(base)
        resolved = substitute_date_placeholders(base, _placeholder_date_string(date))
        has_step_placeholder(resolved) && return replace(resolved, STEP_PLACEHOLDER => step)
        return joinpath(resolved, step)
    end
    if has_step_placeholder(base)
        resolved = replace(String(base), STEP_PLACEHOLDER => step)
        return date_subdir ? joinpath(resolved, _date_string(date)) : resolved
    end
    return date_subdir ? joinpath(base, step, _date_string(date)) : joinpath(base, step)
end

"""
    data_dir(workflow, date) → String

Input directory for `date`, resolved from `base_data_dir` by [`dated_dir`](@ref).
For remote data sources this is the local download cache, which follows the same
layout as a local input tree.
"""
data_dir(workflow::SparrowWorkflow, date) =
    dated_dir(workflow["base_data_dir"], date, use_date_subdir(workflow))

"""
    stable_root(base, param_name) → String

The part of a base directory that does not depend on the date: every path
component that contains no `{` placeholder, in order, or `base` itself when it
has none. Placeholder components are dropped rather than the path being cut at
the first one, so two trees that differ only below a placeholder keep distinct
roots and do not share processed-file markers.

```julia
stable_root("/archive/{YYYYMMDD}/chivo", "base_archive_dir")       # "/archive/chivo"
stable_root("/archive/{YYYYMMDD}/seapol", "base_archive_dir")      # "/archive/seapol"
stable_root("/archive/chivo/{YYYY}/{MM}", "base_archive_dir")      # "/archive/chivo"
stable_root("/archive/{step}/{YYYYMMDD}/{hh}", "base_archive_dir") # "/archive"
```

Errors if the first component is itself a placeholder, since the tree (and its
`.sparrow` markers) must be anchored under a literal directory the user chose.
"""
function stable_root(base::AbstractString, param_name::AbstractString)
    path = String(base)
    occursin('{', path) || return path
    parts = splitpath(path)
    first_literal = findfirst(part -> !(part in ("/", "", ".", "..", "\\")), parts)
    if first_literal === nothing || occursin('{', parts[first_literal])
        msg_error("$param_name = \"$path\" starts with a placeholder. The first " *
                  "directory level must be a literal path, so the processed-file " *
                  "markers have a stable root; write e.g. \"/archive/{YYYYMMDD}\".")
    end
    kept = filter(part -> !occursin('{', part), parts)
    return joinpath(kept...)
end

"""
    archive_root_dir(workflow) → String

Stable root of the archive tree: `base_archive_dir` with its placeholder
components removed (see [`stable_root`](@ref)), or `base_archive_dir` itself
when it has none. Independent of the date, so the hidden `.sparrow`
processed-marker directory that lives here is one per archive tree rather than
one per unit directory (see [`check_processed`](@ref)).
"""
archive_root_dir(workflow::SparrowWorkflow) =
    stable_root(workflow["base_archive_dir"], "base_archive_dir")

"""
    archive_step_dir(workflow, step_name, date) → String

Archive directory for one step's products at `date`, resolved from
`base_archive_dir` by [`step_dated_dir`](@ref). Pass the product's own time (see
[`_parse_filename_time`](@ref)) so an hour- or minute-resolution layout files
each product under the unit it belongs to.
"""
archive_step_dir(workflow::SparrowWorkflow, step_name, date) =
    step_dated_dir(workflow["base_archive_dir"], step_name, date, use_date_subdir(workflow))

"""
    plot_output_dir(workflow, step_name, start_time, fallback) → String

Destination directory for a plot step's figures, resolved from `base_plot_dir`
by [`step_dated_dir`](@ref) — `base_plot_dir/<step_name>/<date>` by default.
Falls back to the step's working `output_dir` (`fallback`) when `base_plot_dir`
is unset. Plot steps write here directly (and are declared `archive=false`),
since the archive machinery only routes archived output to `base_archive_dir`.
"""
function plot_output_dir(workflow::SparrowWorkflow, step_name, start_time, fallback)
    base = get_param(workflow, "base_plot_dir", nothing)
    base === nothing && return fallback
    return step_dated_dir(base, step_name, start_time, use_date_subdir(workflow))
end

"""
    plot_output_dir_for_file(workflow, step_name, file, start_time, fallback) → String

[`plot_output_dir`](@ref) keyed on the time embedded in `file`'s own name, so an
hour- or minute-resolution `base_plot_dir` files each figure under the unit its
input belongs to even when a chunk spans several. Falls back to `start_time`
(the chunk start) for a name with no recognizable timestamp.
"""
function plot_output_dir_for_file(workflow::SparrowWorkflow, step_name, file,
                                  start_time, fallback)
    file_time = something(_parse_filename_time(basename(String(file))), start_time)
    return plot_output_dir(workflow, step_name, file_time, fallback)
end

"""
    get_data_source(workflow::SparrowWorkflow) → DataSource

Get the data source for a workflow. If `data_source` is set in the workflow
parameters, return it. Otherwise, create a `LocalDirSource` from `base_data_dir`
honouring the workflow's `date_subdir` setting.
"""
function get_data_source(workflow::SparrowWorkflow)
    if haskey(workflow.params, "data_source")
        return workflow["data_source"]::DataSource
    else
        return LocalDirSource(workflow["base_data_dir"]; date_subdir=use_date_subdir(workflow))
    end
end

"""
    parse_span_seconds(span) → Int

Convert a span specification to a whole number of seconds. Accepts:

- `Integer`: seconds, passed through.
- `Dates.Period`: any fixed-length period, e.g. `Minute(5)` or `Hour(10)`.
- `AbstractString`: a number with an optional unit code — `"90"` or `"90S"`
  (seconds), `"5M"` (minutes), `"10H"` (hours), `"1D"` (days). Unit codes are
  case-insensitive.

Throws an error for anything else.
"""
parse_span_seconds(span::Integer) = Int(span)
parse_span_seconds(span::Dates.Period) = Dates.value(convert(Dates.Second, span))
function parse_span_seconds(span::AbstractString)
    m = match(r"^\s*(\d+)\s*([a-zA-Z]?)\s*$", span)
    if m === nothing
        error("Invalid span specification \"$span\". Use a number of seconds or " *
              "a number with a unit code: \"90S\" (seconds), \"5M\" (minutes), " *
              "\"10H\" (hours), \"1D\" (days).")
    end
    number = parse(Int, m.captures[1])
    unit = lowercase(m.captures[2])
    multiplier = unit == "" || unit == "s" ? 1 :
                 unit == "m" ? 60 :
                 unit == "h" ? 3600 :
                 unit == "d" ? 86400 :
                 error("Unknown span unit code \"$(m.captures[2])\" in \"$span\". " *
                       "Valid codes are S (seconds), M (minutes), H (hours), D (days).")
    return number * multiplier
end
parse_span_seconds(span) =
    error("Invalid span specification $span of type $(typeof(span)). " *
          "Use a number of seconds, a string like \"5M\", or a Dates.Period.")

"""
    resolve_span_seconds(workflow::SparrowWorkflow) → Int

Resolve the chunk-span (in seconds) used by [`process_workflow`](@ref) to slice
time ranges into successive processing windows.

Resolution order:
1. `span_seconds` if present in `workflow.params`, parsed with
   [`parse_span_seconds`](@ref) — so it may be given as seconds (`1200`),
   a string with a unit code (`"20S"`, `"5M"`, `"10H"`, `"1D"`), or a
   `Dates.Period` (`Minute(5)`). The parsed value is cached back into the
   workflow as an `Int`.
2. Deprecated `minute_span` if present: converted to seconds (×60), the
   workflow is mutated in place to drop `minute_span` and set `span_seconds`,
   and a one-time warning is emitted.
3. Default `600` (10 minutes), preserving the historical default.
"""
function resolve_span_seconds(workflow::SparrowWorkflow)
    if haskey(workflow.params, "span_seconds")
        seconds = parse_span_seconds(workflow["span_seconds"])
        seconds > 0 || error("span_seconds must be positive, got $seconds")
        workflow["span_seconds"] = seconds
        return seconds
    elseif haskey(workflow.params, "minute_span")
        seconds = (workflow["minute_span"]::Int) * 60
        msg_warning("Workflow parameter `minute_span` is deprecated; " *
                    "use `span_seconds = $(seconds)` instead.")
        workflow["span_seconds"] = seconds
        delete!(workflow.params, "minute_span")
        return seconds
    else
        return 600
    end
end

"""
Valid values for the `index_time` workflow parameter.
"""
const INDEX_TIME_OPTIONS = (:scan_start, :start_time, :stop_time)

"""
    resolve_index_time(workflow::SparrowWorkflow) → Symbol

Which `DateTime` the gridding steps write as the time coordinate of each gridded
product. One of:

- `:scan_start` (default): the start time of the scan itself, read from the input
  file. Correct for datasets with irregular scan timing, where an even increment
  is meaningless.
- `:start_time`: the start of the analysis increment (the processing window
  defined by `span_seconds`). Products then fall on a regular time increment.
- `:stop_time`: the end of the analysis increment, i.e. `start_time + span_seconds`.

The parameter may be given as a string or a `Symbol` and is matched
case-insensitively (`"start_time"`, `:start_time`, `"Start_Time"`). Anything else
throws.

This affects only the time coordinate written into the product. The output
*filename* always carries the per-scan time, so two scans landing in the same
analysis increment never overwrite each other.
"""
function resolve_index_time(workflow::SparrowWorkflow)
    value = get_param(workflow, "index_time", :scan_start)
    value isa Union{AbstractString,Symbol} || error(
        "Invalid index_time $(repr(value)) of type $(typeof(value)). " *
        "Valid options are: $(join(INDEX_TIME_OPTIONS, ", ")).")
    mode = Symbol(lowercase(String(value)))
    mode in INDEX_TIME_OPTIONS || error(
        "Invalid index_time $(repr(value)). " *
        "Valid options are: $(join(INDEX_TIME_OPTIONS, ", ")).")
    return mode
end

"""
    chunk_offsets(span_seconds::Int, num_seconds::Int; reverse::Bool=false) → StepRange

Return the start-second offsets for chunking a `num_seconds`-long window into
back-to-back chunks of `span_seconds`. If `reverse` is true, the offsets are
returned in reverse chronological order. If `span_seconds > num_seconds` the
range is empty.
"""
function chunk_offsets(span_seconds::Int, num_seconds::Int; reverse::Bool=false)
    offsets = 0:span_seconds:(num_seconds - span_seconds)
    return reverse ? Base.reverse(offsets) : offsets
end

"""
Human-readable list of the `datetime` formats accepted by
[`parse_datetime_string`](@ref), used in error messages.
"""
const DATETIME_FORMATS = "YYYY, YYYYMM, YYYYMMDD, YYYYMMDD_hh, YYYYMMDD_hhmm, YYYYMMDD_hhmmss"

"""
    parse_datetime_string(s) → (DateTime, Symbol)

Parse a `datetime` specification into the `DateTime` it starts at and a symbol
naming its precision. Exactly six formats are accepted:

| String            | Length | Kind      | DateTime returned      |
|-------------------|--------|-----------|------------------------|
| `YYYY`            | 4      | `:year`   | midnight, Jan 1        |
| `YYYYMM`          | 6      | `:month`  | midnight, 1st of month |
| `YYYYMMDD`        | 8      | `:day`    | midnight that day      |
| `YYYYMMDD_hh`     | 11     | `:hour`   | top of that hour       |
| `YYYYMMDD_hhmm`   | 13     | `:minute` | that minute            |
| `YYYYMMDD_hhmmss` | 15     | `:second` | that second            |

The returned `DateTime` is always the *start* of the window the string names; it
is never aligned or truncated to a `span_seconds` boundary. How much data each
kind covers is decided by [`process_workflow`](@ref).

Any other length, a non-digit where a digit is expected, or an out-of-range
field (month 13, hour 25, ...) raises an error listing the accepted formats.

A `DateTime` is passed through unchanged with kind `:second`, and a `Date`
becomes midnight that day with kind `:day`, so workflow parameters may be given
either as strings or as `Dates` values.
"""
function parse_datetime_string(s::AbstractString)
    str = String(s)
    n = ncodeunits(str)
    pattern, kind =
        n == 4  ? (r"^[0-9]{4}$", :year) :
        n == 6  ? (r"^[0-9]{6}$", :month) :
        n == 8  ? (r"^[0-9]{8}$", :day) :
        n == 11 ? (r"^[0-9]{8}_[0-9]{2}$", :hour) :
        n == 13 ? (r"^[0-9]{8}_[0-9]{4}$", :minute) :
        n == 15 ? (r"^[0-9]{8}_[0-9]{6}$", :second) :
        msg_error("Invalid datetime \"$str\" (length $n). " *
                  "Accepted formats are: $DATETIME_FORMATS.")
    occursin(pattern, str) || msg_error(
        "Invalid datetime \"$str\". Accepted formats are: $DATETIME_FORMATS.")

    year = parse(Int, str[1:4])
    month = kind === :year ? 1 : parse(Int, str[5:6])
    day = kind in (:year, :month) ? 1 : parse(Int, str[7:8])
    hour = kind in (:year, :month, :day) ? 0 : parse(Int, str[10:11])
    minute = kind in (:year, :month, :day, :hour) ? 0 : parse(Int, str[12:13])
    second = kind === :second ? parse(Int, str[14:15]) : 0

    datetime = try
        DateTime(year, month, day, hour, minute, second)
    catch e
        msg_error("Invalid datetime \"$str\": $(safe_exception_string(e)). " *
                  "Accepted formats are: $DATETIME_FORMATS.")
    end
    return datetime, kind
end
parse_datetime_string(datetime::DateTime) = (datetime, :second)
parse_datetime_string(date::Date) = (DateTime(date), :day)
parse_datetime_string(datetime) =
    msg_error("Invalid datetime $(repr(datetime)) of type $(typeof(datetime)). " *
              "Use a DateTime or a string in one of: $DATETIME_FORMATS.")

"""
    time_window_chunks(start_time::DateTime, stop_time::DateTime, span_seconds::Integer;
                       reverse::Bool=false) → Vector{Tuple{DateTime,DateTime}}

Split the half-open interval `[start_time, stop_time)` into back-to-back chunks
of `span_seconds`. Unlike [`chunk_offsets`](@ref), a trailing partial chunk is
*clipped* to `stop_time` rather than dropped, so the whole requested window is
always covered. Chunks are also split at midnight, because each volume reads
its input from a single day directory; a chunk that would cross midnight ends
at 00:00 and the next chunk starts there. Returns an empty vector when
`stop_time <= start_time`, and the chunks in reverse chronological order when
`reverse` is true.

# Example
```julia
julia> time_window_chunks(DateTime(2024,1,1,14), DateTime(2024,1,1,14,25), 600)
3-element Vector{Tuple{DateTime, DateTime}}:
 (DateTime("2024-01-01T14:00:00"), DateTime("2024-01-01T14:10:00"))
 (DateTime("2024-01-01T14:10:00"), DateTime("2024-01-01T14:20:00"))
 (DateTime("2024-01-01T14:20:00"), DateTime("2024-01-01T14:25:00"))
```
"""
function time_window_chunks(start_time::DateTime, stop_time::DateTime,
                            span_seconds::Integer; reverse::Bool=false)
    span = Int(span_seconds)
    span > 0 || msg_error("span_seconds must be positive, got $span")
    chunks = Tuple{DateTime,DateTime}[]
    stop_time > start_time || return chunks
    chunk_start = start_time
    while chunk_start < stop_time
        next_midnight = DateTime(Dates.Date(chunk_start)) + Dates.Day(1)
        chunk_stop = min(chunk_start + Dates.Second(span), stop_time, next_midnight)
        push!(chunks, (chunk_start, chunk_stop))
        chunk_start = chunk_stop
    end
    return reverse ? Base.reverse(chunks) : chunks
end

"""
    resolve_time_window(workflow::SparrowWorkflow) → Union{Nothing,Tuple{DateTime,DateTime}}

Return the explicit processing period set by the `start_time` and `stop_time`
workflow parameters (or the `--start`/`--stop` command-line options), or
`nothing` when the workflow is driven by `datetime` instead.

Both parameters must be given together, each may be a `DateTime` or any string
accepted by [`parse_datetime_string`](@ref), and `stop_time` must be after
`start_time`. The window is half-open: `[start_time, stop_time)`.
"""
function resolve_time_window(workflow::SparrowWorkflow)
    has_start = haskey(workflow.params, "start_time")
    has_stop = haskey(workflow.params, "stop_time")
    if has_start != has_stop
        missing_key = has_start ? "stop_time" : "start_time"
        msg_error("Workflow parameter `$missing_key` is missing. " *
                  "`start_time` and `stop_time` must be set together.")
    end
    has_start || return nothing

    start_time, _ = parse_datetime_string(workflow["start_time"])
    stop_time, _ = parse_datetime_string(workflow["stop_time"])
    stop_time > start_time || msg_error(
        "stop_time ($(Dates.format(stop_time, "YYYYmmdd_HHMMSS"))) must be after " *
        "start_time ($(Dates.format(start_time, "YYYYmmdd_HHMMSS"))).")
    return (start_time, stop_time)
end

"""
    set_window_datetime(workflow::SparrowWorkflow) → String

Set `workflow["datetime"]` to the start of the workflow's `start_time`/`stop_time`
window, formatted as `YYYYMMDD_hhmmss`, and log the window.

The `datetime` parameter is kept in sync so log and directory names stay
sensible, but [`process_workflow`](@ref) always prefers the explicit window.
"""
function set_window_datetime(workflow::SparrowWorkflow)
    start_time = workflow["start_time"]::DateTime
    stop_time = workflow["stop_time"]::DateTime
    workflow["datetime"] = Dates.format(start_time, "YYYYmmdd_HHMMSS")
    msg_info("Running in archive mode from $(Dates.format(start_time, "YYYYmmdd_HHMMSS")) " *
             "to $(Dates.format(stop_time, "YYYYmmdd_HHMMSS"))")
    return workflow["datetime"]
end

"""
    @workflow_type Name

Create a new workflow type that inherits from [`SparrowWorkflow`](@ref).

This macro generates:
1. A struct with a `params::Dict{String,Any}` field
2. A keyword constructor that converts kwargs to String-keyed Dict

# Example
```julia
@workflow_type MyWorkflow

workflow = MyWorkflow(
    base_working_dir = "/tmp/work",
    base_archive_dir = "/data/archive",
    base_data_dir = "/data/raw",
    steps = [
        "qc" => QCStep,
        "grid" => GridStep
    ]
)
```

# Expands to
```julia
struct MyWorkflow <: SparrowWorkflow
    params::Dict{String,Any}
end

MyWorkflow(; kwargs...) = MyWorkflow(Dict{String,Any}(string(k) => v for (k, v) in kwargs))
```

# See Also
- [`@workflow_types`](@ref)
- [`@workflow_step`](@ref)
"""
macro workflow_type(name)
    if isdefined(__module__, name)
        return nothing
    end
    return quote
        struct $(esc(name)) <: SparrowWorkflow
            params::Dict{String,Any}
        end

        $(esc(name))(; kwargs...) = $(esc(name))(Dict{String,Any}(string(k) => v for (k, v) in kwargs))
    end
end

"""
    @workflow_types Name1 Name2 Name3...

Define multiple workflow types at once.

Equivalent to calling [`@workflow_type`](@ref) for each type individually.

# Example
```julia
@workflow_types RadarQC RadarGrid RadarMerge
```

# See Also
- [`@workflow_type`](@ref)
"""
macro workflow_types(names...)
    exprs = []
    for name in names
        if !isdefined(__module__, name)
            push!(exprs, quote
                struct $(esc(name)) <: SparrowWorkflow
                    params::Dict{String,Any}
                end
                $(esc(name))(; kwargs...) = $(esc(name))(Dict{String,Any}(string(k) => v for (k, v) in kwargs))
            end)
        end
    end
    return Expr(:block, exprs...)
end

"""
    @workflow_step Name

Define a workflow step type for dispatch.

Step types are empty structs used for type-based dispatch in [`workflow_step`](@ref)
function implementations.

# Example
```julia
@workflow_step ConvertData

function Sparrow.workflow_step(workflow::MyWorkflow, ::Type{ConvertData},
                               input_dir::String, output_dir::String;
                               kwargs...)
    # Implementation
end
```

# Expands to
```julia
struct ConvertData end
```

# See Also
- [`@workflow_type`](@ref)
- [`workflow_step`](@ref)
"""
macro workflow_step(name)
    if isdefined(__module__, name)
        return nothing
    end
    return quote
        struct $(esc(name)) end
    end
end

"""
    run_workflow(workflow::SparrowWorkflow, parsed_args) → Bool

Execute a complete workflow from start to finish.

This is the main entry point for executing workflows. It sets up workflow parameters,
assigns workers for distributed processing, and processes the workflow across the
specified time range.

# Arguments
- `workflow`: A workflow instance created with [`@workflow_type`](@ref)
- `parsed_args`: Parsed command-line arguments (Dict with keys like "start", "end", "nworkers", etc.)

# Returns
- `true` if workflow completed successfully, `false` otherwise

# Description
The function performs these steps:
1. Sets up workflow parameters from command-line arguments
2. Assigns workers for distributed processing (if workers available)
3. Processes the workflow across the specified time range
4. Handles errors and cleanup

# Called By
The `main` function in the Sparrow module (automatically when using the `sparrow` script)

# See Also
- [`assign_workers`](@ref)
- [`process_workflow`](@ref)
"""
function run_workflow(workflow::SparrowWorkflow, parsed_args)

    # Override the log_prefix if provided in the arguments, otherwise use a default based on the workflow type and current time
    log_prefix = "$(typeof(workflow))_$(Dates.format(now(UTC), "YYYYmmdd_HHMMSS"))"
    if parsed_args["log_prefix"] != "default"
        log_prefix = parsed_args["log_prefix"]
    end

    # Set all the parameters from the provided workflow file or command line arguments
    setup_workflow_params(workflow, parsed_args)

    # Save the original stdout/stderr before redirection
    original_stdout = stdout
    original_stderr = stderr

    # Set up the log files and redirect the output
    outfile = log_prefix * ".log"
    msg_info("Redirecting workflow output to $outfile...")
    out = open(outfile, "w")
    redirect_stdout(out)
    redirect_stderr(out)

    # Redirect the output on each worker process to a separate log file if more than one worker
    num_workers = length(workers())
    if num_workers > 1
        for i in 1:num_workers
            local outfile = log_prefix * "_worker_$(i).log"
            wait(save_at(workers()[i], :out, :(open($(outfile), "w"))))
            wait(get_from(workers()[i], :(redirect_stdout(out))))
            wait(get_from(workers()[i], :(redirect_stderr(out))))
        end
    else
        wait(save_at(workers()[1], :out, :(open($(outfile), "w"))))
        wait(get_from(workers()[1], :(redirect_stdout(out))))
        wait(get_from(workers()[1], :(redirect_stderr(out))))
    end

    # Run the main processing loop
    status = assign_workers(workflow)

    # Close the output files
    close(out)
    for i in 1:num_workers
        wait(get_from(workers()[i], :(close(out))))
    end

    # Restore original stdout/stderr
    redirect_stdout(original_stdout)
    redirect_stderr(original_stderr)

    return status
end

"""
    setup_workflow_params(workflow::SparrowWorkflow, parsed_args)

Internal function to set up workflow parameters from command-line arguments.

Merges command-line arguments into the workflow's parameter dictionary.

The processing period is resolved from the first of these that is present:

1. `--datetime` on the command line (anything other than the default `"now"`).
   Any `datetime` or `start_time`/`stop_time` in the workflow file is overridden
   and the window pair is removed from the parameters.
2. `--start`/`--stop` on the command line. Both must be given together; a
   `datetime` in the workflow file is ignored.
3. `start_time`/`stop_time` in the workflow file. Both must be given together,
   and the workflow file may not also set `datetime`.
4. `datetime` in the workflow file.
5. `"now"`, i.e. the current time.

Realtime mode accepts none of these and errors if any is supplied. When a
start/stop window is active, `workflow["datetime"]` is set to the start of the
window formatted as `YYYYMMDD_hhmmss` so log names stay sensible, but
[`process_workflow`](@ref) processes the whole window.

# See Also
- [`resolve_time_window`](@ref)
- [`parse_datetime_string`](@ref)
- [`process_workflow`](@ref)
"""
function setup_workflow_params(workflow::SparrowWorkflow, parsed_args)
    # This function can be used to set up any workflow specific parameters or directories before processing starts

    # Store type name and params in the workflow dict for workers to reconstruct
    workflow_type_name = typeof(workflow).name.name
    workflow["workflow_type_name"] = String(workflow_type_name)
    num_workers = length(workers())
    workflow["num_workers"] = num_workers

    cli_datetime = parsed_args["datetime"]
    cli_start = get(parsed_args, "start", "none")
    cli_stop = get(parsed_args, "stop", "none")
    has_cli_datetime = cli_datetime != "now"
    has_cli_start = cli_start != "none"
    has_cli_stop = cli_stop != "none"
    has_config_datetime = haskey(workflow.params, "datetime")
    has_config_start = haskey(workflow.params, "start_time")
    has_config_stop = haskey(workflow.params, "stop_time")
    realtime = (haskey(workflow.params, "realtime") && workflow["realtime"]) || parsed_args["realtime"]

    if realtime && has_cli_datetime
        msg_error("Cannot specify a datetime when running in realtime mode. Please remove the --datetime argument or remove the --realtime flag.")
    end
    if realtime && (has_cli_start || has_cli_stop)
        msg_error("Cannot specify --start/--stop when running in realtime mode. Please remove the --start and --stop arguments or remove the --realtime flag.")
    end
    if realtime && (has_config_start || has_config_stop)
        msg_error("Cannot set start_time/stop_time in the workflow file when running in realtime mode. Please remove those parameters or turn off realtime mode.")
    end
    if has_cli_datetime && (has_cli_start || has_cli_stop)
        msg_error("Cannot combine --datetime with --start/--stop. Please supply either a single --datetime or a --start/--stop pair.")
    end
    if has_cli_start != has_cli_stop
        msg_error("Both --start and --stop must be given ($(has_cli_start ? "--stop" : "--start") is missing). " *
                  "Accepted formats are: $DATETIME_FORMATS.")
    end

    if realtime
        msg_info("Running in realtime mode")
        workflow["realtime"] = true
        workflow["datetime"] = "now"
    else
        workflow["realtime"] = false

        if has_cli_datetime
            # 1. An explicit --datetime wins over anything in the workflow file.
            if has_config_datetime
                msg_info("Overriding datetime in workflow file with $cli_datetime datetime provided in arguments")
            end
            if has_config_start || has_config_stop
                msg_info("Overriding start_time/stop_time in workflow file with $cli_datetime datetime provided in arguments")
                delete!(workflow.params, "start_time")
                delete!(workflow.params, "stop_time")
            end
            # Fix if user mistakenly put "SEA" in front of the datetime
            workflow["datetime"] = startswith(cli_datetime, "SEA") ? cli_datetime[4:end] : cli_datetime
            # Fail on a malformed datetime here rather than later on a worker
            parse_datetime_string(workflow["datetime"])
            msg_info("Running in archive mode on $(workflow["datetime"])")

        elseif has_cli_start
            # 2. An explicit --start/--stop pair wins over anything in the workflow file.
            if has_config_datetime
                msg_info("Ignoring datetime in workflow file in favor of the --start/--stop window provided in arguments")
            end
            if has_config_start || has_config_stop
                msg_info("Overriding start_time/stop_time in workflow file with the window provided in arguments")
            end
            workflow["start_time"] = cli_start
            workflow["stop_time"] = cli_stop
            # Parses both ends and validates that the window runs forwards
            start_time, stop_time = resolve_time_window(workflow)
            workflow["start_time"] = start_time
            workflow["stop_time"] = stop_time
            set_window_datetime(workflow)

        elseif has_config_start || has_config_stop
            # 3. A start_time/stop_time pair in the workflow file.
            if has_config_datetime
                msg_error("The workflow file sets both datetime and start_time/stop_time, which is ambiguous. " *
                          "Keep one of them, or override them on the command line with --datetime or --start/--stop.")
            end
            # resolve_time_window errors if only one of the two is present.
            start_time, stop_time = resolve_time_window(workflow)
            workflow["start_time"] = start_time
            workflow["stop_time"] = stop_time
            set_window_datetime(workflow)

        elseif has_config_datetime
            # 4. A datetime in the workflow file (not clobbered by the "now" default).
            config_datetime = workflow["datetime"]
            if config_datetime isa Date
                # A Date means the whole day, so keep the 8-digit form
                config_datetime = Dates.format(config_datetime, "YYYYmmdd")
            elseif !(config_datetime isa AbstractString)
                config_datetime = Dates.format(first(parse_datetime_string(config_datetime)),
                                               "YYYYmmdd_HHMMSS")
            end
            # Fix if user mistakenly put "SEA" in front of the datetime
            workflow["datetime"] = startswith(config_datetime, "SEA") ? config_datetime[4:end] : config_datetime
            # Fail on a malformed datetime here rather than later on a worker
            workflow["datetime"] == "now" || parse_datetime_string(workflow["datetime"])
            msg_info("Running in archive mode on $(workflow["datetime"])")

        else
            # 5. Nothing specified anywhere: process the current time.
            workflow["datetime"] = "now"
            msg_info("Running in archive mode on now")
        end
    end

    if parsed_args["force_reprocess"]
        workflow["force_reprocess"] = parsed_args["force_reprocess"]
    else
        workflow["force_reprocess"] = get_param(workflow, "force_reprocess", false)
    end

    # Build the Daisho parameters once on the main process so the TOML is
    # validated before any workers start; the struct is plain data and ships
    # to the workers with the rest of the workflow params. Workflows without
    # gridding steps don't need a daisho_config at all.
    if haskey(workflow.params, "daisho_config")
        workflow["daisho_params"] = DaishoParameters(workflow["daisho_config"])
    end

    # Validate the output directory layout on the main process so a mistyped
    # placeholder or a non-Bool date_subdir fails at startup rather than creating
    # a literal "{yyyy}" directory hours into a run.
    for key in ("base_data_dir", "base_archive_dir", "base_plot_dir")
        haskey(workflow.params, key) || continue
        value = workflow.params[key]
        value isa AbstractString || continue
        # {step} names the level the step directory goes at, so it only makes
        # sense in the two output trees; base_data_dir has no step.
        validate_date_placeholders(value, key; allow_step = key != "base_data_dir")
    end
    # The archive tree needs a literal leading directory to anchor the .sparrow
    # processed-marker directory to, whatever placeholders follow it.
    if haskey(workflow.params, "base_archive_dir") &&
       workflow.params["base_archive_dir"] isa AbstractString
        stable_root(workflow.params["base_archive_dir"], "base_archive_dir")
    end
    # The working tree layout is fixed, so placeholders there would only ever
    # produce a literal "{YYYYMMDD}" directory.
    if haskey(workflow.params, "base_working_dir") &&
       workflow.params["base_working_dir"] isa AbstractString &&
       occursin(r"\{[^}]*\}", workflow.params["base_working_dir"])
        msg_error("Date placeholders are not supported in base_working_dir " *
                  "(got \"$(workflow.params["base_working_dir"])\"); the working tree " *
                  "is always laid out as base_working_dir/<random>/<step>/YYYYMMDD.")
    end
    use_date_subdir(workflow)

    # Validate on the main process so a typo fails at startup rather than hours
    # later on a worker part-way through a gridding step.
    resolve_index_time(workflow)

    return workflow
end

"""
    apply_paths_file!(workflow::SparrowWorkflow, path::AbstractString) → SparrowWorkflow

Override a workflow's directory parameters from a separate "paths file", so the
same workflow file can run unmodified on different machines (e.g. a shared
workflow checked into version control, with per-machine paths kept out of it).

The file at `path` is a plain Julia script that assigns some or all of the five
recognized variables as top-level globals:

- `base_data_dir`
- `base_working_dir`
- `base_archive_dir`
- `base_plot_dir`
- `date_subdir`

Each one that the file defines overrides the matching key in `workflow`; any it
leaves undefined is untouched, and any other global the file defines (e.g. a
site-specific `qc_base`) is ignored. The file is `include`d into a fresh,
disposable module rather than into `Sparrow` itself, so calling this more than
once (as tests do) never collides with a previous call and stray globals never
leak into the package.

# Throws
- If `path` does not exist.
- If the file defines none of the five recognized variables.

# See Also
- [`setup_workflow_params`](@ref)
"""
function apply_paths_file!(workflow::SparrowWorkflow, path::AbstractString)
    isfile(path) || msg_error("Paths file $path does not exist.")

    # A fresh module per call: repeated calls (e.g. in tests) never collide,
    # and the file's globals never leak into the Sparrow module itself.
    m = Module(:SparrowPathsFile)
    Base.include(m, path)

    recognized_keys = ("base_data_dir", "base_working_dir", "base_archive_dir",
                        "base_plot_dir", "date_subdir")
    overridden = String[]
    for key in recognized_keys
        sym = Symbol(key)
        if Base.invokelatest(isdefined, m, sym)
            workflow[key] = Base.invokelatest(getfield, m, sym)
            push!(overridden, key)
        end
    end

    if isempty(overridden)
        msg_error("Paths file $path does not define any of the recognized variables: " *
                   join(recognized_keys, ", ") * ". Other variables are ignored.")
    end

    msg_info("Overriding workflow parameters from paths file $path: $(join(overridden, ", "))")

    return workflow
end

# Main function to process radar data
"""
    poll_directory(raw_dir::String) → Vector{String}

Read a directory and return files (not directories or hidden files), newest first.
Returns basenames. Wrapped in try/catch for NFS resilience.
"""
function poll_directory(raw_dir::String)
    try
        entries = readdir(raw_dir)
        filter!(entries) do name
            fullpath = joinpath(raw_dir, name)
            !isdir(fullpath) && !startswith(name, ".")
        end
        return reverse(entries)
    catch e
        msg_warning("Error reading directory $raw_dir: $e")
        return String[]
    end
end

"""
    check_and_fetch_task!(tasks, filequeue, t, workflow, archive_dir) → Symbol

Check the status of task slot `t`. Returns:
- `:open` — slot is unassigned or idle
- `:running` — task is still running
- `:ready` — task future is ready (completed or errored), slot cleared
- `:processed` — file shows as processed in archive, slot cleared
"""
function check_and_fetch_task!(tasks, filequeue, t, workflow, archive_dir)
    if !isassigned(tasks, t) || filequeue[t] == "none"
        return :open
    end

    # Non-blocking check if the task future is ready
    if isready(tasks[t])
        try
            status = fetch(tasks[t])
            msg_info("Task $t completed: $status at $(now(UTC))")
        catch e
            msg_warning("Task $t errored: $e at $(now(UTC))")
        end
        flush(stdout)
        filequeue[t] = "none"
        return :ready
    end

    # Check if the file shows as processed in the archive
    if check_processed(workflow, filequeue[t], archive_dir)
        msg_info("Clearing finished task $t at $(now(UTC))")
        try
            status = fetch(tasks[t])
            msg_info("Task $t $status at $(now(UTC))")
        catch e
            msg_warning("Error fetching task $t: $e at $(now(UTC))")
        end
        flush(stdout)
        filequeue[t] = "none"
        return :processed
    end

    return :running
end

"""
    assign_to_slot!(tasks, filequeue, t, file, workflow) → Nothing

Assign `file` to task slot `t` and start processing on the corresponding worker.
"""
function assign_to_slot!(tasks, filequeue, t, file, workflow)
    filequeue[t] = file
    tasks[t] = get_from(workers()[t], :(process_workflow($(workflow))))
    msg_info("$file assigned to task slot $t at $(now(UTC))")
    flush(stdout)
    return nothing
end

"""
    find_open_slot!(tasks, filequeue, file, workflow, archive_dir) → Int

Scan all task slots, clearing finished ones via `check_and_fetch_task!`.
If an open slot is found, assign the file and return the slot index.
Returns -1 if no slot is available.
"""
function find_open_slot!(tasks, filequeue, file, workflow, archive_dir)
    for t in 1:length(tasks)
        slot_status = check_and_fetch_task!(tasks, filequeue, t, workflow, archive_dir)
        if slot_status != :running
            assign_to_slot!(tasks, filequeue, t, file, workflow)
            return t
        end
    end
    return -1
end

"""
    wait_for_slot!(tasks, filequeue, file, workflow, archive_dir, timeout) → Int

Block with `sleep(1)` polling until a task slot opens or `timeout` seconds elapse.
Logs progress every 60 seconds. Returns slot index or -1 on timeout.
"""
function wait_for_slot!(tasks, filequeue, file, workflow, archive_dir, timeout)
    msg_info("Queue full, waiting to schedule $file")
    flush(stdout)
    waiting_time = 0
    while waiting_time < timeout
        if waiting_time % 60 == 0
            msg_info("Waited $waiting_time seconds for a slot...")
            flush(stdout)
        end
        for t in 1:length(tasks)
            slot_status = check_and_fetch_task!(tasks, filequeue, t, workflow, archive_dir)
            if slot_status != :running
                assign_to_slot!(tasks, filequeue, t, file, workflow)
                msg_info("Task slot $t opened up for $file at $(now(UTC))")
                return t
            end
        end
        sleep(1)
        waiting_time += 1
    end
    return -1
end

"""
    clear_finished_tasks!(tasks, filequeue, workflow, archive_dir) → Int

End-of-cycle cleanup: check all slots and clear any that have finished.
Returns the number of slots cleared.
"""
function clear_finished_tasks!(tasks, filequeue, workflow, archive_dir)
    cleared = 0
    for t in 1:length(tasks)
        status = check_and_fetch_task!(tasks, filequeue, t, workflow, archive_dir)
        if status in (:ready, :processed)
            cleared += 1
        end
    end
    return cleared
end

"""
    assign_workers(workflow::SparrowWorkflow)

Distribute files across available workers for parallel processing.

Creates a file queue and distributes processing tasks across all available workers.
Files are organized by time windows and assigned to workers as they become available.

# Arguments
- `workflow`: Workflow instance with configured parameters

# Prerequisites
- Workers must be initialized (via `addprocs` or cluster manager)
- Workflow must be loaded on all workers

# Configurable Parameters (via workflow)
- `poll_interval` (default 5): Seconds between polling cycles
- `queue_timeout` (default 600): Max seconds to wait for a queue slot
- `retry_on_failure` (default false): If true, requeue timed-out files

# See Also
- [`process_workflow`](@ref)
- [`run_workflow`](@ref)
"""
function assign_workers(workflow::SparrowWorkflow)

    msg_info("Processing data with $(typeof(workflow))...")

    # Process a time period of radar data
    if !workflow["realtime"]
        try
            wait(get_from(workers()[1], :(process_workflow($(workflow)))))
        catch e
            msg_warning("Error processing workflow: $(safe_exception_string(e))")
            flush(stdout)
            return false
        end
    else
        # Configurable parameters with backward-compatible defaults
        poll_interval = get_param(workflow, "poll_interval", 5)
        queue_timeout = get_param(workflow, "queue_timeout", 600)
        retry_on_failure = get_param(workflow, "retry_on_failure", false)

        # Get data source (LocalDirSource if not explicitly set)
        source = get_data_source(workflow)
        # One chunk's worth of history, so a file that lands just after a unit
        # boundary is still found in the directory it was written to.
        span_seconds = resolve_span_seconds(workflow)

        # The processed-marker directory sits at the stable archive root, which
        # does not depend on the date, so resolve it once for the whole run.
        base_archive_dir = archive_root_dir(workflow)

        msg_info("Watching for real time data...")
        flush(stdout)

        num_workers = length(workers())
        tasks = Array{Distributed.Future}(undef, num_workers)
        filequeue = fill("none", num_workers)
        retry_queue = String[]

        while true
            try
                poll_stop = now(UTC)
                poll_start = poll_stop - Dates.Second(span_seconds)
                radar_date = Dates.format(poll_stop, "YYYYmmdd")

                # Get files to process: retry queue first, then new files
                files_to_process = String[]
                if retry_on_failure && !isempty(retry_queue)
                    append!(files_to_process, retry_queue)
                    empty!(retry_queue)
                end

                if is_remote(source)
                    # Remote sources own their own layout; discovery stays day-based
                    new_files = [basename(f) for f in discover_files(source, radar_date)]
                else
                    # Poll the current unit directory plus any earlier one the last
                    # span still reaches into: at day resolution that is today, plus
                    # yesterday for one span after midnight; at hour or minute
                    # resolution the current unit plus the previous one near the
                    # boundary. Unit directories that do not exist yet are skipped
                    # quietly, and only the default base/YYYYMMDD (or flat) layout
                    # has its directory created, as before; placeholder layouts are
                    # left to the data writer so no empty hour/minute dirs are made.
                    if !has_date_placeholder(source.base_dir)
                        mkpath(_local_dir(source, poll_stop))
                    end
                    new_files = String[]
                    for raw_dir in unit_dirs(source, poll_start, poll_stop)
                        isdir(raw_dir) || continue
                        append!(new_files, poll_directory(raw_dir))
                    end
                    # Files are keyed by basename downstream, so de-duplicate
                    unique!(new_files)
                    # A flat directory also holds earlier days' files, which have
                    # no markers for the current window; only queue files from the
                    # day the look-back starts in onwards.
                    if _is_flat(source)
                        new_files = _filter_names_by_window(new_files,
                                                            DateTime(Dates.Date(poll_start)),
                                                            DateTime(2100))
                    end
                end
                append!(files_to_process, new_files)

                msg_trace("Checking for new data at $(now(UTC))...")

                for file in files_to_process
                    # Skip hidden files, already processed, or already queued
                    if startswith(file, ".")
                        continue
                    end
                    if check_processed(workflow, file, base_archive_dir)
                        msg_trace("$file already processed, skipping...")
                        continue
                    end
                    if file in filequeue
                        msg_trace("$file is in the queue, skipping...")
                        continue
                    end

                    msg_debug("New file detected: $file")
                    msg_debug("Current queue: $filequeue")
                    flush(stdout)

                    # Try to find an open slot
                    slot = find_open_slot!(tasks, filequeue, file, workflow, base_archive_dir)
                    if slot == -1
                        # All slots busy — wait for one to open
                        slot = wait_for_slot!(tasks, filequeue, file, workflow, base_archive_dir, queue_timeout)
                        if slot == -1
                            if retry_on_failure
                                push!(retry_queue, file)
                                msg_warning("No slots opened in $(queue_timeout)s, requeueing $file")
                            else
                                msg_warning("No slots opened in $(queue_timeout)s! Skipping $file")
                            end
                        end
                    end
                end

                # End-of-cycle cleanup
                clear_finished_tasks!(tasks, filequeue, workflow, base_archive_dir)

            catch e
                msg_warning("Error in realtime polling loop: $e")
                flush(stdout)
            end

            sleep(poll_interval)
        end
    end

    return true
end

"""
    process_workflow(workflow::SparrowWorkflow) → Bool

Process a workflow with the main process (non-distributed).

This function processes the entire workflow sequentially on the main process.
Used when running without distributed workers.

# Arguments
- `workflow`: Workflow instance

# Returns
- `true` if processing succeeded, `false` otherwise

# Description
Processes all time windows and workflow steps sequentially without using
distributed workers. Useful for debugging or when parallelization is not needed.

The processing period comes from either an explicit `start_time`/`stop_time`
window or the `datetime` workflow parameter.

## `start_time` / `stop_time`

If both are set (in the workflow file, or via `--start`/`--stop`), the half-open
window `[start_time, stop_time)` is split into `span_seconds` chunks. The final
chunk is clipped to `stop_time` rather than dropped, so the whole window is
covered, and chunks are split at midnight so each volume reads a single day
directory. Days with no data are skipped.

## `datetime`

`datetime` is always the *start* of the window and is never aligned or truncated
to a `span_seconds` boundary. Its length selects how much is processed:

| `datetime`        | Window processed                                        |
|-------------------|---------------------------------------------------------|
| `YYYY`            | the whole year, chunked by `span_seconds`               |
| `YYYYMM`          | the whole month, chunked by `span_seconds`              |
| `YYYYMMDD`        | that whole day, chunked by `span_seconds`               |
| `YYYYMMDD_hh`     | that whole hour, chunked by `span_seconds`              |
| `YYYYMMDD_hhmm`   | one window, `[that minute, that minute + span_seconds)` |
| `YYYYMMDD_hhmmss` | one window, `[that second, that second + span_seconds)` |

Any other length raises an error listing the accepted formats.

Year, month, day and hour runs are chunked from the start of the year, month,
day or hour. If `span_seconds` does not divide the range evenly the trailing
partial chunk is *not* processed (a warning is emitted); use
`start_time`/`stop_time` to process a partial window instead.

The chunk length is `span_seconds`, resolved via [`resolve_span_seconds`](@ref).
Set `reverse = true` to walk the chunks in reverse chronological order; `reverse`
is optional and defaults to `false`.

# See Also
- [`assign_workers`](@ref)
- [`run_workflow`](@ref)
- [`resolve_span_seconds`](@ref)
- [`resolve_time_window`](@ref)
- [`parse_datetime_string`](@ref)
- [`time_window_chunks`](@ref)
- [`chunk_offsets`](@ref)
"""
function process_workflow(workflow::SparrowWorkflow)

    # Set the local variables from the workflow
    span_seconds = resolve_span_seconds(workflow)
    force_reprocess = workflow["force_reprocess"]
    reverse_order = get_param(workflow, "reverse", false)
    # When false (default), any volume that errors aborts the whole batch. Set
    # `skip_failed_volumes = true` in the workflow to log and continue instead.
    skip_failed_volumes = get_param(workflow, "skip_failed_volumes", false)

    # Get data source for checking data availability
    source = get_data_source(workflow)

    # The processed-file markers live at the stable archive root, which does not
    # depend on the date or on the archive tree's directory unit, so resolve once.
    marker_dir = archive_root_dir(workflow)

    # Count of volumes skipped due to errors (only when skip_failed_volumes)
    skipped = 0

    # Helper to process a single chunk. The markers are written as soon as the
    # volume finishes archiving, so a crash partway through a batch leaves
    # completed volumes marked and skippable on restart.
    function process_chunk(start_time::DateTime, stop_time::DateTime)
        msg_info("Processing $(Dates.format(start_time, "YYYYmmdd_HHMMSS"))...")
        try
            processed, archived = process_volume(workflow, start_time, stop_time)
            mark_processed(workflow, processed, marker_dir)
            mark_processed(workflow, archived, marker_dir)
        catch e
            skip_failed_volumes || rethrow()
            skipped += 1
            msg_warning("Skipping volume $(Dates.format(start_time, "YYYYmmdd_HHMMSS")): " *
                        safe_exception_string(e))
            flush(stdout)
        end
    end

    # Warn once per run if span_seconds does not tile the fixed-length ranges
    # (day, hour) evenly, since the trailing partial chunk is not processed.
    partial_warned = false
    function warn_partial_chunks(num_seconds::Int)
        partial_warned && return nothing
        if span_seconds > num_seconds
            partial_warned = true
            msg_warning("span_seconds ($(span_seconds)s) is longer than the $(num_seconds)s " *
                        "range selected by datetime, so nothing will be processed. " *
                        "Use start_time/stop_time to process a window of arbitrary length.")
        elseif num_seconds % span_seconds != 0
            partial_warned = true
            msg_warning("span_seconds ($(span_seconds)s) does not divide the $(num_seconds)s " *
                        "range selected by datetime evenly; the trailing " *
                        "$(num_seconds % span_seconds)s will not be processed. " *
                        "Use start_time/stop_time to process the remainder.")
        end
        return nothing
    end

    # Helper to process all span_seconds chunks within a single day.
    function process_day_chunks(day_dt::DateTime;
                                hour_offset::Int=0, num_seconds::Int=86400)
        warn_partial_chunks(num_seconds)
        timerange = chunk_offsets(span_seconds, num_seconds; reverse=reverse_order)
        for t in timerange
            start_time = day_dt + Dates.Hour(hour_offset) + Dates.Second(t)
            stop_time = start_time + Dates.Second(span_seconds)
            process_chunk(start_time, stop_time)
        end
    end

    # Helper to iterate over a range of days, skipping those without data
    function process_day_range(first_day::DateTime, dayrange)
        ordered = reverse_order ? Base.reverse(dayrange) : dayrange
        for d in ordered
            day_dt = first_day + Dates.Day(d)
            if !has_data(source, Dates.format(day_dt, "YYYYmmdd"))
                msg_info("No data for $(Dates.format(day_dt, "YYYYmmdd")), skipping...")
                flush(stdout)
                continue
            end
            process_day_chunks(day_dt)
        end
    end

    # An explicit start_time/stop_time window takes precedence over datetime
    window = resolve_time_window(workflow)

    if window !== nothing
        # Process an arbitrary window, clipping the final chunk to stop_time
        window_start, window_stop = window
        msg_info("Processing $(Dates.format(window_start, "YYYYmmdd_HHMMSS")) to " *
                 "$(Dates.format(window_stop, "YYYYmmdd_HHMMSS")) in $(span_seconds)s chunks...")
        flush(stdout)
        # has_data is a directory listing (a network call for remote sources),
        # so check each day once rather than once per chunk.
        day_has_data = Dict{String,Bool}()
        any_processed = false
        for (chunk_start, chunk_stop) in time_window_chunks(window_start, window_stop,
                                                            span_seconds; reverse=reverse_order)
            day = Dates.format(chunk_start, "YYYYmmdd")
            available = get!(day_has_data, day) do
                found = has_data(source, day)
                if !found
                    msg_info("No data for $day, skipping...")
                    flush(stdout)
                end
                found
            end
            available || continue
            any_processed = true
            process_chunk(chunk_start, chunk_stop)
        end
        if !any_processed
            msg_info("No data in any day of the requested window, nothing to do...")
            flush(stdout)
            return "not processed due to missing data"
        end
    else
        datetime = get_param(workflow, "datetime", "now")

        # Change "now" to the current datetime in the format YYYYMMDD_hhmmss
        if datetime == "now"
            datetime = Dates.format(now(UTC), "YYYYmmdd_HHMMSS")
        end

        base_datetime, kind = parse_datetime_string(datetime)

        if kind === :year
            # Process a whole year (YYYY)
            num_days = Dates.value(base_datetime + Dates.Year(1) - base_datetime) ÷ (1000 * 60 * 60 * 24)
            msg_info("Processing year $(Dates.format(base_datetime, "YYYY")) ($num_days days)...")
            flush(stdout)
            process_day_range(base_datetime, 0:(num_days - 1))
        elseif kind === :month
            # Process a whole month (YYYYMM)
            num_days = Dates.value(base_datetime + Dates.Month(1) - base_datetime) ÷ (1000 * 60 * 60 * 24)
            msg_info("Processing month $(Dates.format(base_datetime, "YYYY-mm")) ($num_days days)...")
            flush(stdout)
            process_day_range(base_datetime, 0:(num_days - 1))
        elseif kind === :day
            # Process one day (YYYYMMDD)
            msg_info("Processing one day...")
            flush(stdout)
            if !has_data(source, Dates.format(base_datetime, "YYYYmmdd"))
                msg_info("No data for $(Dates.format(base_datetime, "YYYYmmdd")), nothing to do...")
                flush(stdout)
                return "not processed due to missing data"
            end
            process_day_chunks(base_datetime)
        elseif kind === :hour
            # Process one hour (YYYYMMDD_hh)
            day_dt = DateTime(Dates.Date(base_datetime))
            msg_info("Processing one hour...")
            if !has_data(source, Dates.format(day_dt, "YYYYmmdd"))
                msg_info("No data for $(Dates.format(day_dt, "YYYYmmdd")), nothing to do...")
                flush(stdout)
                return "not processed due to missing data"
            end
            flush(stdout)
            process_day_chunks(day_dt;
                              hour_offset=Dates.hour(base_datetime), num_seconds=3600)
        else
            # Process a single window starting at the given minute or second
            # (YYYYMMDD_hhmm or YYYYMMDD_hhmmss)
            process_chunk(base_datetime, base_datetime + Dates.Second(span_seconds))
        end
    end

    flush(stdout)
    if skipped > 0
        msg_warning("Completed batch with $(skipped) skipped volume(s) due to errors.")
        return "processed with $(skipped) skipped volume(s)"
    end
    return "processed successfully"
end

"""
    process_volume(workflow::SparrowWorkflow, start_time, stop_time)

Internal function to process a single time volume through all workflow steps.

# Arguments
- `workflow`: Workflow instance
- `start_time`: Start time for this volume
- `stop_time`: Stop time for this volume

# Description
Executes all workflow steps in sequence for files within the specified time window.
"""
function process_volume(workflow::SparrowWorkflow, start_time, stop_time)

    date = Dates.format(start_time, "YYYYmmdd")
    processed_files = []

    # Set up the working directories
    temp_dir = initialize_working_dirs(workflow, date; start_time=start_time, stop_time=stop_time)

    # The returned `input_files` is used by the caller to mark processed files.
    # link_base_data has already selected this chunk's inputs from the data
    # source, whatever its layout, into the working base_data directory, so list
    # that rather than re-deriving the source directory here. Then restrict to
    # [start_time, stop_time) by scan time so nothing outside the window is
    # marked processed without actually being touched.
    working_data_dir = joinpath(temp_dir, "base_data", date)
    input_files = readdir(working_data_dir; join=true)
    filter!(!isdir, input_files)
    filter!(input_files) do file
        scan_start = get_scan_start(file)
        scan_start >= start_time && scan_start < stop_time
    end

    # Run the workflow steps
    for (step_num, (step_name, step_type, input_name, archive)) in enumerate(workflow["steps"])
        if archive
            msg_info("Running archive step $(step_num): $(step_name) using $(step_type) from $(input_name)...")
            flush(stdout)
        else
            msg_info("Running temporary step $(step_num): $(step_name) using $(step_type) from $(input_name)...")
            flush(stdout)
        end

        run_workflow_step(workflow, step_num, start_time, stop_time, temp_dir)
    end

    # Clean up and move to archive
    processed_files = archive_workflow(workflow, temp_dir, date; start_time=start_time)

    # Remove the temporary directories (robust to ENOTEMPTY on networked FS)
    remove_working_dir(temp_dir)

    msg_info("Completed $(typeof(workflow)) workflow from $(start_time) to $(stop_time) with $(length(input_files)) input files and $(length(processed_files)) processed, archived files.")
    flush(stdout)
    return input_files, processed_files
end

# Main QC workflow dispatcher - takes a workflow type as argument
"""
    run_workflow_step(workflow::SparrowWorkflow, step_num, start_time, stop_time, temp_dir)

Internal function to execute a single workflow step.

Calls the user-defined [`workflow_step`](@ref) function for the specified step.

# Arguments
- `workflow`: Workflow instance
- `step_num`: Step number (1-indexed)
- `start_time`: Start time for this processing window
- `stop_time`: Stop time for this processing window
- `temp_dir`: Temporary directory for this processing run
"""
function run_workflow_step(workflow::SparrowWorkflow, step_num, start_time, stop_time, temp_dir)

    # Common preprocessing that applies to all workflows
    date = Dates.format(start_time, "YYYYmmdd")
    steps = workflow["steps"]
    step_name, step_type, input_name, archive = steps[step_num]
    input_dir = joinpath(temp_dir, input_name, date)
    output_dir = joinpath(temp_dir, step_name, date)

    if hasmethod(workflow_step, Tuple{typeof(workflow), Type{step_type}, String, String})
        msg_info("Running $(typeof(workflow)) workflow step $(step_num): $(step_name)")
        flush(stdout)
        workflow_step(workflow, step_type, input_dir, output_dir;
                     step_name=step_name, step_num=step_num, start_time=start_time, stop_time=stop_time)
    elseif hasmethod(workflow_step, Tuple{SparrowWorkflow, Type{step_type}, String, String})
        msg_info("Running Sparrow provided step $(step_num): $(step_name)")
        flush(stdout)
        workflow_step(workflow, step_type, input_dir, output_dir;
                     step_name=step_name, step_num=step_num, start_time=start_time, stop_time=stop_time)
    elseif step_type in PLOT_STEP_TYPES && Base.get_extension(Sparrow, :SparrowPlotExt) === nothing
        msg_error("Workflow step $(step_name) ($(step_type)) needs the Sparrow plotting extension, " *
                   "which is not loaded. Install the plotting packages with " *
                   "`Pkg.add([\"CairoMakie\", \"GeoMakie\", \"ColorSchemes\", \"Images\"])` in the " *
                   "environment Sparrow runs in; they are loaded automatically at startup " *
                   "(see the startup warning for why the load failed).")
    else
        msg_error("Workflow step $(step_name) is not implemented by $(typeof(workflow)) or Sparrow provided functions. Please implement workflow_step(workflow::$(typeof(workflow)), step_type::$(step_type), input_dir::String, output_dir::String) to run this workflow step.")
    end
    msg_info("Completed step $(step_num): $(step_name)")
    flush(stdout)
    return true
end

"""
    check_processed(workflow::SparrowWorkflow, file::String, archive_dir::String) → Bool

Check if a file has already been processed (exists in archive).

`archive_dir` is the stable archive root from [`archive_root_dir`](@ref), not a
dated directory: there is one `.sparrow` marker directory per archive tree, so a
marker stays findable however the products below it are organized by time.

# Arguments
- `workflow`: Workflow instance
- `file`: File path to check
- `archive_dir`: Archive root directory (see [`archive_root_dir`](@ref))

# Returns
- `true` if file already processed, `false` otherwise
"""
function check_processed(workflow::SparrowWorkflow, file::String, archive_dir::String)

    # Make sure the hidden processed directory exists
    mkpath(joinpath(archive_dir, ".sparrow"))
    return isfile(marker_path(workflow, archive_dir, file))
end

# Path of the hidden processed-marker for `file`. Shared by check_processed
# (reader) and mark_processed (writer) so the two can never drift apart.
marker_path(workflow::SparrowWorkflow, archive_dir::String, file::String) =
    joinpath(archive_dir, ".sparrow", "$(typeof(workflow))_$(basename(file))")

"""
    mark_processed(workflow::SparrowWorkflow, files, archive_dir::String)

Touch a processed-marker file for each entry in `files` under the hidden
`.sparrow` directory in `archive_dir`, the stable archive root from
[`archive_root_dir`](@ref). Empty `files` is a no-op (apart from ensuring the
marker directory exists). Idempotent. Mirrors [`check_processed`].
"""
function mark_processed(workflow::SparrowWorkflow, files, archive_dir::String)
    mkpath(joinpath(archive_dir, ".sparrow"))
    for file in files
        touch(marker_path(workflow, archive_dir, file))
    end
end
