# Workflow Guide

This guide provides in-depth information on creating and managing workflows in Sparrow.jl.

## Workflow Architecture

A Sparrow workflow consists of three main components:

1. **Workflow Type**: A struct that holds configuration parameters
2. **Workflow Steps**: Processing stages that transform data
3. **Step Functions**: Implementations that perform the actual work

## Creating Workflow Types

### Using the @workflow_type Macro

The `@workflow_type` macro creates a new workflow type that automatically:
- Inherits from `SparrowWorkflow`
- Implements the dictionary interface
- Provides a keyword constructor

```julia
@workflow_type MyWorkflow
```

This expands to:

```julia
struct MyWorkflow <: SparrowWorkflow
    params::Dict{String,Any}
end

MyWorkflow(; kwargs...) = MyWorkflow(Dict{String,Any}(string(k) => v for (k, v) in kwargs))
```

### Multiple Workflow Types

You can define multiple workflow types in the same file:

```julia
@workflow_types RadarQC RadarGrid RadarMerge
```

### Manual Workflow Definition

For more control, you can define workflows manually:

```julia
struct CustomWorkflow <: SparrowWorkflow
    params::Dict{String,Any}
    
    function CustomWorkflow(; kwargs...)
        params = Dict{String,Any}(string(k) => v for (k, v) in kwargs)
        
        # Add validation
        if !haskey(params, "required_param")
            error("CustomWorkflow requires 'required_param'")
        end
        
        new(params)
    end
end
```

## Defining Workflow Steps

### Using @workflow_step

Steps are typically empty structs used for dispatch:

```julia
@workflow_step ConvertStep
@workflow_step QCStep
@workflow_step GridStep
```

### Step Ordering

Steps are defined as an ordered list in your workflow instance:

```julia
workflow = MyWorkflow(
    # Format: (step_name, step_type, input_directory, archive)
    steps = [
        ("convert", ConvertStep, "base_data", false),
        ("qc", QCStep, "convert", false),
        ("grid", GridStep, "qc", true)
    ],
    # ... other params
)
```

The order in the vector determines execution order. Each step receives output from the previous step as input.

## Implementing Step Functions

### Function Signature

Step functions must follow this signature:

```julia
function Sparrow.workflow_step(
    workflow::YourWorkflowType,
    ::Type{YourStepType},
    input_dir::String,
    output_dir::String;
    step_name::String="",
    step_num::Int=0,
    kwargs...
)
    # Your implementation
    return num_files_processed
end
```

### Parameters

- `workflow`: Your workflow instance (access parameters via `workflow["key"]`)
- `::Type{YourStepType}`: Step type for dispatch
- `input_dir`: Directory containing input files for this step
- `output_dir`: Directory where output files should be written
- `step_name`: Name of the step (from workflow definition)
- `step_num`: Step number in the workflow (1-indexed)
- `kwargs...`: Additional keyword arguments

### Return Value

Step functions should return the number of files processed (or 0 if no files were processed).

### Example Implementation

```julia
function Sparrow.workflow_step(workflow::MyWorkflow, ::Type{ConvertStep},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_info("Step $(step_num): $(step_name) - Converting files")
    
    # Create output directory
    mkpath(output_dir)
    
    # Get workflow parameters
    file_pattern = get_param(workflow, "file_pattern", "*.raw")
    
    # Find input files
    input_files = readdir(input_dir; join=true)
    filter!(f -> occursin(Regex(file_pattern), f), input_files)
    
    # Process each file
    processed_count = 0
    for input_file in input_files
        try
            output_file = joinpath(output_dir, basename(input_file) * ".nc")
            
            # Your processing logic
            convert_radar_file(input_file, output_file)
            
            processed_count += 1
            msg_debug("Converted $(basename(input_file))")
        catch e
            msg_warning("Failed to convert $(basename(input_file)): $(e)")
        end
    end
    
    msg_info("Processed $(processed_count) files in step $(step_name)")
    return processed_count
end
```

## Workflow Parameters

### Required Parameters

These parameters are required for the workflow system to function:

```julia
workflow = MyWorkflow(
    # Directory structure
    base_working_dir = "/path/to/temp",      # Temporary working directory
    base_archive_dir = "/path/to/archive",   # Archived/processed files
    base_data_dir = "/path/to/raw",          # Raw input data
    
    # Workflow definition
    # Format: (step_name, step_type, input_directory, archive)
    steps = [
        ("step1", Step1Type, "base_data", false),
        ("step2", Step2Type, "step1", true)
    ]
)
```

### Common Optional Parameters

```julia
workflow = MyWorkflow(
    # ... required params ...
    
    # Time handling
    span_seconds = "10M",          # Chunk length: seconds (600) or "20S"/"5M"/"10H"/"1D"
    start_time = "20240101_1400",  # Optional explicit processing period, given
    stop_time  = "20240102_0600",  #   together and used instead of datetime
    reverse = false,               # Process in reverse chronological order
    index_time = "scan_start",     # Time coordinate of gridded output:
                                   #   "scan_start" (default), "start_time", "stop_time"
    
    # Directories
    base_plot_dir = "/plots",      # Output plots directory
    date_subdir = true,            # Append a YYYYmmdd level to the base directories
                                   #   (default true; see "Customizing the date directory")
    
    # Radar-specific
    raw_moment_names = ["DBZ", "VEL", "WIDTH"],
    qc_moment_names = ["DBZ", "VEL"],
    daisho_config = "/path/to/daisho.toml",  # Daisho TOML for the gridding steps
    
    # Logging
    message_level = 2,             # 0=error, 1=warning, 2=info, 3=debug, 4=trace
    
    # Custom parameters
    my_threshold = 10.0,
    my_flag = true
)
```

### Accessing Parameters

```julia
# Direct access (throws error if key not found)
value = workflow["parameter_name"]

# With default value
value = get_param(workflow, "parameter_name", default_value)

# With type checking
value = get_param(workflow, "parameter_name", ExpectedType)
```

### Adding Parameters Dynamically

Since workflows behave like dictionaries:

```julia
# Add or update a parameter
workflow["new_parameter"] = "value"

# Check if parameter exists
if haskey(workflow.params, "optional_param")
    # Use it
end
```

## Data Flow and Directory Structure

### Directory Hierarchy

With the default layout, every tree carries a `YYYYmmdd` date level. For a
workflow with the steps `convert`, `qc` and `grid` processing 1 January 2024:

```
base_data_dir/
└── 20240101/                  # raw input files for the day
    ├── cfrad.20240101_000012.000_..._SUR.nc
    └── ...

base_working_dir/
└── Xa7Bq2/                    # one random scratch directory per chunk
    ├── base_data/20240101/    # symlinks to the chunk's input files
    ├── convert/20240101/
    ├── qc/20240101/
    └── grid/20240101/

base_archive_dir/
├── .sparrow/                  # hidden processed-file markers
├── convert/20240101/
├── qc/20240101/
└── grid/20240101/

base_plot_dir/
├── plot_rhi/20240101/
└── plot_composite/20240101/
```

The working tree is disposable: it is created per chunk under a random
subdirectory of `base_working_dir` and removed when the chunk finishes. Only
steps declared with `archive = true` have their output moved to
`base_archive_dir`; plot steps write straight to `base_plot_dir`.

### Customizing the date directory

The date does not have to be the deepest level, and the directory unit does not
have to be a day. `base_data_dir`, `base_archive_dir` and `base_plot_dir` accept
the placeholders below. When a base directory contains any of them, the time is
substituted **in place** and no date level is appended, so the date can sit
anywhere in the path — above a platform directory, for instance.

| Token             | Unit   | 2024-01-01 13:05 | Allowed in                                      |
| ----------------- | ------ | ---------------- | ----------------------------------------------- |
| `{YYYY}`          | day    | `2024`           | data, archive, plot                             |
| `{MM}`            | day    | `01`             | data, archive, plot                             |
| `{DD}`            | day    | `01`             | data, archive, plot                             |
| `{YYYYmmdd}`      | day    | `20240101`       | data, archive, plot                             |
| `{HH}`            | hour   | `13`             | data, archive, plot                             |
| `{YYYYmmdd_HH}`   | hour   | `20240101_13`    | data, archive, plot                             |
| `{mm}`            | minute | `05`             | data, archive, plot                             |
| `{YYYYmmdd_HHMM}` | minute | `20240101_1305`  | data, archive, plot                             |
| `{step}`          | —      | the step name    | archive, plot only                              |

`{MM}` is the month and `{mm}` the minute, as in the remote sources'
`prefix_template`. Without a `{step}` token the step name is appended after the
resolved base, which is the historical layout; with one it goes exactly where
you put it. `{step}` in `base_data_dir` is an error — raw input has no step.

| Parameter value | Resolved directory for 2024-01-01 13:05 |
| --- | --- |
| `base_archive_dir = "/archive"` | `/archive/<step>/20240101/` |
| `base_archive_dir = "/archive/{YYYYmmdd}/chivo"` | `/archive/20240101/chivo/<step>/` |
| `base_archive_dir = "/archive/{YYYY}/{MM}/{DD}"` | `/archive/2024/01/01/<step>/` |
| `base_archive_dir = "/archive/{step}/{YYYYmmdd}/{HH}"` | `/archive/grid/20240101/13/` |
| `base_plot_dir = "/figs/{YYYYmmdd_HH}"` | `/figs/20240101_13/<step>/` |
| `base_data_dir = "/data/{YYYYmmdd}/{HH}{mm}"` | `/data/20240101/1305/` |
| `base_data_dir = "/data/chivo"` with `date_subdir = false` | `/data/chivo/` (read directly) |

An unrecognized token — `{yyyy}`, `{YYYYMMDD}`, `{date}` — is rejected at
startup with the list of valid placeholders, rather than creating a directory
with that literal name. So is a `base_archive_dir` whose *first* component is a
placeholder (`"/{YYYYmmdd}/archive"`): the archive tree needs one literal root,
see the `.sparrow` markers below.

#### The directory unit is independent of `span_seconds`

The finest token present sets the tree's time organization unit — day, hour or
minute (minute is the finest supported; there is no second-level directory).
That unit has **no effect on processing granularity**: a chunk is always
`span_seconds` long, and a chunk is never split to fit a directory.

- **Reading.** A chunk reads *every* unit directory its window overlaps. A
  10-minute chunk running 13:55–14:05 against `base_data_dir =
  "/data/{YYYYmmdd}/{HH}"` reads both `/data/20240101/13/` and
  `/data/20240101/14/`, so a rapid-scan volume that spans the top of the hour
  arrives whole. Missing unit directories are skipped quietly; only a window
  with no existing directory at all warns.
- **Writing.** Each product is filed by the timestamp in its *own* filename
  (`gridded_<kind>_<YYYYmmdd_HHMMSS>.nc`, `cfrad.YYYYmmdd_HHMMSS...`), with the
  chunk start as the fallback for an unrecognizable name. So the 13:55–14:05
  chunk above writes its 13:5x products into `.../20240101/13/` and its 14:0x
  products into `.../20240101/14/`. Figures follow the same rule per input file.

Pick the unit for the volume of data you expect per directory; pick
`span_seconds` for the analysis increment you want. They are unrelated.

#### Opting out of the date level

To drop the date level entirely without using placeholders, set the optional
`date_subdir` parameter to `false`:

```julia
workflow = MyWorkflow(
    base_data_dir = "/data/chivo",     # files sit directly here, no 20240101/ level
    base_archive_dir = "/archive/chivo",
    date_subdir = false,
    ...
)
```

With `date_subdir = false` the input directory is read flat, so Sparrow selects
a window's files by the timestamps embedded in the filenames
(`cfrad.YYYYmmdd_HHMMSS...`, `KEVXYYYYmmdd_HHMMSS...`, `...YYYYmmdd-HHMMSS...`).
Files whose names carry no recognizable timestamp are offered to every window
and filtered by their scan time; they only make a day count as "having data"
when nothing in the directory has a parseable name. `date_subdir` is ignored for
any base directory that already contains a placeholder.

#### Where the processed-file markers live

The hidden `.sparrow` directory of processed-file markers lives at the **stable
root** of the archive tree: `base_archive_dir` with its placeholder components
removed, or `base_archive_dir` itself when it has none.

| `base_archive_dir` | Marker directory |
| --- | --- |
| `/archive/chivo` | `/archive/chivo/.sparrow/` |
| `/archive/{YYYYmmdd}/chivo` | `/archive/chivo/.sparrow/` |
| `/archive/{YYYYmmdd}/seapol` | `/archive/seapol/.sparrow/` |
| `/archive/chivo/{YYYY}/{MM}` | `/archive/chivo/.sparrow/` |
| `/archive/{step}/{YYYYmmdd}/{HH}` | `/archive/.sparrow/` |

There is one marker directory per archive tree, so a marker written by one chunk
stays findable by the next whatever unit the products below it are organized by,
and two trees that differ only below a placeholder (`chivo` and `seapol` above)
keep separate markers. That is why the first component of `base_archive_dir`
may not be a placeholder.

#### Realtime polling

In realtime mode the poller watches the unit directory the current time falls
in, plus any earlier one that the last `span_seconds` still reaches into: at day
resolution that is today, and yesterday as well for one span after midnight; at
hour or minute resolution it is the current unit plus the previous one when
within a span of the boundary. Unit directories that do not exist yet are
skipped quietly. Only the default `base_data_dir/YYYYmmdd` (or flat) layout has
its current directory created for it; a placeholder layout is left to the data
writer, so the poller never litters an hourly or per-minute tree with empty
directories.

Two things are deliberately unaffected:

- **The working tree.** `base_working_dir/<random>/<step>/YYYYmmdd/` is fixed;
  it is scratch space that is deleted after each chunk, and some steps (notably
  `RadxConvertStep`) rely on its date level.
- **Remote data sources.** `S3BucketSource` and `HTTPDirSource` lay out their
  remote paths with the `prefix_template`/`base_url` placeholders, and discovery
  against them stays day-based. `base_data_dir` still controls the layout of the
  *local download cache* for those sources, and follows the same rules as a
  local input directory — each downloaded file is cached under the unit
  directory its own timestamp belongs to.

### Step Input/Output

Each step receives:
- `input_dir`: Output directory from the previous step (or raw data for step 1)
- `output_dir`: A unique directory for this step's output

The workflow system automatically:
1. Creates output directories
2. Passes output of step N as input to step N+1
3. Archives final outputs

### Time-Based Processing

When processing time-series data:

```julia
workflow = MyWorkflow(
    span_seconds = 600,   # 10 minutes
    # ...
)
```

The workflow system:
1. Divides the time range (start to end) into chunks
2. Processes each chunk sequentially or in parallel
3. Finds files matching each time window
4. Runs all steps for that time window

`span_seconds` is the chunk width in seconds, so high-cadence data can be sliced
at sub-minute granularity (e.g. `span_seconds = 10`). It also accepts a string
with a unit code — `"20S"` (seconds), `"5M"` (minutes), `"10H"` (hours),
`"1D"` (days) — or a `Dates.Period` such as `Minute(5)`.

#### Selecting the Period to Process

The period itself comes from either a single `datetime` (the `--datetime`
command-line option, or a `datetime` workflow parameter) or an explicit
`start_time`/`stop_time` pair.

A `datetime` is always the **start** of the period and is **never aligned or
truncated to a `span_seconds` boundary**. The number of digits selects how much
is processed:

| `datetime`        | Period processed                                    |
|-------------------|-----------------------------------------------------|
| `2024`            | the whole year, chunked by `span_seconds`           |
| `202401`          | the whole month, chunked by `span_seconds`          |
| `20240101`        | that whole day, chunked by `span_seconds`           |
| `20240101_14`     | that whole hour, chunked by `span_seconds`          |
| `20240101_1418`   | one window: 14:18:00 to 14:18:00 + `span_seconds`   |
| `20240101_141820` | one window: 14:18:20 to 14:18:20 + `span_seconds`   |

Year, month, day and hour runs are chunked from the start of the year, month,
day or hour; if `span_seconds` does not divide the range evenly the trailing
partial chunk is skipped with a warning.

For an arbitrary period, set both `start_time` and `stop_time` instead:

```julia
workflow = MyWorkflow(
    span_seconds = "10M",
    start_time = "20240101_1400",   # inclusive
    stop_time  = "20240102_0600",   # exclusive
)
```

or pass the window at run time:

```bash
sparrow my_workflow.jl --start 20240101_1400 --stop 20240102_0600
```

The window is half-open — `[start_time, stop_time)` — and its final chunk is
clipped to `stop_time` rather than dropped; chunks are also split at midnight. When several of these are present,
`--datetime` beats `--start`/`--stop`, which beat `start_time`/`stop_time` in
the workflow file, which beat `datetime` in the workflow file, which beats
`"now"`. A workflow file that sets both `datetime` and `start_time`/`stop_time`
is ambiguous and raises an error, and realtime mode accepts none of them. See
[Selecting the Processing Period](@ref) for the full details.

#### Migration from `minute_span`

The legacy `minute_span` parameter is still accepted for backward compatibility.
On first use, Sparrow converts it to `span_seconds` (multiplying by 60), removes
the old key from the workflow, and emits a one-time deprecation warning. New
workflows should use `span_seconds` directly.

### Time Coordinate of Gridded Output

The `index_time` parameter selects which `DateTime` the gridding steps write as
the time coordinate of each gridded product:

| Value | Time coordinate |
|-------|-----------------|
| `"scan_start"` (default) | Start of the scan, read from the input file |
| `"start_time"` | Start of the analysis increment |
| `"stop_time"` | End of the analysis increment (`start_time + span_seconds`) |

Use the default `"scan_start"` for datasets with irregular scan timing, where
snapping products to an even increment is meaningless. Use `"start_time"` or
`"stop_time"` when downstream consumers expect successive products to be
separated by exactly one `span_seconds` increment.

The value may be given as a string or a `Symbol`, matched case-insensitively.
An unrecognized value errors when the workflow is set up, before any data is read.

This affects only the time coordinate inside the product. The output *filename*
always carries the per-scan time, so two scans landing in the same analysis
increment still produce two distinct files rather than one overwriting the other.

## Distributed Processing

### Worker Assignment

Sparrow automatically distributes time chunks across workers:

```julia
# Workers are assigned file batches
assign_workers(workflow)
```

Files are queued and distributed to available workers as they complete tasks.

### Step Function on Workers

Your step functions run on worker processes. Important considerations:

1. **Module Loading**: Workflow files are loaded on all workers automatically
2. **Message Level**: Set message level on workers for proper logging
3. **Shared Data**: Workers have separate memory; use files for communication
4. **Error Handling**: Return 0 or throw to signal failure

### Worker-Specific Code

```julia
function Sparrow.workflow_step(workflow::MyWorkflow, ::Type{MyStep},
                               input_dir::String, output_dir::String;
                               kwargs...)
    
    # Get worker ID
    worker_id = myid()
    msg_debug("Running on worker $(worker_id)")
    
    # Worker-specific logic
    if nworkers() > 1
        msg_info("Distributed mode with $(nworkers()) workers")
    end
    
    # Process files...
end
```

## Advanced Features

### Conditional Steps

```julia
function Sparrow.workflow_step(workflow::MyWorkflow, ::Type{ConditionalStep},
                               input_dir::String, output_dir::String;
                               kwargs...)
    
    # Skip step based on condition
    if !get_param(workflow, "enable_advanced_qc", false)
        msg_info("Skipping advanced QC (not enabled)")
        return 0
    end
    
    # Proceed with processing...
end
```

### Chaining External Tools

```julia
function Sparrow.workflow_step(workflow::MyWorkflow, ::Type{RadxStep},
                               input_dir::String, output_dir::String;
                               kwargs...)
    
    mkpath(output_dir)
    
    for file in readdir(input_dir; join=true)
        output_file = joinpath(output_dir, basename(file))
        
        # Call external tool
        cmd = `RadxConvert -f $(file) -outdir $(output_dir) -outformat cfradial`
        
        try
            run(cmd)
            msg_debug("Converted $(basename(file))")
        catch e
            msg_error("RadxConvert failed on $(file): $(e)")
            return 0
        end
    end
    
    return length(readdir(input_dir))
end
```

### Custom File Discovery

```julia
function Sparrow.workflow_step(workflow::MyWorkflow, ::Type{CustomDiscovery},
                               input_dir::String, output_dir::String;
                               kwargs...)
    
    # Custom pattern matching
    pattern = get_param(workflow, "file_pattern", r".*\.nc$")
    
    files = []
    for (root, dirs, filenames) in walkdir(input_dir)
        for filename in filenames
            if occursin(pattern, filename)
                push!(files, joinpath(root, filename))
            end
        end
    end
    
    msg_info("Found $(length(files)) files matching pattern")
    
    # Process files...
end
```

### Metadata Propagation

```julia
function Sparrow.workflow_step(workflow::MyWorkflow, ::Type{MetadataStep},
                               input_dir::String, output_dir::String;
                               kwargs...)
    
    mkpath(output_dir)
    
    # Read metadata from previous step
    metadata_file = joinpath(input_dir, ".metadata.json")
    if isfile(metadata_file)
        metadata = JSON.parsefile(metadata_file)
        msg_debug("Loaded metadata: $(metadata)")
    else
        metadata = Dict()
    end
    
    # Add metadata for this step
    metadata["step_name"] = get(kwargs, :step_name, "")
    metadata["processed_at"] = now()
    
    # Process files...
    
    # Save updated metadata
    output_metadata = joinpath(output_dir, ".metadata.json")
    open(output_metadata, "w") do io
        JSON.print(io, metadata, 2)
    end
    
    return 1
end
```

## Error Handling

### Step-Level Errors

```julia
function Sparrow.workflow_step(workflow::MyWorkflow, ::Type{SafeStep},
                               input_dir::String, output_dir::String;
                               kwargs...)
    
    processed = 0
    errors = 0
    
    for file in readdir(input_dir; join=true)
        try
            # Process file
            process_file(file, output_dir)
            processed += 1
        catch e
            msg_warning("Failed to process $(basename(file)): $(e)")
            errors += 1
            
            # Continue or abort?
            if errors > 10
                msg_error("Too many errors, aborting step")
                return 0
            end
        end
    end
    
    msg_info("Processed $(processed) files, $(errors) errors")
    return processed
end
```

### Validation

```julia
function Sparrow.workflow_step(workflow::MyWorkflow, ::Type{ValidateStep},
                               input_dir::String, output_dir::String;
                               kwargs...)
    
    # Validate required parameters
    required_params = ["threshold", "method", "output_format"]
    for param in required_params
        if !haskey(workflow.params, param)
            msg_error("Missing required parameter: $(param)")
            return 0
        end
    end
    
    # Validate input files exist
    input_files = readdir(input_dir)
    if isempty(input_files)
        msg_warning("No input files found in $(input_dir)")
        return 0
    end
    
    # Proceed with processing...
end
```

## Best Practices

1. **Keep Steps Focused**: Each step should do one thing well
2. **Use Message Levels Appropriately**: Error for failures, warning for issues, info for progress
3. **Return Accurate Counts**: Return the actual number of files processed
4. **Create Output Directories**: Always `mkpath(output_dir)` before writing
5. **Handle Missing Files Gracefully**: Empty input is often valid (skip processing)
6. **Validate Parameters Early**: Check required parameters at step start
7. **Use Type Dispatch**: Define step types for clear separation of concerns
8. **Document Your Steps**: Add comments explaining complex logic
9. **Test Incrementally**: Test each step independently before chaining
10. **Log Progress**: Use debug/trace messages for detailed progress tracking

## Testing Workflows

For information on testing workflows, see:
- Unit testing individual steps
- Integration testing complete workflows
- Generating test fixtures
- Running tests locally and in CI
