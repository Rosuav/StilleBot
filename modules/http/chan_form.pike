inherit annotated;
inherit hook;
inherit http_websocket;
inherit builtin_command;
constant markdown = #"# Forms for $$channel$$

* loading...
{:#forms}

[Create form](:#createform)

> ### Edit form
>
> $$formfields$$
> [Link to form](form?form=FORMID :#viewform target=_blank) (only while form is open)<br>
> [View form responses](form?responses=FORMID :#viewresp target=_blank) (opens in new window)<br>
> [Delete form](:#delete_form)
>
> <div id=formelements></div>
> <select id=addelement><option value=\"\">Add new element$$elementtypes$$</select>
>
> [Close](:.dialog_close)
{: tag=formdialog #editformdlg}

<style>
.openform {cursor: pointer;}
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
label span {
	min-width: 10em;
	font-weight: bold;
	display: inline-block;
}
</style>
";

constant formview = #"# $$formtitle$$

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
label span {
	min-width: 10em;
	font-weight: bold;
	display: inline-block;
}
.required { /* The marker that follows a required field, not to be confused with input:required */
	color: red;
}
img[alt=\"(avatar)\"] {
	height: 40px;
	vertical-align: middle;
}
</style>
";

constant formcloser = #"# $$formtitle$$

Thank you for filling out this form! (TODO: Let the broadcaster customize this text.)

";

constant formresponses = #"# Form responses

Permitted | Submitted | Twitch user | Answers
----------|-----------|-------------|---------
loading... | -
{:#responses}

> ### Form response
>
> <label><span>Permitted at:</span> <input readonly name=permitted></label><br>
> <label><span>Submitted at:</span> <input readonly name=timestamp></label><br>
>
> loading...
> {:#formresponse}
>
> [Close](:.dialog_close)
{: tag=dialog #responsedlg}

";

array formfields = ({
	({"id", "readonly", "Form ID"}),
	({"formtitle", "", "Title"}),
	({"is_open", "type=checkbox", "Open form"}),
});

array _element_types = ({ //Search for _element_types in this and the JS to find places to add more
	({"twitchid", "Twitch username"}), //If mandatory, will force user to be logged in to submit
	({"simple", "Text input"}),
	({"paragraph", "Paragraph input"}),
	({"address", "Street address"}),
	//({"radio", "Selection (radio) buttons"}), //Should generally be made mandatory
	({"checkbox", "Check box(es)"}), //If mandatory, at least one checkbox must be selected (but more than one may be)
	({"text", "Informational text"}),
});
mapping element_types = (mapping)_element_types;
mapping element_attributes = ([ //Matches _element_types
	"twitchid": (["permitted_only": type_boolean]),
	"simple": (["label": type_string]),
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

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	string|zero formid = req->variables->form;
	string nonce = req->variables->nonce;
	if (nonce) {
		//TODO: If the nonce is found, set formid to the corresponding form
		//Otherwise, return failure (don't fall through - that would allow nonce=&form= usage)
		//TODO: Have a maximum age for nonce validity, configurable per form?
		return 0; //Nonce not found or invalid. TODO: Return a nicer error?
	}
	if (formid) {
		//If the form is open, anyone may fill it out by providing the form ID.
		mapping cfg = await(G->G->DB->load_config(req->misc->channel->userid, "forms"));
		mapping form = cfg->forms[formid];
		if (!form) return 0; //Bad form ID? Kick back a boring 404 page.
		string|zero permitted_id = 0; //Set to eg "49497888" if a nonce was used and a user granted permission
		if (!req->variables->nonce && !form->is_open) {
			//TODO: Return a nicer page saying that the form is closed.
			return 0;
		}
		multiset missing = (<>); //If anything is missing, we'll rerender the form
		if (req->request_type == "POST") {
			werror("Variables: %O\n", req->variables);
			mapping response = ([
				"timestamp": time(),
				"ip": req->get_ip(),
			]);
			mapping fields = ([]);
			foreach (form->elements, mapping el) {
				switch (el->type) { //_element_types
					case "twitchid": {
						//There's no form element for this. If you're logged in, we use the session user.
						//What we do here is all about the validation.
						mapping|zero user = req->misc->session->user;
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
							string field = "field-" + el->name + (-i || ""); //Must match the field generation below
							if (el->required && !req->variables[field]) missing[field] = 1;
							else if (req->variables[field]) fields[field] = 1;
						}
						break;
					}
					case "address": {
						mapping parts = ([]);
						foreach (address_parts, [string name, string lbl]) {
							string field = "field-" + el->name + "-" + name; //Again, must match the below
							int reqd = el->required && has_value(address_required, name);
							string|zero val = req->variables[field];
							if (reqd && (!val || val == "")) missing[field] = 1;
							else fields[field] = parts[name] = val;
						}
						//Also save the address as a single piece
						fields[el->name] = sprintf("%s\n%s\n%s %s  %s\n%s\n",
							parts->name || "",
							parts->street || "",
							parts->city || "", parts->state || "", parts->postalcode || "",
							parts->country || "");
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
				if (nonce) response->nonce = nonce;
				await(G->G->DB->mutate_config(req->misc->channel->userid, "formresponses") {mapping resp = __ARGS__[0];
					if (!resp[formid]) resp[formid] = ([]);
					resp[formid]->responses += ({response});
					if (resp[formid]->nonces) m_delete(resp[formid]->nonces, nonce);
				});
				return render_template(formcloser, ([
					"formtitle": form->formtitle,
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
				"attributes": 1,
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
							elem = sprintf("You are currently logged in as ![(avatar)](%s) %s. This form was granted to another user. [Change user](:.twitchlogin)",
								user->profile_image_url, user->display_name);
						else
							elem = "This form was granted to a specific Twitch user; you are not currently logged in. [Confirm identity](:.twitchlogin)";
					} else if (user)
						elem = sprintf("You are currently logged in as ![(avatar)](%s) %s. Not you? [Change user](:.twitchlogin)",
							user->profile_image_url, user->display_name);
					else if (el->required)
						elem = "You are not currently logged in. [Confirm identity](:.twitchlogin) to submit this form.";
					else
						elem = "You are not currently logged in. If you wish, [confirm identity](:.twitchlogin) to include this with the form.";
					break;
				}
				case "simple":
					elem = sprintf("<label><span>%s</span> <input name=%q%s>%s</label>",
						el->label, "field-" + el->name,
						el->required ? " required" : "",
						missing[el->name] ? " <span class=required title=Required>\\* Please enter something</span>" :
							el->required ? " <span class=required title=Required>\\*</span>" : "",
					);
					break;
				case "paragraph":
					elem = sprintf("<label><span>%s</span>%s<br><textarea name=%q rows=8 cols=80%s></textarea></label>",
						el->label,
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
			"formdata": formdata,
		]) | req->misc->chaninfo);
	}
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo); //Should there be non-privileged info shown?
	if (string formid = req->variables->responses) {
		//TODO: Allow the form to be configured to permit mods. By default, broadcaster only.
		//Since websocket_validate is synchronous, the easiest way is probably to hack this
		//to retain in memory the fact that this form ID permits mods.
		mapping cfg = await(G->G->DB->load_config(req->misc->channel->userid, "forms"));
		mapping form = cfg->forms[formid];
		if (!form) return 0; //Bad form ID? Kick back a boring 404 page.
		if (req->misc->channel->userid != (int)req->misc->session->user->id) {
			//TODO: Include a banner saying what went wrong (or just have an error page, this is opened
			//in a new tab anyway).
			return redirect("form");
		}
		return render_template(formresponses, ([
			"vars": (["ws_group": formid + "#" + req->misc->channel->userid, "ws_type": ws_type, "formdata": form]),
		]));
	}
	return render(req, (["vars": (["ws_group": "", "address_parts": address_parts]),
		"formfields": sprintf("%{* <label>%[2]s: <input class=formmeta name=%[0]s %[1]s></label>\n> %}", formfields),
		"elementtypes": sprintf("%{<option value=\"%s\">%s%}", _element_types),
	]) | req->misc->chaninfo);
}

string websocket_validate(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(msg->group);
	if (grp != "" && channel->userid != (int)conn->session->user->id) return "Broadcaster only";
	return ::websocket_validate(conn, msg);
}

bool need_mod(string grp) {return 1;}
__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	if (grp == "") {
		//List of forms, and form editing (for any form)
		mapping cfg = await(G->G->DB->load_config(channel->userid, "forms"));
		if (!cfg->forms) return (["forms": ({ })]);
		return (["forms": cfg->forms[cfg->formorder[*]]]);
	}
	//Form responses (single form)
	mapping resp = await(G->G->DB->load_config(channel->userid, "formresponses"))[grp];
	if (!resp) return 0; //Bad form ID (or maybe no responses yet)
	array responses = ({ }), order = ({ });
	//First, go through all the permissions and key them by their nonces
	mapping nonces = ([]);
	foreach (resp->permissions || ({ }), mapping perm) {
		nonces[perm->nonce] = perm;
	}
	//Now find all form responses, and match up their permissions if available
	foreach (resp->responses, mapping r) {
		mapping perm = r->nonce && m_delete(nonces, r->nonce);
		responses += ({r | (perm || ([]))});
		order += ({perm ? perm->timestamp : r->timestamp});
	}
	//Any remaining permissions, add them in as unfilled forms
	responses += values(nonces);
	order += values(nonces)->timestamp;
	sort(order, responses);
	return (["responses": responses]);
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
	mapping editable = (["formtitle": "string", "is_open": "bool"]);
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

bool type_string(string value) {return 1;}
bool type_boolean(string value) {return value == "1" || value == "0" || value == "";}

constant command_description = "Grant form fillout";
constant builtin_name = "Form fillout";
constant builtin_param = ({"Form ID"}); //TODO: Drop-down
constant vars_provided = ([
	"{nonce}": "Unique nonce for this user's form fillout",
	"{url}": "Direct link to fill out the form",
]);

__async__ mapping message_params(object channel, mapping person, array param) {
	mapping form = await(G->G->DB->load_config(channel->userid, "forms"))[param[0]];
	if (!form) return ([]); //Including if you mess up the ID
	return ([]);
}

protected void create(string name) {::create(name);}

/* Next steps:
* Nonce-based permissions (note that failed submissions eg form missing a required field don't consume the permission slot)
* More field types esp twitchid. Note that this will require a login button and that will reload the page after login.
  - The user MUST be allowed to change user even if currently logged in.
* Required fields - if blank/omitted, form submission will be rejected; also use HTML required attribute and style them appropriately
* Descriptive paragraph on any/all form elements
*/
