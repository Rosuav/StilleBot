inherit http_websocket;
inherit builtin_command;
inherit hook;
inherit irc_callback;
/* Bot operators, if you want to use TTS:
* Create credentials on Google Cloud Platform
  - https://cloud.google.com/docs/authentication/production
  - Will need a service account and a JSON key
  - Store the JSON key in stillebot/tts-credentials.json (or symlink it there)
* Install the Google Cloud SDK https://cloud.google.com/sdk/docs/install
* Test the credentials:
  $ GOOGLE_APPLICATION_CREDENTIALS=tts-credentials.json gcloud auth application-default print-access-token
  - Should produce a lot of text and no visible error messages
* The first 1M or 4M characters per month are free, then 4 USD or 16 USD per
  million characters. Since I disable Wavenet voices here, it's 4M then 4 USD,
  but removing that check would make it more expensive (fine if low throughput).
The credentials file will be automatically loaded on code update, and should be used thereafter.
*/
constant markdown = #"# Alertbox management for channel $$channel$$

> ### Library
>
> Upload files (up to 8MB each) to use in your alerts. You may also link to files
> that are accessible on the internet.<br>NOTE: OBS does not support all media formats,
> and best results are often achieved with GIF, WEBM, WAV, OGG, and PNG.
>
> <div id=uploaderror class=hidden></div>
>
> <div id=uploadfrm><div id=uploads></div></div>
>
> <p><label class=selectmode><input type=radio name=chooseme data-special=None> None<br></label>
> <span class=selectmode><input type=radio name=chooseme data-special=URL><label> URL: <input id=customurl size=100></label><br></span>
> <span class=selectmode><input type=radio name=chooseme data-special=FreeMedia><label> Free Media: <input id=freemedia size=20></label><br></span>
> <form>Upload new file: <input type=file multiple></form></p>
>
> [Select](:#libraryselect disabled=true) [Close](:.dialog_close)
{: tag=dialog #library}

$$notmodmsg||To use these alerts, [show the preview](:#authpreview) from which you can access your unique display link.<br>$$
$$blank||Keep this link secret; if the authentication key is accidentally shared, you can [Revoke Key](:#revokekey .dlg) to generate a new one.$$

$$notmod2||[Show library](:.showlibrary) [Recent events](:#recentevents .dlg)$$

> ### Revoke authentication key
>
> If your authentication key is accidentally shared, don't panic! It can be quickly and<br>
> easily revoked here, before anyone can use it to snoop on your alerts.
>
> After doing this, you will need to update any browser sources showing your alerts,<br>
> but all your configuration will be retained.
>
> Your authentication key has been used from these locations:
> * loading IP history...
> {: #ip_log}
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

<!-- -->

> ### Recent events
> Note that host alerts will only be listed here if the Pike backend is used.
> <div id=replays>loading...</div>
>
> [Close](:.dialog_close)
{: tag=dialog #recenteventsdlg}

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
#uploads .inactive {
	display: none;
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
/* If the entire block should be deemed 'inherited' at once, adjust the styling */
.inheritblock {
	padding: 0.5em;
	margin: 0.5em 0; /* Shave half the margin to make the padding */
	width: fit-content;
}

.expandbox {
	border: 1px solid black;
	padding: 0 2em;
	margin: 1em 0;
}
.expandbox summary {margin-left: -1.75em;} /* Pull the summary back to the left */

.mode-alertset .not-alertset {display: none;}
.mode-variant .not-variant {display: none;}

.cheer-only {display: none;}
[data-type^=cheer] .cheer-only {display: revert;}

#uploaderror {
	margin-bottom: 0.5em;
	background: #fee;
	border: 1px solid red;
	padding: 0.125em 0.5em;
	max-width: -moz-fit-content;
	max-width: fit-content;
}
#uploaderror.hidden {display: none;}

.invisible {visibility: hidden;}

.need-auth {
	margin: 1em;
	border: 1px solid blue;
	padding: 0.5em;
	max-width: -moz-fit-content;
	max-width: fit-content;
	background: #eef;
}

.replayalert {
	padding: 0 3px;
}
</style>

> ### Alert preview
>
> Drag this to OBS or use this URL as a browser source:
> <a id=alertboxlink href=\"alertbox?key=LOADING\" target=_blank>Alert Box</a><br><label id=alertboxlabel>
> Click to reveal: <input readonly disabled size=65 value=\"https://sikorsky.rosuav.com/channels/$$channel$$/alertbox?key=(hidden)\" id=alertboxdisplay></label>
>
> Your alerts currently look like this:
>
> <iframe id=alertembed width=600 height=400></iframe>
>
> TODO: Have a background color selection popup, and buttons for all alert types, not just hosts
>
> [Test host alert](:.testalert data-type=hostalert) [Test follow alert](:.testalert data-type=follower)
> [Test sub alert](:.testalert data-type=sub) [Test cheer alert](:.testalert data-type=cheer) [Close](:.dialog_close)
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

constant MAX_PER_FILE = 8, MAX_TOTAL_STORAGE = 25; //MB
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
]), ([ //Alert types sent to the command editor begin here - first two are sliced off; see stdalerts.
	"id": "hostalert",
	"label": "Host",
	"heading": "Hosted by another channel",
	"description": "When some other channel hosts yours",
	"placeholders": ([
		"username": "Channel name (equivalently {NAME})",
		"viewers": "View count (equivalently {VIEWERS})",
		"is_raid": "Is this host a raid?",
	]),
	"testpholders": (["viewers": ({1, 100}), "VIEWERS": ({1, 100}), "is_raid": ({0, 0})]),
	"builtin": "chan_alertbox",
	"condition_vars": ({"is_raid"}),
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
		"msg": "Resub message, if included",
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
		"msg": "Message text including emotes",
	]),
	"testpholders": (["bits": ({1, 25000})]),
	"builtin": "connection",
	"condition_vars": ({"bits"}),
]), ([
	//Settings for personal alerts (must be last in the array)
	"placeholders": ([
		"text": "Text provided with the alert trigger",
	]),
	"testpholders": ([
		"text": "This is a test personal alert.",
		"TEXT": "This is a test personal alert.",
	]),
	"condition_vars": ({"'text"}),
])});
constant SINGLE_EDIT_ATTRS = ({"image", "sound"}); //Attributes that can be edited by the client without changing the rest
constant RETAINED_ATTRS = SINGLE_EDIT_ATTRS + ({"version", "variants", "image_is_video"}); //Attributes that are not cleared when a full edit is done (changing the format)
constant FORMAT_ATTRS = ("format name description active alertlength alertgap cond-label cond-disableautogen "
			"tts_text tts_dwell tts_volume tts_filter_emotes tts_filter_badwords tts_filter_words tts_voice tts_min_bits "
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
	"padvert": "0", "padhoriz": "0", "textalign": "start", "textformat": "",
	"shadowx": "0", "shadowy": "0", "shadowalpha": "0", "bgalpha": "0",
	"tts_text": "", "tts_dwell": "0", "tts_volume": 0, "tts_filter_emotes": "cheers",
	"tts_filter_badwords": "none", "tts_min_bits": "0",
]);
constant LATEST_VERSION = 4; //Bump this every time a change might require the client to refresh.
constant COMPAT_VERSION = 1; //If the change definitely requires a refresh, bump this too.
//Version 3 supports <video> tags for images.
//Version 4 supports TTS.

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	if (string key = req->variables->key) {
		string group = req->variables->key;
		if (key == "preview-only") {
			//Preview mode works for mods, works for the demo, but not otherwise.
			//For the demo, test alerts go to the IP address; for mods, they go to
			//the user name; for anyone else, there should be a more useful error
			//than just "Bad key".
			if (req->misc->channel->name == "#!demo") group = "demo-" + req->get_ip();
			else if (req->misc->is_mod) group = "preview-" + req->misc->session->user->login;
			else return (["error": 401, "type": "text/plain", "data": "Preview mode requires mod login (or the demo account)."]);
		}
		else if (key != persist_status->path("alertbox", (string)req->misc->channel->userid)->authkey)
			return (["error": 401, "type": "text/plain", "data": "Bad key - check the URL from the config page (or remove key= from the URL)"]);
		return render_template("alertbox.html", ([
			"vars": ([
				"ws_type": ws_type, "ws_code": "alertbox",
				"ws_group": group + req->misc->channel->name,
				"alertbox_version": LATEST_VERSION,
			]),
			"channelname": req->misc->channel->name[1..],
		]) | req->misc->chaninfo);
	}
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
		"stdalerts": ALERTTYPES[2..<1],
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
		"vars": (["ws_group": "control",
			"maxfilesize": MAX_PER_FILE, "maxtotsize": MAX_TOTAL_STORAGE,
			"avail_voices": G->G->tts_config->avail_voices || ({ }),
			"host_alert_scopes": req->misc->channel->name != "#!demo" && ensure_bcaster_token(req, "chat:read"),
		]),
	]) | req->misc->chaninfo);
}

//Find the alertset that this alert depends on. Note that (as of 20220520) only
//one alertset can be active at a time, and therefore we do not support conflicting
//alertset choices in an inheritance chain; therefore there will be only one alert
//set chosen, the one closest to the tip (furthest from the root at the defaults).
string find_alertset(mapping alerts, string id) {
	mapping alert = alerts[id];
	if (!alert) return 0; //Shouldn't happen? Bad alert set name.
	if (string s = alert["cond-alertset"]) return s;
	if (alert->parent && alert->parent != "" && alert->parent != "defaults")
		return find_alertset(alerts, alert->parent);
}

mapping resolve_inherits(mapping alerts, string id, mapping alert, string alertset) {
	string par = alert->?parent || (id != alertset && alertset) || "defaults";
	mapping parent = id == "defaults" ? NULL_ALERT //The defaults themselves are defaulted to the vanilla null alert.
		: resolve_inherits(alerts, par, alerts[par], alertset); //Everything else has a parent, potentially implicit.
	if (!alert) return parent;
	return parent | filter(alert) {return __ARGS__[0] && __ARGS__[0] != "";}; //Shouldn't need to filter since it's done on save, may be able to remove this later
}

void resolve_all_inherits(string userid) {
	mapping alerts = persist_status->path("alertbox", userid)->alertconfigs, ret = ([]);
	if (alerts) foreach (alerts; string id; mapping alert) if (id != "defaults") {
		//First walk the list of parents to find the alert set.
		string alertset = find_alertset(alerts, id);
		//Then, resolve inherits via the list of parents AND the alert set.
		mapping resolved = ret[id] = resolve_inherits(alerts, id, alert, alertset);
		//Finally, update some derived information to save effort later.
		resolved->text_css = textformatting_css(resolved);
		if (resolved->image_is_video && COMPAT_VERSION < 3) resolved->version = 3;
		if (resolved->tts_text && COMPAT_VERSION < 4) resolved->version = 4;
	}
	G_G_("alertbox_resolved")[userid] = ret;
}

void resolve_affected_inherits(string userid, string id) {
	//TODO maybe: Resolve this ID, and anything that depends on it.
	//Best way would be to switch this and resolve_all, so that
	//resolve_all really means "resolve those affected by defaults".
	//For now, a bit of overkill: just always resolve all.
	resolve_all_inherits(userid);
}

EventSub raidin = EventSub("raidin", "channel.raid", "1") {
	object channel = G->G->irc->channels["#" + __ARGS__[0]];
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (cfg->hostbackend == "pike") {
		string target = __ARGS__[1]->from_broadcaster_user_login; //TODO: Use user_name instead?
		int viewers = __ARGS__[1]->viewers;
		send_alert(channel, "hostalert", ([
			"NAME": target, "username": target,
			"VIEWERS": viewers, "viewers": viewers,
			"is_raid": 1,
		]));
	}
	//The JS backend doesn't know about raids, won't get alerts for them, but should
	//at very least include them in the hostlist command (which is a hack anyway).
	if (!cfg->hostbackend || cfg->hostbackend == "js")
		send_updates_all(cfg->authkey + channel->name, (["raidhack": __ARGS__[1]->from_broadcaster_user_login]));
	//Stdio.append_file("alertbox_hosts.log", sprintf("[%d] SRVRAID: %s -> %O\n", time(), __ARGS__[0], __ARGS__[1]));
};

void ensure_host_connection(string chan) {
	//If host alerts are active, we need notifications so we can push them through.
	object channel = G->G->irc->channels["#" + chan];
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (cfg->hostbackend == "pike") {
		werror("ALERTBOX: Ensuring connection for %O/%O\n", chan, channel->userid);
		irc_connect((["user": chan, "userid": channel->userid]))->then() {
			werror("ALERTBOX: Connected to %O\n", chan);
		}->thencatch() {
			werror("ALERTBOX: Unable to connect to %O\n", chan);
			werror("%O\n", __ARGS__);
		};
		raidin(chan, (["to_broadcaster_user_id": (string)channel->userid]));
	}
}

bool need_mod(string grp) {return grp == "control" || has_prefix(grp, "preview-");}
string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (string err = ::websocket_validate(conn, msg)) return err;
	if (sscanf(msg->group, "preview-%s#", string user) && user) {
		//Groups like "preview-fred#joe" require (a) that Fred be logged in,
		//and (b) that Fred be a mod for Joe. The first is checked above.
		if (user == "" || user != conn->session->user->?login) return "That's not you";
	}
	if (sscanf(msg->group, "demo-%s#", string ip) && ip) {
		if (ip != conn->remote_ip) return "That's not where you are";
	}
	[object channel, string grp] = split_channel(msg->group);
	mapping cfg = channel && persist_status->path("alertbox", (string)channel->userid);
	if (grp == cfg->?authkey) {
		//When using the official auth key (which will yield the OAuth token), log
		//the IP address used. This will give some indication of whether the key
		//has been leaked. In case mods aren't granted full details of the bcaster's
		//internet location, we obscure the actual IPs behind "IP #1", "IP #2" etc,
		//with the translation to dotted-quad or IPv6 being stored separately.

		//1) Translate conn->remote_ip into an IP index
		int idx = search(cfg->ip_history || ({ }), conn->remote_ip);
		if (idx == -1) {
			cfg->ip_history += ({conn->remote_ip});
			idx = sizeof(cfg->ip_history) - 1;
		}
		//2) Add a log entry, as compactly as possible
		if (!cfg->ip_log || !sizeof(cfg->ip_log) || cfg->ip_log[-1][0] != idx) {
			//Add a new log entry: this IP index, one retrieval between now and now
			cfg->ip_log += ({({idx, 1, time(), time()})});
		} else {
			//For compactness, augment the existing entry.
			array log = cfg->ip_log[-1];
			++log[1]; log[3] = time();
		}
		persist_status->save();
	}
}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (grp == cfg->authkey //The broadcaster, not requiring any login token
		|| has_prefix(grp, "preview-") //Any mod, with the same login token (test alerts only, and only from same user)
		|| (channel->name == "#!demo" && has_prefix(grp, "demo-")) //Anyone using the demo (test alerts from same IP)
	) {
		//Cut-down information for the display
		string chan = channel->name[1..];
		ensure_host_connection(chan);
		string token;
		if (grp == cfg->authkey && has_value((persist_status->path("bcaster_token_scopes")[chan]||"") / " ", "chat:read")) {
			//FIXME: Default to NOT using the JS backend
			if (!cfg->hostbackend || cfg->hostbackend == "js") token = persist_status->path("bcaster_token")[chan];
			else token = "backendinstead";
		}
		return ([
			"alertconfigs": G_G_("alertbox_resolved")[(string)channel->userid] || ([]),
			"token": token,
			"hostlist_command": cfg->hostlist_command || "",
			"hostlist_format": cfg->hostlist_format || "",
			"version": COMPAT_VERSION,
		]);
	}
	if (grp != "control") return 0; //If it's not "control" and not the auth key (or a preview key), it's probably an expired auth key.
	array files = ({ });
	if (id) {
		if (!cfg->files) return 0;
		int idx = search(cfg->files->id, id);
		return idx >= 0 && cfg->files[idx];
	}
	if (!cfg->alertconfigs) cfg->alertconfigs = ([]);
	cfg->alertconfigs->defaults = resolve_inherits(cfg->alertconfigs, "defaults",
		cfg->alertconfigs->defaults || ([]), 0);
	return (["items": cfg->files || ({ }),
		"alertconfigs": cfg->alertconfigs,
		"alerttypes": ALERTTYPES[..<1] + (cfg->personals || ({ })),
		"hostlist_command": cfg->hostlist_command || "",
		"hostlist_format": cfg->hostlist_format || "",
		"replay": cfg->replay || ({ }),
		"replay_offset": cfg->replay_offset || 0,
		"ip_log": cfg->ip_log || ({ }),
		"hostbackend": cfg->hostbackend || "js", //FIXME: Default to "none", or to "pike" if auth
	]);
}

void websocket_cmd_getkey(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->user->id != (string)channel->userid) {
		conn->sock->send_text(Standards.JSON.encode((["cmd": "authkey", "key": "preview-only"]), 4));
		return;
	}
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (!cfg->authkey) {cfg->authkey = String.string2hex(random_string(11)); persist_status->save();}
	conn->sock->send_text(Standards.JSON.encode((["cmd": "authkey", "key": cfg->authkey]), 4));
}

void websocket_cmd_auditlog(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->user->id != (string)channel->userid) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	conn->sock->send_text(Standards.JSON.encode((["cmd": "auditlog", "ip_history": cfg->ip_history]), 4));
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
	array mimetype = (msg->mimetype || "") / "/";
	if (sizeof(mimetype) != 2)
		error = sprintf("Unrecognized MIME type %O", msg->mimetype);
	else if (!(<"image", "audio", "video">)[mimetype[0]])
		error = "Only audio and image (including video) files are supported";
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
	if (changed_alert) update_one(cfg->authkey + channel->name, file->id); //TODO: Is this needed? Does the client conn use these pushes?
}

int(0..1) valid_alert_type(string type, mapping|void cfg) {
	if (has_value(ALERTTYPES->id, type)) return 1;
	if (cfg->?personals && has_value(cfg->personals->id, type)) return 1;
}

void websocket_cmd_testalert(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	//NOTE: Fake clients are fully allowed to send test alerts, but they go only
	//to clients on the same IP address. Similarly, mods sending test alerts will
	//send them to clients on the same login.
	string dest;
	if (channel->name == "#!demo") dest = "demo-" + conn->remote_ip;
	else if (conn->session->user->id == (string)channel->userid) dest = cfg->authkey;
	else dest = "preview-" + conn->session->user->login;
	string basetype = msg->type || ""; sscanf(basetype, "%s-%s", basetype, string variation);
	//TODO: Use send_with_tts() here?
	mapping alert = ([
		"send_alert": valid_alert_type(basetype, cfg) ? msg->type : "hostalert",
		"NAME": channel->name[1..], "username": channel->name[1..], //TODO: Use the display name
		"test_alert": 1,
	]);
	if (variation && !cfg->alertconfigs[msg->type]) alert->send_alert = basetype; //Borked variation name? Test the base alert instead.
	int idx = search(ALERTTYPES->id, basetype);
	mapping pholders = ALERTTYPES[idx]->testpholders;
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
	send_updates_all(dest + channel->name, alert);
}

void websocket_cmd_config(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->fake) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	foreach ("hostlist_command hostlist_format hostbackend" / " ", string key)
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
		if (!cfg->alertconfigs[basetype]) cfg->alertconfigs[basetype] = ([]);
		msg->type = basetype + "-" + variation;
		sock_reply = (["cmd": "select_variant", "type": basetype, "variant": variation]);
	} else if (variation) {
		//Existing variant requested. Make sure the ID has already existed.
		if (!cfg->alertconfigs[msg->type]) return;
	}
	if (!msg->format) {
		//If the format is not specified, this is a partial update, which can
		//change only the SINGLE_EDIT_ATTRS - all others are left untouched.
		mapping data = cfg->alertconfigs[msg->type];
		if (!data) data = cfg->alertconfigs[msg->type] = ([]);
		foreach (SINGLE_EDIT_ATTRS, string attr) if (msg[attr]) data[attr] = msg[attr];
		if (msg->image) {
			//If you're setting the image, see if we need to set the "image_is_video" flag
			int idx = search((cfg->files || ({ }))->url, msg->image);
			if (idx == -1) {
				//If it's a link, let the client tell us which tag to use. It'll
				//only hurt the client if this is wrong anyway.
				data->image_is_video = has_prefix(msg->image, "https://") && msg->image_is_video;
			}
			else data->image_is_video = has_prefix(cfg->files[idx]->mimetype, "video/");
		}
		resolve_affected_inherits((string)channel->userid, msg->type);
		persist_status->save();
		send_updates_all(conn->group);
		send_updates_all(cfg->authkey + channel->name);
		if (sock_reply) conn->sock->send_text(Standards.JSON.encode(sock_reply, 4));
		return;
	}
	//If the format *is* specified, this is a full update, *except* for the retained
	//attributes. Any unspecified attribute will be deleted, setting it to inherit.
	int hosts_were_active = cfg->alertconfigs->?hostalert->?active;
	mapping data = cfg->alertconfigs[msg->type] = filter(
		mkmapping(RETAINED_ATTRS, (cfg->alertconfigs[msg->type]||([]))[RETAINED_ATTRS[*]])
		| mkmapping(FORMAT_ATTRS, msg[FORMAT_ATTRS[*]]))
			{return __ARGS__[0] && __ARGS__[0] != "";}; //Any blank values get removed and will be inherited.
	//You may inherit from "", meaning the defaults, or from any other alert that
	//doesn't inherit from this alert. Attempting to do so will just reset to "".
	//NOTE: Currently you can only inherit from a base alert. This helps to keep
	//the UI a bit less cluttered.
	//Note that technically, the full MRO consists of this array, followed by the
	//alert set (if present), followed by the channel defaults and global defaults.
	if (basetype != "defaults" && stringp(msg->parent) && msg->parent != "" && msg->parent != "defaults" && valid_alert_type(msg->parent, cfg)) {
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

	//Volume can only be set when the audio file is set. If audio inherits (which
	//will be common for variants), volume will also inherit. In theory, you might
	//want to have a variant with "same audio but a little louder"; but since there
	//is no way to express "a little louder" without setting an exact volume, I'm OK
	//with not being able to express "same audio" without explicitly picking the file.
	if (!data->sound) m_delete(data, "volume");
	if (data->format && !has_value(VALID_FORMATS, data->format)) m_delete(data, "format");
	//Similarly, colors can only be set when there's a thing to set the color on. That's
	//governed by either the width or alpha of the corresponding 'thing'. If you don't
	//specify either width or alpha, inherit the color too.
	foreach (indices(data), string key) {
		if (has_suffix(key, "color") && key != "color") {
			string base = key - "color";
			if (!data[base + "width"] && !data[base + "alpha"]) m_delete(data, key);
		}
	}
	textformatting_validate(data);

	if (basetype != "defaults") {
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
		array(string) condvars = ALERTTYPES[idx]->condition_vars;
		if (condvars) foreach (condvars, string c) {
			int is_str = c[0] == '\'';
			c = c[is_str..]; //Strip off the text marker
			string oper = msg["condoper-" + c];
			if (!oper || oper == "") continue; //Don't save the value if no operator set
			int|string val = msg["condval-" + c];
			//The "true" and "false" pseudo-operators are really equality with booleans
			if (oper == "true") {oper = "=="; val = 1;}
			if (oper == "false") {oper = "=="; val = 0;}
			//TODO-STRCOND: Need == and incl for strings
			if (oper != "==" && oper != ">=") oper = ">="; //May need to expand the operator list, but these are the most common
			data["condoper-" + c] = oper;
			//Note that setting the operator and leaving the value blank will set the value to zero.
			if (!is_str) val = (int)val;
			data["condval-" + c] = val;
			if (is_str) val = sizeof(val); //TODO: Tweak specificities in some way to make the display look good
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
	}
	resolve_affected_inherits((string)channel->userid, msg->type);
	if (variation) {
		//For convenience, every time a change is made, we update an array of
		//variants in the base alert's data.
		if (!cfg->alertconfigs[basetype]) cfg->alertconfigs[basetype] = ([]);
		array ids = ({ }), specs = ({ }), names = ({ });
		foreach (cfg->alertconfigs; string id; mapping info)
			if (has_prefix(id, basetype + "-")) {
				ids += ({id});
				specs += ({-info->specificity});
				names += ({lower_case(info->name)});
			}
		sort(names, ids); sort(specs, ids);
		cfg->alertconfigs[basetype]->variants = ids;
	}
	persist_status->save();
	send_updates_all(conn->group);
	send_updates_all(cfg->authkey + channel->name);
	if (sock_reply) conn->sock->send_text(Standards.JSON.encode(sock_reply, 4));
	if (!hosts_were_active) {
		//Host alerts may have just been activated. Make sure we have a backend.
		werror("ALERTBOX: Hosts weren't active for %O/%O\n", channel->name[1..], channel->userid);
		ensure_host_connection(channel->name[1..]);
	}
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

//Words created by a quick brainstorm among DeviCat's community :)
constant cutewords = "puppy kitten crumpet tutu butterscotch flapjack pilliwiggins "
	"puffball buttercup cupcake cookie sprinkle fluffball fluffy squish poke hue "
	"smoosh sweetheart lovely sugarplum blossom kitty paw marshmallow sparkles "
	"chihuahua loaf poof pow bonk hug cuddles meow coffee cherry nom nibbles "
	"fudge cocoa vanilla choco berry tart giggle love dream cotton candy oreo "
	"blueberry rainbow treasure princess cutie shiny dance bread sakura train "
	"gift art flag candle heart love magic save tada hug cool party plush star "
	"donut teacup cat purring flower sugar biscuit pillow banana berry " / " ";
continue Concurrent.Future send_with_tts(object channel, mapping args, string|void destgroup) {
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (!cfg->alertconfigs[args->send_alert]) return 0; //On replay, if the alert doesn't exist, do nothing. TODO: Replay a base alert if variant deleted?
	mapping inh = G_G_("alertbox_resolved", (string)channel->userid, args->send_alert);
	string fmt = inh->tts_text || "", text = "";
	int bits = (int)args->bits;
	if (bits && bits < (int)inh->tts_min_bits) fmt = "";
	while (sscanf(fmt, "%s{%s}%s", string before, string tok, string after) == 3) {
		string replacement = args[tok] || "";
		if (tok == "msg" || tok == "text") {
			if (inh->tts_filter_emotes == "emotes") replacement = args->_noemotes || replacement;
			if (inh->tts_filter_emotes == "cheers" && args->_emoted) {
				//Cheer emotes are the subset of emotes whose IDs start with "/". (That's
				//a StilleBot hack - see connection.pike where cheeremotes are added to the
				//emotes array for the convenience of everything else.) Since we have the
				//URLs for the emotes, check which ones look like emoticon URLs.
				replacement = "";
				foreach (args->_emoted, string|mapping part) {
					if (stringp(part)) replacement += part;
					else if (has_value(part->img, "emoticons/v2")) replacement += part->title;
				}
			}
			if (inh->tts_filter_badwords != "none") {
				if (G->G->tts_config->badwordlist_fetchtime < time() - 86400) {
					object res = yield(Protocols.HTTP.Promise.get_url(
						"https://raw.githubusercontent.com/coffee-and-fun/google-profanity-words/main/data/list.txt"
					));
					G->G->tts_config->badwordlist_fetchtime = time();
					G->G->tts_config->badwordlist = (multiset)String.trim((res->get() / "\n")[*]);
				}
				array words = replacement / " ";
				multiset bad = G->G->tts_config->badwordlist;
				foreach (words; int i; string w) {
					//For the purposes of badword filtering, ignore all non-alphabetics.
					//TODO: Handle "abc123qwe" by checking both abc and qwe?
					sscanf(w, "%*[^A-Za-z]%[A-Za-z]", w);
					if (w == "" || !bad[w]) continue;
					if (inh->tts_filter_badwords == "message") {words = ({ }); break;}
					switch (inh->tts_filter_badwords) {
						case "skip": words[i] = ""; break;
						case "replace": words[i] = random(cutewords); break;
						default: break;
					}
				}
				replacement = words * " ";
			}
		}
		else if (tok == "" || tok[0] == '_') replacement = "";
		text += before + replacement;
		fmt = after;
	}
	text += fmt;
	array voice = (inh->tts_voice || "") / "/";
	if (sizeof(voice) != 3) voice = G->G->tts_config->default_voice / "/";
	if (string token = text != "" && G->G->tts_config->?access_token) {
		object reqargs = Protocols.HTTP.Promise.Arguments((["headers": ([
				"Authorization": "Bearer " + token,
				"Content-Type": "application/json; charset=utf-8",
			]), "data": string_to_utf8(Standards.JSON.encode(([
				"input": (["text": text]),
				"voice": ([
					"languageCode": voice[0],
					"name": voice[1],
					"ssmlGender": voice[2],
				]),
				"audioConfig": (["audioEncoding": "OGG_OPUS"]),
			])))]));
		object res = yield(Protocols.HTTP.Promise.post_url("https://texttospeech.googleapis.com/v1/text:synthesize", reqargs));
		mixed data; catch {data = Standards.JSON.decode_utf8(res->get());};
		if (mappingp(data) && data->error->?details[?0]->?reason == "ACCESS_TOKEN_EXPIRED") {
			Stdio.append_file("tts_error.log", sprintf("%sTTS access key expired after %d seconds\n",
				ctime(time()), time() - G->G->tts_config->access_token_fetchtime));
			mixed _ = yield(fetch_tts_credentials(1));
			reqargs->headers->Authorization = "Bearer " + G->G->tts_config->access_token;
			object res = yield(Protocols.HTTP.Promise.post_url("https://texttospeech.googleapis.com/v1/text:synthesize", reqargs));
			catch {data = Standards.JSON.decode_utf8(res->get());};
			//Exactly one retry attempt; if it fails, fall through and report a generic error.
		}
		if (mappingp(data) && stringp(data->audioContent))
			args->tts = "data:audio/ogg;base64," + data->audioContent;
		else Stdio.append_file("tts_error.log", sprintf("%sBad TTS response: %O\n-------------\n", ctime(time()), data));
	}
	send_updates_all((destgroup || cfg->authkey) + channel->name, args);
}

constant builtin_name = "Send Alert";
constant builtin_description = "Send an alert on the in-browser alertbox. Best with personal (not standard) alerts. Does nothing (no error) if the alert is disabled.";
constant builtin_param = ({"/Alert type/alertbox_id", "Text"});
constant vars_provided = ([
	"{error}": "Error message, if any",
]);
constant command_suggestions = ([]); //This isn't something that you'd create a default command for - it'll want to be custom. (And probably a special, not a command, anyway.)

//Attempt to send an alert. Returns 1 if alert sent, 0 if not (eg if alert disabled).
//Note that the actual sending of the alert is asynchronous, esp if TTS is used.
int(1bit) send_alert(object channel, string alerttype, mapping args) {
	mapping cfg = persist_status->path("alertbox")[(string)channel->userid];
	if (!cfg->?authkey) return 0;
	int suppress_alert = 0;
	mapping alert = cfg->alertconfigs[alerttype]; if (!alert) return 0; //No alert means it can't possibly fire
	if (!alert->active) return 0;
	if (!args->text) { //Alert-specific conditions are ignored if the alert is pushed via the builtin
		int idx = search(ALERTTYPES->id, (alerttype/"-")[0]); //TODO: Rework this so it's a lookup instead (this same check is done twice)
		array(string) condvars = ALERTTYPES[idx]->condition_vars;
		if (condvars) foreach (condvars, string c) {
			//TODO-STRCOND: Don't intify if string var
			int val = (int)args[c];
			int comp = alert["condval-" + c];
			switch (alert["condoper-" + c]) {
				//TODO-STRCOND: Need incl operator for strings
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
	} else { //When pushed via the builtin, the only condition possible is a string comparison on the text.
		string val = args->text;
		string comp = alert["condval-text"];
		switch (alert["condoper-text"]) {
			case "==": if (val != comp) return 0;
			//TODO: Need incl operator as above
			default: break;
		}
	}
	//Note that due to the oddities of alertsets and inheritance, we actually
	//use the *resolved* config to check an alert set. This allows a variant
	//to choose its alertset, it allows a base alert to choose the alertset
	//for all variants, but not for the base alert AND the variant to select
	//conflicting alertsets. Since (as of 20220520) you can't have multiple
	//alert sets active at once, such an alert would never fire anyway.
	mapping resolved = G_G_("alertbox_resolved", (string)channel->userid, alerttype);
	string setname = resolved["cond-alertset"];
	if (mapping set = cfg->alertconfigs[setname]) {
		//Check that the alert set is active, if one is selected
		if (!set->active) return 0;
	}

	//If any variant responds, use that instead.
	foreach (alert->variants || ({ }), string subid)
		if (send_alert(channel, subid, args)) return 1;

	if (suppress_alert) return 0;
	//A completely null alert does not actually fire.
	if (!resolved->image && !resolved->sound && resolved->tts_text == "" && resolved->textformat == "") return 0;

	//Retain alert HERE to remember the precise type
	//On replay, if alerttype does not exist, replay with base alert type?
	args |= (["send_alert": alerttype]);
	//The mapping saved here needs to be disconnected from the one used downstream. Otherwise,
	//we'd be retaining big TTS blobs and stuff.
	//TODO: Prune if necessary (but if so, increment cfg->replay_offset by the number removed)
	cfg->replay += ({args | (["alert_timestamp": time()])});
	persist_status->save();
	send_updates_all("control" + channel->name);
	spawn_task(send_with_tts(channel, args));
	return 1;
}

void websocket_cmd_replay_alert(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (!intp(msg->idx)) return;
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	int idx = msg->idx - cfg->replay_offset;
	if (idx < 0 || idx >= sizeof(cfg->replay)) return;
	//TODO: Deduplicate with testalert
	string dest;
	if (channel->name == "#!demo") dest = "demo-" + conn->remote_ip;
	else if (conn->session->user->id == (string)channel->userid) dest = cfg->authkey;
	else dest = "preview-" + conn->session->user->login;
	//Resend the alert exactly as-is, modulo configuration changes.
	spawn_task(send_with_tts(channel, cfg->replay[idx] | (["test_alert": 1]), dest));
}

mapping parse_emotes(string text, mapping person) {
	string noemotes = "";
	array emoted = ({ });
	int pos = 0;
	if (person->emotes) foreach (person->emotes, [string id, int start, int end]) {
		string before = text[pos..start-1];
		noemotes += before; emoted += ({before});
		emoted += ({([
			//It'd be kinda nice to be able to select the image format based on the
			//font size of the surrounding text (1.0, 2.0, 3.0), but for now, just
			//use the highest resolution image and hope it caches well.
			"img": emote_url(id, 3),
			"title": text[start..end], //Emote name
		])});
		pos = end + 1;
	}
	return (["_noemotes": noemotes + text[pos..], "_emoted": emoted + ({text[pos..]})]);
}

mapping message_params(object channel, mapping person, array|string param)
{
	string alert, text;
	if (arrayp(param)) [alert, text] = param;
	else sscanf(param, "%s %s", alert, text);
	if (!alert || alert == "") return (["{error}": "Need an alert type"]);
	mapping cfg = persist_status->path("alertbox", (string)channel->userid);
	if (!valid_alert_type(alert, cfg)) return (["{error}": "Unknown alert type"]);
	mapping emotes = ([]);
	//TODO: If text isn't exactly %s but is contained in it, give an offset.
	//TODO: If %s is contained in text, parse that somehow too.
	if (text == person->vars[?"%s"]) emotes = parse_emotes(text, person);
	int sent = send_alert(channel, alert, ([
		"TEXT": text || "",
		"text": text || "",
		"username": person->displayname,
	]) | emotes);
	return (["{error}": "", "{alert_sent}": sent ? "yes" : "no"]);
}

@hook_follower:
void follower(object channel, mapping follower) {
	send_alert(channel, "follower", ([
		"NAME": follower->user_name,
		"username": follower->user_name,
	]));
}

//When we fire a dedicated sub bomb alert, save extra->msg_param_origin_id into this
//set, and it will suppress all the alerts from the individuals. Assumptions: The IDs
//are unique across all channels; code will not be updated in the middle of processing
//of a sub bomb (a very narrow window normally - this isn't the length of the alerts);
//and IDs will not be reused.
multiset subbomb_ids = (<>);

@hook_subscription:
void subscription(object channel, string type, mapping person, string tier, int qty, mapping extra, string|void msg) {
	mapping cfg = persist_status->path("alertbox")[(string)channel->userid];
	if (!cfg->?authkey) return;
	int months = (int)extra->msg_param_cumulative_months || 1;
	//If this channel has a subbomb alert variant, the follow-up sub messages will be skipped.
	if (extra->came_from_subbomb && subbomb_ids[extra->msg_param_origin_id]) return;
	mapping args = ([
		"username": person->displayname,
		"tier": tier, "months": months,
		"streak": extra->msg_param_streak_months || "1",
		"msg": msg || "",
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
void cheer(object channel, mapping person, int bits, mapping extra, string msg) {
	mapping cfg = persist_status->path("alertbox")[(string)channel->userid];
	if (!cfg->?authkey) return;
	send_alert(channel, "cheer", ([
		"username": person->displayname,
		"bits": (string)bits,
		"msg": msg,
	]) | parse_emotes(msg, person));
}

constant messagetypes = ({"PRIVMSG"});
void irc_message(string type, string chan, string msg, mapping attrs) {
	if (attrs->user == "jtv") {
		//TODO: Filter to new hosts only
		//TODO: Clear the "new hosts" list when stream goes on/offline
		//-- maybe use timestamps, or when online, clear since last went-offline
		//seenhosts[chan] = 1;
		//For zero-viewer hosts, it looks like "USERNAME is now hosting you."
		//Check what the message says if there are viewers.
		string target = "-", viewers = "0";
		if (has_suffix(msg, " is now hosting you."))
			sscanf(msg, "%s is", target);
		//else sscanf(msg, "%s is now hosting for %s viewers", target, viewers)?
		werror("ALERTBOX: Host target (%O, %O, %O)\n", chan, target, viewers);
		Stdio.append_file("alertbox_hosts.log", sprintf("[%d] SRVHOST: %s -> %O\n", time(), chan, msg));
		if (target && target != "-") {
			object channel = G->G->irc->channels[chan]; if (!channel) return;
			mapping cfg = persist_status->path("alertbox", (string)channel->userid);
			if (cfg->hostbackend == "pike") {
				send_alert(channel, "hostalert", ([
					"NAME": target, "username": target,
					"VIEWERS": viewers, "viewers": viewers,
					"is_raid": 0,
				]));
			}
		}
	}
}

void websocket_cmd_loghost(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%*s#%s", string chan);
	//Technically someone could spam me with these, but I really hope nobody would be that petty :)
	Stdio.append_file("alertbox_hosts.log", sprintf("[%d] CLIHOST: %s -> %O\n", time(), "#" + chan, msg));
}

void irc_closed(mapping options) {
	::irc_closed(options);
	//If we still need host alerts for this user, reconnect.
	mapping cfg = persist_status->path("alertbox", (string)options->userid);
	array socks = websocket_groups[cfg->authkey + "#" + options->user] || ({ });
	werror("ALERTBOX: irc_closed for %O, %d connections, active %O\n", options->user, sizeof(socks), cfg->hostbackend == "pike");
	if (sizeof(socks) && cfg->hostbackend == "pike") irc_connect(options);
}

continue Concurrent.Future fetch_tts_credentials(int fast) {
	mapping rc = Process.run(({"gcloud", "auth", "application-default", "print-access-token"}),
		(["env": getenv() | (["GOOGLE_APPLICATION_CREDENTIALS": "tts-credentials.json"])]));
	G->G->tts_config->access_token = String.trim(rc->stdout);
	//Not sure, but I think credentials expire after a while. It's quite slow to
	//generate them, though, and I'd rather generate only when needed; so for now,
	//this will stay here for diagnosis purposes only. If I can figure out an
	//expiration time, I'll schedule a regeneration at or just before that time.
	//CJA 20220525: Now fetching automatically whenever there's a problem. It'd
	//still be good to preempt that if we can.
	G->G->tts_config->access_token_fetchtime = time();
	if (fast) return 0;
	//To filter to just English results, add "?languageCode=en"
	object res = yield(Protocols.HTTP.Promise.get_url("https://texttospeech.googleapis.com/v1/voices",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Authorization": "Bearer " + G->G->tts_config->access_token,
		])]))));
	mixed data; catch {data = Standards.JSON.decode_utf8(res->get());};
	if (!mappingp(data) || !data->voices) return 0;
	mapping languages = ([]);
	foreach (data->voices, mapping v) {
		//For now, I'm excluding all the premium Wavenet voices. Depending on usage,
		//these might be able to be reenabled, or I could make them a premium feature
		//from my end (ie people who contribute to the costs of TTS can use them).
		if (has_value(v->name, "Wavenet")) continue;
		//The "Neural" voices seem locked - I get Forbiddens. Same with the test voice.
		if (!has_value(v->name, "Standard")) continue;
		//It seems that every voice supports just one language. If this is ever not
		//the case, then hopefully the first one listed is the most important.
		string langcode = m_delete(v, "languageCodes")[0];
		v->selector = sprintf("%s/%s/%s", langcode, v->name, v->ssmlGender);
		v->desc = sprintf("%s (%s)", v->name, lower_case(v->ssmlGender[..0]));
		sscanf(langcode, "%s-%s", string lang, string cc);
		//Google uses ISO 639-3 codes, but I only have a 639-2 table (and 639-1 lookups).
		lang = Standards.ISO639_2.map_639_1(lang) || lang;
		mapping langname = ([
			"eng": " English", //Hack: Sort English at the top since most of my users speak English
			"cmn": "Chinese (Mandarin)",
			"yue": "Chinese (Yue)", //Or should these be inverted ("Yue Chinese")?
		])[lang] || Standards.ISO639_2.get_language(lang) || lang;
		languages[langname + " (" + cc + ")"] += ({v});
	}
	foreach (languages; string lang; array voices) sort(voices->name, voices);
	//Just to make sure the selection isn't completely empty, have a final fallback
	//This is the language code used in the docs (as of 20220519). It shouldn't be
	//used, like, ever, but if TTS isn't available for whatever reason, this means
	//we won't just fail hard.
	if (!sizeof(languages)) languages["en-GB"] = ({(["selector": "en-GB/en-GB-Standard-A/FEMALE", "desc": "Default Voice"])});
	array fallback = languages["en-US"] || languages["en-GB"] || values(languages)[0];
	G->G->tts_config->default_voice = fallback[0]->selector;
	array all_voices = (array)languages;
	sort(indices(languages), all_voices);
	G->G->tts_config->avail_voices = all_voices;
}

protected void create(string name) {
	::create(name);
	//See if we have a credentials file. If so, get local credentials via gcloud.
	if (!G->G->tts_config) G->G->tts_config = ([]);
	if (file_stat("tts-credentials.json") && !G->G->tts_config->access_token) spawn_task(fetch_tts_credentials(0));
	mapping resolved = G_G_("alertbox_resolved");
	//mapping resolved = G->G->alertbox_resolved = ([]); //Use this instead (once) if a change breaks inheritance
	foreach (persist_status->path("alertbox"); string userid;)
		if (!resolved[userid]) resolve_all_inherits(userid);
}

/* A Tale of Two Backends

(Technically three, since "None" is viable, but it's just "not this and not this")

Host alerts can be provided serverside (backend == "pike") or clientside (backend == "js").
These are not currently at feature parity, and they will never be identical in flexibility or security.

JS backend
==========

* Uses ComfyJS inside CEF inside OBS
* Supports !hostlist command to report current hosts
* Independent of IRC issues on Sikorsky
* Requires OAuth token to be sent to client

Pike backend
============

* Uses IRC and pushes signals on websocket
* No !hostlist command. If one is needed, try using the command system to implement it?
* Requires OAuth on the back end only - much safer
* Capable of alert variants, filtering, etc
* Can recognize raids
* Stores replayable alerts

*/
