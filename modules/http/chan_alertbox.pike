inherit http_websocket;
inherit builtin_command;
inherit hook;
constant markdown = #"# Alertbox management for channel $$channel$$

> ### Library
>
> Upload files (up to 5MB each) to use in your alerts. You may also
> link to files that are accessible on the internet.
>
> <div id=uploadfrm><div id=uploads></div></div>
>
> <p><label class=selectmode><input type=radio name=chooseme data-special=None> None<br></label>
> <span class=selectmode><input type=radio name=chooseme data-special=URL><label> URL: <input id=customurl size=100></label><br></span>
> <form>Upload new file: <input type=file multiple></form></p>
>
> [Select](:#libraryselect disabled=true) [Close](:.dialog_close)
{: tag=dialog #library}

$$notmodmsg||To use these alerts, [show the preview](:#authpreview) from which you can access your unique display link.<br>$$
$$blank||Keep this link secret; if the authentication key is accidentally shared, you can [Revoke Key](:#revokekey) to generate a new one.$$

$$notmod2||[Show library](:.showlibrary)$$

> ### Revoke authentication key
>
> If your authentication key is accidentally shared, don't panic! It can be quickly and<br>
> easily revoked here, before anyone can use it to snoop on your alerts.
>
> After doing this, you will need to update any browser sources showing your alerts,<br>
> but all your configuration will be retained.
>
> [Generate a new key, disabling the old one](:#confirmrevokekey) [Cancel](:.dialog_close)
{: tag=dialog #revokekeydlg}

<ul id=alertselectors><li id=newpersonal><button id=addpersonal title=\"Add new personal alert\">+</button></li></ul><style id=selectalert></style><div id=alertconfigs></div>

> ### Rename file
> Renaming a file has no effect on alerts; call them whatever you like. FIXME: Write better description.
>
> <div class=thumbnail></div>
>
> <form id=renameform method=dialog>
> <input type=hidden name=id>
> <label>Name: <input name=name size=50></label>
>
> [Apply](:#renamefile type=submit) [Cancel](:.dialog_close)
> </form>
{: tag=dialog #renamefiledlg}

<!-- -->

> ### Delete <span class=deltype>file</span>
> Really delete this <span class=deltype>file</span>?
>
> [...](...)
>
> <div class=thumbnail></div>
>
> Once deleted, this file will no longer be available for alerts, and if<br>
> reuploaded, will have a brand new URL.
> {: #deletewarning}
>
> [Delete](:#delete) [Cancel](:.dialog_close)
{: tag=dialog #confirmdeletedlg}

<!-- -->

> ### Unsaved changes
> Unsaved changes. Save or discard them?
> {:#discarddesc}
>
> [Save and continue](:#unsaved-save) [Discard changes](:#unsaved-discard) [Cancel](:.dialog_close)
{: tag=dialog #unsaveddlg}

<!-- -->

> ### Alert variations
> <form id=replaceme>loading...</form>
{: tag=dialog #variationdlg}

<style>
#uploadfrm {
	border: 1px solid black;
	background: #eee;
	padding: 1em;
}
#uploads {
	display: flex;
	flex-wrap: wrap;
}
#uploads > label {
	border: 1px solid black; /* TODO: Show incomplete uploads with a different border */
	margin: 0.5em;
	padding: 0.5em;
	position: relative;
}
#uploads figure {
	margin: 0;
	padding: 0 1em;
}
#uploads input[type=radio] {
	position: absolute;
}
input[name=chooseme]:checked ~ figure {
	background: aliceblue;
}
#uploads .active {
	/* TODO: Style the library elements so you can see which ones are selectable.
	When you simply 'show library', that's all of them (but the radio buttons are
	disabled); but if you ask to select an image or sound, only those of that type
	are active (and will have radio buttons). */
}
#uploads .inactive {
	/* Alternatively, style the inactive ones. Current placeholder: crosshatched. */
	filter: grayscale(50%);
	background: repeating-linear-gradient(
		-45deg,
		#eee,
		#eee 10px,
		#ccc 10px,
		#ccc 12px
	);
}
#uploads .confirmdelete {
	position: absolute;
	right: 0.5em; top: 0.5em;
}
.confirmdelete {
	width: 20px; height: 23px;
	padding: 0;
}
.thumbnail {
	width: 150px; height: 150px;
	background: none center/contain no-repeat;
}
figcaption {
	max-width: 150px;
	overflow-wrap: break-word;
}
.thumbnail audio {max-width: 100%; max-height: 100%;}

.alertconfig {
	margin: 0 3px 3px 0;
	border: 1px solid black;
	padding: 8px;
}
#alertconfigs .alertconfig {display: none;}

#library.noselect .selectmode {display: none;}
.preview {
	max-height: 2em;
	vertical-align: middle;
}
input[type=range] {vertical-align: middle;}

#alertselectors {
	display: flex;
	list-style-type: none;
	margin-bottom: 0;
	padding: 0;
}
#alertselectors input {display: none;}
#alertselectors label {
	display: inline-block;
	cursor: pointer;
	padding: 0.4em;
	margin: 0 1px;
	font-weight: bold;
	border: 1px solid black;
	border-radius: 0.5em 0.5em 0 0;
	height: 2em; width: 8em;
	text-align: center;
}
#alertselectors input:checked + label {background: #efd;}
#addpersonal {
	height: 24px; width: 24px;
	margin: 4px;
}
form:not(.unsaved-changes) .if-unsaved {display: none;}
.editpersonaldesc,.renamefile {
	padding: 0;
	margin-right: 5px;
}
.editpersonaldesc {
	padding: 0;
	margin-left: 5px;
}
.inherited, .inherited ~ label input[type=color], .inherited ~ input[type=color] {
	background: #cdf;
}
.dirty.inherited, .dirty.inherited ~ label input[type=color], .dirty.inherited ~ input[type=color] {
	background: #fdf;
}
/* On the defaults tab, don't show blanks in any special way (there's no user-controlled inheritance beyond defaults) */
.no-inherit input {background: #ffe;} /* Revert these to my global default for editable text */
.no-inherit label, .no-inherit select {background: revert;} /* These don't have a global default, so revert to UA style */

.expandbox {
	border: 1px solid black;
	padding: 0 2em;
}
.expandbox summary {margin-left: -1.75em;} /* Pull the summary back to the left */

.mode-alertset .not-alertset {display: none;}
.mode-variant .not-variant {display: none;}
</style>

> ### Alert preview
>
> Drag this to OBS or use this URL as a browser source:
> <a id=alertboxlink href=\"alertbox?key=LOADING\" target=_blank>Alert Box</a><br><label>
> Click to reveal: <input readonly disabled size=65 value=\"https://sikorsky.rosuav.com/channels/rosuav/alertbox?key=(hidden)\" id=alertboxdisplay></label>
>
> Your alerts currently look like this:
>
> <iframe id=alertembed width=600 height=400></iframe>
>
> TODO: Have a background color selection popup, and buttons for all alert types, not just hosts
>
> [Test host alert](:.testalert data-type=hostalert) [Close](:.dialog_close)
{: tag=dialog #previewdlg}

<!-- -->

> ### Personal alert
>
> Personal alert types are not triggered automatically, but are available for your channel's
> commands and specials. They can be customized just like the standard alerts can, and can be
> tested from here, yada yada include description pls.
>
> <form id=editpersonal method=dialog><input type=hidden name=id>
> <label>Tab label: <input name=label> Keep this short and unique</label><br>
> <label>Heading: <input name=heading size=60></label><br>
> <label>Description:<br><textarea name=description cols=60 rows=4></textarea></label>
>
> [Save](:#savepersonal type=submit) [Delete](:#delpersonal) [Cancel](:.dialog_close)
> </form>
{: tag=dialog #personaldlg style=max-width:min-content}

<!-- -->

> ### Send test alert
>
> This alert has variations available. Would you like to:
>
> * Test just the base alert, as detailed on this page
> * Test all the active alerts for the current alert set (<span id=tvactivedesc>N</span> alerts)
> * Test all alert variations and the base alert (<span id=tvalldesc>N</span> in total)
>
> [Base alert](:.testvariant #tvbase) [Active only](:.testvariant #tvactive)
> [All variants](:.testvariant #tvall) [Cancel](:.dialog_close)
{: tag=dialog #testalertdlg}
";

constant MAX_PER_FILE = 5, MAX_TOTAL_STORAGE = 25; //MB
//Every standard alert should have a 'builtin' which says which module will trigger this.
//Not currently used, beyond that standard alerts have a builtin and personal alerts don't.
constant ALERTTYPES = ({([
	"id": "defaults",
	"label": "Defaults",
	"heading": "Defaults for all alerts",
	"description": "Settings selected here will apply to all alerts, but can be overridden on each alert.",
	"placeholders": ([]),
	"testpholders": ([]),
	"builtin": "chan_alertbox",
]), ([
	//Pseudo-alert used for the Alert Variant dialog
	"id": "variant",
	"label": "(Variant)",
	"heading": "Alert Variation",
	"description": "Choose a variant of the current alert, apply filters to choose when it happens, and configure it as needed.",
	"placeholders": ([]),
	"testpholders": ([]),
	"builtin": "chan_alertbox",
	"condition_vars": ({ }),
]), ([
	"id": "hostalert",
	"label": "Host",
	"heading": "Hosted by another channel",
	"description": "When some other channel hosts yours",
	"placeholders": (["username": "Channel name (equivalently {NAME})", "viewers": "View count (equivalently {VIEWERS})"]),
	"testpholders": (["viewers": ({1, 100}), "VIEWERS": ({1, 100})]),
	"builtin": "chan_alertbox",
]), ([
	"id": "follower",
	"label": "Follow",
	"heading": "Somebody followed your channel",
	"description": "When someone follows your channel, and remains followed for at least a fraction of a second",
	"placeholders": (["username": "Display name of the new follower (equivalently {NAME})"]),
	"testpholders": ([]),
	"builtin": "poll",
	"condition_vars": ({ }),
]), ([
	"id": "sub",
	"label": "Subscription",
	"heading": "New subscriber",
	"description": "Whenever anyone subscribes for the first time (including if gifted)",
	"placeholders": ([
		"username": "Display name of the subscriber; for a sub bomb, is the channel name",
		"tier": "Tier (1, 2, or 3) of the subscription",
		"months": "Number of months subscribed for (0 for new subs)",
		"gifted": "0 for voluntary subs, 1 for all forms of gift sub",
		"giver": "Display name of the giver of a sub or sub bomb",
		"subbomb": "For community sub gifts, the number of subscriptions given - otherwise 0",
		"streak": "Number of consecutive months subscribed",
	]),
	"testpholders": (["tier": ({1, 3}), "months": ({1, 60}), "gifted": "0", "subbomb": ({0, 0}), "streak": "1"]),
	"builtin": "connection",
	"condition_vars": ({"tier", "months", "gifted", "subbomb"}),
]), ([
	"id": "cheer",
	"label": "Cheer",
	"heading": "Cheer",
	"description": "When someone uses bits to cheer in the channel (this does not include extensions and special features).",
	"placeholders": ([
		"username": "Display name of the giver of the subs",
		"bits": "Number of bits cheered",
	]),
	"testpholders": (["bits": ({1, 25000})]),
	"builtin": "connection",
	"condition_vars": ({"bits"}),
])});
constant RETAINED_ATTRS = ({"image", "sound", "variants"});
constant FORMAT_ATTRS = ("active format alertlength alertgap cond-label cond-disableautogen "
			"layout alertwidth alertheight textformat volume") / " " + TEXTFORMATTING_ATTRS;
constant VALID_FORMATS = "text_image_stacked text_image_overlaid" / " ";
//List all defaults here. They will be applied to everything that isn't explicitly configured.
constant NULL_ALERT = ([
	"active": 0, "format": "text_image_stacked",
	"alertlength": 6, "alertgap": 1,
	"layout": "USE_DEFAULT", //Due to the way invalid keywords are handled, this effectively will use the first available layout as the default.
	"alertwidth": 250, "alertheight": 250,
	"volume": 0.5, "whitespace": "normal",
	"fontweight": "normal", "fontstyle": "normal", "fontsize": "24",
	"strokewidth": "None", "strokecolor": "#000000", "borderwidth": "0",
	"padvert": "0", "padhoriz": "0", "textalign": "start",
	"shadowx": "0", "shadowy": "0", "shadowalpha": "0", "bgalpha": "0",
]);
constant LATEST_VERSION = 1; //Bump this every time a change might require the client to refresh.
constant COMPAT_VERSION = 1; //If the change definitely requires a refresh, bump this too.

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (string key = req->variables->key) {
		//TODO: If key is incorrect, give static error, something readable.
		if (key != persist_status->path("alertbox", (string)req->misc->channel->userid)->authkey)
			return (["error": 401, "data": "Bad key", "type": "text/plain"]);
		return render_template("alertbox.html", ([
			"vars": ([
				"ws_type": ws_type, "ws_code": "alertbox",
				"ws_group": req->variables->key + req->misc->channel->name,
				"alertbox_version": LATEST_VERSION,
			]),
			"channelname": req->misc->channel->name[1..],
		]) | req->misc->chaninfo);
	}
	//TODO: Give some useful info if not a mod, since that might be seen if someone messes up the URL
	if (string scopes = req->misc->channel->name != "#!demo" && ensure_bcaster_token(req, "chat:read"))
		return render_template("login.md", (["scopes": scopes, "msg": "authentication as the broadcaster"]));
	if (!req->misc->is_mod) {
		if (req->misc->session->user) return render(req, req->misc->chaninfo | ([
			"notmodmsg": "You're logged in, but you're not a recognized mod. Please say something in chat so I can see your sword.",
			"blank": "",
			"notmod2": "Functionality on this page will be activated for mods (and broadcaster) only.",
		]));
		return render_template("login.md", (["msg": "moderator privileges"]));
	}
	mapping cfg = persist_status->path("alertbox", (string)req->misc->channel->userid);
	//For API usage eg command viewer, provide some useful information in JSON.
	if (req->variables->summary) return jsonify(([
		"stdalerts": ALERTTYPES,
		"personals": cfg->personals || ({ }),
	]));
	if (!req->misc->session->fake && req->request_type == "POST") {
		if (!req->variables->id) return jsonify((["error": "No file ID specified"]));
		int idx = search((cfg->files || ({ }))->id, req->variables->id);
		if (idx < 0) return jsonify((["error": "Bad file ID specified (may have been deleted already)"]));
		mapping file = cfg->files[idx];
		if (file->url) return jsonify((["error": "File has already been uploaded"]));
		if (file->size < sizeof(req->body_raw)) return jsonify((["error": "Requested upload of " + file->size + "bytes, not " + sizeof(req->body_raw) + " bytes!"]));
		string filename = sprintf("%d-%s", req->misc->channel->userid, file->id);
		Stdio.write_file("httpstatic/uploads/" + filename, req->body_raw);
		file->url = sprintf("%s/static/upload-%s", persist_config["ircsettings"]->http_address, filename);
		persist_status->path("upload_metadata")[filename] = (["mimetype": file->mimetype]);
		persist_status->save();
		update_one("control" + req->misc->channel->name, file->id); //Display connection doesn't need to get updated.
		return jsonify((["url": file->url]));
	}
	return render(req, ([
		"vars": (["ws_group": "control", "maxfilesize": MAX_PER_FILE, "maxtotsize": MAX_TOTAL_STORAGE]),
	]) | req->misc->chaninfo);
}

mapping resolve_inherits(mapping alerts, string id, mapping alert) {
	string par = alert->?parent || "defaults"; //TODO: For MRO insertion of sets, insert "|| alert->cond_alertset" or similar.
	mapping parent = id == "defaults" ? NULL_ALERT //The defaults themselves are defaulted to the vanilla null alert.
		: resolve_inherits(alerts, par, alerts[par]); //Everything else has a parent, potentially implicit.
	if (!alert) return parent;
	return parent | filter(alert) {return __ARGS__[0] && __ARGS__[0] != "";}; //Shouldn't need to filter since it's done on save, may be able to remove this later
}

mapping resolve_all_inherits(mapping alerts) {
	mapping ret = ([]);
	if (alerts) foreach (alerts; string id; mapping alert)
		if (id != "defaults") ret[id] = resolve_inherits(alerts, id, alert);
	return ret;
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (grp == cfg->authkey) {
		//Cut-down information for the display
		string chan = channel->name[1..];
		string token;
		if (channel->name == "#!demo") token = "!demo"; //Permit test alerts but no chat connection
		else if (has_value((persist_status->path("bcaster_token_scopes")[chan]||"") / " ", "chat:read"))
			token = persist_status->path("bcaster_token")[chan];
		return ([
			"alertconfigs": resolve_all_inherits(cfg->alertconfigs),
			"token": token,
			"hostlist_command": cfg->hostlist_command || "",
			"hostlist_format": cfg->hostlist_format || "",
			"version": COMPAT_VERSION,
		]);
	}
	if (grp != "control") return 0; //If it's not "control" and not the auth key, it's probably an expired auth key.
	array files = ({ });
	if (id) {
		if (!cfg->files) return 0;
		int idx = search(cfg->files->id, id);
		return idx >= 0 && cfg->files[idx];
	}
	if (!cfg->alertconfigs) cfg->alertconfigs = ([]);
	cfg->alertconfigs->defaults = resolve_inherits(cfg->alertconfigs, "defaults",
		cfg->alertconfigs->defaults || ([]));
	return (["items": cfg->files || ({ }),
		"alertconfigs": cfg->alertconfigs,
		"alerttypes": ALERTTYPES + (cfg->personals || ({ })),
		"hostlist_command": cfg->hostlist_command || "",
		"hostlist_format": cfg->hostlist_format || "",
	]);
}

void websocket_cmd_getkey(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (!cfg->authkey) {cfg->authkey = String.string2hex(random_string(11)); persist_status->save();}
	conn->sock->send_text(Standards.JSON.encode((["cmd": "authkey", "key": cfg->authkey]), 4));
}

//NOW it's personal.
void websocket_cmd_makepersonal(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (!cfg->personals) cfg->personals = ({ });
	mapping info;
	if (msg->id && msg->id != "") {
		//Look up an existing one to edit
		int idx = search(cfg->personals->id, msg->id);
		if (idx == -1) return; //ID specified and not found? Can't save.
		info = cfg->personals[idx];
	}
	else {
		string id;
		do {id = replace(MIME.encode_base64(random_string(9)), (["/": "1", "+": "0"]));}
		while (has_value(cfg->personals->id, id));
		cfg->personals += ({info = (["id": id])});
	}
	foreach ("label heading description" / " ", string key)
		if (stringp(msg[key])) info[key] = msg[key];
	persist_status->save();
	send_updates_all(conn->group);
	send_updates_all(cfg->authkey + channel->name);
}

void websocket_cmd_delpersonal(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (!cfg->personals) return; //Nothing to delete
	if (!stringp(msg->id)) return;
	int idx = search(cfg->personals->id, msg->id);
	if (idx == -1) return; //Not found (maybe was already deleted)
	cfg->personals = cfg->personals[..idx-1] + cfg->personals[idx+1..];
	if (cfg->alertconfigs) m_delete(cfg->alertconfigs, msg->id);
	persist_status->save();
	send_updates_all(conn->group, (["delpersonal": msg->id]));
}

void websocket_cmd_upload(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (!cfg->files) cfg->files = ({ });
	if (!intp(msg->size) || msg->size < 0) return; //Protocol error, not permitted. (Zero-length files are fine, although probably useless.)
	int used = `+(0, @cfg->files->allocation);
	//Count 1KB chunks, rounding up, and adding one chunk for overhead. Won't make much
	//difference to most files, but will stop someone from uploading twenty-five million
	//one-byte files, which would be just stupid :)
	int allocation = (msg->size + 2047) / 1024;
	string error;
	if (!has_prefix(msg->mimetype, "image/") && !has_prefix(msg->mimetype, "audio/"))
		error = "Currently only audio and image files are supported - video support Coming Soon";
	else if (msg->size > MAX_PER_FILE * 1048576)
		error = "File too large (limit " + MAX_PER_FILE + " MB)";
	else if (used + allocation > MAX_TOTAL_STORAGE * 1024)
		error = "Unable to upload, storage limit of " + MAX_TOTAL_STORAGE + " MB exceeded. Delete other files to make room.";
	//TODO: Check if the file name is duplicated? Maybe? Not sure. It's not a fundamental
	//blocker. Maybe the front end should check instead, and offer to delete the old one.
	//TODO: Sanitize the name - at least a length check.
	if (error) {
		conn->sock->send_text(Standards.JSON.encode((["cmd": "uploaderror", "name": msg->name, "error": error]), 4));
		return;
	}
	string id;
	while (has_value(cfg->files->id, id = String.string2hex(random_string(14))))
		; //I would be highly surprised if this loops at all, let alone more than once
	cfg->files += ({([
		"id": id, "name": msg->name,
		"size": msg->size, "allocation": allocation,
		"mimetype": msg->mimetype, //TODO: Ensure that it's a valid type, or at least formatted correctly
	])});
	persist_status->save();
	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "id": id, "name": msg->name]), 4));
	update_one(conn->group, id); //Note that the display connection doesn't need to be updated
}

void websocket_cmd_delete(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (msg->type == "variant") {
		//Delete an alert variant. Only valid if it's a variant (not a base
		//alert - personals are deleted differently), and has no effect if
		//the alert doesn't exist.
		if (!stringp(msg->id) || !has_value(msg->id, '-')) return;
		if (!cfg->alertconfigs) return;
		sscanf(msg->id, "%s-%s", string basetype, string variation);
		mapping base = cfg->alertconfigs[basetype]; if (!base) return;
		if (!arrayp(base->variants)) return; //A properly-saved alert variant should have a base alert with a set of variants.
		m_delete(cfg->alertconfigs, msg->id);
		base->variants -= ({msg->id});
		persist_status->save();
		send_updates_all(conn->group);
		send_updates_all(cfg->authkey + channel->name);
		conn->sock->send_text(Standards.JSON.encode((["cmd": "select_variant", "type": basetype, "variant": ""]), 4));
		return;
	}
	if (!cfg->files) return; //No files, can't delete
	int idx = search(cfg->files->id, msg->id);
	if (idx == -1) return; //Not found.
	mapping file = cfg->files[idx];
	cfg->files = cfg->files[..idx-1] + cfg->files[idx+1..];
	string fn = sprintf("%d-%s", channel->userid, file->id);
	rm("httpstatic/uploads/" + fn); //If it returns 0 (file not found/not deleted), no problem
	m_delete(persist_status->path("upload_metadata"), fn);
	int changed_alert = 0;
	if (file->url) 
		foreach (cfg->alertconfigs || ([]);; mapping alert)
			while (string key = search(alert, file->url)) {
				alert[key] = "";
				changed_alert = 1;
			}
	persist_status->save();
	update_one(conn->group, file->id);
	if (changed_alert) update_one(cfg->authkey + channel->name, file->id);
}

int(0..1) valid_alert_type(string type, mapping|void cfg) {
	if (has_value(ALERTTYPES->id, type)) return 1;
	if (cfg->?personals && has_value(cfg->personals->id, type)) return 1;
}

void websocket_cmd_testalert(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	//NOTE: Fake clients are fully allowed to send test alerts, but they will go
	//to *every* client. This means multiple people playing with the demo
	//simultaneously will see each other's alerts show up.
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	string basetype = msg->type || ""; sscanf(basetype, "%s-%s", basetype, string variation);
	mapping alert = ([
		"send_alert": valid_alert_type(basetype, cfg) ? msg->type : "hostalert",
		"NAME": channel->name[1..], "username": channel->name[1..], //TODO: Use the display name
		"test_alert": 1,
	]);
	if (variation && !cfg->alertconfigs[msg->type]) alert->send_alert = basetype; //Borked variation name? Test the base alert instead.
	int idx = search(ALERTTYPES->id, basetype);
	mapping pholders = idx >= 0 ? ALERTTYPES[idx]->testpholders : ([
		"text": "This is a test personal alert.",
		"TEXT": "This is a test personal alert.",
	]);
	mapping alertcfg = cfg->alertconfigs[msg->type];
	foreach (pholders; string key; string|array value) {
		if (alertcfg["condoper-" + key] == "==") {alert[key] = (string)alertcfg["condval-" + key]; continue;}
		int minimum = alertcfg["condoper-" + key] == ">=" && alertcfg["condval-" + key];
		if (arrayp(value)) {
			if (stringp(value[0])) alert[key] = random(value); //Minimums not supported
			else {
				//Pick a random number no less than the minimum. Note that since random(-123)
				//always returns zero, it's okay to have minimum > value[1], and we'll just
				//pick the user-specified minimum.
				if (!minimum || minimum < value[0]) minimum = value[0];
				alert[key] = (string)(random(value[1] - minimum + 1) + minimum);
			}
		}
		else alert[key] = value;
	}
	send_updates_all(cfg->authkey + channel->name, alert);
}

void websocket_cmd_config(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	foreach ("hostlist_command hostlist_format" / " ", string key)
		if (stringp(msg[key])) cfg[key] = msg[key];
	persist_status->save();
	send_updates_all(conn->group);
	send_updates_all(cfg->authkey + channel->name);
}

void websocket_cmd_alertcfg(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	string basetype = msg->type || ""; sscanf(basetype, "%s-%s", basetype, string variation);
	if (!valid_alert_type(basetype, cfg)) return;
	if (!cfg->alertconfigs) cfg->alertconfigs = ([]);
	mapping sock_reply;
	if (variation == "") {
		//New variant requested. Generate a subid and use that.
		//Note that if (!variation), we're editing the base alert, not a variant.
		do {variation = replace(MIME.encode_base64(random_string(9)), (["/": "1", "+": "0"]));}
		while (cfg->alertconfigs[basetype + "-" + variation]);
		msg->type = basetype + "-" + variation;
		sock_reply = (["cmd": "select_variant", "type": basetype, "variant": variation]);
	} else if (variation) {
		//Existing variant requested. Make sure the ID has already existed.
		if (!cfg->alertconfigs[msg->type]) return;
	}
	if (!msg->format) {
		//If the format is not specified, this is a partial update, which can
		//change only the RETAINED_ATTRS - all others are left untouched.
		mapping data = cfg->alertconfigs[msg->type];
		if (!data) data = cfg->alertconfigs[msg->type] = ([]);
		foreach (RETAINED_ATTRS, string attr) if (msg[attr]) data[attr] = msg[attr];
		persist_status->save();
		send_updates_all(conn->group);
		send_updates_all(cfg->authkey + channel->name);
		if (sock_reply) conn->sock->send_text(Standards.JSON.encode(sock_reply, 4));
		return;
	}
	//If the format *is* specified, this is a full update, *except* for the retained
	//attributes. Any unspecified attribute will be deleted, setting it to inherit
	//from the parent (not yet implemented) or be omitted altogether.
	mapping data = cfg->alertconfigs[msg->type] = filter(
		mkmapping(RETAINED_ATTRS, (cfg->alertconfigs[msg->type]||([]))[RETAINED_ATTRS[*]])
		| mkmapping(FORMAT_ATTRS, msg[FORMAT_ATTRS[*]]))
			{return __ARGS__[0] && __ARGS__[0] != "";}; //Any blank values get removed and will be inherited.
	//You may inherit from "", meaning the defaults, or from any other alert that
	//doesn't inherit from this alert. Attempting to do so will just reset to "".
	//NOTE: Currently you can only inherit from a base alert. This helps to keep
	//the UI a bit less cluttered.
	if (stringp(msg->parent) && msg->parent != "" && msg->parent != "defaults" && valid_alert_type(msg->parent, cfg)) {
		array mro = cfg->alertconfigs[msg->parent]->?mro;
		if (!mro) mro = ({msg->parent});
		if (!has_value(mro, msg->type)) {
			data->parent = msg->parent;
			data->mro = ({msg->type}) + mro;
		} else mro = ({ });
		//Otherwise, leave data->mro and data->parent unset.
		//If this alert exists in the MROs of any other alerts, they need to be recalculated.
		foreach (cfg->alertconfigs; string id; mapping alert) {
			int idx = search(alert->mro || ({ }), msg->type);
			if (idx == -1) continue;
			alert->mro = alert->mro[..idx] + mro;
		}
	}
	mapping inh = resolve_inherits(cfg->alertconfigs, msg->type, data);
	if (!has_value(VALID_FORMATS, inh->format)) {
		m_delete(data, "format"); //Inheriting will usually be safe. Usually.
		inh = resolve_inherits(cfg->alertconfigs, msg->type, data); //Overkill, but whatever.
		//If it's STILL not valid, then that probably means a parent is broken. Force to a safe default.
		if (!has_value(VALID_FORMATS, inh->format)) data->format = inh->format = NULL_ALERT->format;
	}
	textformatting_validate(data);
	data->text_css = textformatting_css(inh);
	//Calculate specificity.
	//The calculation assumes that all comparison values are nonnegative integers.
	//It is technically possible to cheer five and a half million bits in a single
	//message (spam "uni99999" over and over till you reach 500 characters), and so
	//even though that is more than a little ridiculous, I'm declaring that a single
	//value is worth 10,000,000.
	//Note that the specificity calculation is not scaled differently for different
	//variables, and "sub tier == 2" is also worth 10,000,000.
	int specificity = 0;
	int idx = search(ALERTTYPES->id, basetype);
	array(string) condvars = idx >= 0 && ALERTTYPES[idx]->condition_vars;
	if (condvars) foreach (condvars, string c) {
		string oper = msg["condoper-" + c];
		if (!oper || oper == "") continue; //Don't save the value if no operator set
		if (oper != "==" && oper != ">=") oper = ">="; //May need to expand the operator list, but these are the most common
		data["condoper-" + c] = oper;
		//Note that setting the operator and leaving the value blank will set the value to zero.
		int val = (int)msg["condval-" + c];
		data["condval-" + c] = val;
		//Note that ">= 0" is no specificity, as zero is considered "unassigned".
		//Note: Technically, the specificity could be the same for all equality
		//checks; however, since alert variants are ordered by specificity, it is
		//more elegant to have them sort by their values.
		specificity += oper == "==" ? 10000000 + val : val;
	}
	string alertset = msg["cond-alertset"];
	if (alertset && alertset != "" && has_value(cfg->alertconfigs->defaults->?variants || ({ }), alertset)) {
		data["cond-alertset"] = alertset;
		specificity += 100000000; //Setting an alert set is worth ten equality checks. I don't think there'll ever be ten equality checks to have.
	}
	data->specificity = specificity;
	if (variation) {
		//For convenience, every time a change is made, we update an array of
		//variants in the base alert's data.
		if (!cfg->alertconfigs[basetype]) cfg->alertconfigs[basetype] = ([]);
		array ids = ({ }), specs = ({ });
		foreach (cfg->alertconfigs; string id; mapping info)
			if (has_prefix(id, basetype + "-")) {
				ids += ({id});
				specs += ({-info->specificity});
			}
		sort(specs, ids);
		cfg->alertconfigs[basetype]->variants = ids;
	}
	persist_status->save();
	send_updates_all(conn->group);
	send_updates_all(cfg->authkey + channel->name);
	if (sock_reply) conn->sock->send_text(Standards.JSON.encode(sock_reply, 4));
}

void websocket_cmd_renamefile(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Rename a file. Won't change its URL (since that's based on ID),
	//nor the name of the file as stored (ditto), so this is really an
	//"edit description" endpoint. But users will think of it as "rename".
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (!stringp(msg->id) || !stringp(msg->name)) return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (!cfg->files) return; //No files, can't rename
	int idx = search(cfg->files->id, msg->id);
	if (idx == -1) return; //Not found.
	mapping file = cfg->files[idx];
	file->name = msg->name;
	persist_status->save();
	update_one(conn->group, file->id);
}

void websocket_cmd_revokekey(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	string prevkey = m_delete(cfg, "authkey");
	persist_status->save();
	send_updates_all(conn->group, (["authkey": "<REVOKED>"]));
	send_updates_all(prevkey + channel->name, (["breaknow": 1]));
}

//Currently no UI for this, but it works if you fiddle on the console.
void websocket_cmd_reload(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	//Send a fake version number that's higher than the current, thus making it think
	//it needs to update. After it reloads, it will get the regular state, with the
	//current version, so it'll reload once and then be happy.
	send_updates_all(cfg->authkey + channel->name, (["version": LATEST_VERSION + 1]));
}

constant builtin_name = "Send Alert";
constant builtin_description = "Send an alert on the in-browser alertbox. Best with personal (not standard) alerts. Does nothing (no error) if the alert is disabled.";
constant builtin_param = ({"/Alert type/alertbox_id", "Text"});
constant vars_provided = ([
	"{error}": "Error message, if any",
]);
constant command_suggestions = ([]); //This isn't something that you'd create a default command for - it'll want to be custom. (And probably a special, not a command, anyway.)

//Attempt to send an alert. Returns 1 if alert sent, 0 if not (eg if alert disabled).
int(1bit) send_alert(object channel, string alerttype, mapping args) {
	mapping cfg = persist_status->path("alertbox")[(string)channel->userid];
	if (!cfg->?authkey) return 0;
	int suppress_alert = 0;
	if (!args->text) { //Conditions are ignored if the alert is pushed via the builtin
		mapping alert = cfg->alertconfigs[alerttype]; if (!alert) return 0; //No alert means it can't possibly fire
		if (!alert->active) return 0;
		int idx = search(ALERTTYPES->id, (alerttype/"-")[0]); //TODO: Rework this so it's a lookup instead (this same check is done twice)
		array(string) condvars = idx >= 0 ? ALERTTYPES[idx]->condition_vars : ({ });
		foreach (condvars, string c) {
			int val = (int)args[c];
			int comp = alert["condval-" + c];
			switch (alert["condoper-" + c]) {
				case "==": if (val != comp) return 0;
				case ">=": if (val < comp) return 0;
				default: {
					//The subbomb flag is special. If an alert variant does not
					//specify that it is looking for sub bombs, then it implicitly
					//does not fire for sub bombs; however, if a base alert does
					//not specify sub bombs, it will check its variants, and only
					//suppress the base alert itself.
					if (c == "subbomb" && val) suppress_alert = 1;
				}
			}
		}
		//TODO: Check that the alert set is active, if one is selected

		//If any variant responds, use that instead.
		foreach (alert->variants || ({ }), string subid)
			if (send_alert(channel, subid, args)) return 1;
	}
	if (suppress_alert) return 0;
	send_updates_all(cfg->authkey + channel->name, (["send_alert": alerttype]) | args);
	return 1;
}

mapping message_params(object channel, mapping person, array|string param)
{
	string alert, text;
	if (arrayp(param)) [alert, text] = param;
	else sscanf(param, "%s %s", alert, text);
	if (!alert || alert == "") return (["{error}": "Need an alert type"]);
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (!valid_alert_type(alert, cfg)) return (["{error}": "Unknown alert type"]);
	send_alert(channel, alert, ([
		"TEXT": text || "",
		"text": text || "",
	]));
	return (["{error}": ""]);
}

@hook_follower:
void follower(object channel, mapping follower) {
	send_alert(channel, "follower", ([
		"NAME": follower->displayname,
		"username": follower->displayname,
	]));
}

//When we fire a dedicated sub bomb alert, save extra->msg_param_origin_id into this
//set, and it will suppress all the alerts from the individuals. Assumptions: The IDs
//are unique across all channels; code will not be updated in the middle of processing
//of a sub bomb (a very narrow window normally - this isn't the length of the alerts);
//and IDs will not be reused.
multiset subbomb_ids = (<>);

@hook_subscription:
void subscription(object channel, string type, mapping person, string tier, int qty, mapping extra) {
	mapping cfg = persist_status->path("alertbox")[(string)channel->userid];
	if (!cfg->?authkey) return;
	int months = (int)extra->msg_param_cumulative_months || 1;
	//If this channel has a subbomb alert variant, the follow-up sub messages will be skipped.
	if (extra->came_from_subbomb && subbomb_ids[extra->msg_param_origin_id]) return;
	mapping args = ([
		"username": person->displayname,
		"tier": tier, "months": months,
		"streak": extra->msg_param_streak_months || "1",
	]);
	if ((<"subgift", "subbomb">)[type]) {
		args->gifted = "1";
		args->giver = person->displayname;
		args->username = extra->msg_param_recipient_display_name;
		if (type == "subbomb") {
			args->username = channel->name;
			args->subbomb = (string)extra->msg_param_mass_gift_count;
		}
	}
	if (!send_alert(channel, "sub", args)) return; //If alert didn't happen, don't do any further processing.
	if (type == "subbomb") subbomb_ids[extra->msg_param_origin_id] = 1; //Suppress the other alerts
}

@hook_cheer:
void cheer(object channel, mapping person, int bits, mapping extra) {
	mapping cfg = persist_status->path("alertbox")[(string)channel->userid];
	if (!cfg->?authkey) return;
	send_alert(channel, "cheer", ([
		"username": extra->displayname,
		"bits": (string)bits,
	]));
}

protected void create(string name) {::create(name);}
