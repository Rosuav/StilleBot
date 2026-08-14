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
//- grid - the original grid of tile names. Can be passed to load_image to recreate the grid.
//         Notably, this references tiles by *name* rather than content, so updating a tile can update its grids.
//- cellx, celly - cell size. Currently always 25x25. Recorded on every grid in case flexibility is needed.
//- gridborder - if nonzero, a gap will be added between tiles (pixels)
//- gridcolor - if present, is an array [r,g,b] for the colour of the grid border. NOTE: If this is set but the
//         gridborder is zero, instead a single pixel dot will be set in the lower right of every cell, giving a
//         subtle alignment marker without consuming space.


constant markdown = #"# Mockups

<p id=status></p>

Scene: <select id=sceneselector><option disabled>loading...</select> <span id=scenebuttons></span>

<div id=sidebyside><div id=canvasscroll><canvas width=2700 height=1500></canvas></div><div id=elementlist></div></div>

> ### Edit element
> <p id=imageselect>Image: <select id=imageselector></select> <input type=number id=xsize> x <input type=number id=ysize></p>
> <p id=bgselect>Background: <select id=bgselector></select></p>
>
> Name: <input id=elementtitle>
> <textarea id=elementdesc rows=5 cols=80></textarea>
>
> [Save](:type=submit) [Close](:.dialog_close) [Delete](:#deleteelement)
{: tag=formdialog #editelementdlg}

<style>
#deleteelement {
	background: red;
	color: yellow;
	margin-left: 1em;
}
#sidebyside {
	border: 1px solid black;
	display: flex;
	gap: 0.5em;
	max-height: 800px; /* FIXME: main needs to be made flex so this gets all remaining space instead of a fixed arbitrary height */
}
#canvasscroll {
	flex-grow: 1;
	overflow: auto;
}
#elementlist li {text-wrap: nowrap;}
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

[Configure](:#configurebtn) [Resize](:.opendlg data-dlg=resizedlg)
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
/* Note that 'tile mode' also includes icons */
.tilemode .gridonly {display: none;}
.gridmode .tileonly {display: none;}
#imagelist li {display: none;}
#imagelist.showtype-tile li.type-tile {display: list-item;}
#imagelist.showtype-icon li.type-icon {display: list-item;}
#imagelist.showtype-grid li.type-grid {display: list-item;}
#selections {cursor: default; font-size: small;}
/* TODO: Put a checkerboard background on #grid so transparent pixels aren't the same as any single colour */
#grid {margin-top: 1em;}
td {
	width: 25px;
	height: 25px;
}
#management {width: 100%;}
#management td {vertical-align: top;}
#mgmtheading {margin-bottom: 0;}
#imagelist {
	margin-top: 0;
	max-height: 8em;
	overflow-y: auto;
}
</style>

> ### Configuration and management
> Mode: <label><input type=radio name=mode id=tilemode> Tile</label> <label><input type=radio name=mode id=iconmode> Icon</label> <label><input type=radio name=mode id=gridmode> Grid</label>
>
> #### Images
> {:#mgmtheading}
> <ul id=imagelist></ul>
>
> <form id=saveimage>Save as: <input name=savename required> <button type=submit>Save</button></form>
>
> [Configure](:#reconfigure) [Close](:.dialog_close)
{: tag=dialog #configuredlg}
";

constant markdown_guest = #"# Mockups

You are not currently logged in. If someone has sent you a direct link to a
mockup to view or edit, check the URL to make sure it's correct; if you wish
to create a new mockup, you will need to [log in with a Twitch account](:.twitchlogin)

";

mapping meta_cache;
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
	if (!conn->landing) return (["error": "Only create mockups from your landing page"]);
	string id;
	await(G->G->DB->mutate_config(0, "mockup") {mapping mocks = __ARGS__[0];
		do {id = replace(MIME.encode_base64(random_string(12)), (["/": "q", "+": "X"]));} while (mocks[id]);
		mocks[id] = ([
			"created_at": time(),
			"created_by": conn->session->user->id,
			"title": "New Mockup",
			"description": "Describe the purpose of your mockup here.",
			"mutate": "",
			"scenes": (["default": (["title": "New Scene"])]),
			"elements": ([]),
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

//Will handle (["cmd": "example"]) as a mutator.
//Must NOT be asynchronous. Is allowed to return a response.
mapping|zero wsedit_example(mapping mock, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mock->counter += (int)msg->increment || 1;
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
		scene->elements[msg->id] |= (["x": (float)msg->x, "y": (float)msg->y]);
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
//NOTE: Before calling this, ensure that meta_cache has been populated. If this function is ever made async,
//it could ensure that it's loaded, but currently it depends on the caller.
array(Image.Image|mapping) load_image(array(array(string)) grid, mapping|void xtra) {
	if (!arrayp(grid) || !sizeof(grid) || !arrayp(grid[0]) || !sizeof(grid[0])) return ({0, 0, ([])});
	if (!mappingp(xtra)) xtra = ([]);
	mapping features = ([]);
	int cellx = 1, celly = 1, gridborder = 0;
	array(int) gridcolor;
	if (xtra->type == "grid" && arrayp(xtra->cellsize) && sizeof(xtra->cellsize) == 2) [cellx, celly] = xtra->cellsize;
	else if (xtra->type == "grid") cellx = celly = 25;
	if (cellx > 1 || celly > 1) {
		//Cell mode. Enables the border if requested.
		gridborder = (int)xtra->gridborder;
		if (sscanf(xtra->gridcolor || "??", "#%2x%2x%2x", int r, int g, int b)) gridcolor = ({r, g, b});
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
		for (int x = 1; x < sizeof(grid[0]); ++x) {
			int xpos = x * (cellx + gridborder) - gridborder;
			image->line(xpos, 0, xpos, ysize, @gridcolor);
			alpha->line(xpos, 0, xpos, ysize, 255, 255, 255);
		}
		for (int y = 1; y < sizeof(grid); ++y) {
			int ypos = y * (celly + gridborder) - gridborder;
			image->line(0, ypos, ysize, ypos, @gridcolor);
			alpha->line(0, ypos, ysize, ypos, 255, 255, 255);
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
	//TODO: If gridcolor but not gridborder, draw the overlay dots
	return ({image, alpha, features});
}

//Saves all kinds of image - icons, tiles, and grids
__async__ void websocket_cmd_save_image(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!conn->landing) return;
	if (!(<"icon", "tile", "grid">)[msg->type]) return;
	if (!meta_cache) meta_cache = await(G->G->DB->load_config(1, "mockup"));
	//The front end sends us a 2D array of colour identifiers given in six digit hex.
	//Let's make, yaknow, an actual image. In PNG.
	[Image.Image image, Image.Image alpha, mapping xtra] = load_image(msg->grid, msg);
	if (!image) return;
	string png = Image.PNG.encode(image, (["alpha": alpha]));
	string url = "data:image/png;base64," + MIME.encode_base64(png, 1);
	mapping meta;
	await(G->G->DB->mutate_config(1, "mockup") {meta = __ARGS__[0];
		if (!meta->icons) meta->icons = ([]);
		if (!meta->tiles) meta->tiles = ([]);
		if (!meta->grids) meta->grids = ([]);
		meta[msg->type + "s"][msg->name] = ([
			"url": url,
			"created_at": time(),
			"created_by": conn->session->user->id,
			"xsize": image->xsize(), "ysize": image->ysize(),
		]) | xtra;
	});
	meta_cache = meta;
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
	[Image.Image image, Image.Image alpha, mapping xtra] = load_image(msg->grid);
	if (!image) return 0;
	image = image->scale((int)msg->xsize, (int)msg->ysize);
	alpha = alpha->scale((int)msg->xsize, (int)msg->ysize);
	return (["cmd": "image_loaded", "grid": decode_image(image, alpha)]);
}

//TODO: Have a way for the owner to set the password. This should send to all connected clients
//a message saying (["cmd": "mutation", "allowed": 0]) so they reset to read-only display; if
//a hacked-on client ignores this message, mutators will fail (since the password is rechecked
//inside websocket_msg(), but the UI elements will still all be there, which would be confusing.

protected void create(string name) {::create(name);}
