"""
A `AbstractSampled` (from DimensionalData.jl) with projections attached.

Fields and behaviours are identical to `Sampled` with the addition of
`crs` and `usercrs` fields.

If both `crs` and `usercrs` fields contain crs data (in a GeoFormat wrapper 
from GeoFormatTypes.jl) the selector inputs and plot axes will be converted 
from and to the specified `usercrs` projection automatically. A common use case
would be to pass `usercrs=EPSG(4326)` to the constructor when loading eg. a GDALarray:

```julia
GDALarray(filename; usercrs=EPSG(4326))
```

The underlying `crs` will be detected by GDAL.

If `usercrs` is not supplied (ie. `isa Nothing`), the base index will be shown on plots, 
and selectors will need to use whatever format it is in.
"""
struct Projected{O<:Order,Sp,Sa,C,IC} <: AbstractSampled{O,Sp,Sa}
    order::O
    span::Sp
    sampling::Sa
    crs::C
    usercrs::IC
end
Projected(; order=Ordered(), span=UnknownSpan(), 
              sampling=Points(), crs, usercrs=nothing) =
    Projected(order, span, sampling, crs, usercrs)

crs(mode::Projected, dim) = crs(mode)
crs(mode::Projected) = mode.crs

usercrs(mode::Projected, dim) = usercrs(mode)
usercrs(mode::Projected) = mode.usercrs

rebuild(g::Projected, order=order(g), span=span(g), 
        sampling=sampling(g), crs=crs(g), usercrs=usercrs(g)) =
    Projected(order, span, sampling, crs, usercrs)