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

NEXT STEPS
1. Turn this into a module with an exportable entrypoint that takes an image and returns ({({x, y}), ...})
2. Generate and save a hull for every image uploaded to the Pile of Pics
3. Make use of these hulls in the pile itself. Note that the vertices need to be clockwise, so reverse the array
   This should be an alternative to Rectangle and Circle, which will continue to behave as they now do.
4. Maybe figure out a hull simplification algorithm to reduce the number of vertices? Provide that as an option
   to the end user - more vertices will mean cleaner-looking collisions, but may impact framerate. Measure first;
   it's possible that the cost is actually irrelevant. It's also possible that there doesn't need to be any
   granularity between "detect the hull properly" and "use a rectangle/circle" - if frame rate is a problem,
   select a simplified hull directly.
5. Ensure that changing the shape type will correctly replace all elements (should already be the case but confirm).

Can we draw the full extent of the search line at each point where it finds a new vertex? Would be dense in the
regions where the hull is curved, but still probably okay. Would make a cool animation.

What if the search line is drawn in a hue that corresponds to the atan2 of the search angle?
*/

constant emote = "https://static-cdn.jtvnw.net/emoticons/v2/390023/static/light/3.0";

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
	//Image.Image base = Image.JPEG.decode(Stdio.read_file("../CJAPrivate/FanartProjects/CandiCatSakura2022_ColoringPage.jpg"));
	//mapping img = (["image": base, "alpha": base->invert()]);
	//Ignore the image and work with the alpha
	Image.Image searchme = img->alpha->threshold(5);
	//Optionally crop away what we don't need. Probably not long-term necessary?
	//array ac = searchme->find_autocrop();
	//searchme = searchme->copy(@ac); img->alpha = img->alpha->copy(@ac); img->image = img->image->copy(@ac);
	int xlim = searchme->xsize(), ylim = searchme->ysize();
	//Image.Image hull = Image.Image(xlim, ylim);
	//~ Image.Image hull = searchme->copy();
	Image.Image hull = img->image->copy();
	//First, find a starting pixel P1.
	System.Timer tm = System.Timer();
	array|zero P1 = topleft_pixel(searchme, xlim, ylim);
	if (!P1) exit(1, "Entirely transparent image\n"); //Algorithm not useful, probably stick with a full-size hull or something.
	array Q = ({0, P1[1]});
	array P = ({P1});
	//Scan down the left border
	while (Q[1] < ylim - 1) {
		Q[1]++;
		array Pn = scan_line(searchme, xlim, ylim, P[-1], Q, hull);
		if (Pn) P += ({Pn});
	}
	//Scan across the bottom border
	while (Q[0] < xlim - 1) {
		Q[0]++;
		array Pn = scan_line(searchme, xlim, ylim, P[-1], Q, hull);
		if (Pn) P += ({Pn});
	}
	//Scan up the right border
	while (Q[1] > 0) {
		Q[1]--;
		array Pn = scan_line(searchme, xlim, ylim, P[-1], Q, hull);
		if (Pn) P += ({Pn});
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
				if (Pn[0] != P1[0]) P += ({Pn});
				break;
			}
			P += ({Pn});
		}
	}
	//werror("All pixels %O\n", P);
	werror("Found %d-segment hull in %.3fs\n", sizeof(P), tm->peek());
	hull->setcolor(255, 0, 128);
	for (int i = 1; i < sizeof(P); ++i) {
		hull->line(@P[i-1], @P[i]);
		img->alpha->line(@P[i-1], @P[i], 255, 255, 255);
	}
	if (sizeof(P) > 1) {
		hull->line(@P[-1], @P[0]);
		img->alpha->line(@P[-1], @P[0], 255, 255, 255);
	}
	Stdio.write_file("hull.png", Image.PNG.encode(hull, (["alpha": img->alpha])));
}
