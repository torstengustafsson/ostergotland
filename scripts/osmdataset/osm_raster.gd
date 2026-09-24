class_name OsmRaster
extends RefCounted

## Renders OSM ways onto a single-channel mask image (paint-on-black:
## 1.0 where the feature is painted, 0.0 elsewhere). The shader can sample it
## via a uniform like any other mask texture.
##
## Projection uses the bounds passed in (usually the terrain bounds, which may
## be larger than the OSM download's own bounds) so the result lines up with
## the heightmap and water mask in world space.
##
## Image has no draw_line/fill_polygon in Godot 4.7, so these are implemented
## here with Bresenham lines and an even-odd scanline polygon fill.


## Paints `ways` onto a black Image of the given size. Closed polygons are
## filled when `fill_closed` is true (e.g. building footprints, water areas);
## otherwise (or for open ways) segments are stroked with `line_width`.
static func rasterize(dataset: OsmDataset, ways: Array[OsmWay], bounds: OsmBounds,
		width: int, height: int, fill_closed: bool = false, line_width: int = 1) -> Image:
	var img := Image.create(width, height, false, Image.FORMAT_L8)
	img.fill(Color.BLACK)

	for way in ways:
		if way.nd.size() < 2:
			continue

		var pts := pixel_points(dataset, way, bounds, width, height)

		if fill_closed and way.is_closed():
			_fill_polygon(img, pts, Color.WHITE)
			continue

		for i in pts.size() - 1:
			_draw_line(img, Vector2i(pts[i]), Vector2i(pts[i + 1]),
					Color.WHITE, line_width)

	return img


## Projects a way's node ids to pixel positions on an image of the given size
## covering `bounds`. Shared by rasterize() and OsmFeature.pixel_points().
static func pixel_points(dataset: OsmDataset, way: OsmWay, bounds: OsmBounds,
		width: int, height: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for ref in way.nd:
		var lon_lat: Vector2 = dataset.node_position(ref)
		var px: Vector2i = bounds.to_pixel(lon_lat.x, lon_lat.y, width, height)
		pts.append(Vector2(px))
	return pts


static func _draw_line(img: Image, a: Vector2i, b: Vector2i, color: Color, width: int) -> void:
	var x0: int = a.x
	var y0: int = a.y
	var x1: int = b.x
	var y1: int = b.y
	var dx: int = absi(x1 - x0)
	var dy: int = -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err: int = dx + dy

	var half := maxi((width - 1) / 2, 0)
	while true:
		_plot(img, x0, y0, color, half)
		if x0 == x1 and y0 == y1:
			break
		var e2: int = 2 * err
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy


## Fills a w x w square centred on (x, y), clamped to the image.
static func _plot(img: Image, x: int, y: int, color: Color, half: int) -> void:
	if half <= 0:
		img.set_pixel(x, y, color)
		return
	var from := Vector2i(x - half, y - half)
	var to := Vector2i(x + half, y + half)
	from.x = maxi(from.x, 0)
	from.y = maxi(from.y, 0)
	to.x = mini(to.x, img.get_width() - 1)
	to.y = mini(to.y, img.get_height() - 1)
	img.fill_rect(Rect2i(from, to - from + Vector2i.ONE), color)


## Even-odd scanline fill. `points` may include the duplicated closing vertex.
static func _fill_polygon(img: Image, points: PackedVector2Array, color: Color) -> void:
	if points.size() < 3:
		return
	var min_y := int(points[0].y)
	var max_y := int(points[0].y)
	for p in points:
		min_y = mini(min_y, int(p.y))
		max_y = maxi(max_y, int(p.y))

	for y in range(maxi(min_y, 0), mini(max_y, img.get_height() - 1) + 1):
		var xs := PackedFloat64Array()
		for i in points.size() - 1:
			var p0: Vector2 = points[i]
			var p1: Vector2 = points[i + 1]
			if p0 == p1:
				continue
			if (p0.y <= y and p1.y > y) or (p1.y <= y and p0.y > y):
				var t := (float(y) - p0.y) / (p1.y - p0.y)
				xs.append(p0.x + t * (p1.x - p0.x))
		xs.sort()
		for i in range(0, xs.size() - 1, 2):
			var xa := maxi(int(floor(xs[i])), 0)
			var xb := mini(int(ceil(xs[i + 1])), img.get_width() - 1)
			if xb > xa:
				img.fill_rect(Rect2i(xa, y, xb - xa, 1), color)
