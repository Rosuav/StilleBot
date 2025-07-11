inherit http_websocket;
inherit builtin_command;
inherit hook;
inherit annotated;
inherit enableable_module;

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
* In addition to WaveNet, there are a bunch of options for pricier TTS. Is it
  worth enabling some of them as paid features?
  https://cloud.google.com/text-to-speech/pricing?hl=en
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
> <div id=uploadfrm class=primary>\
<ul class=tabset>\
<li><input type=radio name=mediatab id=select-freemedia value=freemedia checked><label for=select-freemedia>Free Media</label></li>\
<li><input type=radio name=mediatab id=select-personal value=personal><label for=select-personal>Personal</label></li>\
<li><input type=radio name=mediatab id=select-other value=other><label for=select-other>Other</label></li>\
</ul>\
<div id=mediatab_freemedia><div id=freemedialibrary class=\"filelist primary\"></div></div>\
<div id=mediatab_personal><div id=uploads class=filelist></div></div>\
<div id=mediatab_other><p>&nbsp;</p>\
  <label class=selectmode><input type=radio name=chooseme data-special=None> None</label><br>\
  <span class=selectmode><input type=radio name=chooseme data-special=URL><label> URL: <input id=customurl size=100></label></span>\
</div>\
</div>
> &nbsp;
>
> <label>Upload new file: <input class=fileuploader type=file multiple></label>
> <div class=filedropzone>Or drop files here to upload</div>
>
> &nbsp;
>
> [Select](:#libraryselect disabled=true) [Close](:.dialog_close)
{: tag=dialog #library .resizedlg}

<!-- -->

$$notmodmsg||To use these alerts, [show the preview](:#authpreview) from which you can access your unique display link.<br>$$
$$blank||Keep this link secret; if the authentication key is accidentally shared, you can [Revoke Key](:.opendlg data-dlg=revokekeydlg) to generate a new one.$$

$$notmod2||[Show library](:.showlibrary) [Recent events](:.opendlg data-dlg=recenteventsdlg)$$

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

<ul class=tabset><li id=newpersonal><button id=addpersonal title=\"Add new personal alert\">+</button></li></ul><style id=selectalert></style><div id=alertconfigs></div>

> ### Rename file
> Renaming a file has no effect on alerts; the name is for your benefit entirely.
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
> <div id=replays>loading...</div>
>
> [Close](:.dialog_close)
{: tag=dialog #recenteventsdlg}

<style>
.blur {
	border: 1px solid black;
}
.blur input {
	border: 0;
	background: none;
	filter: blur(2px);
}

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

.tabset {
	display: flex;
	flex-wrap: wrap;
	list-style-type: none;
	margin-bottom: 0;
	padding: 0;
}
.tabset input {display: none;}
.tabset label {
	display: inline-block;
	cursor: pointer;
	padding: 0.4em;
	margin: 0 1px;
	font-weight: bold;
	border: 1px solid black;
	border-radius: 0.5em 0.5em 0 0;
	height: 2em; width: 7.8em;
	text-align: center;
}
.tabset input:checked + label {background: #efd;}
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

#replays {
	display: flex;
	flex-direction: column-reverse; /* Recent at the top */
}
</style>

> ### Alert preview
>
> Drag this to OBS or use this URL as a browser source:
> <a id=alertboxlink href=\"alertbox?key=LOADING\" target=_blank>Alert Box</a><br><label id=alertboxlabel>
> Click to reveal: <span class=blur><input readonly size=65 value=\"https://mustardmine.com/channels/$$channel$$/alertbox?key=(hidden)\" id=alertboxdisplay></span></label>
>
> Your alerts currently look like this:
>
> <iframe id=alertembed width=600 height=400></iframe>
>
> [Test raid alert](:.testalert data-type=hostalert) [Test follow alert](:.testalert data-type=follower)
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

<!-- -->

> ### Manage images and sounds
>
> Select sounds and/or images to be triggered here. These become alert variants.
>
> Keyword | Image | Sound | Hide? | One-shot | Del? | Test
> --------|-------|-------|-------|----------|------|------
> loading... | - | - | - | - | - | -
>
> For these to be functional, you will need a !redeem command and optionally a<br>
> channel point redemption. [Create them!](:#enable_redeem_cmd)
> {: #need-redeem-cmd hidden=1}
>
> [Close](:.dialog_close)
{: tag=dialog #gif-variants}
";

constant MAX_PER_FILE = 16, MAX_TOTAL_STORAGE = 100; //MB
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
	"label": "Raid",
	"heading": "Raided by another channel",
	"description": "When some other channel raids (formerly hosts) yours",
	"placeholders": ([
		"username": "Channel name (equivalently {NAME})",
		"viewers": "View count (equivalently {VIEWERS})",
		"is_raid": "Is this a raid? (As of Oct 2022, always true.)",
	]),
	"testpholders": (["viewers": ({1, 100}), "VIEWERS": ({1, 100}), "is_raid": ({1, 1})]),
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
	"id": "kofi",
	"label": "Ko-Fi",
	"heading": "Ko-Fi donation, new membership, sale, or commission",
	"description": "When someone supports your channel using your Ko-Fi page",
	"placeholders": ([
		"username": "Display name of the supporter",
		"amount": "Amount donated or total sale value (includes currency)",
		"msg": "Message text (if not flagged private)",
		"tiername": "Membership tier, if applicable",
		"is_membership": "Is this a membership (recurring subscription)?",
		"is_shopsale": "Is this a shop item sale?",
		"is_commission": "Is this a commission?",
	]),
	"testpholders": (["amount": "5 USD"]),
	"builtin": "integrations",
	"condition_vars": ({"amount", "is_membership", "is_shopsale", "is_commission", "tiername"}),
]), ([
	"id": "fourthwall",
	"label": "4th Wall",
	"heading": "Fourth Wall sale, donation, or subscription",
	"description": "When someone supports your channel via your Fourth Wall store",
	"placeholders": ([
		"username": "Display name of the supporter",
		"amount": "Amount donated or total sale value",
		"msg": "Message text (if any)",
		"type": "Type of support eg ORDER_PLACED",
	]),
	"testpholders": (["amount": "5"]),
	"builtin": "integrations",
	"condition_vars": ({"amount", "type"}),
]), ([
	"id": "gif",
	"label": "GIFs/Sounds",
	"heading": "Triggerable GIFs or sounds for your community",
	"description": "When someone redeems the reward or otherwise triggers one",
	"placeholders": ([
		"text": "Keyword (ID) for the particular image",
		"is_hidden": "Set to Yes to hide this from the catalogue (it's still viewable)",
	]),
	"testpholders": (["text": "demo"]),
	"builtin": "chan_alertbox",
	"condition_vars": ({"'text", "is_hidden"}),
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
constant SINGLE_EDIT_ATTRS = ({"image", "sound", "muted"}); //Attributes that can be edited by the client without changing the rest
constant RETAINED_ATTRS = SINGLE_EDIT_ATTRS + ({"version", "variants", "image_is_video"}); //Attributes that are not cleared when a full edit is done (changing the format)
constant FORMAT_ATTRS = ("format name description active alertlength alertgap cond-label cond-disableautogen "
			"tts_text tts_dwell tts_volume tts_filter_emotes tts_filter_badwords tts_filter_words tts_voice tts_min_bits "
			"layout alertwidth alertheight textformat volume oneshot") / " " + TEXTFORMATTING_ATTRS;
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
constant LATEST_VERSION = 5; //Bump this every time a change might require the client to refresh.
constant COMPAT_VERSION = 1; //If the change definitely requires a refresh, bump this too.
//Version 3 supports <video> tags for images.
//Version 4 supports TTS.
//Version 5 adds one-shot animations, lengthening alerts to fit.
@retain: mapping tts_config = ([]);
mapping stock_alerts; // == DB->load_config(0, "alertbox")->alertconfigs; cached, fetched on code reload only.

//Text-to-speech rate schedule. RATE_MAX is one higher than the highest defined rate.
enum {RATE_STANDARD, RATE_PREMIUM, RATE_MAX};

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
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
		else if (key != await(G->G->DB->load_config(req->misc->channel->userid, "alertbox"))->authkey)
			return (["error": 401, "type": "text/plain", "data": "Bad key - check the URL from the config page (or remove key= from the URL)"]);
		return render_template("alertbox.html", ([
			"vars": ([
				"ws_type": ws_type, "ws_code": "alertbox",
				"ws_group": group + "#" + req->misc->channel->userid,
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
		return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	}
	if (req->variables->summary) {
		//For API usage eg command viewer, provide some useful information in JSON.
		//Note that this may be queried on a non-active bot, and must remain accurate.
		mapping cfg = await(G->G->DB->load_config(req->misc->channel->userid, "alertbox"));
		return jsonify(([
			"stdalerts": ALERTTYPES[2..<1],
			"personals": cfg->personals || ({ }),
		]));
	}
	mapping premium = await(G->G->DB->load_config(0, "premium_accounts"));
	mapping prem = premium[(string)req->misc->channel->userid] || ([]);
	return render(req, ([
		"vars": (["ws_group": "control",
			"maxfilesize": MAX_PER_FILE, "maxtotsize": MAX_TOTAL_STORAGE,
			"avail_voices": tts_config->avail_voices[?prem->tts_rate] || ({ }),
			"follower_alert_scopes": req->misc->channel->name != "#!demo" && ensure_bcaster_token(req, "moderator:read:followers"),
		]),
	]) | req->misc->chaninfo);
}

//Take a user's alert configs and add in any implicit stock alerts
mapping incorporate_stock_alerts(mapping alertconfigs) {
	mapping alerts = alertconfigs + ([]); //Allow mutation
	//For any alerts that aren't configured here, copy in the corresponding stock alert
	foreach (sort(indices(stock_alerts)), string key) { //NOTE: Must sort, to ensure that base alerts are sighted before their variants
		if (alerts[key]) continue;
		if (sscanf(key, "%s-%s", string base, string var) && var) {
			//Gotta have the variant in the base, which probably means it's largely stock
			if (!alerts[base] || !has_value(alerts[base]->variants || ({ }), key)) continue;
		}
		//Okay. Copy it in.
		alerts[key] = stock_alerts[key];
	}
	return alerts;
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

mapping resolve_inherits(mapping alerts, string id, mapping|zero alert, string|zero alertset) {
	string par = alert->?parent || (id != alertset && alertset) || "defaults";
	mapping parent = id == "defaults" ? NULL_ALERT //The defaults themselves are defaulted to the vanilla null alert.
		: resolve_inherits(alerts, par, alerts[par], alertset); //Everything else has a parent, potentially implicit.
	if (!alert) return parent;
	return parent | alert;
}

void resolve_all_inherits(mapping cfg, string userid) {
	float vol = cfg->muted ? 0.0 : (cfg->mastervolume || 1.0);
	mapping alerts = incorporate_stock_alerts(cfg->alertconfigs || ([]));
	mapping ret = ([]);
	foreach (alerts; string id; mapping alert) if (id != "defaults") {
		//First walk the list of parents to find the alert set.
		string alertset = find_alertset(alerts, id);
		//Then, resolve inherits via the list of parents AND the alert set.
		mapping resolved = ret[id] = resolve_inherits(alerts, id, alert, alertset);
		//Volume overrides are applied at resolution time, to simplify the client.
		if (resolved->muted) resolved->volume = resolved->tts_volume = 0.0;
		else {resolved->volume = (float)resolved->volume * vol; resolved->tts_volume = (float)resolved->tts_volume * vol;}
		//Finally, update some derived information to save effort later.
		resolved->text_css = textformatting_css(resolved);
		if (resolved->image_is_video && COMPAT_VERSION < 3) resolved->version = 3;
		if (resolved->tts_text && COMPAT_VERSION < 4) resolved->version = 4;
		if (resolved->oneshot && COMPAT_VERSION < 5) resolved->version = 5;
		foreach (({"image", "sound"}), string url) {
			if (sscanf(resolved[url] || "f", "freemedia://%s", string fn) && fn) {
				mapping media = G->G->freemedia_filelist->_lookup[fn] || ([]);
				//TODO: What if !media?
				resolved[url] = media->url;
			}
			if (sscanf(resolved[url] || "u", "uploads://%s", string fn) && fn) {
				//We assume here that the file does exist - cheaper than looking it up.
				//If it doesn't, the URL given here will toss a 404 back.
				resolved[url] = sprintf("%s/upload/%s", G->G->instance_config->http_address, fn);
			}
		}
	}
	G_G_("alertbox_resolved")[userid] = ret;
}

void resolve_affected_inherits(mapping cfg, string userid, string id) {
	//TODO maybe: Resolve this ID, and anything that depends on it.
	//Best way would be to switch this and resolve_all, so that
	//resolve_all really means "resolve those affected by defaults".
	//For now, a bit of overkill: just always resolve all.
	resolve_all_inherits(cfg, userid);
}

@EventNotify("channel.raid=1"):
void raidin(object _, mapping info) {
	object channel = G->G->irc->id[(int)info->to_broadcaster_user_id]; if (!channel) return;
	string target = info->from_broadcaster_user_login; //TODO: Use user_name instead?
	int viewers = info->viewers;
	send_alert(channel, "hostalert", ([
		"NAME": target, "username": target,
		"VIEWERS": viewers, "viewers": viewers,
		"is_raid": 1,
	]));
}

void ensure_host_connection(string chan) {
	//If host alerts are active, we need notifications so we can push them through. Function name is orphanned.
	object channel = G->G->irc->channels["#" + chan];
	if (!channel->userid) return; //Most likely the demo channel. Don't try to set up notifications.
}

__async__ void ensure_tts_credentials(int need_tts) { //If you already KNOW we need it, skip the search
	remove_call_out(m_delete(G->G, "ensure_tts_callout"));
	//Check if any connected account uses TTS
	if (!need_tts) {
		//List every channel that uses TTS, then see if any are currently connected.
		array tts_users = await(G->G->DB->query_ro("select twitchid, data -> 'authkey' as authkey from stillebot.config where keyword = 'alertbox' and data -> 'uses_tts' = '1'"));
		foreach (tts_users, mapping cfg) {
			//If you're using the renderer front end, or the editing control panel,
			//ensure that TTS is available (so that test alerts work). Note that
			//preview logins won't trigger this, since they will only ever receive
			//alerts if there's a corresponding control connection.
			if (sizeof(websocket_groups[cfg->authkey + "#" + cfg->userid] || ({ }))) {need_tts = 1; break;}
			if (sizeof(websocket_groups["control#" + cfg->userid] || ({ }))) {need_tts = 1; break;}
		}
	}
	if (!need_tts) return;
	float age = time(tts_config->access_token_fetchtime);
	if (age > 3500) {age = 0.0; spawn_task(fetch_tts_credentials(1));}
	G->G->ensure_tts_callout = call_out(ensure_tts_credentials, 3500.0 - age, 0);
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
	tts_check(channel->userid);
}

__async__ void tts_check(string|int channelid) {
	mapping cfg = await(G->G->DB->load_config(channelid, "alertbox"));
	if (cfg->uses_tts) {
		//Ensure that we have TTS credentials, but note that the current connection has yet
		//to be added to the group arrays (as it's not yet validated). So delay the check
		//and allow the (synchronous) incorporation into the arrays, so that ensure() can
		//see this connection - otherwise, starting the first connection won't check for
		//credentials.
		call_out(ensure_tts_credentials, 0, 1);
	}
}

__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	if (grp == cfg->authkey //The broadcaster, not requiring any login token
		|| has_prefix(grp, "preview-") //Any mod, with the same login token (test alerts only, and only from same user)
		|| (channel->name == "#!demo" && has_prefix(grp, "demo-")) //Anyone using the demo (test alerts from same IP)
	) {
		//Cut-down information for the display. NOTE: If ever previews and the live
		//display are disconnected here, be aware that update_all() uses preview to
		//calculate state, since the authkey might not exist if the broadcaster has
		//never deployed the alertbox. Previews should still remain functional.
		string chan = channel->name[1..];
		ensure_host_connection(chan);
		return ([
			"alertconfigs": G_G_("alertbox_resolved")[(string)channel->userid] || ([]),
			"token": "backendinstead", //20240225: Feature removed, but old copies of the JS may still be around. Can drop this after a reasonable delay.
			"version": COMPAT_VERSION,
		]);
	}
	if (grp != "control") return 0; //If it's not "control" and not the auth key (or a preview key), it's probably an expired auth key.
	if (id) {
		array files = await(G->G->DB->list_channel_files(channel->userid, id));
		return sizeof(files) && (files[0]->metadata | (["id": files[0]->id]));
	}
	array files = await(G->G->DB->list_channel_files(channel->userid));
	foreach (files; int i; mapping f) files[i] = f->metadata | (["id": f->id]);
	if (!cfg->alertconfigs) cfg->alertconfigs = ([]);
	cfg->alertconfigs->defaults = resolve_inherits(cfg->alertconfigs, "defaults",
		cfg->alertconfigs->defaults || ([]), 0);
	return (["items": files,
		"alertconfigs": incorporate_stock_alerts(cfg->alertconfigs),
		"alerttypes": ALERTTYPES[..<1] + (cfg->personals || ({ })),
		"mastervolume": undefinedp(cfg->mastervolume) ? 1.0 : (float)cfg->mastervolume,
		"mastermuted": cfg->muted ? Val.true : Val.false, //Force it to be a boolean so JS can do equality checks
		"replay": cfg->replay || ({ }),
		"replay_offset": cfg->replay_offset || 0,
		"ip_log": cfg->ip_log || ({ }),
		"need_redeem_cmd": !channel->commands->redeem,
	]);
}

//Push out changes to all appropriate sockets, including previews.
void update_all(string|int channelid, string authkey) {
	send_updates_all("control#" + channelid); //The control socket gets all the info (different state to the others)
	//Gather a full list of display sockets. Note that this will still ONLY send to
	//the correct authkey, since an older code that used to check out should not allow
	//you access, unless there's a Vader override.
	array allsocks = ({ });
	foreach (websocket_groups; string grp; array socks)
		if (has_suffix(grp, "#" + channelid) &&
			(grp == authkey + "#" + channelid || has_prefix(grp, "preview-") || has_prefix(grp, "demo-")))
				allsocks += socks;
	//Note that we use preview rather than the authkey here since there
	//might not be an authkey. It's the same state anyway.
	get_state("preview-#" + channelid)->then() {_low_send_updates(__ARGS__[0], allsocks);};
}

__async__ void websocket_cmd_getkey(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	if (conn->session->user->id != (string)channel->userid) {
		conn->sock->send_text(Standards.JSON.encode((["cmd": "authkey", "key": "preview-only"]), 4));
		return;
	}
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	if (!cfg->authkey) {
		cfg->authkey = String.string2hex(random_string(11));
		G->G->DB->save_config(channel->userid, "alertbox", cfg);
	}
	conn->sock->send_text(Standards.JSON.encode((["cmd": "authkey", "key": cfg->authkey]), 4));
}

//NOW it's personal.
@"is_mod": __async__ mapping|zero wscmd_makepersonal(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	if (!cfg->personals) cfg->personals = ({ });
	mapping info, ret;
	if (msg->id && msg->id != "") {
		//Look up an existing one to edit
		int idx = search(cfg->personals->id, msg->id);
		if (idx == -1) return 0; //ID specified and not found? Can't save.
		info = cfg->personals[idx];
	}
	else {
		//Generate an ID that hasn't been used before, and which doesn't start with
		//a digit. Starting with a digit theoretically should be okay, but it causes
		//some issues in CSS, and special-casing the selectors is a lot more hassle
		//than just making sure the IDs always begin with an alphabetic.
		string id;
		do {id = replace(MIME.encode_base64(random_string(9)), (["/": "1", "+": "0"]));}
		while (has_value(cfg->personals->id, id) || id[0] < 'A');
		cfg->personals += ({info = (["id": id])});
		ret = (["cmd": "selecttab", "id": id]);
	}
	foreach ("label heading description" / " ", string key)
		if (stringp(msg[key])) info[key] = msg[key];
	await(G->G->DB->save_config(channel->userid, "alertbox", cfg));
	update_all(channel->userid, cfg->authkey);
	return ret;
}

@"is_mod": __async__ void wscmd_delpersonal(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	if (!cfg->personals) return; //Nothing to delete
	if (!stringp(msg->id)) return;
	int idx = search(cfg->personals->id, msg->id);
	if (idx == -1) return; //Not found (maybe was already deleted)
	cfg->personals = cfg->personals[..idx-1] + cfg->personals[idx+1..];
	if (cfg->alertconfigs) {m_delete(cfg->alertconfigs, msg->id); resolve_all_inherits(cfg, (string)channel->userid);}
	await(G->G->DB->save_config(channel->userid, "alertbox", cfg));
	send_updates_all(conn->group, (["delpersonal": msg->id]));
}

//NOTE: Also invoked by chan_monitors.pike
@"is_mod": __async__ void wscmd_upload(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!intp(msg->size) || msg->size < 0) return; //Protocol error, not permitted. (Zero-length files are fine, although probably useless.)
	array files = await(G->G->DB->list_channel_files(channel->userid));
	int used = `+(0, @files->allocation);
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
	mapping attrs = ([
		"name": msg->name,
		"size": msg->size, "allocation": allocation,
		"mimetype": msg->mimetype,
	]);
	if (conn->type == "chan_monitors") {
		//Hack: When something is uploaded via the Pile of Pics, autocrop transparency away.
		//TODO: Provide a proper option for doing this, independently of socket type
		attrs->autocrop = 1;
	}
	string id = await(G->G->DB->prepare_file(channel->userid, conn->session->user->id, attrs, 0));
	conn->sock->send_text(Standards.JSON.encode((["cmd": "upload", "id": id, "name": msg->name]), 4));
	update_one(conn->group, id); //Note that the display connection doesn't need to be updated
}

@hook_uploaded_file_edited: __async__ void file_uploaded(mapping file) {
	update_one("control#" + file->channel, file->id); //Display connection doesn't need to get updated.
	if (!file->metadata) {
		//File has been deleted. Purge all references to it.
		mapping cfg = await(G->G->DB->load_config(file->channel, "alertbox"));
		int changed_alert = 0;
		string uri = "uploads://" + file->id;
		foreach (cfg->alertconfigs || ([]);; mapping alert)
			while (string key = search(alert, uri)) {
				alert[key] = "";
				changed_alert = 1;
			}
		if (changed_alert) await(G->G->DB->save_config(file->channel, "alertbox", cfg));
	}
}

//Update the magic variable $nonhiddengifredeems$
void update_gif_variants(object channel, mapping cfg) {
	array kwd = ({ });
	foreach (cfg->alertconfigs->gif->variants || ({ }), string var) {
		mapping alert = cfg->alertconfigs[var] || ([]);
		if (!alert["condval-is_hidden"]) kwd += ({alert["condval-text"]});
	}
	sort(kwd);
	channel->set_variable("nonhiddengifredeems", kwd * ", ", "");
}

@"is_mod": __async__ void wscmd_delete(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	if (msg->type == "variant") {
		//Delete an alert variant. Only valid if it's a variant (not a base
		//alert - personals are deleted differently), and has no effect if
		//the alert doesn't exist.
		if (!stringp(msg->id) || !has_value(msg->id, '-')) return;
		if (!cfg->alertconfigs) return;
		sscanf(msg->id, "%s-%s", string basetype, string variation);
		copy_stock(cfg->alertconfigs, basetype);
		mapping base = cfg->alertconfigs[basetype]; if (!base) return;
		if (!arrayp(base->variants)) return; //A properly-saved alert variant should have a base alert with a set of variants.
		m_delete(cfg->alertconfigs, msg->id);
		base->variants -= ({msg->id});
		resolve_affected_inherits(cfg, (string)channel->userid, msg->id);
		await(G->G->DB->save_config(channel->userid, "alertbox", cfg));
		if (basetype == "gif") update_gif_variants(channel, cfg);
		update_all(channel->userid, cfg->authkey);
		conn->sock->send_text(Standards.JSON.encode((["cmd": "select_variant", "type": basetype, "variant": ""]), 4));
		return;
	}
	if (msg->type == "alert") {
		if (!stringp(msg->id) || has_value(msg->id, '-')) return; //Don't delete variants this way (see above instead)
		if (!cfg->alertconfigs) return;
		mapping base = m_delete(cfg->alertconfigs, msg->id);
		if (!base) return; //Already didn't exist.
		if (arrayp(base->variants)) m_delete(cfg->alertconfigs, base->variants[*]);
		resolve_affected_inherits(cfg, (string)channel->userid, msg->id);
		await(G->G->DB->save_config(channel->userid, "alertbox", cfg));
		if (msg->id == "gif") update_gif_variants(channel, cfg);
		update_all(channel->userid, cfg->authkey);
		return;
	}
	G->G->DB->delete_file(channel->userid, msg->id);
}

int(0..1) valid_alert_type(string type, mapping|void cfg) {
	if (has_value(ALERTTYPES->id, type)) return 1;
	if (cfg->?personals && has_value(cfg->personals->id, type)) return 1;
}

__async__ void websocket_cmd_testalert(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
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
	mapping alertcfg = cfg->alertconfigs[msg->type] || stock_alerts[msg->type];
	if (!alertcfg) return;
	int idx = search(ALERTTYPES->id, basetype);
	mapping pholders = ALERTTYPES[idx]->testpholders;
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
	send_updates_all(channel, dest, alert);
}

@"is_mod": __async__ void wscmd_config(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	//foreach ("" / " ", string key) //No configs that are simple strings, actually
	//	if (stringp(msg[key])) cfg[key] = msg[key];
	if (!undefinedp(msg->mastervolume)) cfg->mastervolume = min(max((float)msg->mastervolume, 0.0), 1.0);
	if (!undefinedp(msg->muted)) cfg->muted = !!msg->muted;
	//After changing master audio settings, redo all inherit resolutions
	if (!undefinedp(msg->mastervolume) || !undefinedp(msg->muted)) resolve_all_inherits(cfg, (string)channel->userid);
	await(G->G->DB->save_config(channel->userid, "alertbox", cfg));
	update_all(channel->userid, cfg->authkey);
}

void check_tts_usage(int channelid, mapping cfg) {
	if (!undefinedp(cfg->uses_tts)) return; //Assume it's correct already. Delete the key if it's invalid.
	//Does any alert use TTS? If so, say that we use TTS.
	//Note that, this is somewhat conservative; it will flag the account as using TTS
	//even if the alert in question is disabled, blocked by impossible filtering, etc.
	//The rule is that if uses_tts is set to 0, you should never need TTS credentials.
	cfg->uses_tts = 0;
	foreach (cfg->alertconfigs || ([]); string kw; mapping alert) {
		if (alert->tts_text && alert->tts_text != "") {cfg->uses_tts = 1; break;}
	}
	G->G->DB->save_config(channelid, "alertbox", cfg);
}

void copy_stock(mapping alertconfigs, string basetype) {
	//If an alerts isn't yet configured here, copy in the corresponding stock alert
	mapping base = alertconfigs[basetype]; if (base) return;
	//Copy in the alert. Be sure to avoid unintended change propagation.
	alertconfigs[basetype] = base = Standards.JSON.decode(Standards.JSON.encode(stock_alerts[basetype] || ([])));
	//If the alert has variants, copy those too. Not recursive.
	foreach (base->variants || ({ }), string var)
		alertconfigs[var] = Standards.JSON.decode(Standards.JSON.encode(stock_alerts[var]));
}

@"is_mod": __async__ void wscmd_alertcfg(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	string basetype = msg->type || ""; sscanf(basetype, "%s-%s", basetype, string variation);
	if (!valid_alert_type(basetype, cfg)) return;
	if (!cfg->alertconfigs) cfg->alertconfigs = ([]);
	copy_stock(cfg->alertconfigs, basetype);

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
		//Note that attempting to edit a borked variant ID might cause the base alert
		//to get copied, but then not saved. It shouldn't have any material effect.
		if (!cfg->alertconfigs[msg->type]) return;
	}

	mapping data = cfg->alertconfigs[msg->type];
	if (!data) data = cfg->alertconfigs[msg->type] = ([]);
	if (!msg->format && !msg->set && !msg->unset) {
		//If the format is not specified, this is a partial update, which can
		//change only the SINGLE_EDIT_ATTRS - all others are left untouched.
		if (msg->image) {
			//If you're setting the image, see if we need to set the "image_is_video" flag.
			//Also, if the image URI is invalid, don't set it (retain the previous).
			if (sscanf(msg->image, "uploads://%s", string imgid) && imgid) {
				mapping file = await(G->G->DB->get_file(imgid));
				if (!file) m_delete(msg, "image");
				else data->image_is_video = has_prefix(file->metadata->mimetype, "video/");
			}
			else if (sscanf(msg->image, "freemedia://%s", string fn) && fn) {
				mapping media = G->G->freemedia_filelist->_lookup[fn];
				if (!media) m_delete(msg, "image");
				else data->image_is_video = has_prefix(media->mimetype, "video/");
			}
			//If it's a link, let the client tell us which tag to use. It'll
			//only hurt the client if this is wrong anyway.
			else data->image_is_video = has_prefix(msg->image, "https://") && msg->image_is_video;
		}
		foreach (SINGLE_EDIT_ATTRS, string attr) if (!undefinedp(msg[attr])) data[attr] = msg[attr];
		resolve_affected_inherits(cfg, (string)channel->userid, msg->type);
		await(G->G->DB->save_config(channel->userid, "alertbox", cfg));
		update_all(channel->userid, cfg->authkey);
		if (sock_reply) conn->sock->send_text(Standards.JSON.encode(sock_reply, 4));
		return;
	}
	//If the format *is* specified, and set/unset are not, this is a full update,
	//*except* for the retained attributes. Any unspecified attribute will be
	//deleted, setting it to inherit. (set/unset handling is done below.)

	int hosts_were_active = cfg->alertconfigs->?hostalert->?active;
	//If you've added or removed TTS, make sure that the uses_tts flag is accurate.
	string tts_was = cfg->alertconfigs[msg->type]->tts_text || "";
	string tts_now = msg->tts_text || "";
	if (tts_was == "" && tts_now != "") cfg->uses_tts = 1;
	if (tts_was != "" && tts_now == "") {m_delete(cfg, "uses_tts"); call_out(check_tts_usage, 0.25, channel->userid, cfg);}
	if (msg->set || msg->unset) {
		//Set the given mapping of attributes, and unset the given names.
		//Otherwise, retain existing values.
		//TODO: Merge single-item updates into this?
		foreach (msg->set || ([]); string kwd; mixed val) {
			if (!val || val == "") msg->unset += ({kwd}); //Actually an unset operation, like a MIDI Note-On with velocity zero
			else if (has_value(FORMAT_ATTRS, kwd)) data[kwd] = val;
			else if (has_prefix(kwd, "condoper-") || has_prefix(kwd, "condval-")) msg[kwd] = val; //Technically you could put these into the body of the message, but that's not the official API.
		}
		foreach (msg->unset || ({ }), string kwd) {
			if (has_value(FORMAT_ATTRS, kwd)) m_delete(data, kwd);
			//You may delete a conditional with any of these prefixes and it'll delete both parts.
			sscanf(kwd, "cond-%s", string cond);
			if (!cond) sscanf(kwd, "condoper-%s", cond);
			if (!cond) sscanf(kwd, "condval-%s", cond);
			if (cond) {m_delete(data, "condoper-" + cond); m_delete(data, "condval-" + cond);}
		}
	}
	else data = cfg->alertconfigs[msg->type] = filter(
		mkmapping(RETAINED_ATTRS, data[RETAINED_ATTRS[*]])
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
	//TODO: Allow volume to be set when audio is set, or when video is set and contains
	//audio data. For now, just allowing it always (that's what happens when you're on
	//time pressure and debugging stuff).
	//if (!data->sound) m_delete(data, "volume");
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
	//Check for legacy URLs and update them.
	foreach (({"image", "sound"}), string url) if (data[url] && sscanf(data[url], "uploads://%s", string fn) && fn && !has_value(fn, '-')) {
		string|zero redir = await(G->G->DB->load_config(0, "upload_redirect"))[fn];
		if (redir && sscanf(redir, "https://sikorsky.rosuav.com/upload/%s", string dest)) {
			werror("Legacy URL: %s %s\nResolves to: %O\n", url, data[url], redir);
			data[url] = "uploads://" + dest;
		}
	}
	resolve_affected_inherits(cfg, (string)channel->userid, msg->type);
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
	await(G->G->DB->save_config(channel->userid, "alertbox", cfg));
	if (basetype == "gif") update_gif_variants(channel, cfg);
	update_all(channel->userid, cfg->authkey);
	if (sock_reply) conn->sock->send_text(Standards.JSON.encode(sock_reply, 4));
	if (!hosts_were_active) {
		//Host alerts may have just been activated. Make sure we have a backend.
		//werror("ALERTBOX: Hosts weren't active for %O/%O\n", channel->name[1..], channel->userid);
		ensure_host_connection(channel->name[1..]);
	}
}

@"is_mod": __async__ void wscmd_renamefile(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Rename a file. Won't change its URL (since that's based on ID),
	//nor where the file is stored (it's in the DB), so this is really an
	//"edit description" endpoint. But users will think of it as "rename".
	if (!stringp(msg->id) || !stringp(msg->name)) return;
	mapping file = await(G->G->DB->get_file(msg->id));
	if (!file || file->channel != channel->userid) return; //Not found in this channel.
	file->metadata->name = msg->name;
	G->G->DB->update_file(file->id, file->metadata);
	update_one(conn->group, file->id);
}

@"is_mod": __async__ void wscmd_revokekey(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string prevkey;
	await(G->G->DB->mutate_config(channel->userid, "alertbox") {prevkey = m_delete(__ARGS__[0], "authkey");});
	send_updates_all(conn->group, (["authkey": "<REVOKED>"]));
	send_updates_all(channel, prevkey, (["breaknow": 1]));
}

//Currently no UI for this, but it works if you fiddle on the console.
@"is_mod": __async__ void wscmd_reload(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	//Send a fake version number that's higher than the current, thus making it think
	//it needs to update. After it reloads, it will get the regular state, with the
	//current version, so it'll reload once and then be happy.
	//NOTE: Despite previews done by mods being isolated from the broadcaster, this
	//signal is not. This allows emergency fixes as needed, though they shouldn't ever
	//make any difference. Could disallow mods from using this if necessary. Note also
	//that you can't remotely reload your preview in this way. It's also probably not
	//necessary, given that normal use of previews will be in a context where you can
	//reload manually; inside OBS or equivalent, it's going to be the live key.
	send_updates_all(channel, cfg->authkey, (["version": LATEST_VERSION + 1]));
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
__async__ string filter_bad_words(string text, string mode) {
	if (tts_config->badwordlist_fetchtime < time() - 86400) {
		object res = await(Protocols.HTTP.Promise.get_url(
			"https://raw.githubusercontent.com/coffee-and-fun/google-profanity-words/main/data/list.txt"
		));
		tts_config->badwordlist_fetchtime = time();
		tts_config->badwordlist = (multiset)String.trim((res->get() / "\n")[*]);
	}
	array words = text / " ";
	multiset bad = tts_config->badwordlist;
	foreach (words; int i; string w) {
		//For the purposes of badword filtering, ignore all non-alphabetics.
		//TODO: Handle "abc123qwe" by checking both abc and qwe?
		sscanf(w, "%*[^A-Za-z]%[A-Za-z]", w);
		if (w == "" || !bad[w]) continue;
		if (mode == "message") return "";
		switch (mode) {
			case "skip": words[i] = ""; break;
			case "replace": words[i] = random(cutewords); break;
			default: break;
		}
	}
	return words * " ";
}

__async__ string|zero text_to_speech(string text, string voice, int|void userid) {
	string token = tts_config->?access_token;
	if (!token) return 0;
	array v = voice / "/";
	//Different whitelists for different userids (default to rate 0 aka Standard if not recognized)
	mapping premium = await(G->G->DB->load_config(0, "premium_accounts"));
	mapping prem = premium[(string)userid] || ([]);
	if (!tts_config->voices[prem->tts_rate][v[1]]) return 0;
	object reqargs = Protocols.HTTP.Promise.Arguments((["headers": ([
			"Authorization": "Bearer " + token,
			"Content-Type": "application/json; charset=utf-8",
		]), "data": string_to_utf8(Standards.JSON.encode(([
			"input": (["text": text]),
			"voice": ([
				"languageCode": v[0],
				"name": v[1],
				"ssmlGender": v[2],
			]),
			"audioConfig": (["audioEncoding": "OGG_OPUS"]),
		])))]));
	System.Timer tm = System.Timer();
	object res = await(Protocols.HTTP.Promise.post_url("https://texttospeech.googleapis.com/v1/text:synthesize", reqargs));
	float delay = tm->get();
	Stdio.append_file("tts_stats.log", sprintf("User %d text %O fetch time %.3f\n", userid, text, delay));
	mixed data; catch {data = Standards.JSON.decode_utf8(res->get());};
	if (mappingp(data) && data->error->?details[?0]->?reason == "ACCESS_TOKEN_EXPIRED") {
		Stdio.append_file("tts_error.log", sprintf("%sTTS access key expired after %d seconds\n",
			ctime(time()), time() - tts_config->access_token_fetchtime));
		await(fetch_tts_credentials(1));
		reqargs->headers->Authorization = "Bearer " + tts_config->access_token;
		object res = await(Protocols.HTTP.Promise.post_url("https://texttospeech.googleapis.com/v1/text:synthesize", reqargs));
		catch {data = Standards.JSON.decode_utf8(res->get());};
		//Exactly one retry attempt; if it fails, fall through and report a generic error.
	}
	if (mappingp(data) && stringp(data->audioContent))
		return "data:audio/ogg;base64," + data->audioContent;
	Stdio.append_file("tts_error.log", sprintf("%sBad TTS response: %O\n-------------\n", ctime(time()), data));
}

__async__ void send_with_tts(object channel, mapping args, string|void destgroup, mapping cfg) {
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
			if (inh->tts_filter_badwords != "none") replacement = await(filter_bad_words(replacement, inh->tts_filter_badwords));
		}
		else if (tok == "" || tok[0] == '_') replacement = "";
		text += before + replacement;
		fmt = after;
	}
	text += fmt;
	string voice = inh->tts_voice || "";
	if (sizeof(voice / "/") != 3) voice = tts_config->default_voice;
	if (string tts = text != "" && await(text_to_speech(text, voice, channel->userid))) args->tts = tts;
	send_updates_all((destgroup || cfg->authkey) + "#" + channel->userid, args);
}

constant builtin_name = "Send Alert";
constant builtin_description = "Send an alert on the in-browser alertbox. Best with personal (not standard) alerts. Does nothing (no error) if the alert is disabled.";
constant builtin_param = ({"/Alert type/alertbox_id", "Text"});
constant vars_provided = (["{alert_sent}": "Either 'yes' or 'no' depending on whether the alert happened."]);

//Attempt to send an alert. Returns 1 if alert sent, 0 if not (eg if alert disabled).
//Note that the actual sending of the alert is asynchronous, esp if TTS is used.
__async__ int(1bit) send_alert(object channel, string alerttype, mapping args, mapping|void cfg) {
	if (!cfg) cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	if (!cfg->authkey) return 0;
	int suppress_alert = 0;
	mapping alert = cfg->alertconfigs[?alerttype]; if (!alert) return 0; //No alert means it can't possibly fire
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
		//NOTE: With GIF alerts, there will potentially be an is_hidden flag, but it
		//does not affect alert filtering.
		switch (alert["condoper-text"]) {
			//Note that comparisons are currently case insensitive and there's no way to configure that. Should there be?
			case "==": if (lower_case(String.trim(val)) != lower_case(String.trim(comp))) return 0;
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
		if (await(send_alert(channel, subid, args, cfg))) return 1;

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
	await(G->G->DB->save_config(channel->userid, "alertbox", cfg));
	send_updates_all(channel, "control");
	spawn_task(send_with_tts(channel, args, 0, cfg));
	return 1;
}

__async__ void websocket_cmd_replay_alert(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel || grp != "control") return;
	//Note that alert replaying IS permitted for fake mods (ie demo channel)
	if (!intp(msg->idx)) return;
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	int idx = msg->idx - cfg->replay_offset;
	if (idx < 0 || idx >= sizeof(cfg->replay)) return;
	//TODO: Deduplicate with testalert
	string dest;
	if (channel->name == "#!demo") dest = "demo-" + conn->remote_ip;
	else if (conn->session->user->id == (string)channel->userid) dest = cfg->authkey;
	else dest = "preview-" + conn->session->user->login;
	//Resend the alert exactly as-is, modulo configuration changes.
	spawn_task(send_with_tts(channel, cfg->replay[idx] | (["test_alert": 1]), dest, cfg));
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

__async__ mapping message_params(object channel, mapping person, [string alert, string text], mapping msgcfg) {
	if (!alert || alert == "") error("Need an alert type\n");
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	if (!valid_alert_type(alert, cfg)) error("Unknown alert type\n");
	if (msgcfg->simulate) {
		string label = alert;
		foreach (ALERTTYPES + (cfg->personals || ({ })), mapping a)
			if (a->id == alert) label = a->label;
		msgcfg->simulate("Send alert " + label);
		return ([]);
	}
	mapping emotes = ([]);
	//TODO: If text isn't exactly %s but is contained in it, give an offset.
	//TODO: If %s is contained in text, parse that somehow too.
	if (text == person->vars[?"%s"]) emotes = parse_emotes(text, person);
	int sent = await(send_alert(channel, alert, ([
		"TEXT": text || "",
		"text": text || "",
		"username": person->displayname,
	]) | emotes, cfg));
	return (["{alert_sent}": sent ? "yes" : "no"]);
}

@hook_follower:
void follower(object channel, mapping follower) {
	if (!follower) {werror("NULL FOLLOWER: %O\n", channel); return;}
	send_alert(channel, "follower", ([
		"NAME": follower->user_name,
		"username": follower->user_name,
	]));
}

//Sub bombs result in a dedicated "sub bomb" notification, followed by the individual
//sub gifts. If we have a sub bomb alert, we fire that when the notification comes in,
//and then suppress the individual alerts; but if we don't, the individual ones will
//happen. This raises a bit of a problem. All those alerts will arrive in short order,
//and we have to fetch from the database asynchronously, so we need to respond to the
//individual alert before we even know whether a sub bomb alert exists.
//Thus, this. It maps extra->msg_param_origin_id (which is the same for the bomb and
//all the individuals) to one of three options:
//0 (absent): No sub bomb known, or no sub bomb alert. Let the alert fire.
//An array: Add yourself to the array and do nothing.
//1: We've fired the bomb alert, so suppress the individual alert.
mapping(string:array|int(0..1)) subbomb_ids = ([]);

@hook_subscription:
void subscription(object channel, string type, mapping person, string tier, int qty, mapping extra, string|void msg) {
	int months = (int)extra->msg_param_cumulative_months || 1;
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
	//If this channel has a subbomb alert variant, the follow-up sub messages will be skipped.
	string id = extra->msg_param_origin_id;
	if (extra->came_from_subbomb) {
		if (arrayp(subbomb_ids[id])) subbomb_ids[id] += ({args});
		if (subbomb_ids[id]) return;
	}
	if (type == "subbomb") {
		subbomb_ids[id] = ({ });
		send_subbomb_alert(channel, args, id);
	}
	else send_alert(channel, "sub", args);
}

__async__ void send_subbomb_alert(object channel, mapping args, string id) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "alertbox"));
	if (await(send_alert(channel, "sub", args, cfg))) {
		//A sub bomb alert was sent. Suppress the rest.
		subbomb_ids[id] = 1;
	} else {
		//The bomb wasn't sent. Queue up any of the existing alerts, and
		//remove the marker so subsequent alerts will fire naturally.
		foreach (m_delete(subbomb_ids, id), args) await(send_alert(channel, "sub", args, cfg));
	}
}

@hook_cheer:
void cheer(object channel, mapping person, int bits, mapping extra, string msg) {
	//TODO: Should there be a boolean to say is_powerup so they can be filtered
	//out or given variant alerts? Note that some rewards may include emoted
	//text, which is not going to be parsed correctly at the moment. Would be
	//nice to parse out extra->message->emotes in that situation.
	send_alert(channel, "cheer", ([
		"username": person->displayname,
		"bits": (string)bits,
		"msg": msg,
	]) | parse_emotes(msg, person));
}

constant ENABLEABLE_FEATURES = ([
	"!redeem": ([
		"description": "Trigger GIF/sound alerts via redemption or command",
		"response": ([
			"conditional": "string",
			"expr1": "{param}",
			"message": ([
				"conditional": "string",
				"expr1": "$nonhiddengifredeems$",
				"message": "Select one of the (top secret!) keywords to redeem an alert!",
				"otherwise": "Available GIFs: $nonhiddengifredeems$",
			]),
			"otherwise": ([
				"conditional": "catch",
				"message": ([
					"builtin": "chan_alertbox", "builtin_param": ({"gif", "{param}"}),
					"message": ([
						"conditional": "string", "casefold": "",
						"expr1": "{alert_sent}", "expr2": "yes",
						"message": ([
							"builtin": "chan_pointsrewards",
							"builtin_param": ({"{rewardid}", "fulfil", "{redemptionid}"}),
							"message": ([
								"conditional": "string",
								"expr1": "{error}",
								"message": "",
								"otherwise": "Unexpected error: {error}",
							]),
						]),
						"otherwise": ([
							"builtin": "chan_pointsrewards",
							"builtin_param": ({"{rewardid}", "cancel", "{redemptionid}"}),
							"message": "Unrecognized keyword {param}, points refunded",
						]),
					]),
				]),
				"otherwise": ([
					"builtin": "chan_pointsrewards",
					"builtin_param": ({"{rewardid}", "cancel", "{redemptionid}"}),
					"message": "Unexpected error: {error}",
				]),
			]),
		]),
	]),
]);

int can_manage_feature(object channel, string kwd) {return channel->commands[kwd - "!"] ? 2 : 1;}

void enable_feature(object channel, string kwd, int state) {
	mapping info = ENABLEABLE_FEATURES[kwd]; if (!info) return;
	array tok = token_for_user_id(channel->userid);
	if (kwd == "!redeem" && has_value(tok[1] / " ", "channel:manage:redemptions")) {
		//Attempt to create a GIF redeem reward - this will fail if not partner/affiliate
		if (state) {
			string prompt = "Select a GIF to trigger: $nonhiddengifredeems$";
			twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + channel->userid,
				(["Authorization": "Bearer " + tok[0]]),
				(["method": "POST", "json": ([
					"title": "GIFs and sounds",
					"prompt": channel->expand_variables(prompt),
					"cost": 1000,
					"global_cooldown_seconds": 60,
					"is_global_cooldown_enabled": Val.true,
					"is_user_input_required": Val.true,
				])]),
			)->then() {
				//Update the !redeem command to respond to this reward.
				mapping cmd = channel->commands->redeem;
				if (!cmd) return; //No command? Don't update.
				string rewardid = __ARGS__[0]->data[0]->id;
				if (!mappingp(cmd)) cmd = (["message": cmd, "redemption": rewardid]);
				else cmd = cmd | (["redemption": rewardid]);
				G->G->cmdmgr->update_command(channel, "", kwd - "!", cmd);
				G->G->DB->mutate_config(channel->userid, "dynamic_rewards") {
					__ARGS__[0][rewardid] = ([
						"basecost": 0, "availability": "{online}", "formula": "PREV",
						"prompt": prompt,
					]);
				};
			}
			->thencatch() {werror("Error creating !redeem reward: %O\n", __ARGS__);}; //TODO: Ignore the "must be partner/affiliate" error.
		} else {
			mapping cmd = channel->commands->redeem;
			if (mappingp(cmd) && cmd->redemption) twitch_api_request(
					"https://api.twitch.tv/helix/channel_points/custom_rewards?" +
					"broadcaster_id=" + channel->userid +
					"&id=" + cmd->redemption,
				(["Authorization": "Bearer " + tok[0]]),
				(["method": "DELETE"]))
				->thencatch() {werror("Error deleting !redeem reward: %O\n", __ARGS__);};
		}
	}
	G->G->cmdmgr->update_command(channel, "", kwd - "!", state && info->response);
}

@"is_mod": void wscmd_enable_redeem_cmd(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	enable_feature(channel, "!redeem", 1);
	send_updates_all(conn->group);
}

__async__ void fetch_tts_credentials(int fast) {
	mapping rc = await(run_process(({"gcloud", "auth", "application-default", "print-access-token"}),
		(["env": getenv() | (["GOOGLE_APPLICATION_CREDENTIALS": "tts-credentials.json"])])));
	tts_config->access_token = String.trim(rc->stdout);
	//Credentials expire after an hour, regardless of usage. It's quite slow to
	//generate them, so we do it only as needed; if anything fails in the preemptive
	//checks, we'll run into an issue and then automatically fetch, but otherwise,
	//this is just to help with scheduling. It might be nicer if we had an expiration
	//date instead, but for now we just use the fetch time.
	tts_config->access_token_fetchtime = time();
	if (fast) return 0;
	//To filter to just English results, add "?languageCode=en"
	object res = await(Protocols.HTTP.Promise.get_url("https://texttospeech.googleapis.com/v1/voices",
		Protocols.HTTP.Promise.Arguments((["headers": ([
			"Authorization": "Bearer " + tts_config->access_token,
		])]))));
	mixed data; catch {data = Standards.JSON.decode_utf8(res->get());};
	if (!mappingp(data) || !data->voices) return 0;
	//Rate 0 is standard, rate 1 is premium. Maybe add even higher rates in the future??
	array(mapping) language_rates = allocate(RATE_MAX, ([]));
	tts_config->voices = allocate(RATE_MAX, (<>));
	foreach (data->voices, mapping v) {
		//For now, I'm excluding all the premium Wavenet voices. Depending on usage,
		//these might be able to be reenabled, or I could make them a premium feature
		//from my end (ie people who contribute to the costs of TTS can use them).
		int rate;
		if (has_value(v->name, "Standard")) rate = 0;
		else if (has_value(v->name, "Wavenet")) rate = 1;
		else continue; //Completely exclude all the other types, some of which are VERY pricey
		//It seems that every voice supports just one language. If this is ever not
		//the case, then hopefully the first one listed is the most important.
		string langcode = m_delete(v, "languageCodes")[0];
		v->selector = sprintf("%s/%s/%s", langcode, v->name, v->ssmlGender);
		v->desc = sprintf("%s (%s)", v->name, lower_case(v->ssmlGender[..0]));
		sscanf(langcode, "%s-%s", string lang, string cc);
		//Google uses ISO 639-3 codes, but I only have a 639-2 table (and 639-1 lookups).
		lang = Standards.ISO639_2.map_639_1(lang) || lang;
		string langname = ([
			"eng": " English", //Hack: Sort English at the top since most of my users speak English
			"cmn": "Chinese (Mandarin)",
			"yue": "Chinese (Yue)", //Or should these be inverted ("Yue Chinese")?
		])[lang] || Standards.ISO639_2.get_language(lang) || lang;
		for (int r = rate; r < RATE_MAX; ++r) {
			tts_config->voices[r][v->name] = 1;
			language_rates[r][langname + " (" + cc + ")"] += ({v});
		}
	}
	foreach (language_rates; int rate; mapping languages) {
		foreach (languages; string lang; array voices) sort(voices->name, voices);
		//Just to make sure the selection isn't completely empty, have a final fallback
		//This is the language code used in the docs (as of 20220519). It shouldn't be
		//used, like, ever, but if TTS isn't available for whatever reason, this means
		//we won't just fail hard.
		if (!sizeof(languages)) languages["en-GB"] = ({(["selector": "en-GB/en-GB-Standard-A/FEMALE", "desc": "Default Voice"])});
		array fallback = languages["en-US"] || languages["en-GB"] || values(languages)[0];
		tts_config->default_voice = fallback[0]->selector;
		array all_voices = (array)languages;
		sort(indices(languages), all_voices);
		language_rates[rate] = all_voices;
	}
	tts_config->avail_voices = language_rates;
}

__async__ void initialize_inherits() {
	//Fetch the free media file list if needed, then resolve inherits (which needs free media URLs)
	if (G->G->freemedia_filelist->?_last_fetched < time() - 3600) {
		Protocols.HTTP.Promise.Result res = await(Protocols.HTTP.Promise.get_url("https://rosuav.github.io/free-media/filelist.json"));
		mapping fl = G->G->freemedia_filelist = Standards.JSON.decode_utf8(res->get());
		fl->_last_fetched = time();
		fl->_lookup = mkmapping(fl->files->filename, fl->files);
	}
	mapping resolved = G_G_("alertbox_resolved");
	//mapping resolved = G->G->alertbox_resolved = ([]); //Use this instead (once) if a change breaks inheritance
	mapping allcfg = await(G->G->DB->load_all_configs("alertbox"));
	stock_alerts = allcfg[0]->alertconfigs;
	foreach (allcfg; int userid; mapping cfg)
		if (!resolved[(string)userid]) resolve_all_inherits(cfg, (string)userid);
}

protected void create(string name) {
	::create(name);
	//See if we have a credentials file. If so, get local credentials via gcloud.
	if (file_stat("tts-credentials.json") /*&& !tts_config->access_token*/) spawn_task(fetch_tts_credentials(0));
	initialize_inherits();
	G->G->send_alert = send_alert;
	ensure_tts_credentials(0);
}
