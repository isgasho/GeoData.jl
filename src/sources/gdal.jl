using .ArchGDAL

const AG = ArchGDAL

export GDALarray, GDALstack, GDALarrayMetadata, GDALdimMetadata

const GDAL_LON_ORDER = Forward()
const GDAL_LAT_ORDER = Reverse()
const GDAL_BAND_ORDER = Forward()
const GDAL_RELATION = Forward()


# Metadata ########################################################################

"""
    GDALmetadata(val::Dict)

[`Metadata`](@ref) wrapper for `GDALarray` dimensions.
"""
struct GDALdimMetadata{K,V} <: DimMetadata{K,V}
    val::Dict{K,V}
end

"""
    GDALarrayMetadata(val::Dict)

[`Metadata`](@ref) wrapper for `GDALarray`.
"""
struct GDALarrayMetadata{K,V} <: ArrayMetadata{K,V}
    val::Dict{K,V}
end


# Array ########################################################################

"""
    GDALarray(filename; 
              usercrs=nothing, 
              name="", 
              dims=nothing, 
              refdims=(), 
              metadata=nothing, 
              missingval=nothing)

Load a file lazily using gdal. `GDALarray` will be converted to [`GeoArray`](@ref) 
after indexing or other manipulations. `GeoArray(GDALarray(filename))` will do this
immediately.

`GDALarray`s are always 3 dimensional, and have [`Lat`](@ref), [`Lon`](@ref) and
[`Band`](@ref) dimensions.

## Arguments

- `filename`: `String` pointing to a grd file. Extension is optional.

## Keyword arguments

- `usercrs`: CRS format like `EPSG(4326)` used in `Selectors` like `Between` and `At`, and 
  for plotting. Can be any CRS `GeoFormat` from GeoFormatTypes.jl, like `WellKnownText`.
- `name`: `String` name for the array.
- `dims`: `Tuple` of `Dimension`s for the array. Detected automatically, but can be passed in.
- `refdims`: `Tuple of` position `Dimension`s the array was sliced from.
- `missingval`: Value reprsenting missing values. Detected automatically when possible, but 
  can be passed it.
- `metadata`: [`Metadata`](@ref) object for the array. Detected automatically as
  [`GDALarrayMetadata`](@ref), but can be passed in.

# Example

```julia
A = GDALarray("folder/file.tif"; usercrs=EPSG(4326))
# Select Australia using lat/lon coords, whatever the crs is underneath.
A[Lat(Between(-10, -43), Lon(Between(113, 153)))
```
"""
struct GDALarray{T,N,F,D<:Tuple,R<:Tuple,Na<:AbstractString,Me,Mi,S
                } <: DiskGeoArray{T,N,D,LazyArray{T,N}}
    filename::F
    dims::D
    refdims::R
    name::Na
    metadata::Me
    missingval::Mi
    size::S
end
GDALarray(filename::AbstractString; kwargs...) = begin
    isfile(filename) || error("file not found: $filename")
    gdalread(filename) do raster
        GDALarray(raster, filename; kwargs...) 
    end
end
GDALarray(raster::AG.RasterDataset, filename, key=nothing; 
          usercrs=nothing, 
          dims=dims(raster, usercrs), 
          refdims=(),
          name="", 
          metadata=metadata(raster), 
          missingval=missingval(raster)) = begin
    sze = size(raster)
    T = eltype(raster)
    N = length(sze)
    GDALarray{T,N,typeof.((filename,dims,refdims,name,metadata,missingval,sze))...
       }(filename, dims, refdims, name, metadata, missingval, sze)
end

# AbstractGeoArray methods

"""
    Base.write(filename::AbstractString, ::Type{GDALarray}, A::AbstractGeoArray;
               driver="GTiff", compress="DEFLATE", tiled=true)

Write a [`GDALarray`](@ref) to file, `.tiff` by default, but other GDAL drivers also work.

GDAL flags `driver`, `compress` and `tiled` can be passed in as keyword arguments.

Returns `filename`.
"""
Base.write(filename::AbstractString, ::Type{<:GDALarray}, A::AbstractGeoArray{T,2}; kwargs...) where T = begin
    all(hasdim(A, (Lon, Lat))) || error("Array must have Lat and Lon dims")

    correctedA = permutedims(A, (Lon(), Lat())) |>
        a -> reorderindex(a, (Lon(GDAL_LON_ORDER), Lat(GDAL_LAT_ORDER))) |>
        a -> reorderrelation(a, GDAL_RELATION)
    checkarrayorder(correctedA, (GDAL_LON_ORDER, GDAL_LAT_ORDER))

    nbands = 1
    indices = 1
    gdalwrite(filename, correctedA, nbands, indices; kwargs...)
end
Base.write(filename::AbstractString, ::Type{<:GDALarray}, A::AbstractGeoArray{T,3}, kwargs...) where T = begin
    all(hasdim(A, (Lon, Lat))) || error("Array must have Lat and Lon dims")
    hasdim(A, Band()) || error("Must have a `Band` dimension to write a 3-dimensional array")

    correctedA = permutedims(A, (Lon(), Lat(), Band())) |>
        a -> reorderindex(a, (Lon(GDAL_LON_ORDER), Lat(GDAL_LAT_ORDER), Band(GDAL_BAND_ORDER))) |>
        a -> reorderrelation(a, GDAL_RELATION)
    checkarrayorder(correctedA, (GDAL_LON_ORDER, GDAL_LAT_ORDER, GDAL_BAND_ORDER))

    nbands = size(correctedA, Band())
    indices = Cint[1:nbands...]
    gdalwrite(filename, correctedA, nbands, indices; kwargs...)
end


# AbstractGeoStack methods

"""
    GDALstack(filenames; keys, kwargs...)
    GDALstack(filenames...; keys, kwargs...)
    GDALstack(filenames::NamedTuple; 
              window=(), 
              metadata=nothing, 
              childkwargs=(),
              refdims=())

Convenience method to create a DiskStack  of [`GDALarray`](@ref) from `filenames`.

Load a stack of files lazily from disk.

## Arguments

- `filenames`: A NamedTuple of stack keys and `String` filenames, or a `Tuple`, 
  `Vector` or splatted arguments of `String` filenames.

## Keyword arguments

- `keys`: Used as stack keys when a `Tuple`, `Vector` or splat of filenames are passed in.
- `window`: A `Tuple` of `Dimension`/`Selector`/indices that will be applied to the 
  contained arrays when they are accessed.
- `metadata`: Metadata as a [`StackMetadata`](@ref) object.
- `childkwargs`: A `NamedTuple` of keyword arguments to pass to the `childtype` constructor.
- `refdims`: `Tuple` of  position `Dimension` the array was sliced from.

## Example

Create a `GDALstack` from four files, that sets the child arrays `usercrs` value
when they are loaded.

```julia
files = (:temp="temp.tif", :pressure="pressure.tif", :relhum="relhum.tif")
stack = GDALstack(files; childkwargs=(usercrs=EPSG(4326),))
stack[:relhum][Lat(Contains(-37), Lon(Contains(144))
```
"""
GDALstack(args...; kwargs...) =
    DiskStack(args...; childtype=GDALarray, kwargs...)

withsource(f, ::Type{<:GDALarray}, filename::AbstractString, key...) =
    gdalread(f, filename)



# DimensionalData methods for ArchGDAL types ###############################

dims(raster::AG.RasterDataset, usercrs=nothing) = begin
    gt = try
        AG.getgeotransform(raster)
    catch
        GDAL_EMPTY_TRANSFORM
    end

    lonsize, latsize = size(raster)

    nbands = AG.nraster(raster)
    band = Band(1:nbands, mode=Categorical(Ordered()))
    sourcecrs = crs(raster)

    lonlat_metadata=GDALdimMetadata()

    # Output Sampled index dims when the transformation is lat/lon alligned,
    # otherwise use Transformed index, with an affine map.
    if isalligned(gt)
        lonstep = gt[GDAL_WE_RES]
        lonmin = gt[GDAL_TOPLEFT_X]
        lonmax = lonmin + lonstep * (lonsize - 1)
        lonrange = LinRange(lonmin, lonmax, lonsize)

        latstep = gt[GDAL_NS_RES]
        latmax = gt[GDAL_TOPLEFT_Y]
        latmin = latmax + latstep * (latsize - 1)
        latrange = LinRange(latmax, latmin, latsize)

        # Spatial data defaults to area/inteval
        sampling = if gdalmetadata(raster.ds, "AREA_OR_POINT") == "Point"
            Points()
        else
            # GeoTiff uses the "pixelCorner" convention
            Intervals(Start())
        end

        latmode = Projected(
            order=Ordered(GDAL_LAT_ORDER, GDAL_LAT_ORDER, GDAL_RELATION),
            sampling=sampling,
            # Use the range step as is will be different to latstep due to float error
            span=Regular(step(latrange)),
            crs=sourcecrs,
            usercrs=usercrs,
        )
        lonmode = Projected(
            order=Ordered(GDAL_LON_ORDER, GDAL_LON_ORDER, GDAL_RELATION),
            span=Regular(step(lonrange)),
            sampling=sampling,
            crs=sourcecrs,
            usercrs=usercrs,
        )

        lon = Lon(lonrange; mode=lonmode, metadata=lonlat_metadata)
        lat = Lat(latrange; mode=latmode, metadata=lonlat_metadata)

        DimensionalData._formatdims(map(Base.OneTo, (lonsize, latsize, nbands)), (lon, lat, band))
    else
        error("Rotated/transformed dimensions are not handled yet. Open a github issue for GeoData.jl if you need this.")
        # affinemap = geotransform_to_affine(geotransform)
        # x = X(affinemap; mode=TransformedIndex(dims=Lon()))
        # y = Y(affinemap; mode=TransformedIndex(dims=Lat()))

        # formatdims((lonsize, latsize, nbands), (x, y, band))
    end
end

missingval(raster::AG.RasterDataset, args...) = begin
    band = AG.getband(raster.ds, 1)
    missingval = AG.getnodatavalue(band)
    T = AG.pixeltype(band)
    try
        missingval = convert(T, missingval)
    catch
        @warn "No data value from GDAL $(missingval) is not convertible to data type $T. `missingval` is probably incorrect."
    end
    missingval
end

metadata(raster::AG.RasterDataset, args...) = begin
    band = AG.getband(raster.ds, 1)
    # color = AG.getname(AG.getcolorinterp(band))
    scale = AG.getscale(band)
    offset = AG.getoffset(band)
    # norvw = AG.noverview(band)
    units = AG.getunittype(band)
    path = first(AG.filelist(raster))
    meta = AG.metadata(raster.ds)
    GDALarrayMetadata(Dict("filepath"=>path, "scale"=>scale, "offset"=>offset, "units"=>units))
end

# metadata(raster::RasterDataset, key) = begin
#     regex = Regex("$key=(.*)")
#     i = findfirst(f -> occursin(regex, f), meta)
#     if i isa Nothing
#         nothing
#     else
#         match(regex, meta[i])[1]
#     end
# end

crs(raster::AG.RasterDataset, args...) =
    WellKnownText(GeoFormatTypes.CRS(), string(AG.getproj(raster.ds)))


# Utils ########################################################################

gdalmetadata(dataset::AG.Dataset, key) = begin
    meta = AG.metadata(dataset)
    regex = Regex("$key=(.*)")
    i = findfirst(f -> occursin(regex, f), meta)
    if i isa Nothing
        nothing
    else
        match(regex, meta[i])[1]
    end
end

gdalread(f, filename::AbstractString) =
    AG.readraster(filename) do raster
        f(raster)
    end

gdalwrite(filename, A, nbands, indices; driver="GTiff", compress="DEFLATE", tiled=true) = begin
    tiledstring = tiled isa Bool ? (tiled ? "YES" : "NO") : tiled
    options = driver == "GTiff" ? ["COMPRESS=$compress", "TILED=$tiledstring"] : String[]

    AG.create(filename;
        driver=AG.getdriver(driver),
        width=size(A, Lon()),
        height=size(A, Lat()),
        nbands=nbands,
        dtype=eltype(A),
        options=options,
    ) do dataset
        # Convert the dimensions to `Projected` if they are `Converted`
        # This allows saving NetCDF to Tiff
        lon, lat = map(dims(A, (Lon(), Lat()))) do d
            convertmode(Projected, d)
        end
        @assert indexorder(lat) == GDAL_LAT_ORDER
        @assert indexorder(lon) == GDAL_LON_ORDER
        # Set the index loci to the start of the cell for the lat and lon dimensions.
        # NetCDF or other formats use the center of the interval, so they need conversion.
        lonindex, latindex = map((lon, lat)) do d
            val(shiftindexloci(Start(), d))
        end
        # Get the geotransform from the updated lat/lon dims
        geotransform = build_geotransform(latindex, lonindex)
        # Convert projection to a string of well known text
        proj = convert(String, convert(WellKnownText, crs(lon)))

        # Write projection, geotransform and data to GDAL
        AG.setproj!(dataset, proj)
        AG.setgeotransform!(dataset, geotransform)
        AG.write!(dataset, data(A), indices)
    end
    return filename
end

#= Geotranforms ########################################################################

See https://lists.osgeo.org/pipermail/gdal-dev/2011-July/029449.html

"In the particular, but common, case of a “north up” image without any rotation or
shearing, the georeferencing transform takes the following form" :
adfGeoTransform[0] /* top left x */
adfGeoTransform[1] /* w-e pixel resolution */
adfGeoTransform[2] /* 0 */
adfGeoTransform[3] /* top left y */
adfGeoTransform[4] /* 0 */
adfGeoTransform[5] /* n-s pixel resolution (negative value) */
=#

const GDAL_EMPTY_TRANSFORM = [0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
const GDAL_TOPLEFT_X = 1
const GDAL_WE_RES = 2
const GDAL_ROT1 = 3
const GDAL_TOPLEFT_Y = 4
const GDAL_ROT2 = 5
const GDAL_NS_RES = 6

isalligned(geotransform) =
    geotransform[GDAL_ROT1] == 0 && geotransform[GDAL_ROT2] == 0

geotransform_to_affine(gt) = begin
    AffineMap([gt[GDAL_WE_RES] gt[GDAL_ROT1]; gt[GDAL_ROT2] gt[GDAL_NS_RES]],
              [gt[GDAL_TOPLEFT_X], gt[GDAL_TOPLEFT_Y]])
end

build_geotransform(lat, lon) = begin
    gt = zeros(6)
    gt[GDAL_TOPLEFT_X] = first(lon)
    gt[GDAL_WE_RES] = step(lon)
    gt[GDAL_ROT1] = 0.0
    gt[GDAL_TOPLEFT_Y] = first(lat)
    gt[GDAL_ROT2] = 0.0
    gt[GDAL_NS_RES] = step(lat)
    return gt
end
