using Sparrow
using Documenter

DocMeta.setdocmeta!(Sparrow, :DocTestSetup, :(using Sparrow); recursive=true)

makedocs(;
    modules=[Sparrow],
    authors="Michael Bell <mmbell@colostate.edu> and contributors",
    sitename="Sparrow.jl",
    format=Documenter.HTML(;
        canonical="https://mmbell.github.io/Sparrow.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/mmbell/Sparrow.jl",
    devbranch="main",
)
