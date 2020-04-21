# These methods are only available if ArchGDAL is loaded.
# Otherwise ProjectedIndex selector crs field must be `nothing`,
# and no reprojection can occur.

sel2indices(mode::ProjectedIndex, dim::Dimension, sel::Contains{<:Number}) = begin
    selval = reproject(usercrs(mode), crs(mode), dim, val(sel))
    DD.contains(dim, rebuild(sel, selval))
end
sel2indices(mode::ProjectedIndex, dim::Dimension, sel::At{<:Number}) = begin
    selval = reproject(usercrs(mode), crs(mode), dim, val(sel))
    DD.at(dim, rebuild(sel, selval))
end
sel2indices(mode::ProjectedIndex, dim::Dimension, sel::Between) = begin
    selval = map(v -> reproject(usercrs(mode), crs(mode), dim, v), val(sel))
    DD.between(dim, rebuild(sel, selval))
end

reproject(source, target, dim::Dimension, val) = val
reproject(source::GeoFormat, target::GeoFormat, dim::Lon, val::Number) =
    ArchGDAL.reproject([(zero(val), val)], source, target)[1][1]
reproject(source::GeoFormat, target::GeoFormat, dim::Lat, val::Number) =
    ArchGDAL.reproject([(val, zero(val))], source, target)[1][2]

reproject(source::GeoFormat, target::GeoFormat, dim::Lon, vals::AbstractArray) =
    first.(ArchGDAL.reproject([(zero(v), v) for v in vals], source, target))
reproject(source::GeoFormat, target::GeoFormat, dim::Lat, vals::AbstractArray) =
    last.(ArchGDAL.reproject([(v, zero(v)) for v in vals], source, target))