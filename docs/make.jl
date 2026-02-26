using Sparrow
using Documenter

DocMeta.setdocmeta!(Sparrow, :DocTestSetup, :(using Sparrow); recursive=true)

makedocs(;
    modules=[Sparrow],
    authors="Michael Bell <mmbell@colostate.edu> and contributors",
    repo="https://github.com/csu-tropical/Sparrow.jl/blob/{commit}{path}#{line}",
    sitename="Sparrow.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://csu-tropical.github.io/Sparrow.jl",
        edit_link="main",
        assets=String[],
        repolink="https://github.com/csu-tropical/Sparrow.jl",
    ),
    pages=[
        "Home" => "index.md",
        "Getting Started" => "getting_started.md",
        "Workflow Guide" => "workflow_guide.md",
        "Provided Workflow Steps" => "provided_steps.md",
        "Examples" => "examples.md",
        "API Reference" => "api.md",
    ],
    warnonly = [:missing_docs, :cross_references],
)

deploydocs(;
    repo="github.com/csu-tropical/Sparrow.jl",
    devbranch="main",
    push_preview=true,
)