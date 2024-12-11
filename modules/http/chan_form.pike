inherit annotated;
inherit hook;
inherit http_websocket;
inherit builtin_command;
constant shared_styles = #"
<style>
label span {
	min-width: 10em;
	font-weight: bold;
	display: inline-block;
}
img[alt=\"(avatar)\"] {
	height: 40px;
	vertical-align: middle;
}
img {
	max-width: 100%;
}
</style>
";

constant markdown = #"# Forms for $$channel$$

* loading...
{:#forms}

[Create form](:#createform) [Manage encryption](:.opendlg data-dlg=encryptiondlg)

> ### Edit form
>
> $$formfields$$
> <label><span>Form completion message:</span><br><textarea class=formmeta name=thankyou placeholder=\"Thank you for filling out this form!\" rows=3 cols=50></textarea></label>
>
> [Link to form](form?form=FORMID :#viewform target=_blank) (only while form is open)<br>
> [View form responses](form?responses=FORMID :#viewresp target=_blank) (opens in new window)<br>
> [Delete form](:#delete_form)
>
> #### Form elements
> <div id=formelements></div>
> <select id=addelement><option value=\"\">Add new element$$elementtypes$$</select>
>
> [Close](:.dialog_close)
{: tag=formdialog #editformdlg}

<style>
.openform {
	color: blue;
	text-decoration: underline;
	cursor: pointer;
}
.element {
	border: 1px solid black;
	margin: 0.5em;
	padding: 0.5em;
}
.element .header {
	background: #ccc;
	margin: -0.5em; /* Put the background all the way to the black border */
	padding: 0.5em; /* But still have the gap */
}
.element .topmatter {
	display: flex;
	justify-content: space-between;
}
#encryptiondlg label span {
	/* These ones are wider */
	min-width: 17em;
}
#encryptiondlg li {
	list-style-type: none;
}
</style>

> ### Encryption
>
> For added security, particularly if you allow your mods to view form responses, you may<br>
> encrypt addresses. This affects only the email address and street address field types.<br>
> Once encryption is enabled, all current and future form responses will be protected.
>
> **CAUTION:** If you lose the password, there is no way to recover the addresses!
>
> * <label><span>Enter password to view addresses:</span> <input type=password autocomplete=current-password size=20 name=decrypt></label> [Show addresses](:#submitpwd)
> * <label><span>Enter a password to encrypt with:</span> <input type=password autocomplete=new-password size=20 name=encrypt></label>
> * <label><span>Enter it again:</span> <input type=password autocomplete=new-password size=20 name=confirm></label>
> * [Decrypt or change password](:#decrypt)
> * [ENCRYPT ADDRESSES](:#encrypt)
>
> [Close](:.dialog_close)
{: tag=formdialog #encryptiondlg}
" + shared_styles;

constant formview = #"# $$formtitle$$

$$formbanner$$

<form method=post>

$$formdata$$

<button type=submit>Submit response</button>
</form>

<style>
form section {
	border: 1px solid black;
	margin: 0.1em;
	padding: 0.5em;
}
textarea {
	vertical-align: text-top;
}
.required { /* The marker that follows a required field, not to be confused with input:required */
	color: red;
}
.banner {
	background: #ffffdd;
	border: 1px solid #ffff00;
	position: fixed;
	top: 0; left: 0; right: 0;
	min-height: 2em;
	text-align: center;
	font-size: larger;
	padding: 0.8em;
}
button img {
	height: 1.5em;
	vertical-align: bottom;
}
.errorbanner {
	background: #ffdddd;
	border: 1px solid #ff0000;
	width: 100%;
	text-align: center;
	padding: 0.4em;
}
</style>
" + shared_styles;

constant formmessage = #"# $$formtitle$$

$$message$$

" + shared_styles;

constant formresponses = #"# Form responses

[Back to form list](form)

* <label><input type=checkbox id=showarchived> Show archived responses</label>
* <label>Group by <select id=groupfield><option value=\"\">Select field...</select></label>
{:#responseoptions}

&nbsp; | Permitted | Submitted | Twitch user | Answers
-------|-----------|-----------|-------------|---------
loading... | -
{:#responses}

[Download CSV](:#downloadcsv) [Archive selected](:#archiveresponses disabled=1) [Delete selected](:#deleteresponses disabled=1)

> ### Form response
>
> <label><span>Permitted at:</span> <input readonly name=permitted></label><br>
> <label><span>Submitted at:</span> <input readonly name=timestamp></label><br>
> <div id=archived_at></div>
>
> <div id=formdesc></div>
>
> Field | Response
> ------|---------
> loading... | -
> {:#formresponse}
>
> [Close](:.dialog_close)
{: tag=dialog #responsedlg}

<style>
#responseoptions {
	list-style-type: none;
	padding: 0;
	display: flex;
	gap: 2em;
}
.checkbox-unchecked { /* Test for readability and unobtrusiveness */
	opacity: .75;
}
:has(#showarchived:checked) ~ table tr.archived {
	display: revert;
}
tr.archived {
	display: none;
	font-style: italic;
	background: #ccc;
}
tr.row-default {background: #eef;}
tr.row-alternate {background: #efe;}
.twocol {
	display: flex;
	gap: 1em;
}
.twocol > * {
	width: max-content;
	margin: 0;
}
.column {
	display: flex;
	flex-direction: column;
	justify-content: space-around;
}
</style>

> ### Encrypted addresses
>
> Content in this channel's forms is encrypted with a password.
>
> <label><span>Enter password to view addresses:</span> <input type=password autocomplete=current-password size=20 name=decrypt></label> [Show addresses](:#submitpwd .dialog_close)
>
> [Cancel](:.dialog_close)
{: tag=formdialog #passworddlg}
" + shared_styles;

array formfields = ({
	({"id", "readonly", "Form ID"}),
	({"formtitle", "", "Title"}),
	({"is_open", "type=checkbox", "Open form"}),
	({"mods_see_responses", "type=checkbox", "Allow mods to see responses"}),
});

array _element_types = ({ //Search for _element_types in this and the JS to find places to add more
	({"twitchid", "Twitch username"}), //If mandatory, will force user to be logged in to submit
	({"simple", "Text input"}),
	({"url", "URL (web address)"}),
	({"paragraph", "Paragraph input"}),
	({"address", "Street address"}),
	//({"radio", "Selection (radio) buttons"}), //Should generally be made mandatory
	({"checkbox", "Check box(es)"}), //If mandatory, at least one checkbox must be selected (but more than one may be)
	({"text", "Informational text"}),
});
mapping element_types = (mapping)_element_types;
mapping element_attributes = ([ //Matches _element_types
	"twitchid": ([
		"permitted_only": type_boolean,
		"require_follower": type_boolean,
		"require_subscriber": type_boolean,
	]),
	"simple": (["label": type_string]),
	"url": (["label": type_string]),
	"paragraph": (["label": type_string]),
	"address": ([
		"label-name": type_string,
		"label-street": type_string,
		"label-city": type_string,
		"label-state": type_string,
		"label-postalcode": type_string,
		"label-country": type_string,
	]),
	"checkbox": (["label[]": type_string]),
	"text": ([]), //No special attributes, only the universal ones
]);
array address_parts = ({
	({"name", "Name"}),
	({"street", "Street"}),
	({"city", "City"}),
	({"state", "State/Province"}),
	({"postalcode", "Postal code"}),
	({"country", "Country"}),
});
constant address_required = ({"name", "street", "city", "country"}); //If an address field is required, which parts are?

@retain: mapping session_decryption_key = ([]);

//Encrypt a string and return an array of blocks, or leave it cleartext and return as-is
string|array(string) encrypt_with_key(object rsakey, string text) {
	if (!rsakey || !text || text == "") return text;
	//The block size given requires 8 bytes of chunk overhead
	return String.string2hex(rsakey->encrypt((string_to_utf8(text) / (rsakey->block_size() - 8.0))[*])[*]);
	//After it's encrypted, we store it as an array of hex strings, eg
	//({"221933daa9451fb56f3...", "472efdc635e657bd91d..."})
	//There is a small amount of information in the number of blocks, but with a 1024-bit key
	//you get 117-byte blocks. That means anything up to 117 bytes (in UTF-8) will be stored
	//as a single block, giving little useful information - maybe you could figure out that
	//someone has a long street address or something. This would be further obscured by moving
	//to a 2048-bit key and getting 245-byte blocks; very few inputs would need a second chunk.
}

mapping mods_see_responses = ([]); //Map a group (eg "7957ea32#49497888", encoding both the form ID and channel) to the timestamp it was last seen as having this status
__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	string|zero formid = req->variables->form;
	string nonce = req->variables->nonce;
	if (nonce) {
		//If the nonce is found, set formid to the corresponding form
		//Otherwise, return failure (don't fall through - that would allow nonce=&form= usage)
		//TODO: Have a maximum age for nonce validity, configurable per form?
		mapping resp = await(G->G->DB->load_config(req->misc->channel->userid, "formresponses"));
		formid = 0;
		foreach (resp; string id; mapping f) if (mapping p = f->permissions[?nonce]) {
			//Found! If necessary, check age and reject if too old.
			//Note that we don't check the user ID here. If you're not logged in, you can
			//still see the form, just not submit it. Also, if you're logged in as the
			//wrong user, you need to get a page from which you can change user.
			if (!p->used) formid = id; //Otherwise, no more permission.
			break;
		}
		if (!formid) return 0; //Nonce not found or invalid. TODO: Return a nicer error?
	}
	if (formid) {
		//If the form is open, anyone may fill it out by providing the form ID.
		mapping cfg = await(G->G->DB->load_config(req->misc->channel->userid, "forms"));
		mapping form = cfg->forms[formid];
		if (!form) return 0; //Bad form ID? Kick back a boring 404 page.
		string|zero permitted_id = 0; //Set to eg "49497888" if a nonce was used and a user granted permission
		string banner = "";
		if (!req->variables->nonce && !form->is_open) {
			//TODO: Return a nicer page saying that the form is closed.
			//If you're a mod, the form can still be viewed (but not submitted).
			if (req->misc->is_mod && req->request_type != "POST") banner = "<div class=banner>Form preview, cannot be submitted</div>";
			else return 0;
		}
		multiset missing = (<>); //If anything is missing, we'll rerender the form
		if (req->request_type == "POST") {
			mapping response = ([
				"timestamp": time(),
				"ip": req->get_ip(),
			]);
			mapping fields = ([]);
			object rsakey = cfg->encryptkey && Crypto.RSA()->set_public_key(cfg->encryptkey, 65537);
			foreach (form->elements, mapping el) {
				switch (el->type) { //_element_types
					case "twitchid": {
						//There's no form element for this. If you're logged in, we use the session user.
						//What we do here is all about the validation.
						mapping|zero user = req->misc->session->user;
						//Note that "require_follower" and "require_subscriber" actually just pretend
						//that there's no user if the current user doesn't fit the req; this makes them
						//mostly useless if not combined with "required".
						//There's currently no option for "must be a sub, or a mod" or complex things
						//like that. For those, figure it out yourself, sorry.
						if (el->require_follower && user && (int)user->id != req->misc->channel->userid) {
							//You don't follow yourself, so we'll arbitrarily permit self-fill-out
							mapping info = await(twitch_api_request(sprintf(
								"https://api.twitch.tv/helix/channels/followers?broadcaster_id=%d&user_id=%d",
								req->misc->channel->userid, (int)user->id),
								(["Authorization": req->misc->channel->userid])));
							if (!sizeof(info->data)) user = 0;
						}
						if (el->require_subscriber && user && (int)user->id != req->misc->channel->userid) {
							//But you DO subscribe to yourself, so we could skip that check.
							mapping info = await(twitch_api_request(sprintf(
								"https://api.twitch.tv/helix/subscriptions?broadcaster_id=%d&user_id=%d",
								req->misc->channel->userid, (int)user->id),
								(["Authorization": req->misc->channel->userid])));
							if (!sizeof(info->data)) user = 0;
						}
						if (el->permitted_only && permitted_id && permitted_id != user->?id)
							missing[el->name] = 1;
						else if (user)
							//If a user changes display name or avatar or something, this will show the
							//credentials as of form submission; but since the ID's there, you can check
							//to see what their current name is. Note also that this does not save into
							//fields[] but directly into response[], and having more than one twitchid
							//field is useless (they both look in the same session anyway).
							response->submitted_by = user & (<"id", "login", "display_name", "profile_image_url">);
						else if (el->required)
							missing[el->name] = 1;
						break;
					}
					case "checkbox": {
						if (el->label) foreach (el->label; int i; string l) {
							string field = el->name + (-i || ""); //Must match the field generation below
							if (el->required && !req->variables["field-" + field]) missing[field] = 1;
							else if (req->variables["field-" + field]) fields[field] = 1;
						}
						break;
					}
					case "address": {
						mapping parts = ([]);
						foreach (address_parts, [string name, string lbl]) {
							string field = el->name + "-" + name; //Again, must match the below
							int reqd = el->required && has_value(address_required, name);
							string|zero val = req->variables["field-" + field];
							if (reqd && (!val || val == "")) missing[field] = 1;
							else fields[field] = encrypt_with_key(rsakey, parts[name] = val);
						}
						//Also save the address as a single piece
						fields[el->name] = encrypt_with_key(rsakey, sprintf("%s\n%s\n%s %s  %s\n%s\n",
							parts->name || "",
							parts->street || "",
							parts->city || "", parts->state || "", parts->postalcode || "",
							parts->country || ""));
						break;
					}
					default: {
						string|zero val = req->variables["field-" + el->name];
						if (el->required && (!val || val == "")) missing[el->name] = 1;
						else fields[el->name] = val;
					}
				}
			}
			if (!sizeof(missing)) {
				response->fields = fields;
				response->nonce = nonce || String.string2hex(random_string(14)); //Every response must have a unique nonce (TODO: ensure uniqueness)
				await(G->G->DB->mutate_config(req->misc->channel->userid, "formresponses") {mapping resp = __ARGS__[0];
					if (!resp[formid]) resp[formid] = ([]);
					if (mapping p = resp[formid]->permissions[?nonce]) {
						//The permission is no longer available.
						if (p->used) {
							werror("FORM REUSED %O\n", nonce);
							return; //Silently ignore the second one (for now)
						}
						p->used = 1;
					}
					resp[formid]->responses += ({response});
				});
				send_updates_all(req->misc->channel, formid);
				return render_template(formmessage, ([
					"formtitle": form->formtitle,
					"message": form->thankyou || "Thank you for filling out this form!",
				]) | req->misc->chaninfo);
			}
			//Else we fall through and rerender the form.
		}
		//TODO: Prepopulate the form with req->variables on rerender
		string formdata = "";
		foreach (form->elements, mapping el) {
			string|zero elem = 0;
			string text = "";
			if (el->text && el->text != "") text = Tools.Markdown.parse(el->text, ([
				"renderer": Renderer, "lexer": Lexer,
				"attributes": 1, "extlinktarget": 1, "sanitize": 1,
			]));
			switch (el->type) { //Matches _element_types
				case "twitchid": {
					mapping|zero user = req->misc->session->user;
					if (el->permitted_only && permitted_id) { //Kinda implies required. If the form is open, using the form ID bypasses this, but it still applies if a nonce is used.
						if (user && permitted_id == user->id)
							//It's only available to this user, so don't offer to change user.
							elem = sprintf("You are currently logged in as ![(avatar)](%s) %s.",
								user->profile_image_url, user->display_name);
						else if (user)
							elem = sprintf("You are currently logged in as ![(avatar)](%s) %s. This form was granted to another user. [![Twitch logo](https://static-cdn.jtvnw.net/emoticons/v2/112290/default/light/1.0)  Change user](:.twitchlogin)",
								user->profile_image_url, user->display_name);
						else
							elem = "This form was granted to a specific Twitch user; you are not currently logged in. [![Twitch logo](https://static-cdn.jtvnw.net/emoticons/v2/112290/default/light/1.0)  Confirm identity](:.twitchlogin)";
					} else if (user) {
						//TODO: Deduplicate these checks with the above, esp if repopulating the form
						elem = sprintf("You are currently logged in as ![(avatar)](%s) %s. Not you? [![Twitch logo](https://static-cdn.jtvnw.net/emoticons/v2/112290/default/light/1.0)  Change user](:.twitchlogin)",
							user->profile_image_url || "", user->display_name);
						if (el->require_follower && user && (int)user->id != req->misc->channel->userid) {
							//You don't follow yourself, so we'll arbitrarily permit self-fill-out
							mapping info = await(twitch_api_request(sprintf(
								"https://api.twitch.tv/helix/channels/followers?broadcaster_id=%d&user_id=%d",
								req->misc->channel->userid, (int)user->id),
								(["Authorization": req->misc->channel->userid])));
							if (!sizeof(info->data)) elem += "<div class=errorbanner>Only followers of " + req->misc->channel->display_name + " may fill out this form.</div>";
						}
						if (el->require_subscriber && user && (int)user->id != req->misc->channel->userid) {
							//But you DO subscribe to yourself, so we could skip that check.
							mapping info = await(twitch_api_request(sprintf(
								"https://api.twitch.tv/helix/subscriptions?broadcaster_id=%d&user_id=%d",
								req->misc->channel->userid, (int)user->id),
								(["Authorization": req->misc->channel->userid])));
							if (!sizeof(info->data)) elem += "<div class=errorbanner>Only subscribers to " + req->misc->channel->display_name + " may fill out this form.</div>";
						}
					}
					else if (el->required)
						elem = "You are not currently logged in. [![Twitch logo](https://static-cdn.jtvnw.net/emoticons/v2/112290/default/light/1.0) Confirm identity](:.twitchlogin) to submit this form.";
					else
						elem = "You are not currently logged in. If you wish, [![Twitch logo](https://static-cdn.jtvnw.net/emoticons/v2/112290/default/light/1.0) confirm identity](:.twitchlogin) to include this with the form.";
					break;
				}
				case "simple":
					elem = sprintf("<label><span>%s</span> <input name=%q%s>%s</label>",
						el->label || "", "field-" + el->name,
						el->required ? " required" : "",
						missing[el->name] ? " <span class=required title=Required>\\* Please enter something</span>" :
							el->required ? " <span class=required title=Required>\\*</span>" : "",
					);
					break;
				case "url":
					elem = sprintf("<label><span>%s</span> <input type=url name=%q%s>%s</label>",
						el->label || "", "field-" + el->name,
						el->required ? " required" : "",
						missing[el->name] ? " <span class=required title=Required>\\* Please enter a URL (web address)</span>" :
							el->required ? " <span class=required title=Required>\\*</span>" : "",
					);
					break;
				case "paragraph":
					elem = sprintf("<label><span>%s</span>%s<br><textarea name=%q rows=8 cols=80%s></textarea></label>",
						el->label || "",
						missing[el->name] ? " <span class=required title=Required>\\* Please enter something</span>" :
							el->required ? " <span class=required title=Required>\\*</span>" : "",
						"field-" + el->name,
						el->required ? " required" : "",
					);
					break;
				case "address":
					elem = "";
					foreach (address_parts, [string name, string lbl]) {
						if (el["label-" + name] && el["label-" + name] != "") lbl = el["label-" + name];
						string field = "field-" + el->name + "-" + name;
						int reqd = el->required && has_value(address_required, name);
						elem += sprintf("<label><span>%s</span> <input name=%q%s>%s</label><br>",
							lbl, field,
							reqd ? " required" : "",
							missing[field] ? " <span class=required title=Required>\\* Please enter something</span>" :
								reqd ? " <span class=required title=Required>\\*</span>" : "",
						);
					}
					break;
				case "checkbox": {
					elem = "<ul>";
					if (el->label) foreach (el->label; int i; string l) {
						//"field-foo-1", "field-foo-2", etc but leave the first one unadorned
						string field = "field-" + el->name + (-i || ""); //Must match the form response handling above
						elem += sprintf("<li><label><input%s type=checkbox name=%q> %s%s</label></li>",
							el->required ? " required" : "",
							field, l, 
							missing[field] ? " <span class=required title=Required>\\* This must be checked</span>" :
								el->required ? " <span class=required title=Required>\\*</span>" : "",
						);
					}
					elem += "</ul>";
					break;
				}
				case "text": elem = ""; break; //Descriptive text - no actual form controls
				default: break;
			}
			if (elem) formdata += sprintf("<section id=%q>%s%s</section>\n", "field-" + el->name, text, elem);
		}
		return render_template(formview, ([
			"formtitle": form->formtitle,
			"formbanner": banner,
			"formdata": formdata,
		]) | req->misc->chaninfo);
	}
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo); //Should there be non-privileged info shown?
	if (string formid = req->variables->responses) {
		mapping cfg = await(G->G->DB->load_config(req->misc->channel->userid, "forms"));
		mapping form = cfg->forms[formid];
		if (!form) return 0; //Bad form ID? Kick back a boring 404 page.
		if (req->misc->channel->userid != (int)req->misc->session->user->id) {
			if (form->mods_see_responses) mods_see_responses[formid + "#" + req->misc->channel->userid] = time();
			else return render_template(formmessage, ([
				"formtitle": form->formtitle,
				"message": "This form is restricted and only the broadcaster can view the responses.",
			]) | req->misc->chaninfo);
		}
		return render_template(formresponses, ([
			"vars": (["ws_group": formid + "#" + req->misc->channel->userid, "ws_type": ws_type, "formdata": form]),
		]) | req->misc->chaninfo);
	}
	return render(req, (["vars": ([
			"ws_group": "", "address_parts": address_parts,
			"follower_scopes": req->misc->channel->name != "#!demo" && ensure_bcaster_token(req, "moderator:read:followers"),
			"subscriber_scopes": req->misc->channel->name != "#!demo" && ensure_bcaster_token(req, "channel:read:subscriptions"),
		]),
		"formfields": sprintf("%{* <label><span>%[2]s:</span> <input class=formmeta name=%[0]s %[1]s></label>\n> %}", formfields),
		"elementtypes": sprintf("%{<option value=\"%s\">%s%}", _element_types),
	]) | req->misc->chaninfo);
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(msg->group);
	if (grp != "" && channel->userid != (int)conn->session->user->id) {
		//If we've had a page load within the last 60 seconds, and the form had mod permissions,
		//let it go through. Otherwise, reject - but query, thus allowing a potential retry.
		if (mods_see_responses[msg->group] < time() - 60) {
			G->G->DB->load_config(channel->userid, "forms")->then() {
				mapping form = __ARGS__[0]->forms[grp];
				if (form->mods_see_responses) mods_see_responses[msg->group] = time();
			};
			return "Broadcaster only";
		}
	}
	return ::websocket_validate(conn, msg);
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "forms"));
	if (grp == "") {
		//List of forms, and form editing (for any form)
		return ([
			"forms": cfg->forms ? cfg->forms[cfg->formorder[*]] : ({ }),
			"encryption": (["active": !!cfg->encryptkey]), //In the future, may configure which fields get affected (currently always and only addresses)
		]);
	}
	//Form responses (single form)
	mapping resp = await(G->G->DB->load_config(channel->userid, "formresponses"))[grp];
	if (!resp) return 0; //Bad form ID (or maybe no responses yet)
	array responses = ({ }), order = ({ });
	mapping nonces = (resp->permissions || ([])) | ([]); //We'll mutate this
	//Now find all form responses, and match up their permissions if available
	foreach (resp->responses; int idx; mapping r) {
		mapping perm = m_delete(nonces, r->nonce);
		if (r->deleted) continue;
		responses += ({r | (perm || ([]))});
		order += ({perm ? -perm->permitted : -r->timestamp});
	}
	//Any remaining permissions, add them in as unfilled forms
	responses += values(nonces);
	order += -values(nonces)->permitted[*];
	sort(order, responses);
	return (["responses": responses, "forminfo": cfg->forms[grp]]);
}

__async__ mapping wscmd_create_form(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping form_data;
	await(G->G->DB->mutate_config(channel->userid, "forms") {mapping cfg = __ARGS__[0];
		if (!cfg->forms) cfg->forms = ([]);
		string id;
		do {id = String.string2hex(random_string(4));} while (cfg->forms[id]);
		cfg->forms[id] = form_data = ([
			"id": id,
			"formtitle": "New Form", //Doesn't have to be unique, so I won't say "New Form #4" here
		]);
		cfg->formorder += ({id});
	});
	send_updates_all(channel, "");
	return (["cmd": "openform", "form_data": form_data]);
}

__async__ void wscmd_delete_form(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	await(G->G->DB->mutate_config(channel->userid, "forms") {mapping cfg = __ARGS__[0];
		if (!cfg->forms) return;
		m_delete(cfg->forms, msg->id);
		cfg->formorder -= ({msg->id});
	});
	send_updates_all(channel, "");
}

__async__ void wscmd_form_meta(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping editable = (["formtitle": "string", "is_open": "bool", "mods_see_responses": "bool", "thankyou": "string"]);
	await(G->G->DB->mutate_config(channel->userid, "forms") {mapping cfg = __ARGS__[0];
		mapping form_data = cfg->forms[?msg->id]; if (!form_data) return;
		foreach (editable; string key; string type) if (!undefinedp(msg[key])) {
			switch (type) {
				case "string": form_data[key] = (string)msg[key]; break;
				case "bool": form_data[key] = !!msg[key]; break;
				//TODO: Permit numerics too? Float or just int?
			}
		}
	});
	send_updates_all(channel, "");
}

//TODO: Allow a form's ID to be changed, subject to restrictions:
// * Must be unique (within this channel)
// * Must be an atom - -A-Za-z0-9_ and maybe a few others, notably no spaces
// * Length 1-15 characters? Maybe a bit longer but not huge.
//Be sure to migrate all form responses to the new ID

__async__ void wscmd_add_element(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping form_data;
	if (!element_types[msg->type]) return;
	await(G->G->DB->mutate_config(channel->userid, "forms") {mapping cfg = __ARGS__[0];
		form_data = cfg->forms[?msg->id]; if (!form_data) return;
		multiset in_use = (multiset)(form_data->elements || ({ }))->name;
		string name = msg->type;
		int i = 1;
		while (in_use[name]) name = sprintf("%s #%d", msg->type, ++i);
		form_data->elements += ({(["type": msg->type, "name": name])});
	});
	send_updates_all(channel, "");
}

__async__ void wscmd_edit_element(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping|zero form_data;
	if (!intp(msg->idx) || msg->idx < 0 || !stringp(msg->field) || msg->field == "") return;
	await(G->G->DB->mutate_config(channel->userid, "forms") {mapping cfg = __ARGS__[0];
		form_data = cfg->forms[?msg->id]; if (!form_data) return;
		if (msg->idx >= sizeof(form_data->elements)) return;
		mapping el = form_data->elements[msg->idx];
		string val = msg->value ? (string)msg->value : "";
		if (msg->field == "name") {
			//Special-case: Names must be unique and non-blank
			//Note that setting to the same name that it already has is going to
			//look like a collision; but it wouldn't make any difference anyway,
			//so it's okay to handle it as an error.
			if (val == "" || sizeof(val) > 25) return;
			if (has_value(form_data->elements->name, val)) return;
			el->name = val;
			form_data = 0; return; //Signal acceptance of the edit
		}
		else if (msg->field == "text") {
			//All fields can have descriptive text.
			el->text = val;
			form_data = 0; return;
		}
		else if (msg->field == "required") {
			//All fields can be made Required. There are some (eg "text") where this has no
			//effect, though, and their Required checkboxes are hidden on the front end; if
			//you mess around and set its Required, we'll happily store it and do nothing.
			if (msg->value) el->required = 1; else m_delete(el, "required");
			form_data = 0; return;
		}
		else if (msg->field[-1] == ']') {
			sscanf(msg->field, "%s[%d]", string basename, int idx);
			if (msg->field != sprintf("%s[%d]", basename, idx)) return; //Strict formatting, no extra zeroes or anything
			function validator = element_attributes[el->type][basename + "[]"];
			if (!validator || !validator(val)) return;
			if (!arrayp(el[basename])) el[basename] = ({ });
			while (sizeof(el[basename]) <= idx) el[basename] += ({""});
			el[basename][idx] = val;
			el[basename] -= ({""}); //Set to blank to delete an entry
			form_data = 0; return;
		}
		else if (function validator = element_attributes[el->type][msg->field]) {
			if (!validator(val)) return;
			if (validator == type_boolean) el[msg->field] = val == "1";
			else el[msg->field] = val;
			form_data = 0; return;
		}
	});
	if (!form_data) send_updates_all(channel, "");
}

__async__ void wscmd_move_element(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!intp(msg->idx) || msg->idx < 0 || !intp(msg->dir) || !msg->dir) return;
	int other = msg->idx + msg->dir;
	if (other < 0) return; //Normally dir will be -1 or 1, but in theory, you could fiddle and send a -2, which is okay but weird
	await(G->G->DB->mutate_config(channel->userid, "forms") {mapping cfg = __ARGS__[0];
		mapping form_data = cfg->forms[?msg->id]; if (!form_data) return;
		if (msg->idx >= sizeof(form_data->elements) || other >= sizeof(form_data->elements)) return;
		mapping tmp = form_data->elements[msg->idx];
		form_data->elements[msg->idx] = form_data->elements[other];
		form_data->elements[other] = tmp;
	});
	send_updates_all(channel, "");
}

__async__ void wscmd_delete_element(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping form_data;
	if (!intp(msg->idx) || msg->idx < 0) return 0;
	await(G->G->DB->mutate_config(channel->userid, "forms") {mapping cfg = __ARGS__[0];
		form_data = cfg->forms[?msg->id]; if (!form_data) return;
		if (msg->idx < sizeof(form_data->elements)) {
			form_data->elements[msg->idx] = 0;
			form_data->elements -= ({0});
		}
	});
	send_updates_all(channel, "");
}

Crypto.RSA generate_keypair(string pwd) {
	//This isn't meant to be 100% secure, but it should be better than clear text.
	string state = "MustardMine simple password encryption";
	string rnd = "";
	//Use SHA256 as a PRNG. Repeatedly hash the password to generate more random bytes.
	string hash_based_random(int sz) {
		while (sz > sizeof(rnd)) {
			state = Crypto.SHA256.hash(state + pwd);
			rnd += state;
		}
		string ret = rnd[..sz-1];
		rnd = rnd[sz..];
		return ret;
	}
	//Basically, what we do is use a reproducible PRNG in place of the normal source of random bytes,
	//then use keypair generation to come up with two large primes in the normal way. (We then reset
	//the object to use proper randomness, although it's unlikely to matter.) We store the product of
	//the two primes (called "n" in RSA literature and retrieved via the get_n() method) - the public
	//key - and only retain the actual RSA object (which contains the private key - the two primes p
	//and q) in local memory. I would *love* to be able to do the decryption work on the client, but
	//that would require a full RSA decryption implementation in JavaScript, and I'm not willing to
	//bet everything on that. Might be worth looking into later though.
	return Crypto.RSA()->set_random(hash_based_random)->generate_key(1024)->set_random(random_string);
}

void wscmd_set_decryption_password(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	session_decryption_key[channel->userid + ":" + conn->session->nonce] = generate_keypair(msg->password);
}

__async__ void wscmd_encrypt(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!stringp(msg->password)) return;
	object prevkey, newkey;
	int(1bit) reencrypt;
	mapping cfg = await(G->G->DB->mutate_config(channel->userid, "forms") {mapping cfg = __ARGS__[0];
		//First make sure you entered the correct previous password (if any).
		if (cfg->encryptkey) {
			prevkey = session_decryption_key[channel->userid + ":" + conn->session->nonce];
			if (!prevkey || prevkey->get_n() != cfg->encryptkey) return;
		}
		if (msg->password == "") m_delete(cfg, "encryptkey");
		else {
			newkey = session_decryption_key[channel->userid + ":" + conn->session->nonce] = generate_keypair(msg->password);
			cfg->encryptkey = newkey->get_n();
		}
		reencrypt = 1;
	});
	if (reencrypt) await(G->G->DB->mutate_config(channel->userid, "formresponses") {mapping resp = __ARGS__[0];
		foreach (resp; string formid; mapping frm) {
			mapping form = cfg->forms[formid];
			foreach (frm->responses || ({ }), mapping response) {
				//Decrypt everything first.
				mapping fields = response->fields;
				if (!fields) continue;
				if (prevkey) {
					foreach (fields; string k; string|array v)
						if (arrayp(v)) fields[k] = utf8_to_string(prevkey->decrypt(String.hex2string(v[*])[*]) * "");
					if (arrayp(response->ip)) response->ip = utf8_to_string(prevkey->decrypt(String.hex2string(response->ip[*])[*]) * "");
				}
				void encrypt(string key) {
					if (!fields[key] || fields[key] == "") return; //No need to encrypt blank entries
					if (!newkey) return; //Decrypting without encrypting
					fields[key] = encrypt_with_key(newkey, fields[key]);
				}
				foreach (form->elements, mapping el) switch (el->type) { //_element_types
					case "address": {
						encrypt(el->name); //The combined version
						foreach (address_parts, [string name, string lbl])
							encrypt(el->name + "-" + name);
						break;
					}
					case "email": encrypt(el->name); break; //TODO
					default: break;
				}
			}
		}
	});
	send_updates_all(channel, "");
}

mapping|zero wscmd_decrypt(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!arrayp(msg->data)) return 0;
	object key = session_decryption_key[channel->userid + ":" + conn->session->nonce];
	if (!key) return 0;
	array decrypted = ({ });
	foreach (msg->data, array txt) {
		string dec = utf8_to_string(key->decrypt(String.hex2string(txt[*])[*]) * "");
		if (dec != "") decrypted += ({(["enc": txt, "dec": dec])});
	}
	if (sizeof(decrypted)) return (["cmd": "decrypted", "decryption": decrypted]);
}

bool type_string(string value) {return 1;}
bool type_boolean(string value) {return value == "1" || value == "0" || value == "";}

//Take a selection of form response nonces and do something to them all.
__async__ void manipulate_responses(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg, function update) {
	if (!arrayp(msg->nonces)) return;
	multiset nonces = (multiset)msg->nonces;
	string formid = conn->subgroup;
	await(G->G->DB->mutate_config(channel->userid, "formresponses") {mapping resp = __ARGS__[0];
		if (!resp[formid]) return; //No responses, nothing to delete
		foreach (resp[formid]->responses, mapping r) if (nonces[r->nonce]) update(r);
		//Hard delete from permissions - no need to keep them around
		if (resp[formid]->permissions) resp[formid]->permissions -= nonces;
	});
	send_updates_all(channel, formid);
}

void wscmd_delete_responses(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	//Soft delete from responses. There's no current way to retrieve them, but at least the data's
	//not destroyed.
	manipulate_responses(channel, conn, msg) {__ARGS__[0]->deleted = time();};
}

void wscmd_archive_responses(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	manipulate_responses(channel, conn, msg) {if (!__ARGS__[0]->archived) __ARGS__[0]->archived = time();};
}

void wscmd_unarchive_responses(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	manipulate_responses(channel, conn, msg) {m_delete(__ARGS__[0], "archived");};
}

__async__ void wscmd_download_csv(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (!arrayp(msg->nonces)) return;
	multiset nonces = (multiset)msg->nonces;
	string formid = conn->subgroup;
	mapping resp = await(G->G->DB->load_config(channel->userid, "formresponses"));
	if (!resp[formid]) return; //No responses, nothing to download (TODO: report error)
	mapping cfg = await(G->G->DB->load_config(channel->userid, "forms"));
	mapping form = cfg->forms[formid];
	if (!form) return;
	array(string) headers = ({"datetime"});
	foreach (form->elements, mapping el) switch (el->type) { //_element_types
		case "twitchid": case "simple": case "url": case "paragraph":
			headers += ({el->name});
			break;
		case "address":
			//Provide the individual parts, plus the combined one
			//TODO: When the user asks for CSV download, prompt for some options, including address
			//format: "Combined", "Parts", "Parts + Combined", "Parts + Spreadsheet Formula"
			headers += (el->name + "-" + address_parts[*][0][*]) + ({el->name});
			break;
		case "checkbox":
			foreach (el->label || ({ }); int i;) headers += ({el->name + (-i || "")});
			break;
		default: break;
	}
	array(array) rows = ({headers});
	foreach (resp[formid]->responses, mapping r) if (nonces[r->nonce]) {
		array row = ({r->timestamp ? ctime(r->timestamp)[..<1] : ""}); //TODO: Format date/time more nicely
		foreach (form->elements, mapping el) switch (el->type) { //_element_types
			case "twitchid":
				row += ({r->submitted_by ? r->submitted_by->display_name : ""});
				break;
			case "simple": case "url": case "paragraph":
				row += ({r->fields[el->name]});
				break;
			case "address":
				//Addresses are a bit weird. You might be able to make this work with just the combined field,
				//or maybe it works better like this.
				row += r->fields[(el->name + "-" + address_parts[*][0][*])[*]] + ({sprintf(
					"=%c%d&CHAR(13)&%c%[1]d&CHAR(13)&%c%[1]d&\" \"&%c%[1]d&\"  \"&%c%[1]d&CHAR(13)&%c%[1]d",
					'A' + sizeof(row),
					1 + sizeof(rows),
					'B' + sizeof(row),
					'C' + sizeof(row),
					'D' + sizeof(row),
					'E' + sizeof(row),
					'F' + sizeof(row),
				)});
				break;
			case "checkbox":
				foreach (el->label || ({ }); int i;) row += ({r->fields[el->name + (-i || "")] ? "yes" : "no"});
				break;
			default: break;
		}
		rows += ({row});
	}
	String.Buffer csv = String.Buffer();
	foreach (rows, array row) {
		foreach (row; int i; string cell) {
			if (i) csv->add(",");
			if (!cell) cell = "";
			if (has_value(cell, '"') || has_value(cell, '\n')) csv->add("\"" + replace(cell, (["\\": "\\\\", "\"": "\"\""])) + "\"");
			else csv->add(cell);
		}
		csv->add("\n");
	}
	send_msg(conn, (["cmd": "download_csv", "csvdata": csv->get()]));
}

constant command_description = "Grant form fillout";
constant builtin_name = "Form fillout";
constant builtin_param = ({"Form ID", "User name"}); //TODO: Drop-down
constant vars_provided = ([
	"{nonce}": "Unique nonce for this user's form fillout",
	"{url}": "Direct link to fill out the form",
]);

__async__ mapping message_params(object channel, mapping person, array param, mapping cfg) {
	if (cfg->simulate) {cfg->simulate("Send form"); return ([]);}
	string formid = param[0];
	mapping user = await(get_user_info(param[1] - "@", "login"));
	string nonce;
	mapping form_data = await(G->G->DB->load_config(channel->userid, "forms"))->forms[formid];
	await(G->G->DB->mutate_config(channel->userid, "formresponses") {mapping resp = __ARGS__[0];
		if (!resp[formid]) resp[formid] = ([]);
		if (!resp[formid]->permissions) resp[formid]->permissions = ([]);
		nonce = String.string2hex(random_string(14));
		resp[formid]->permissions[nonce] = ([
			"permitted": time(),
			"authorized_for": user & (<"id", "login", "display_name", "profile_image_url">),
			"nonce": nonce,
		]);
	});
	if (!nonce) return ([]);
	send_updates_all(channel, formid);
	return (["{nonce}": nonce, "{url}": sprintf("%s/channels/%s/form?nonce=%s",
		G->G->instance_config->http_address || "http://BOT_ADDRESS",
		channel->login, nonce,
	)]);
}

protected void create(string name) {::create(name);}
