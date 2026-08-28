#charset utf-8
inherit http_websocket;
inherit annotated;

//Terminology note: Images (pixel art) come in three varieties.
//- An *icon* is used to create an *element* on a mockup. It can be any size, and the element can also resize that.
//- A *tile* is placed on a *grid* to form a background for the mockup. It is always 25x25.
//- A *grid* generally consists only of tiles and transparent cells, though colour cells are also valid.
//In the meta mapping, all three of these should always exist (meta.icons, meta.tiles, meta.grids) even if empty.
//All three are keyed by id. The values are all mappings with the following keys:
//- created_at, created_by - timestamp and Twitch user ID of the first time they were saved
//- xsize, ysize - dimensions in pixels
//- url - "data:image/png;base64," + the MIME-encoded PNG data for the image
//Grids additionally have the following:
//- grid - the original grid of tile names. Can be passed to encode_image to recreate the grid.
//         Notably, this references tiles by *name* rather than content, so updating a tile can update its grids.
//- cellx, celly - cell size. Currently always 25x25. Recorded on every grid in case flexibility is needed.
//- gridborder - if nonzero, a gap will be added between tiles (pixels)
//- gridcolor - if present, is an array [r,g,b] for the colour of the grid border. NOTE: If this is set but the
//         gridborder is zero, instead a single pixel dot will be set in the lower right of every cell, giving a
//         subtle alignment marker without consuming space.


constant markdown = #"# Mockups

<p id=status hidden></p>

<div id=spacer>
<div>Scene: <span id=scenebuttons></span></div>
<div id=modeselector>Mode:</div>
<div id=righttools></div>
</div>

<div id=sidebyside><div id=canvasscroll><canvas width=2700 height=1500></canvas></div><div id=elementlist></div></div>

> ### Edit element
> <fieldset id=positionselect></fieldset>
> <p id=imageselect>Image: <select id=imageselector></select> <input type=number id=xsize> x <input type=number id=ysize> <label class=gapbefore>Stack order <input type=number id=zgroup></label></p>
> <p id=bgselect>Background: <select id=bgselector></select></p>
>
> Name: <input id=elementtitle>
> <textarea id=elementdesc rows=5 cols=80></textarea>
>
> [Save](:type=submit) [Close](:.dialog_close) [Clone](:#cloneelement) [Delete](:#deleteelement)
{: tag=formdialog #editelementdlg}

<style>
/* Use all available space and then have scrolling internally instead */
main {
	max-width: unset;
	padding: 0 1.5em;
	position: fixed;
	inset: 0;
	display: flex;
	flex-direction: column;
}
#topbar {display: none;} /* Not relevant on this page, no need to waste the real estate */
#spacer {
	display: flex;
	justify-content: space-between;
}
#modeselector input {display: none;}
#modeselector svg {
	height: 1.5em;
	vertical-align: top;
	border: 3px outset lightgrey;
	margin-left: 3px;
}
#modeselector input:checked ~ svg {
	border-style: inset;
}
#cloneelement {
	background: #88ffff;
	margin-left: 1em;
}
#deleteelement {
	background: red;
	color: yellow;
	margin-left: 1em;
}
#sidebyside {
	border: 1px solid black;
	display: flex;
	gap: 0.5em;
	min-height: 0;
	flex: 1;
	margin-bottom: 1em; /* Bit of gap so you know you've reached the bottom */
}
#canvasscroll {
	flex-grow: 1;
	overflow: auto;
}
#elementlist {
	overflow-y: auto;
	min-width: fit-content;
	padding-bottom: 0.5em;
}
#elementlist li {text-wrap: nowrap;}
#elementlocked {display: none;}
#elementlocked ~ svg {
	height: 1.25em; width: 1.25em;
}
#elementlocked ~ #lockclosed {display: none;}
#elementlocked:checked ~ #lockopen {display: none;}
#elementlocked:checked ~ #lockclosed {display: inline;}
.gapbefore {margin-left: 40px;}
</style>
";

constant markdown_landing = #"# Mockups

You have the following mockups:

* loading...
{:#allmockups}

[Create new](:#create_mockup)

[Edit pixel art](mockup?pixelart)
";

constant markdown_pixelart = #"# Mockups - Pixel Art

> ### Import image
> Import from URL: <input type=url id=importurl>
>
> Import by uploading: <input class=fileuploader type=file accept=\"image/*\">
>
> <div class=filedropzone>Or drop a file here to import</div>
>
> [Import](:type=submit) [Cancel](:.dialog_close)
{: tag=formdialog #importdlg}

[Configure](:#configurebtn) [Resize](:.opendlg data-dlg=resizedlg) [Import](:.opendlg data-dlg=importdlg)
<table border=1 id=selections><tr><td>Current</td><td id=curcolor></td><td class=pickcolor data-color=>Transparent</td></tr></table>

> ### Custom Colors
> <ul id=colorlist></ul>
>
> [Save](:type=submit) [Cancel](:.dialog_close)
{: tag=formdialog #customcolordlg}

<table border=1 id=palette class=tileonly></table>
<table border=1 id=toolbox class=gridonly></table>

> ### Resize image
> Resize to: <input type=number id=xsize> x <input type=number id=ysize><br>
> <label><input type=radio checked name=mode> Crop/position</label>
> <label><input type=radio name=mode id=scale> Rescale</label>
> <label><input type=radio name=mode id=antialias> Antialias</label>
>
> [Resize](:type=submit) [Cancel](:.dialog_close)
{: tag=formdialog #resizedlg}

<table border=1 id=grid></table>

<style>
main {padding-bottom: 0.5em;}
/* Note that 'tile mode' also includes icons */
.tilemode .gridonly {display: none;}
.gridmode .tileonly {display: none;}
#imagelist li {display: none;}
#imagelist.showtype-tile li.type-tile {display: list-item;}
#imagelist.showtype-icon li.type-icon {display: list-item;}
#imagelist.showtype-grid li.type-grid {display: list-item;}
#gridconfig {display: none;}
.showtype-grid ~ #gridconfig {display: block;}
#imagelist::before {
	display: block;
	font-weight: bold;
}
#imagelist.showtype-tile::before {content: \"Tiles\";}
#imagelist.showtype-icon::before {content: \"Icons\";}
#imagelist.showtype-grid::before {content: \"Grids\";}
#selections {cursor: default; font-size: small;}
#grid {
	margin-top: 1em;
	margin-bottom: 0.5em; /* Bit of gap so you know you've reached the bottom */
	/* Checkerboard background so transparent pixels aren't the same as any single colour */
	background: repeating-conic-gradient(#ddd 0 25%, #fff 0 50%) 50% / 26px 26px;
}
td {
	width: 26px; height: 26px;
	min-width: 26px; min-height: 26px; /* Prevent the cells from imploding */
}
#management {width: 100%;}
#management td {vertical-align: top;}
#imagelist {
	max-height: 8em;
	overflow-y: auto;
}
</style>

> ### Configuration and management
> <p>Mode:
>     <label title=\"Icons form the basis of movable elements\"><input type=radio name=mode id=iconmode> Icon</label>
>     <label title=\"Tiles are used on grids\"><input type=radio name=mode id=tilemode> Tile</label>
>     <label title=\"Grids assemble tiles into a background\"><input type=radio name=mode id=gridmode> Grid</label>
> </p>
>
> <ul id=imagelist></ul>
>
> <p id=gridconfig>Grid:
> <label><input type=checkbox id=gridvisible>Visible</label>
> <input type=color id=gridcolor>
> <label>Thickness <input type=number minimum=0 id=gridborder> px</label>
> </p>
>
> <form id=saveimage method=dialog>Save as: <input name=savename required> <button type=submit>Save</button></form>
>
> [Close](:.dialog_close)
{: tag=dialog #configuredlg}
";

constant markdown_guest = #"# Mockups

You are not currently logged in. If someone has sent you a direct link to a
mockup to view or edit, check the URL to make sure it's correct; if you wish
to create a new mockup, you will need to [log in with a Twitch account](:.twitchlogin)

";

mapping meta_cache;

//Three-skew rotation done with no antialiasing, to preserve pixel values as precisely
//as possible. This gives somewhat odd results in some cases, but overall seems better
//than using the default img->rotate() which antialiases.
Image.Image pixel_skewy(Image.Image img, float inc) {
	Image.Image dest = Image.Image(img->xsize(), img->ysize() + (int)ceil(img->xsize() * abs(inc)));
	int ofs = inc < 0 && (int)(img->xsize() * -inc);
	for (int x = 0; x < img->xsize(); ++x) for (int y = 0; y < img->ysize(); ++y) {
		dest->setpixel(x, y + ofs + (int)(x * inc + 0.5), @img->getpixel(x, y));
	}
	return dest;
}

Image.Image pixel_skewx(Image.Image img, float inc) {
	Image.Image dest = Image.Image(img->xsize() + (int)ceil(img->ysize() * abs(inc)), img->ysize());
	int ofs = inc < 0 && (int)(img->ysize() * -inc);
	for (int x = 0; x < img->xsize(); ++x) for (int y = 0; y < img->ysize(); ++y) {
		dest->setpixel(x + ofs + (int)(y * inc + 0.5), y, @img->getpixel(x, y));
	}
	return dest;
}

Image.Image pixel_rotate(Image.Image img, int|float angle) {
	//Start with simple rotations to minimize error
	while (angle >= 45) {img = img->rotate_ccw(); angle -= 90;}
	while (angle <= -45) {img = img->rotate_cw(); angle += 90;}
	if (angle > 0.5 || angle < -0.5) {
		//The final rotation, between -45 and 45 degrees
		float angle = angle * 3.141592653589793 / 180.0;
		float yskew = -tan(angle/2);
		img = pixel_skewy(img, yskew);
		img = pixel_skewx(img, sin(angle));
		img = pixel_skewy(img, yskew);
	}
	return img;
}

mapping generate_snapshot(mapping mock, string|void scene, mapping(string:mapping)|void icon_cache) {
	if (!icon_cache) icon_cache = ([]);
	mapping sc = mock->scenes[scene];
	if (!sc) {
		//TODO: Call self recursively, generating per-scene images, then combine them into a PDF.
		//Share the icon_cache to speed things up
		sc = values(mock->scenes)[0]; //Pick one arbitrarily for now.
	}
	mapping bg = meta_cache->grids[mock->bg];
	int xsize = 1, ysize = 1;
	if (bg) {
		xsize = max(xsize, bg->xsize);
		ysize = max(ysize, bg->ysize);
		sscanf(bg->url, "data:image/png;base64,%s", string raw);
		bg = Image.PNG._decode(MIME.decode_base64(raw));
	}
	//Run over all the elements in this scene and figure out the required extents
	//(expanding xsize/ysize as needed).
	foreach (sc->elements; string id; mapping pos) {
		//TODO: Handle rotated images better. For simplicity, just use the max
		//of x and y for both.
		mapping el = mock->elements[id]; if (!el) continue;
		int sz = max(el->xsize, mock->ysize) / 2;
		xsize = max(xsize, pos->x + sz);
		ysize = max(ysize, pos->y + sz);
	}
	Image.Image image = Image.Image(xsize, ysize, 255, 255, 255), alpha = Image.Image(xsize, ysize);
	if (bg) {
		//Note that we draw a solid colour background first, then draw the bg image
		//over it. This means there'll be no transparency behind this image.
		//Alternatively, if it's better to have a constant colour behind everything,
		//select that colour as the default when constructing image, and select a
		//default of 255,255,255 when constructing alpha, and remove this box call.
		alpha->box(0, 0, bg->xsize, bg->ysize, 255, 255, 255);
		image->paste_mask(bg->image, bg->alpha, 0, 0);
	}
	array elements = (array)sc->elements;
	sort(elements[*][0], elements);
	foreach (elements, [string id, mapping pos]) {
		mapping el = mock->elements[id];
		if (!el) continue;
		mapping icon = icon_cache[el->image];
		if (!icon) {
			sscanf(meta_cache->icons[el->image]->?url || "!", "data:image/png;base64,%s", string raw);
			icon_cache[el->image] = icon = Image.PNG._decode(MIME.decode_base64(raw));
		}
		//Note that the scaling done here may not exactly match what's done in the front end,
		//eg as regards antialiasing.
		object img = icon->image, alp = icon->alpha;
		if (el->xsize != icon->xsize || el->ysize != icon->ysize) {
			img = img->scale(el->xsize, el->ysize);
			alp = alp->scale(el->xsize, el->ysize);
		}
		if (pos->angle) {
			//NOTE: This can enlarge the image, so subsequent "size" calculations
			//need to use the image object's size.
			//img = img->rotate(pos->angle); //Antialiased rotation
			//alp = alp->rotate(pos->angle);
			img = pixel_rotate(img, pos->angle); //Pixel-perfect (but sometimes wonky) rotation
			alp = pixel_rotate(alp, pos->angle);
		}
		alpha->paste_mask(alp, alp, pos->x - alp->xsize() / 2, pos->y - alp->ysize() / 2);
		image->paste_mask(img, alp, pos->x - img->xsize() / 2, pos->y - img->ysize() / 2);
	}
	return (["data": Image.PNG.encode(image, (["alpha": alpha])), "type": "image/png"]);
}

__async__ mapping(string:mixed)|string http_request(Protocols.HTTP.Server.Request req) {
	if (!meta_cache) meta_cache = await(G->G->DB->load_config(1, "mockup"));
	if (string id = req->variables->view) {
		//Ensure that the requested ID actually exists. This is not checked inside
		//websocket_validate as it doesn't allow asynchronicity, so if we didn't
		//check here, you'd get a successful connection with no useful data - not
		//very user-friendly. Note that this does not require authentication, even
		//for read-write functionality.
		mapping mock = await(G->G->DB->load_config(0, "mockup"))[id];
		if (mock) return render(req, (["vars": (["ws_group": id, "meta": meta_cache])]));
		//Otherwise fall through and show the landing page
	}
	if (string id = req->variables->snapshot) {
		//Take the existing mockup and generate an image for one of its scenes
		mapping mock = await(G->G->DB->load_config(0, "mockup"))[id];
		if (mock) return generate_snapshot(mock, req->variables->scene);
		//Otherwise fall through and show the landing page
	}
	if (string uid = req->misc->session->user->?id) {
		//If you're logged in, show your owned mockups.
		//Pixel art editing uses the same socket group as the landing page for simplicity
		int pa = !!req->variables->pixelart;
		return render(req, pa ? markdown_pixelart : markdown_landing, (["vars": ([
			"ws_group": "uid-" + uid,
			"ws_code": pa ? "mockup_pixelart.js" : "mockup_landing.js",
			"meta": meta_cache,
		])]));
	}
	return render_template(markdown_guest, ([]));
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->group)) return "String group only";
	if (sscanf(msg->group, "uid-%d", int uid) && uid) {
		if (uid != (int)conn->session->user->?id) return "That's not you";
		conn->landing = 1; //Mark that it's a user page, not a mockup
	}
}

mapping describe_mock(mapping mocks, string id) {
	mapping mock = mocks[id];
	if (!mock) mock = (["title": "<DELETED>"]); //Shouldn't happen, data has become inconsistent
	return (["id": id]) | (mock & (<"title", "created_at">));
}

__async__ mapping get_state(string group) {
	mapping mocks = await(G->G->DB->load_config(0, "mockup"));
	if (sscanf(group, "uid-%d", int uid) && uid) {
		mapping yourmocks = await(G->G->DB->load_config(uid, "mockup"));
		return (["allmocks": describe_mock(mocks, (yourmocks->allmocks || ({ }))[*])]);
	}
	mapping mock = mocks[group] || ([]);
	if (mock->deleted) return (["deleted": 1]); //When it's deleted, you can't see anything else about it. It's secretly maintained though.
	return mock;
}

__async__ mapping websocket_cmd_create_mockup(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->session->user->?id) return (["error": "Need to be logged in"]);
	string id;
	await(G->G->DB->mutate_config(0, "mockup") {mapping mocks = __ARGS__[0];
		//NOTE: If you attempt to clone but the ID is wrong, you just create a brand new one from scratch.
		//I could instead use conn->group rather than passing the ID back from the front end, but this
		//would result in an API of "if you do this from the landing page, it's a brand new thing, but if
		//you do it from a mockup, it clones", which is a tad weird. Clearer to have the front end request
		//the cloning of a specific ID.
		mapping old = mocks[msg->id] || ([]);
		do {id = replace(MIME.encode_base64(random_string(12)), (["/": "q", "+": "X"]));} while (mocks[id]);
		mocks[id] = ([
			//Defaults if not specified in the one being cloned
			"description": "Describe the purpose of your mockup here.",
			"mutate": "",
			"scenes": (["default": (["title": "New Scene"])]),
			"elements": ([]),
		]) | old | ([
			//Overrides that apply even if there was an existing one
			"created_at": time(),
			"created_by": conn->session->user->id,
			"title": old->title ? old->title + " Clone" : "New Mockup",
		]);
	});
	await(G->G->DB->mutate_config(conn->session->user->id, "mockup") {mapping mocks = __ARGS__[0];
		mocks->allmocks += ({id});
	});
	send_updates_all(conn->group);
	return (["cmd": "mockup_created", "id": id]);
}

__async__ mapping websocket_cmd_mutate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping mock = await(G->G->DB->load_config(0, "mockup"))[conn->group];
	if (msg->mutate != mock->mutate) return (["cmd": "error", "error": "Incorrect password"]);
	conn->mutate = msg->mutate;
	return (["cmd": "mutation", "allowed": 1]);
}

//Handle all mutators generically; they all need very similar handling.
//Note that the mutator itself must be synchronous; if it requires asynchronicity,
//don't use this shorthand (and probably don't use DB->mutate_config)
__async__ void websocket_msg(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	::websocket_msg(conn, msg);
	function f = this["wsedit_" + msg->?cmd]; if (!f) return;
	if (conn->landing || !conn->mutate) return;
	mapping|zero resp;
	await(G->G->DB->mutate_config(0, "mockup") {mapping mock = __ARGS__[0][conn->group];
		if (!mock || conn->mutate != mock->mutate) return;
		resp = f(mock, conn, msg);
	});
	send_updates_all(conn->group);
	if (resp) send_msg(conn, resp);
}

mapping|zero wsedit_clone_element(mapping mock, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!(<"scenes", "elements">)[msg->cat]) return (["error": "Bad cat"]); //Note that, unlike update_element, this does NOT handle cloning of mockups
	//If you started with "e42", the first guess is "e422", keeping the
	//clone near its original rather than sticking it at the end.
	mapping orig = mock[msg->cat][msg->id];
	if (!orig) return (["error": "Bad id"]);
	string newid;
	int i; for (i = 2; mock[msg->cat][newid = msg->id + i]; ++i);
	mapping new = mock[msg->cat][newid] = orig | ([]);
	if (new->title) new->title += " " + i;
	if (msg->cat == "elements") {
		//For every scene, find this element and offset it by a smidge,
		//and unlock it. This should make it easy to find and grab.
		foreach (values(mock->scenes), mapping sc) {
			if (!sc->elements || !sc->elements[msg->id]) continue;
			mapping pos = sc->elements[newid] = sc->elements[msg->id] | ([]);
			pos->x += 10; pos->y += 10;
			m_delete(pos, "locked");
		}
		return 0;
	}
	/* else if (msg->cat == "scenes") */ return (["cmd": "select_scene", "id": newid]);
}

mapping|zero wsedit_update_element(mapping mock, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!(<"mockup", "scenes", "elements">)[msg->cat]) return (["error": "Bad cat"]); //I would say "shouldn't happen", but everyone who lives with a cat knows that they can be bad. But we love 'em anyway.
	if (msg->_delete) {
		if (msg->cat == "mockup") {
			if (conn->session->user->?id != mock->created_by) return (["error": "Only the owner can delete a mockup"]);
			//Technically I lie on the front end when I say that it's irreversible.
			//But I'm a smidge paranoid... so I'm leaving a 404 marker behind.
			mock->deleted = time();
			//Remove it from the user's list. This happens AFTER the current mutate_config is done.
			G->G->DB->mutate_config(mock->created_by, "mockup") {
				__ARGS__[0]->allmocks -= ({conn->group});
			}->then() {send_updates_all("uid-" + mock->created_by);};
		}
		//For everything other than the mockup, it _is_ irreversible though.
		else m_delete(mock[msg->cat], msg->id);
		//Ensure that there's always at least one scene
		if (msg->cat == "scenes" && !sizeof(mock->scenes))
			mock->scenes["default"] = (["title": "New Scene"]);
		return 0;
	}
	if (msg->id == "" && msg->cat == "elements") {
		//Blank ID means create; maybe this should subsume wsedit_new_scene?
		int i; for (i = 2; mock[msg->cat]["e" + i]; ++i);
		mock[msg->cat][msg->id = "e" + i] = ([]);
	}
	mapping target = msg->cat == "mockup" ? mock : mock[msg->cat][msg->id];
	if (!target) return 0;
	foreach ("title description" / " ", string key)
		if (!undefinedp(msg[key])) target[key] = msg[key];
	if (msg->cat == "elements") {
		//TODO: Validate the image, if not, set some sort of default
		if (msg->image) target->image = msg->image;
		if ((int)msg->xsize) target->xsize = (int)msg->xsize;
		if ((int)msg->ysize) target->ysize = (int)msg->ysize;
		if (!undefinedp(msg->zgroup)) target->zgroup = (int)msg->zgroup;
	}
	if (msg->cat == "mockup") {
		//TODO: Validate the bg image, if not, blank it
		if (msg->bg) target->bg = msg->bg;
	}
}

mapping|zero wsedit_new_scene(mapping mock, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	int i; for (i = 2; mock->scenes["s" + i]; ++i);
	mock->scenes["s" + i] = (["title": "Scene " + i]);
	return (["cmd": "select_scene", "id": "s" + i]);
}

//Not run through wsedit_* as we do a cut-down update message - these will be common messages
__async__ void websocket_cmd_move_element(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->landing || !conn->mutate) return;
	mapping|zero update;
	await(G->G->DB->mutate_config(0, "mockup") {mapping mock = __ARGS__[0][conn->group];
		if (!mock || conn->mutate != mock->mutate) return;
		mapping scene = mock->scenes[msg->scene]; if (!scene) return;
		if (!mock->elements[msg->id]) return;
		if (!scene->elements) scene->elements = ([]);
		if (!scene->elements[msg->id]) scene->elements[msg->id] = ([]);
		if (!undefinedp(msg->x)) scene->elements[msg->id]->x = (int)msg->x;
		if (!undefinedp(msg->y)) scene->elements[msg->id]->y = (int)msg->y;
		if (!undefinedp(msg->locked)) scene->elements[msg->id]->locked = !!msg->locked;
		if (!undefinedp(msg->angle)) scene->elements[msg->id]->angle = (int)(msg->angle * 2) / 2.0;
		if (!undefinedp(msg->flipx)) scene->elements[msg->id]->flipx = !!msg->flipx;
		if (!undefinedp(msg->flipy)) scene->elements[msg->id]->flipy = !!msg->flipy;
		update = (["scene": msg->scene, "id": msg->id, "move_element": scene->elements[msg->id], "cause": msg->clientid]);
	});
	if (update) send_updates_all(conn->group, update);
}

//Supported parameters:
//xtra->type = "icon", "tile", "grid"
//  - "icon" or "tile" - bitmap of pixels (same behaviour)
//  - "grid" - grid of tiles, where each cell is (25,25) unless overridden
//xtra->cellsize = ({x, y}) - override the cell size; must be larger than (1,1)
//xtra->gridborder = 1 - draw a border between the tiles
//xtra->gridcolor = "#000000" - color for that border (if omitted or "", will be transparent)
//NOTE: Before calling this, ensure that meta_cache has been populated. This function is synchronous
//to allow it to be used inside mutate_config (though I'm not 100% enthused about that), so it can't
//also load its own meta.
array(Image.Image|mapping) encode_image(array(array(string)) grid, mapping|void xtra) {
	if (!arrayp(grid) || !sizeof(grid) || !arrayp(grid[0]) || !sizeof(grid[0])) return ({0, 0, ([])});
	if (!mappingp(xtra)) xtra = ([]);
	mapping features = ([]);
	int cellx = 1, celly = 1, gridborder = 0;
	array(int) gridcolor;
	if (xtra->type == "grid") {
		if (arrayp(xtra->cellsize) && sizeof(xtra->cellsize) == 2) [cellx, celly] = xtra->cellsize;
		else if (intp(xtra->cellx) && intp(xtra->celly)) {cellx = xtra->cellx; celly = xtra->celly;}
		else cellx = celly = 25;
	}
	if (cellx > 1 || celly > 1) {
		//Cell mode. Enables the border if requested.
		gridborder = (int)xtra->gridborder;
		if (arrayp(xtra->gridcolor) && sizeof(xtra->gridcolor) == 3) gridcolor = (array(int))xtra->gridcolor;
		else if (sscanf(xtra->gridcolor || "??", "#%2x%2x%2x", int r, int g, int b)) gridcolor = ({r, g, b});
		features->cellx = cellx; features->celly = celly;
		features->gridborder = gridborder;
		if (gridcolor) features->gridcolor = gridcolor;
		//Note: Only put things back into the grid when they are guaranteed safe.
		//Reconstitute if possible, or whitelist.
		features->grid = allocate(sizeof(grid), allocate(sizeof(grid[0]), ""));
	}
	int xsize = sizeof(grid[0]) * (cellx + gridborder) - gridborder;
	int ysize = sizeof(grid)    * (celly + gridborder) - gridborder;
	Image.Image image = Image.Image(xsize, ysize);
	Image.Image alpha = Image.Image(xsize, ysize);
	//Draw the entire grid first, then apply the actual selection of colours or images
	//Note that an over-size tile will overlay the grid slightly.
	if (gridborder && gridcolor) {
		for (int i = 0; i < gridborder; ++i) {
			for (int x = 1; x < sizeof(grid[0]); ++x) {
				int xpos = x * (cellx + gridborder) - gridborder + i;
				image->line(xpos, 0, xpos, ysize, @gridcolor);
				alpha->line(xpos, 0, xpos, ysize, 255, 255, 255);
			}
			for (int y = 1; y < sizeof(grid); ++y) {
				int ypos = y * (celly + gridborder) - gridborder + i;
				image->line(0, ypos, ysize, ypos, @gridcolor);
				alpha->line(0, ypos, ysize, ypos, 255, 255, 255);
			}
		}
	}
	mapping image_cache = ([]);
	foreach (grid; int y; array row) foreach (row; int x; string cell) {
		if (cell == "") continue; //Leave it transparent
		int xpos = x * (cellx + gridborder), ypos = y * (celly + gridborder);
		if (cell[0] == '#') {
			//Currently we don't support a full alpha channel, so any non-transparent cell is fully opaque.
			//If cellx and celly are both 1, this could be simplified to just a setpixel() call, but this works too
			alpha->box(xpos, ypos, xpos + cellx - 1, ypos + celly - 1, 255, 255, 255);
			sscanf(cell, "#%2x%2x%2x", int r, int g, int b);
			image->box(xpos, ypos, xpos + cellx - 1, ypos + celly - 1, r, g, b);
			if (features->grid) features->grid[y][x] = sprintf("#%2x%2x%2x", r, g, b);
		} else if (mapping img = meta_cache->tiles[cell]) {
			//Note that we don't here ensure that it matches its cell size.
			if (!image_cache[img->url]) {
				sscanf(img->url, "data:image/png;base64,%s", string raw);
				if (!raw) continue;
				image_cache[img->url] = Image.PNG._decode(MIME.decode_base64(raw));
			}
			img = image_cache[img->url];
			alpha->paste_mask(img->alpha, img->alpha, xpos, ypos);
			image->paste_mask(img->image, img->alpha, xpos, ypos);
			if (features->grid) features->grid[y][x] = cell;
		}
	}
	//A border of 0 but a selected color gives corner dots. These are drawn _after_ the
	//tiles in the cells, so that this overlays (even if there's no transparent corner).
	if (!gridborder && gridcolor) {
		for (int x = 1; x < sizeof(grid[0]); ++x) {
			for (int y = 1; y < sizeof(grid); ++y) {
				image->setpixel(x * cellx - 1, y * celly - 1, @gridcolor);
				alpha->setpixel(x * cellx - 1, y * celly - 1, 255, 255, 255);
			}
		}
	}
	return ({image, alpha, features});
}

//Saves all kinds of image - icons, tiles, and grids
__async__ void websocket_cmd_save_image(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->landing) return;
	if (!(<"icon", "tile", "grid">)[msg->type]) return;
	if (!meta_cache) meta_cache = await(G->G->DB->load_config(1, "mockup"));
	//The front end sends us a 2D array of colour identifiers given in six digit hex.
	//Let's make, yaknow, an actual image. In PNG.
	[Image.Image image, Image.Image alpha, mapping xtra] = encode_image(msg->grid, msg);
	if (!image) return;
	string png = Image.PNG.encode(image, (["alpha": alpha]));
	string url = "data:image/png;base64," + MIME.encode_base64(png, 1);
	await(G->G->DB->mutate_config(1, "mockup") {mapping meta = meta_cache = __ARGS__[0];
		if (!meta->icons) meta->icons = ([]);
		if (!meta->tiles) meta->tiles = ([]);
		if (!meta->grids) meta->grids = ([]);
		meta[msg->type + "s"][msg->name] = ([
			"url": url,
			"created_at": time(),
			"created_by": conn->session->user->id,
			"xsize": image->xsize(), "ysize": image->ysize(),
		]) | xtra;
		if (msg->type == "tile") {
			//When updating a tile, also redo any grids it's a part of.
			foreach (meta->grids; string id; mapping img) {
				int update = 0;
				foreach (img->grid, array row) if (has_value(row, msg->name)) {update = 1; break;}
				if (!update) continue;
				[Image.Image image, Image.Image alpha, mapping xtra] = encode_image(img->grid, img | (["type": "grid"]));
				if (!image) continue;
				string png = Image.PNG.encode(image, (["alpha": alpha]));
				img->url = "data:image/png;base64," + MIME.encode_base64(png, 1);
			}
		}
	});
	update_meta();
}

void update_meta() {
	//This is a relatively rare thing to change, so we send it out with a dedicated message
	//to all connected clients (regardless of group).
	string text = Standards.JSON.encode((["cmd": "update_meta"]) | meta_cache, 4);
	foreach (values(websocket_groups), array group)
		foreach (group, object sock)
			if (sock && sock->state == 1) sock->send_text(text);
}

__async__ void websocket_cmd_delete_image(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->landing) return;
	if (!(<"icon", "tile", "grid">)[msg->type]) return;
	mapping meta;
	await(G->G->DB->mutate_config(1, "mockup") {meta = __ARGS__[0];
		m_delete(meta[msg->type + "s"], msg->id);
	});
	meta_cache = meta;
	update_meta();
}

array(array(string)) decode_image(Image.Image image, Image.Image alpha) {
	array grid = ({ });
	for (int y = 0; y < image->ysize(); ++y) {
		array row = ({ });
		for (int x = 0; x < image->xsize(); ++x) {
			if (alpha->getpixel(x, y)[0] < 64) row += ({""});
			else row += ({sprintf("#%02x%02x%02x", @image->getpixel(x, y))});
		}
		grid += ({row});
	}
	return grid;
}

__async__ mapping websocket_cmd_load_image(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->landing) return 0;
	if (!(<"icon", "tile", "grid">)[msg->type]) return 0;
	if (!meta_cache) meta_cache = await(G->G->DB->load_config(1, "mockup"));
	mapping img = meta_cache[msg->type + "s"][msg->id];
	if (!img) return (["error": "Image not found"]);
	if (img->grid) return (["cmd": "image_loaded", "id": msg->id, "type": msg->type, "grid": img->grid]); //For grid backgrounds, we retain a viable grid rather than decoding the PNG.
	sscanf(img->url, "data:image/png;base64,%s", string raw);
	if (!raw) return (["error": "Non-local images cannot be loaded"]);
	mapping image = Image.PNG._decode(MIME.decode_base64(raw));
	return (["cmd": "image_loaded", "id": msg->id, "type": msg->type, "grid": decode_image(image->image, image->alpha)]);
}

//The front end can't be bothered doing antialiased rescaling, so it hands us a grid of colours,
//asks us to do the rescaling, and accepts whatever we give it. Not suitable for grid mode - that
//is all done on the front end for simplicity and reduced latency.
__async__ mapping|zero websocket_cmd_rescale(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->landing) return 0;
	if (!meta_cache) meta_cache = await(G->G->DB->load_config(1, "mockup"));
	[Image.Image image, Image.Image alpha, mapping xtra] = encode_image(msg->grid);
	if (!image) return 0;
	image = image->scale((int)msg->xsize, (int)msg->ysize);
	alpha = alpha->scale((int)msg->xsize, (int)msg->ysize);
	return (["cmd": "image_loaded", "grid": decode_image(image, alpha)]);
}

__async__ mapping|zero websocket_cmd_import(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (msg->url) {
		object res = await(Protocols.HTTP.Promise.get_url(msg->url));
		msg->content = res->get();
		msg->name = basename(Standards.URI(msg->url)->path);
	} else if (msg->base64) msg->content = MIME.decode_base64(msg->base64);
	if (!msg->content) return 0; //Note that msg->content will seldom be sent directly, as it's easier to work with base64.
	mapping image = Image.ANY._decode(msg->content);
	return (["cmd": "image_loaded", "id": msg->name, "type": "icon", "grid": decode_image(image->image, image->alpha)]);
}

//TODO: Have a way for the owner to set the password. This should send to all connected clients
//a message saying (["cmd": "mutation", "allowed": 0]) so they reset to read-only display; if
//a hacked-on client ignores this message, mutators will fail (since the password is rechecked
//inside websocket_msg(), but the UI elements will still all be there, which would be confusing.

protected void create(string name) {::create(name);}
