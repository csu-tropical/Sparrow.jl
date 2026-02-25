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
    minute_span = 10,              # Process data in N-minute chunks
    reverse = false,               # Process in reverse chronological order
    
    # Directories
    base_plot_dir = "/plots",      # Output plots directory
    
    # Radar-specific
    raw_moment_names = ["DBZ", "VEL", "WIDTH"],
    qc_moment_names = ["DBZ", "VEL"],
    moment_grid_type = [:linear, :linear, :log],
    
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

Sparrow creates a structured directory hierarchy:

```
base_working_dir/
├── step1_convert/
│   ├── 20240101_0000/
│   ├── 20240101_0010/
│   └── 20240101_0020/
├── step2_qc/
│   ├── 20240101_0000/
│   └── ...
└── step3_grid/
    └── ...

base_archive_dir/
├── converted/
├── qc/
└── gridded/
```

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
    minute_span = 10,
    # ...
)
```

The workflow system:
1. Divides the time range (start to end) into chunks
2. Processes each chunk sequentially or in parallel
3. Finds files matching each time window
4. Runs all steps for that time window

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
