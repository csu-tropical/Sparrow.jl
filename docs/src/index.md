```@meta
CurrentModule = Sparrow
```

# Sparrow.jl

**Ship, Plane, and Anchored Radar Research and Operational Workflows**

Sparrow.jl is a flexible, distributed workflow system for processing radar data. It provides a framework for building custom data processing pipelines with built-in support for quality control, gridding, merging, and visualization.

## Features

- **Flexible Workflow System**: Define custom workflows with multiple processing steps
- **Distributed Processing**: Built-in support for parallel processing across multiple workers
- **Radar Data Processing**: Specialized tools for quality control, gridding, and merging radar data
- **Extensible Architecture**: Easy to add custom processing steps and workflow types
- **Message System**: Configurable logging with multiple severity levels
- **Integration with HPC**: Support for Slurm and other cluster managers

## Quick Start

### Installation

Springsteel and Ronin are registered packages; Daisho and Sparrow are installed directly from GitHub:

```julia
using Pkg
Pkg.add("Springsteel")
Pkg.add(url="https://github.com/csu-tropical/Daisho.jl")
Pkg.add("Ronin")
Pkg.add(url="https://github.com/csu-tropical/Sparrow.jl")
```

Then install the `sparrow` launcher script onto your PATH (default `~/.local/bin`):

```bash
julia -e 'using Sparrow; Sparrow.install_sparrow_script()'
```

### The Simplest Workflow

A workflow file defines a workflow type and a `workflow` variable. The smallest possible workflow uses a single pre-built step and no custom code — `PassThroughStep` just copies files from the data directory to the archive, so you can verify your installation before building anything more complex:

```julia
using Sparrow

@workflow_type SimpleWorkflow

workflow = SimpleWorkflow(
    base_working_dir = "/tmp/sparrow/work",
    base_archive_dir = "/tmp/sparrow/archive",
    base_data_dir = "/path/to/your/radar/files",
    base_plot_dir = "/tmp/sparrow/plots",
    span_seconds = "10M",
    steps = [
        ("copy", PassThroughStep, "base_data", true),
    ],
)
```

Save as `my_workflow.jl` and run it on a day you have data for:

```bash
sparrow my_workflow.jl --datetime 20240101_000000
```

See [Getting Started](getting_started.md) for a walk-through and [Provided Workflow Steps](provided_steps.md) for the ready-made steps (format conversion, QC, gridding, plotting).

### Custom Steps

1. **Define a workflow type** using the `@workflow_type` macro:

```julia
using Sparrow

@workflow_type MyRadarWorkflow
```

2. **Define workflow steps** using the `@workflow_step` macro:

```julia
@workflow_step QualityControl
@workflow_step Gridding
```

3. **Create a workflow instance** with parameters:

```julia
workflow = MyRadarWorkflow(
    base_working_dir = "/path/to/working/dir",
    base_archive_dir = "/path/to/archive",
    base_data_dir = "/path/to/data",
    steps = [
        # Format: (step_name, step_type, input_directory, archive)
        ("qc", QualityControl, "base_data", false),
        ("grid", Gridding, "qc", true)
    ],
    # Add other parameters as needed
)
```

4. **Implement step functions**:

```julia
function Sparrow.workflow_step(workflow::MyRadarWorkflow, ::Type{QualityControl},
                               input_dir::String, output_dir::String;
                               step_name::String="", step_num::Int=0, kwargs...)
    # Your processing logic here
    msg_info("Running quality control on data from $(input_dir)")
    # ... process files ...
    return num_files_processed
end
```

5. **Run the workflow** from the command line:

```bash
sparrow my_workflow.jl --datetime 20240101_000000
```

## Command Line Interface

The `sparrow` script provides a command-line interface for running workflows:

```bash
sparrow workflow.jl [options]

Options:
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

## Documentation Contents

```@contents
Pages = [
    "getting_started.md",
    "workflow_guide.md",
    "provided_steps.md",
    "examples.md",
    "api.md"
]
Depth = 2
```

## Index

```@index
```

## Module Overview

For detailed API documentation, see the [API Reference](api.md).
