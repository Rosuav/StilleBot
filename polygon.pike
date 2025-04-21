/*
Desire: Take any PNG with transparency, and derive a convex hull for it.
This should be able to take any arbitrary image and get some sort of hull, but it's okay
if the hull isn't fully detailed. This will be used for simple collision detection, and
it's better to be simple than perfect.

Current theory: Crop to the bounding box, then remove one triangle from each corner such
that all removed pixels were transparent. This will give an octagon (at most - if a corner
can't be cut, it will be left square), which in theory should neatly contain the pixels
of interest.

Current practice: The 45 deg line seems to be working but others not so much.

Need to test and visualize, or maybe just abandon this algorithm and find something better.

This will eventually be incorporated into chan_pile.pike so that, when you upload an image
to use as an object, it gets a plausible hull.
*/

constant emote = "https://static-cdn.jtvnw.net/emoticons/v2/390023/default/light/3.0";

void find_triangle(Image.Image img, int basex, int basey, int dx, int dy, int limitx, int limity) {
	if (img->getpixel(basex, basey)[0]) return;
	if (img->getpixel(basex + dx, basey)[0]) return;
	if (img->getpixel(basex, basey + dy)[0]) return;
	int x = basex + dx, y = basey + dy;
	while (x != limitx && y != limity) {
		x += dx; y += dy;
		//Scan the line from (basex, y) to (x, basey)
		//If we hit any non-transparent pixel, break.
		//Simplification: This is a 45 degree line, and no fanciness is needed.
		int safe = 1;
		for (int tx = x, ty = basey; ty != y; tx -= dx, ty += dy) {
			if (img->getpixel(tx, ty)[0]) {safe = 0; break;}
		}
		if (!safe) break;
	}
	x -= dx; y -= dy;
	write("At 45 degrees, got %d,%d\n", x, y);
	//Now, try to advance one of the coordinates at a time.
	/*while (x != limitx) {
		x += dx;
		int safe = 1;
		float ty = basey + 0.5, ratio = (float)(y - basey) / (x - basex);
		for (int tx = x; tx != basex; tx -= dx, ty += ratio) {
			if (img->getpixel(tx, (int)ty)[0]) {safe = 0; break;}
		}
		if (!safe) break;
	}
	x -= dx;
	write("Incrementing x: %d,%d\n", x, y);*/
	while (y != limity) {
		y += dy;
		int safe = 1;
		float tx = basex + 0.5, ratio = (float)(x - basex) / (y - basey);
		for (int ty = y; ty != basey; ty -= dy, tx += ratio) {
			if (img->getpixel((int)tx, ty)[0]) {safe = 0; break;}
		}
		if (!safe) break;
	}
	y -= dy;
	write("Incrementing y: %d,%d\n", x, y);
}

int main() {
	mapping img = Image.PNG._decode(Protocols.HTTP.get_url_data(emote));
	write("%O\n", img);
	//Mostly ignore the image and work with the alpha
	//Start with the bounding box. Everything outside that can be ignored.
	//TODO: Make sure there is at least some transparency around the image before doing this
	//Otherwise, there's nothing to do anyway
	Image.Image searchme = img->alpha->threshold(5);
	[int left, int top, int right, int bottom] = searchme->find_autocrop();
	write("Bounding box: %d,%d,%d,%d\n", left, top, right, bottom);
	//Attempt to find triangles that are fully transparent
	//If the corner pixel is transparent, and the two pixels adjacent to it are also,
	//expand a triangle from there until it hits something.
	find_triangle(searchme, left, top, 1, 1, right, bottom);
}
