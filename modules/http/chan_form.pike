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
</style>
";

array formfields = ({
	({"id", "readonly", "Form ID"}),
	({"formtitle", "", "Title"}),
	({"is_open", "type=checkbox", "Open form"}),
});

array _element_types = ({
	({"twitchid", "Twitch username"}), //If mandatory, will force user to be logged in to submit
	({"simple", "Text input"}),
	({"paragraph", "Paragraph input"}),
	({"address", "Street address"}),
	({"radio", "Selection (radio) buttons"}),
	({"checkbox", "Check box(es)"}),
});
mapping element_types = (mapping)_element_types;
mapping element_attributes = ([
	"simple": (["label": type_string]),
	"paragraph": (["label": type_string]),
]);

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	string|zero formid = req->variables->form;
	if (string nonce = req->variables->nonce) {
		//TODO: If the nonce is found, set formid to the corresponding form
		//Otherwise, set formid to zero
		formid = 0; //Nonce not found or invalid.
	}
	if (formid) {
		//If the form is open, anyone may fill it out by providing the form ID.
		mapping cfg = await(G->G->DB->load_config(req->misc->channel->userid, "forms"));
		mapping form = cfg->forms[formid];
		if (!form) return 0; //Bad form ID? Kick back a boring 404 page.
		if (!req->variables->nonce && !form->is_open) {
			//TODO: Return a nicer page saying that the form is closed.
			return 0;
		}
		if (req->request_type == "POST") {
			werror("Variables: %O\n", req->variables);
		}
		string formdata = "";
		foreach (form->elements, mapping el) {
			string|zero elem = 0;
			switch (el->type) {
				case "simple":
					elem = sprintf("<label><span>%s</span> <input name=%q></label>",
						el->label, "field-" + el->name,
					);
					break;
				case "paragraph":
					elem = sprintf("<label><span>%s</span> <textarea name=%q rows=8 cols=80></textarea></label>",
						el->label, "field-" + el->name,
					);
					break;
				default: break;
			}
			if (elem) formdata += sprintf("<section id=%q>%s</section>\n", "field-" + el->name, elem);
		}
		return render_template(formview, ([
			"formtitle": form->formtitle,
			"formdata": formdata,
		]));
	}
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo); //Should there be non-privileged info shown?
	return render(req, (["vars": (["ws_group": ""]),
		"formfields": sprintf("%{* <label>%[2]s: <input class=formmeta name=%[0]s %[1]s></label>\n> %}", formfields),
		"elementtypes": sprintf("%{<option value=\"%s\">%s%}", _element_types),
	]) | req->misc->chaninfo);
}

__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "forms"));
	if (!cfg->forms) return (["forms": ({ })]);
	return (["forms": cfg->forms[cfg->formorder[*]]]);
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
	if (!intp(msg->idx) || msg->idx < 0 || !stringp(msg->field) || !stringp(msg->value)) return;
	await(G->G->DB->mutate_config(channel->userid, "forms") {mapping cfg = __ARGS__[0];
		form_data = cfg->forms[?msg->id]; if (!form_data) return;
		if (msg->idx >= sizeof(form_data->elements)) return;
		mapping el = form_data->elements[msg->idx];
		if (msg->field == "name") {
			//Special-case: Names must be unique and non-blank
			//Note that setting to the same name that it already has is going to
			//look like a collision; but it wouldn't make any difference anyway,
			//so it's okay to handle it as an error.
			if (msg->value == "" || sizeof(msg->value) > 25) return;
			if (has_value(form_data->elements->name, msg->value)) return;
			el->name = msg->value;
			form_data = 0; return; //Signal acceptance of the edit
		}
		else if (function validator = element_attributes[el->type][msg->field]) {
			if (!validator(msg->value)) return;
			el[msg->field] = msg->value;
			form_data = 0; return;
		}
	});
	if (form_data) send_updates_all(channel, "");
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
