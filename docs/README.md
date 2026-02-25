# Sparrow.jl Documentation

This directory contains the documentation for Sparrow.jl, built using [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl).

## Building the Documentation

### Prerequisites

The documentation dependencies are managed in `docs/Project.toml`. To install them:

```bash
cd docs
julia --project -e 'using Pkg; Pkg.instantiate()'
```

### Local Build

To build the documentation locally:

```bash
cd docs
julia --project make.jl
```

This will generate the documentation in `docs/build/`. You can open `docs/build/index.html` in your browser to view the generated documentation.

### Serving Locally

To serve the documentation locally with live updates:

```bash
cd docs
julia --project -e 'using LiveServer; serve(dir="build")'
```

Then open http://localhost:8000 in your browser.

## Documentation Structure

The documentation is organized as follows:

- **index.md**: Home page with overview and quick start
- **getting_started.md**: Installation and first workflow tutorial
- **workflow_guide.md**: In-depth guide to creating workflows
- **examples.md**: Complete workflow examples for common use cases
- **api.md**: API reference documentation

## Contributing to Documentation

### Adding New Pages

1. Create a new `.md` file in `docs/src/`
2. Add the page to the `pages` array in `docs/make.jl`
3. Rebuild the documentation

### Adding Docstrings

Add docstrings to functions in the source code using Julia's docstring syntax:

```julia
"""
    function_name(arg1, arg2) → ReturnType

Brief description of the function.

# Arguments
- `arg1`: Description of first argument
- `arg2`: Description of second argument

# Returns
Description of return value

# Example
\```julia
result = function_name(1, 2)
\```
"""
function function_name(arg1, arg2)
    # implementation
end
```

Documenter.jl will automatically extract and format these docstrings.

### Documentation Style Guide

- Use clear, concise language
- Include examples for complex concepts
- Cross-reference related functions using `[`function_name`](@ref)`
- Use code blocks with syntax highlighting: \```julia
- Add section headers with `#`, `##`, `###` for proper nesting
- Use bullet points and numbered lists for readability

## Deployment

Documentation is automatically built and deployed to GitHub Pages when changes are pushed to the `main` branch (via GitHub Actions CI).

The deployed documentation is available at:
- **Stable**: https://mmbell.github.io/Sparrow.jl/stable/
- **Dev**: https://mmbell.github.io/Sparrow.jl/dev/

## Troubleshooting

### Missing Dependencies

If you get errors about missing packages, run:

```bash
cd docs
julia --project -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'
```

### Build Errors

Common issues:

1. **Missing docstrings**: Add docstrings to exported functions
2. **Broken cross-references**: Check that `@ref` links point to valid functions
3. **Syntax errors in markdown**: Validate markdown syntax

### Testing Documentation Build

Before pushing, always test that the documentation builds successfully:

```bash
cd docs
julia --project make.jl
```

Check for any warnings or errors in the output.

## Additional Resources

- [Documenter.jl Documentation](https://juliadocs.github.io/Documenter.jl/stable/)
- [Julia Manual: Documentation](https://docs.julialang.org/en/v1/manual/documentation/)
- [Markdown Guide](https://www.markdownguide.org/)