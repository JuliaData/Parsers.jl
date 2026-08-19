using Documenter
using Parsers

DocMeta.setdocmeta!(
    Parsers,
    :DocTestSetup,
    :(begin
        import Parsers
        using Dates
    end);
    recursive=true,
)

makedocs(
    sitename="Parsers.jl",
    authors="JuliaData contributors",
    modules=[Parsers],
    clean=true,
    doctest=true,
    checkdocs=:none,
    warnonly=false,
    pagesonly=true,
    format=Documenter.HTML(
        canonical="https://JuliaData.github.io/Parsers.jl/stable/",
        edit_link="main",
        prettyurls=true,
        repolink="https://github.com/JuliaData/Parsers.jl",
    ),
    pages=[
        "Home" => "index.md",
        "Public API" => "api.md",
        "Low-level kernels" => "kernels.md",
        "Migrate from Parsers 2" => "migration.md",
    ],
)

deploydocs(
    repo="github.com/JuliaData/Parsers.jl.git",
    devbranch="main",
    push_preview=true,
)
