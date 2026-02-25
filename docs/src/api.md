# API Reference

```@meta
CurrentModule = Sparrow
```

This page provides detailed documentation for all public APIs in Sparrow.jl.

## Workflow Types and Macros

### @workflow_type

Create a new workflow type that inherits from `SparrowWorkflow`.

**Usage:**
```julia
@workflow_type MyWorkflow
```

**Expands to:**
```julia
struct MyWorkflow <: SparrowWorkflow
    params::Dict{String,Any}
end

MyWorkflow(; kwargs...) = MyWorkflow(Dict{String,Any}(string(k) => v for (k, v) in kwargs))
```

**Example:**
```julia
@workflow_type RadarProcessing

workflow = RadarProcessing(
    base_working_dir = "/tmp/work",
    base_archive_dir = "/data/archive",
    base_data_dir = "/data/raw",
    # Format: (step_name, step_type, input_directory, archive)
    steps = [
        ("qc", QCStep, "base_data", false),
        ("grid", GridStep, "qc", true)
    ]
)
```

### @workflow_types

Define multiple workflow types at once.

**Usage:**
```julia
@workflow_types WorkflowA WorkflowB WorkflowC
```

Equivalent to calling `@workflow_type` for each type individually.

### @workflow_step

Define a workflow step type for dispatch.

**Usage:**
```julia
@workflow_step MyStep
```

**Expands to:**
```julia
struct MyStep end
```

Step types are used for dispatch in `workflow_step` function implementations.

**Example:**
```julia
@workflow_step ConvertData

function Sparrow.workflow_step(workflow::MyWorkflow, ::Type{ConvertData},
                               input_dir::String, output_dir::String;
                               kwargs...)
    # Implementation
end
```

## Core Workflow Functions

### run_workflow

Execute a complete workflow from start to finish.

**Signature:**
```julia
run_workflow(workflow::SparrowWorkflow, parsed_args) → Bool
```

**Arguments:**
- `workflow`: A workflow instance
- `parsed_args`: Parsed command-line arguments (Dict)

**Returns:**
- `true` if workflow completed successfully, `false` otherwise

**Description:**

This is the main entry point for executing workflows. It:
1. Sets up workflow parameters from command-line arguments
2. Assigns workers for distributed processing
3. Processes the workflow across the specified time range
4. Handles errors and cleanup

**Called by:** The `main` function in the Sparrow module

### assign_workers

Distribute files across available workers for parallel processing.

**Signature:**
```julia
assign_workers(workflow::SparrowWorkflow) → Nothing
```

**Arguments:**
- `workflow`: Workflow instance with configured parameters

**Description:**

Creates a file queue and distributes processing tasks across all available workers. Files are organized by time windows and assigned to workers as they become available.

**Prerequisites:**
- Workers must be initialized (via `addprocs` or cluster manager)
- Workflow must be loaded on all workers

### process_workflow

Process a workflow with the main process (non-distributed).

**Signature:**
```julia
process_workflow(workflow::SparrowWorkflow) → Bool
```

**Arguments:**
- `workflow`: Workflow instance

**Returns:**
- `true` if processing succeeded, `false` otherwise

**Description:**

Processes the entire workflow sequentially on the main process. Used when running without distributed workers.

### workflow_step

User-defined function that implements a workflow step.

**Signature:**
```julia
workflow_step(workflow::YourWorkflowType, ::Type{YourStepType},
              input_dir::String, output_dir::String;
              step_name::String="", step_num::Int=0, kwargs...) → Int
```

**Arguments:**
- `workflow`: Your workflow instance
- `::Type{YourStepType}`: Step type for dispatch
- `input_dir`: Directory containing input files
- `output_dir`: Directory for output files
- `step_name`: Name of the step (from workflow definition)
- `step_num`: Step number in the workflow (1-indexed)
- `kwargs...`: Additional keyword arguments

**Returns:**
- Number of files processed (or 0 if step failed/skipped)

**Description:**

This is the function you implement for each workflow step. It receives input files from the previous step (or raw data for the first step) and produces output files for the next step.

**Example:**
```julia
function Sparrow.workflow_step(workflow::MyWorkflow, ::Type{ProcessData},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_info("Processing data in step $(step_num): $(step_name)")
    mkpath(output_dir)
    
    # Find and process files
    files = readdir(input_dir; join=true)
    for file in files
        # Process file...
        output = joinpath(output_dir, basename(file))
        # ... save to output
    end
    
    return length(files)
end
```

## Parameter Access Functions

### get_param

Get a workflow parameter with optional default value or type checking.

**Signatures:**
```julia
get_param(workflow::SparrowWorkflow, key::String, default) → Any
get_param(workflow::SparrowWorkflow, key::String, ::Type{T}) → T
```

**Arguments:**
- `workflow`: Workflow instance
- `key`: Parameter name
- `default`: Default value if parameter not found
- `T`: Expected type (with type assertion)

**Returns:**
- Parameter value, or default if not found (first form)
- Parameter value with type assertion (second form)

**Examples:**
```julia
# With default value
span = get_param(workflow, "minute_span", 10)

# With type checking
moments = get_param(workflow, "raw_moment_names", Vector{String})

# Direct access (throws error if not found)
value = workflow["required_param"]
```

## Message System

### Message Functions

Output messages with severity levels.

**Signatures:**
```julia
message(msg::String, severity::Int=MSG_INFO)
msg_error(msg::String)    # severity = 0
msg_warning(msg::String)  # severity = 1
msg_info(msg::String)     # severity = 2
msg_debug(msg::String)    # severity = 3
msg_trace(msg::String)    # severity = 4
```

**Arguments:**
- `msg`: Message text to display
- `severity`: Message severity level (0-4)

**Description:**

Messages are only displayed if their severity is at or below the current message level (set via `set_message_level`).

**Examples:**
```julia
msg_error("Critical failure in processing")
msg_warning("Missing optional parameter, using default")
msg_info("Processing 100 files")
msg_debug("Intermediate value: $(value)")
msg_trace("Loop iteration $(i)")
```

### set_message_level

Set the global message verbosity level.

**Signature:**
```julia
set_message_level(level::Int) → Nothing
```

**Arguments:**
- `level`: Message level (0-4)

**Message Levels:**
- `0` (`MSG_ERROR`): Only errors
- `1` (`MSG_WARNING`): Errors and warnings
- `2` (`MSG_INFO`): Errors, warnings, and informational (default)
- `3` (`MSG_DEBUG`): Include debug messages
- `4` (`MSG_TRACE`): Include trace messages (very verbose)

**Example:**
```julia
set_message_level(MSG_DEBUG)  # Show debug messages

# Or use integer directly
set_message_level(3)
```

### Message Level Constants

Predefined constants for message severity levels:

- `MSG_ERROR = 0`: Error messages (always shown)
- `MSG_WARNING = 1`: Warning messages
- `MSG_INFO = 2`: Informational messages (default level)
- `MSG_DEBUG = 3`: Debug messages
- `MSG_TRACE = 4`: Trace messages (very detailed)

## Abstract Types

### SparrowWorkflow

Abstract base type for all Sparrow workflows.

**Definition:**
```julia
abstract type SparrowWorkflow <: AbstractDict{String,Any} end
```

**Description:**

All workflow types created with `@workflow_type` inherit from `SparrowWorkflow`. This type:
- Subtypes `AbstractDict{String,Any}` to provide dictionary interface
- Enables type-based dispatch for workflow-specific behavior
- Stores parameters in a `params::Dict{String,Any}` field

**Dictionary Interface:**

Workflows support dictionary operations:

```julia
workflow["key"]              # Get parameter (error if not found)
workflow["key"] = value      # Set parameter
haskey(workflow.params, "key")  # Check if parameter exists
keys(workflow.params)        # Get all parameter names
length(workflow)             # Number of parameters
```

## Utility Functions

### setup_workers

Set up distributed workers for parallel processing.

Called automatically by `run_workflow` based on command-line arguments. Supports:
- Local workers (`-n N`)
- Slurm cluster workers (`--slurm -n N`)

### process_volume

Process a single time volume (time window) through all workflow steps.

**Internal function** - called by `assign_workers` and `process_workflow`.

### run_workflow_step

Execute a single workflow step for a given time range.

**Internal function** - calls the user-defined `workflow_step` function.

### check_processed

Check if a file has already been processed (exists in archive).

**Internal function** - used to skip already-processed files.

## Command-Line Interface

The `sparrow` script provides the command-line interface. Options:

```
workflow                  Workflow file to execute (required, positional)
--datetime DATETIME       Process specific time YYYYmmdd_HHMMSS (default: "now")
--realtime                Process an incoming realtime datastream
--force_reprocess         Force reprocessing of previously processed data
--threads N               Number of threads
--num_workers N           Number of worker processes
-v, --verbose LEVEL       Message verbosity level (0-4, default: 2)
--slurm                   Use Slurm cluster manager
--sge                     Use Sun Grid Engine
--paths_file FILE         File overriding data paths
```

**Example:**
```bash
julia sparrow my_workflow.jl --datetime 20240101_000000 \
    --num_workers 4 --threads 2 -v 2
```

## Extended Example

Here's a complete example showing the API in use:

```julia
using Sparrow

# Define workflow type
@workflow_type DataPipeline

# Define steps
@workflow_step LoadData
@workflow_step ProcessData
@workflow_step SaveResults

# Create workflow instance
workflow = DataPipeline(
    base_working_dir = "/tmp/work",
    base_archive_dir = "/data/archive",
    base_data_dir = "/data/raw",
    # Format: (step_name, step_type, input_directory, archive)
    steps = [
        ("load", LoadData, "base_data", false),
        ("process", ProcessData, "load", false),
        ("save", SaveResults, "process", true)
    ],
    threshold = 10.0,
    message_level = 2
)

# Implement step 1
function Sparrow.workflow_step(workflow::DataPipeline, ::Type{LoadData},
                               input_dir::String, output_dir::String;
                               kwargs...)
    msg_info("Loading data from $(input_dir)")
    mkpath(output_dir)
    
    files = readdir(input_dir; join=true)
    for file in files
        # Load and prepare data
        output = joinpath(output_dir, basename(file))
        cp(file, output)
    end
    
    return length(files)
end

# Implement step 2
function Sparrow.workflow_step(workflow::DataPipeline, ::Type{ProcessData},
                               input_dir::String, output_dir::String;
                               kwargs...)
    msg_info("Processing data")
    mkpath(output_dir)
    
    threshold = get_param(workflow, "threshold", 5.0)
    
    files = readdir(input_dir; join=true)
    for file in files
        # Process with threshold
        msg_debug("Processing $(basename(file)) with threshold $(threshold)")
        output = joinpath(output_dir, basename(file))
        # ... processing logic ...
        cp(file, output)
    end
    
    return length(files)
end

# Implement step 3
function Sparrow.workflow_step(workflow::DataPipeline, ::Type{SaveResults},
                               input_dir::String, output_dir::String;
                               kwargs...)
    msg_info("Saving final results")
    mkpath(output_dir)
    
    files = readdir(input_dir; join=true)
    for file in files
        output = joinpath(output_dir, basename(file))
        cp(file, output)
    end
    
    msg_info("Workflow complete!")
    return length(files)
end
```

Run with:
```bash
julia sparrow pipeline.jl --datetime 20240101_000000
```
