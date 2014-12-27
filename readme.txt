Harpoon TPC/ONC plotter

# chart datum file (datum.yaml)

The plotter translates from latitude and longitude values to the
Lambert Conformal Conic projection used on the TPCs and ONCs. This
requires a mildly complex transformation, with a set of parameters
that differ for each chart (they're also dependent on the specific
scan).

To get these numbers for a chart, open the image file in an editor
that lets you see absolute pixel coordinates (I use The GIMP in "draw"
mode). Pick four points: top left [a], top middle [b], top right [c],
along the same curved parallel of latitude, and bottom left [d] on the
same longitude as top left. They don't have to be right at the edge; I
generally use the nearest whole number of degrees that's on the map.
You can use different labels; just change the latline and lonline
entries accordingly. For southern latitudes, you can invert the "top"
and "bottom" points or not, as you please. (I generally do.)

Record for each of these points the latitude and longitude (a,o) and
the pixel position (x,y).

Also record the standard parallels of the projection, which are
generally noted at the bottom left of the chart, as par1 and par2.
(The formats dd-mm and dd-mm-ss will be understood.) Note that South
latitudes are not generally marked as such; they still need to be
recorded as negative numbers. Parallels are not used in the current
code.

The registration isn't perfect because the scans aren't perfect.

# ETOPO1 depth data: grid-centred bedrock, http://www.ngdc.noaa.gov/mgg/global/global.html via http://vterrain.org/Elevation/Bathy/

# data file format

Data are stored in a YAML file with two hashes: general and units. Use
example files as a baseline.

Wherever you need to specify a location, you can either give lat and
lon components, or use the loc format:

LAT,LON+RANGE@ANGLE

which will be written out as lat/long when it changes.

## drawing objects

Drawing objects can have the types:

circle (needs lat/lon/loc or uses unit's, radius)
box (needs n, s, e, w boundaries)
path (needs segments)
icon (needs file)
arc (needs lat/lon/loc or uses unit's, radius, startangle, endangle, optional minradius)

segments:
move (first only)
line
arc (lat/lon/loc is centre, angle is terminating angle)
close (closes the shape)

You need to specify a "colour" (though objects attached to units
default to the unit's colour) and may specify a "border" colour
(ditto). Default alpha is 128 (50%). For a border only, specify alpha
0 or (for a path) don't close the shape. For shading only, specify
border colour "null".

For drawing objects that are anchored to units, you may use "me" in a
loc entry: this will use the location of the parent unit. "me" can
also be used as a base for offsets:

me+RANGE@ANGLE

## units

lat/lon/loc
type: surface, airborne, helicopter, submarine, missile, torpedo
class: (not used but recommended)
signature/radar: (not used but recommended)
size: (used for radar horizon calculations)

Air units

altitude: (m)
consumption: (kg/nm)
throttle: (multiplier)
maxspeed: (knot)

# plot

# order

maxspeed
consumption (base kg/nm)
throttle

# rangetab

size
