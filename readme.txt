Skutil - Harpoon chart plotter and utility software

# Introduction

This is not a neat integrated software package. This is several lumps
of command-line code, linked together by data files in a structured
format (YAML). You will need to edit data files by hand to use this
code at all. Also, my design goal is to be a referee with computer
assistance, not to recreate computer Harpoon, so I've deliberately not
automated some processes.

Also I run this on a Linux system. It'll probably work on Windows or
MacOS boxes with perl, but I have no access to such machines and no
way of coding for them.

Very broadly:

"plot" plots ship positions in a data file, producing images and HTML
files to be sent to players.

"order" processes movement orders, advancing positions by a set
timespan.

"rangetab" produces an HTML table of ranges and bearings between
units, including radar horizon information.

"sonartab" (under development) prints sonar detection information.

A turn's workflow would typically look like:

- receive player orders
- decide turn length
- code any new player orders into data file
- run "orders" to get new data file (this is the actual movement phase)
- resolve any attacks
- work out detections ("rangetab")
- modify new data file for detection information
- run "plot" to generate maps for one or both sides
- send out maps, wait for orders

## Other things you will need (free)

Perl

Perl modules Geo::Ellipsoid, HTML::Template, Imager, YAML::XS

Download TPC or ONC charts from the collection at
http://www.lib.utexas.edu/maps/tpc/ or
http://www.lib.utexas.edu/maps/onc/ . I rename them so that
"http://www.lib.utexas.edu/maps/tpc/txu-pclmaps-oclc-22834566_b-2a.jpg"
becomes "TPC/b-2a.jpg". These should all live under "maps" in the
working directory.

Download ETOPO1 data set from
http://www.ngdc.noaa.gov/mgg/global/global.html (specifically the
grid-registered bedrock version,
http://www.ngdc.noaa.gov/mgg/global/relief/ETOPO1/data/bedrock/grid_registered/binary/etopo1_bed_g_f4.zip
at the time of writing). Extract the file so that
maps/ETOPO1/etopo1_bed_g_f4.flt is under the working directory.

## chart datum file (datum.yaml)

The plotter translates from latitude and longitude values to the
Lambert Conformal Conic projection used on the TPCs and ONCs. This
requires a mildly complex transformation, with a set of parameters
that differ for each chart (they're also dependent on the specific
scan).

I haven't derived these numbers for every chart in the set, only the
ones I've thought about running games on.

To get these numbers for a new chart, open the image file in an editor
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

Thus one chart entry looks like:

TPC/c-2b:
  latline: a b c
  lonline: a d
  a:
    a: 72
    o: 23
    x: 2054
    y: 329
  b:
    a: 72
    o: 29
    x: 4652
    y: 451
  c:
    a: 72
    o: 39
    x: 8938
    y: 88
  d:
    a: 68
    o: 23
    x: 1490
    y: 5922
  par1: 65-20
  par2: 70-40

If you're feeling kind, send back your new chart registration data and
I'll add them to future releases.

The registration isn't perfect because the scans aren't perfect.

# data file format

Data are stored in a YAML file with two hashes: general and units.

## General hash

general:
  chart: TPC/h-6c <- you can omit this to plot on a plain blue field
                     or set to "osm" to use OpenStreetMap tiles
  draw:           <- see "drawing objects" below
    - type: circle
      radius: 60
      lat: 28.079584
      lon: 48.610972
      colour: DarkSeaGreen3
  orders:
    VDQ: 300 S45  <- see "orders" below
  side:           <- list of sides in the game
    Canadian:
      colour: blue      <- see "colours" below
      keyword: headway  <- pick a random word
      style: friendly   <- "friendly", "neutral", "enemy"
    Iranian:
      colour: red
      keyword: footgear
      style: hostile
  time: 825573600      <- unixtime of this file
  timezone: Asia/Dubai <- standard timezone (IANA zone name)
  turn: intermediate   <- change this to "tactical", "engagement", or
                          a number of seconds

Why would you use OpenStreetMap or a plain field rather than charts?
Because you haven't downloaded that chart, because the engagement
takes place in an area the charts don't cover, because the scenario is
more modern than the 1980s-1990s era of the free TPCs, or because the
chart borders are inconveniently placed for the scenario you're
running.

The random words are used so that charts can be uploaded to a web
server without their names being obvious and predictable - so the URL
can be sent to the player who needs to see it, without needing access
controls to prevent other players from stumbling over it accidentally.

You can get a unixtime with the date command:

$ TZ=Asia/Dubai date -d "29 feb 1996 10am" +%s
825573600

The "engagement" turn length is taken as 15 seconds, representing a
single movement phase.

## Units hash

units:
  Canadian:                    <- must match an entry in the side list
  - HMCS Ville de Québec:      <- name must be unique
      class: Halifax           <- not currently used
      course: 315              <- degrees true
      lat: 25.6
      lon: 52.6
      signature/radar: medium
      size: medium
      short: VDQ               <- optional
      speed: 12                <- knots
      type: surface

A unit _may_ have "style" and "colour" entries as in the side list;
otherwise it will use the default style and colour for that side.

If "short" is not given, the short code (used when plotting) will be
the first three letters of the unit's name. "foreignshort" will be
generated randomly when orders are processed if it's missing, and is
the code by which the unit will be known on other sides' maps.

type must be one of surface, airborne, helicopter, missile, submarine,
torpedo, or sonobuoy; this will determine the plotting icon as well as
some other characteristics.

size is used for radar line-of-sight calculations. signature/radar is
not currently used.

Air units must additionally have:

altitude: (m)

and if they use fuel (i.e. aircraft and helos but not missiles):

consumption: (kg/nm)
fuel: (kg)
throttle: (multiplier)
maxspeed: (knots; maximum non-afterburner speed at any altitude)

which are used to calculate fuel consumption (according to the rule
modification in Naval SITREP 25 p.15). You will need to set fuel
consumption multipliers (for speed, altitude, or clean/dirty state)
explicitly.

## locations

Wherever you need to specify a location, you can either give lat and
lon components, or use the loc format:

loc: LAT,LON+RANGE@ANGLE

which will be written out as lat/long when it changes.

# plot

plot takes one compulsory parameter: the name of the data file to
plot. By default it will produce a small plot (showing all known
units) and a large plot (showing the same information on a full map
sheet) for each side, the small plot zoomed appropriately to be
roughly 800 pixels wide. It will also generate an HTML file that links
the two together, and contains a table of ranges and bearings to known
targets.

If the general->chart parameter is missing from the data file, a plain
blue field will be used instead (with a Mercator-variant projection
rather than the Lambert Conformal Conic), and plotting will be much
faster. If the parameter is "osm", OpenStreetMap data will be
downloaded and used. All functions are still available in these modes,
though the larger plot is not generated.

Optional parameters:

-d 1 - plot depth with contour lines
-d 2 - plot depth with shading
-h 20 - limit track history to 20 minutes (default 30, 0 = off)
-s (sidename) - plot only for that side
-s all - plot a view of all units ignoring detection
-z 1 - don't expand the view

(Note that the S1, S2 and S3 depths are non-canonical expansions of
Shallow. In S2 water, submarines must surface; in S1, they may not
operate at all.)

# orders

Orders are written as a series of instructions separated by spaces,
all on one line. If there are orders still to be executed at the end
of the turn, they'll be carried forward, so you can write orders
arbitrarily far into the future.

100 - go 100 yards
12 - go 12 nautical miles (if >=100, yards is assumed)
50y - go 50 yards
200M - go 200 nautical miles
45kt - change speed to 45 knots
P45 / L45 / S45 / R45 - immediately turn that many degrees port/left
                        or starboard/right
115T - change course to 115 degrees true
15s - continue for 15 seconds
3m - continue for 3 minutes
A+20 - climb 20 metres
A-20 - descend 20 metres
A200 - snap to altitude 200m
A2000/150 - move to altitude 2000m at 150m per 15 seconds (continuing)
Ditto for depth (D) (+ descends, - ascends)
T1.5 - change fuel consumption rate to 1.5x base
T0.6 - change fuel consumption rate to 1/0.6x base
alert - print a warning message when processed
^cDEW - change course to face DEW (continuing)
^iDEW - change course to intercept DEW (continuing)
^25.5,52.5,10 - continue towards 25.5N,52.5E until within 10nm (continuing)

The "^c" intercept simply faces the unit to where its target was at
the start of the turn; the "^i" one calculates the correct course for
a minimum-time intercept assuming the target doesn't change course or
speed. (It may fail, if the moving unit is too slow and too far out of
position to intercept the target.)

Why would you want the "go towards lat/long" mode, rather than just
setting a course? Because on a sphere a course of constant bearing is
not a straight line, and if you're going a long distance in a straight
line your bearing will change as you go. (And the same applies if you
have an aircraft heading home to its carrier - give an intercept
order, and it'll keep on track no matter how the carrier changes
course and speed.)

Note that turn calculations aren't done automatically: if a medium
ship on course 090 wants to turn to 330 at standard rudder, you need
to put this in as:

300 P45 300 P45 300 330T

("go 300 yards", "turn to port 45 degrees", etc., until at last "turn
to course 330")

Similarly, the system doesn't try to account for limited acceleration
or altitude/depth change rate of ships or aircraft.

A unit that runs out of orders will continue on the same course and speed.

## colours

## drawing objects

Drawing objects can have the types:

circle (needs lat/lon/loc, radius)
box (needs n, s, e, w boundaries)
path (needs segments, see below)
icon (needs lat/lon/loc, image filename)
arc (needs lat/lon/loc, radius, anglestart, angleend, optional minradius)

So for example if you want to plot an ESM or sonar contact:

- type: arc
  radius: 40
  anglestart: 75
  angleend: 76

segments can be:
move (first only; lat/lon/loc)
line (lat/lon/loc)
arc (lat/lon/loc is centre, angle is terminating angle)
close (closes the shape)

Where an object type needs a lat/lon or loc, it will default to the
unit's own location. You can use offsets: me+RANGE@ANGLE.

The "arc" segment is a bit complex to use. The point that the path has
reached is the start point; the location specified is the centre of
the circle; the angle defines the end point.

You need to specify a "colour" (though objects attached to units
default to the unit's colour, which defaults to the side's colour) and
may specify a "border" colour (ditto). Default alpha is 128 (50%). For
a border only, specify alpha 0 or (for a path) don't close the shape.
For shading only, specify border colour "null".

## units

# order

# rangetab

size

# sonartab
