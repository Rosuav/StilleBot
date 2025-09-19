/* Desire: Take any PNG with transparency, and derive a convex hull for it.
This should be able to take any arbitrary image and get some sort of hull, but it's okay
if the hull isn't fully detailed. This will be used for simple collision detection, and
it's better to be simple than perfect.

Using an algorithm from Digital Picture Processing by A. Rosenfeld and A. C. Kak, page 269, 1982,
as described in https://support.ptc.com/help/mathcad/r10.0/en/index.html#page/PTC_Mathcad_Help/example_convex_hull.html
1. Locate the topmost opaque pixel row and the leftmost opaque pixel in that row. (Or: Find the first pixel by reading order.) Call this P1.
2. Initial line is from P1 to the start of that row, calling that Q.
3. Rotate the line (P1->Q) counterclockwise until it encounters another opaque pixel. Call this P2....Pn.
4. Repeat this process until we reconnect with P1. At all times, the far pixel will be on the boundary of the image.
5. May need a colinearity test to simplify the hull, as it's possible that multiple consecutive pixels will be selected.

To rotate the line P->Q counterclockwise:
1. Increment the location of Q. If it's on the left edge of the image, move it down one pixel, etc.
2. Iterate from P to Q', as if drawing those pixels, using standard algorithms.

Note that, in effect, "rotating" the line is actually done by scanning Q around the perimeter of the image.
This will always start from the left edge, descending till it reaches the bottom, then proceed around; we
will always return to point P1 before "running out of image", and thus will never need to descend from the
top-left corner to re-find the original position of Q.

This will eventually be incorporated into chan_pile.pike so that, when you upload an image
to use as an object, it gets a plausible hull.
*/

constant emote = "https://static-cdn.jtvnw.net/emoticons/v2/390023/default/light/3.0";

array(int)|zero topleft_pixel(Image.Image searchme, int xlim, int ylim) {
	for (int y = 0; y < ylim; ++y)
		for (int x = 0; x < xlim; ++x)
			if (searchme->getpixel(x, y)[0]) return ({x, y});
}

//Scan from Q to P, returning the first opaque pixel found. Will never return P itself;
//if no other pixel is found, will return zero.
array(int)|zero scan_line(Image.Image searchme, int xlim, int ylim, array P, array Q, Image.Image hull) {
	int dx = P[0] - Q[0], dy = P[1] - Q[1];
	if (!dx && !dy) return 0; //Pn is actually on the boundary. Step to the next pixel.
	if (abs(dx) > abs(dy)) {
		int epsilon = abs(65536 * dy / dx);
		int xsign = dx > 0 || -1, ysign = dy > 0 || -1;
		int y = Q[1], frac = 32768;
		for (int x = Q[0]; x != P[0]; x += xsign) {
			if (searchme->getpixel(x, y)[0]) return ({x, y});
			frac += epsilon;
			if (frac >= 65536) {frac -= 65536; y += ysign;}
		}
	} else {
		int epsilon = abs(65536 * dx / dy);
		int xsign = dx > 0 || -1, ysign = dy > 0 || -1;
		int x = Q[0], frac = 32768;
		for (int y = Q[1]; y != P[1]; y += ysign) {
			if (searchme->getpixel(x, y)[0]) return ({x, y});
			frac += epsilon;
			if (frac >= 65536) {frac -= 65536; x += xsign;}
		}
	}
}

float degrees(array to, array from) {
	return atan2(to[1] - from[1] + 0.0, to[0] - from[0] + 0.0) * 180 / 3.141592653589793;
}

int main() {
	mapping img = Image.PNG._decode(Protocols.HTTP.get_url_data(emote));
	//write("%O\n", img);
	//Ignore the image and work with the alpha
	Image.Image searchme = img->alpha->threshold(5);
	//Image.Image searchme = Image.JPEG.decode(Stdio.read_file("../CJAPrivate/FanartProjects/CandiCatSakura2022_ColoringPage.jpg"))->invert()->threshold(5);
	int xlim = searchme->xsize(), ylim = searchme->ysize();
	//Image.Image hull = Image.Image(xlim, ylim);
	//~ Image.Image hull = searchme->copy();
	Image.Image hull = img->image->copy();
	//First, find a starting pixel P1.
	array|zero P1 = topleft_pixel(searchme, xlim, ylim);
	if (!P1) exit(1, "Entirely transparent image\n"); //Algorithm not useful, probably stick with a full-size hull or something.
	werror("Got pixel %O\n", P1);
	array Q = ({0, P1[1]});
	array P = ({P1});
	//Scan down the left border
	while (Q[1] < ylim - 1) {
		Q[1]++;
		array Pn = scan_line(searchme, xlim, ylim, P[-1], Q, hull);
		if (Pn) {werror("LFound at %d,%d: %d,%d: %.0f\n", @Q, @Pn, degrees(Pn, Q)); P += ({Pn});}
	}
	//Scan across the bottom border
	while (Q[0] < xlim - 1) {
		Q[0]++;
		array Pn = scan_line(searchme, xlim, ylim, P[-1], Q, hull);
		if (Pn) {werror("BFound at %d,%d: %d,%d: %.0f\n", @Q, @Pn, degrees(Pn, Q)); P += ({Pn});}
	}
	//Scan up the right border
	while (Q[1] > 0) {
		Q[1]--;
		array Pn = scan_line(searchme, xlim, ylim, P[-1], Q, hull);
		if (Pn) {werror("RFound at %d,%d: %d,%d: %.0f\n", @Q, @Pn, degrees(Pn, Q)); P += ({Pn});}
	}
	//Scan across the top border. Note that, as soon as we find a point at the
	//same altitude as P1, we are done and can cut the hull across to close it.
	//There cannot be anything above this (because P1 is the topmost opaque
	//pixel), and so the hull must have a straight line here. Special case: If
	//the termination point is, in fact, P1 itself, don't add it again.
	while (Q[0] > 0) {
		Q[0]--;
		array Pn = scan_line(searchme, xlim, ylim, P[-1], Q, hull);
		if (Pn) {
			if (Pn[1] == P1[1]) {
				werror("Terminus at %d,%d: %d,%d: %.0f\n", @Q, @Pn, degrees(Pn, Q));
				if (Pn[0] != P1[0]) P += ({Pn});
				break;
			}
			werror("TFound at %d,%d: %d,%d: %.0f\n", @Q, @Pn, degrees(Pn, Q));
			P += ({Pn});
		}
	}
	//werror("All pixels %O\n", P);
	hull->setcolor(255, 0, 128);
	for (int i = 1; i < sizeof(P); ++i)
		hull->line(@P[i-1], @P[i]);
	if (sizeof(P) > 1) hull->line(@P[-1], @P[0]);
	Stdio.write_file("hull.png", Image.PNG.encode(hull));
}
