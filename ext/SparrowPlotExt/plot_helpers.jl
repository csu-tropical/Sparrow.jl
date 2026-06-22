# Shared helpers for the Fields-API plot steps.
#
# Plotters resolve field roles from the Daisho config (tags) rather than
# hardcoding names, and pull moment arrays from the Fields-API gridded readers
# (`Daisho.read_gridded_*(file, p::DaishoParameters)`), which return fields keyed
# by name and pre-shaped to the grid.

# Resolve a colormap parameter: a Symbol naming a registered ColorScheme maps to
# that scheme; anything else (a Makie built-in Symbol, a `Reverse(...)`, or a
# ColorScheme) passes through unchanged.
cmap(c) = (c isa Symbol && haskey(colorschemes, c)) ? colorschemes[c] : c

"""
    role_field(p, tag, plotname) -> String

Resolve the single field carrying role `tag` (e.g. `:define_detection`,
`:velocity`, `:define_scanned`) from the Daisho `[fields]` config, with a
plot-friendly error (naming the plot) when the tag is absent or ambiguous.
"""
function role_field(p, tag::Symbol, plotname::AbstractString)
    try
        return Daisho.field_with_tag(p, tag)
    catch e
        msg_error("$plotname requires exactly one field tagged `$tag` in the " *
                  "Daisho [fields] config. $(sprint(showerror, e))")
    end
end

"""
    masked(g, name, plotname) -> Matrix{Float32}

Fetch field `name` from a Fields-API reader result `g`, with both I/O sentinels
(`g.io.fill_value`, `g.io.undetect`) masked to `NaN` for display. Errors (naming
the plot) if the field is absent from the gridded file.
"""
function masked(g, name::AbstractString, plotname::AbstractString)
    haskey(g.fields, name) ||
        msg_error("$plotname: field \"$name\" not in gridded file; present: " *
                  "$(sort(collect(keys(g.fields))))")
    return Daisho.mask_sentinels(g.fields[name], g.io)
end

"""
    scanned_blanking(g, scanned_field) -> Array{Float64}

Build the "not-scanned" blanking raster from the `define_scanned` field's RAW
values: `NaN` (transparent) where the gate was scanned (value above the
`fill_value` sentinel — including undetect/clear-air), `0.0` (drawn as the blank
color) where it was never scanned. Uses the raw field, not the sentinel-masked
one, so scanned-but-no-echo gates stay transparent rather than blanked.
"""
function scanned_blanking(g, scanned_field::AbstractString)
    haskey(g.fields, scanned_field) ||
        msg_error("Blanking needs the `define_scanned` field \"$scanned_field\", " *
                  "absent from the gridded file.")
    return ifelse.(g.fields[scanned_field] .> Float32(g.io.fill_value), NaN, 0.0)
end

"""
    safe_contourf!(ax, x, y, z; kwargs...) -> plot or nothing

`contourf!` guarded against all-missing data. Makie's `contourf` throws deep in
`_group_polys` (a `KeyError`) when `z` has no finite values to contour — e.g. an
empty PPI sweep with no detections — which would otherwise abort a whole batch
run on a single dataless grid. Returns the contourf plot when there is something
to draw, or `nothing` when `z` is entirely non-finite (the panel is left empty).
"""
function safe_contourf!(ax, x, y, z; kwargs...)
    any(isfinite, z) || return nothing
    return contourf!(ax, x, y, z; kwargs...)
end

"""
    data_colorbar!(pos, plt; colormap, levels, ticks, label="") -> Colorbar

Place a Colorbar at layout position `pos` for a data panel. When `plt` is a real
plot (data was drawn) the colorbar derives from it. When `plt` is `nothing` (an
empty panel skipped by [`safe_contourf!`](@ref)) the colorbar is reconstructed
from `colormap`/`levels` so the figure layout and color scale stay consistent.
Pass the same `colormap` value handed to `contourf!`.
"""
function data_colorbar!(pos, plt; colormap, levels, ticks, label = "")
    plt === nothing || return Colorbar(pos, plt; ticks = ticks, label = label)
    lvls = collect(levels)
    return Colorbar(pos; colormap = colormap,
        limits = (first(lvls), last(lvls)), ticks = ticks, label = label)
end
