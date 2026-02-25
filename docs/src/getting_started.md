# Getting Started

This guide will walk you through installing Sparrow.jl and creating your first workflow.

## Installation

### Prerequisites

Sparrow.jl requires Julia 1.6 or later. You can download Julia from [julialang.org](https://julialang.org/downloads/).

### Installing Sparrow.jl

Since Sparrow.jl is hosted on GitHub, you can install it using the package manager:

```julia
using Pkg
Pkg.add(url="https://github.com/csu-tropical/Sparrow.jl")
```

### Installing Dependencies

Sparrow.jl has several dependencies that will be automatically installed. However, some external tools may be required for certain operations:

- **RadxConvert**: For converting radar data formats
- **RadxPrint**: For reading radar file metadata

These tools are part of the [LROSE](https://github.com/NCAR/lrose-core) toolkit and should be available in your system PATH if you plan to use the built-in radar processing steps.

## Your First Workflow

Let's create a simple workflow that processes radar data files.

### Step 1: Create a Workflow File

Create a new file called `my_workflow.jl`:

```julia
using Sparrow

# Define your workflow type
@workflow_type SimpleRadarWorkflow

# Define workflow steps
@workflow_step ConvertData
@workflow_step QualityCheck

# Create the workflow instance
workflow = SimpleRadarWorkflow(
    # Directory configuration
    base_working_dir = "/tmp/sparrow_work",
    base_archive_dir = "/data/archive",
    base_data_dir = "/data/raw",
    base_plot_dir = "/data/plots",
    
    # Time parameters
    minute_span = 10,  # Process data in 10-minute chunks
    
    # Define the processing steps
    # Format: (step_name, step_type, input_directory, archive)
    steps = [
        ("convert", ConvertData, "base_data", false),
        ("qc", QualityCheck, "convert", true)
    ],
    
    # Radar moments to process
    raw_moment_names = ["DBZ", "VEL", "WIDTH"],
    qc_moment_names = ["DBZ", "VEL"],
    
    # Message level (0=error, 1=warning, 2=info, 3=debug, 4=trace)
    message_level = 2
)

# Implement the conversion step
function Sparrow.workflow_step(workflow::SimpleRadarWorkflow, ::Type{ConvertData},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_info("Converting data from $(input_dir)")
    
    # Create output directory
    mkpath(output_dir)
    
    # Find input files
    input_files = readdir(input_dir; join=true)
    filter!(f -> endswith(f, ".raw") || endswith(f, ".uf"), input_files)
    
    # Process each file
    for input_file in input_files
        output_file = joinpath(output_dir, basename(input_file) * ".nc")
        
        # Example: call external conversion tool
        run(`radx_convert -f $(input_file) -outdir $(output_dir) -outformat cfradial`)
        
        msg_debug("Converted $(basename(input_file))")
    end
    
    return length(input_files)
end

# Implement the quality check step
function Sparrow.workflow_step(workflow::SimpleRadarWorkflow, ::Type{QualityCheck},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    
    msg_info("Performing quality control on data from $(input_dir)")
    
    mkpath(output_dir)
    
    # Find converted files
    input_files = readdir(input_dir; join=true)
    filter!(f -> endswith(f, ".nc"), input_files)
    
    for input_file in input_files
        # Your QC logic here
        msg_debug("QC check on $(basename(input_file))")
        
        # Copy file to output (replace with actual QC)
        output_file = joinpath(output_dir, basename(input_file))
        cp(input_file, output_file; force=true)
    end
    
    return length(input_files)
end
```

### Step 2: Run the Workflow

Run your workflow from the command line:

```bash
julia sparrow my_workflow.jl --datetime 20240101_000000 -v 2
```

This will process data from January 1, 2024, 00:00:00 with informational message level.

### Step 3: Use Distributed Processing

To use multiple workers for parallel processing:

```bash
julia sparrow my_workflow.jl --datetime 20240101_000000 \
    --num_workers 4 --threads 2 -v 2
```

This uses 4 distributed workers, each with 2 threads.

### Step 4: Run on a Cluster

If you're using a Slurm cluster:

```bash
julia sparrow my_workflow.jl --datetime 20240101_000000 \
    --slurm --num_workers 10
```

This will submit jobs to Slurm with 10 workers.

## Understanding Workflow Parameters

### Required Parameters

Every workflow must have these parameters:

- `base_working_dir`: Temporary working directory for intermediate files
- `base_archive_dir`: Directory for archived/processed files
- `base_data_dir`: Directory containing raw input data
- `steps`: Vector of tuples: `(step_name, step_type, input_directory, archive)`

### Common Optional Parameters

- `base_plot_dir`: Directory for output plots
- `minute_span`: Time span for each processing chunk (in minutes)
- `reverse`: Process files in reverse chronological order (default: false)
- `message_level`: Verbosity level (0-4, default: 2)
- `raw_moment_names`: Names of radar moments in raw data
- `qc_moment_names`: Names of radar moments after QC

### Accessing Parameters

Within your workflow step functions, you can access parameters using dictionary syntax:

```julia
function Sparrow.workflow_step(workflow::SimpleRadarWorkflow, ::Type{MyStep},
                               input_dir::String, output_dir::String;
                               kwargs...)
    
    # Access required parameters
    data_dir = workflow["base_data_dir"]
    
    # Access with default value
    span = Sparrow.get_param(workflow, "minute_span", 10)
    
    # Access and type check
    moments = Sparrow.get_param(workflow, "raw_moment_names", Vector{String})
end
```

## Message System

Sparrow provides a structured message system for logging:

```julia
# Different severity levels
msg_error("Critical error!")        # Level 0 - always shown
msg_warning("Something suspicious")  # Level 1
msg_info("Processing file X")       # Level 2 (default)
msg_debug("Intermediate value: Y")  # Level 3
msg_trace("Detailed iteration Z")   # Level 4

# Set message level globally
set_message_level(MSG_DEBUG)  # Show debug and higher

# Or set in workflow parameters
workflow = MyWorkflow(
    message_level = 3,  # Debug level
    # ... other params
)
```

## Next Steps

- Read the [Workflow Guide](workflow_guide.md) for detailed information on building workflows
- Check out the [Examples](examples.md) for more complex use cases
- Browse the [API Reference](api.md) for complete function documentation

## Common Issues

### World Age Errors

If you see world age errors, make sure you're using the `sparrow` launcher script rather than directly calling Julia, or use `Base.invokelatest` when dynamically loading workflow files.

### Worker Communication

If workers can't access your workflow type, ensure the workflow file is included on all workers. The `sparrow` script handles this automatically.

### File Path Issues

Always use absolute paths for directory parameters, or ensure relative paths are resolved correctly relative to where you run the command.
