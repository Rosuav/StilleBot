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
> Form ID:
> <label>Form title <input name=formtitle></label>
>
> <div id=formelements></div>
>
> [Close](:.dialog_close)
{: tag=formdialog #editformdlg}

";

constant formview = #"# $$formtitle$$

$$formdata$$
";

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	if (string nonce = req->variables->nonce) {
		//...
	}
	if (string formid = req->variables->form) {
		//...
	}
	if (!req->misc->is_mod) return render_template("login.md", req->misc->chaninfo); //Should there be non-privileged info shown?
	return render(req, (["vars": (["ws_group": ""])]) | req->misc->chaninfo);
}

__async__ mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = await(G->G->DB->load_config(channel->userid, "forms"));
	if (!cfg->forms) return (["forms": ({ })]);
	return (["forms": cfg->forms[cfg->formorder[*]]]);
}

__async__ mapping wscmd_createform(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	string id;
	await(G->G->DB->mutate_config(channel->userid, "forms") {mapping cfg = __ARGS__[0];
		if (!cfg->forms) cfg->forms = ([]);
		do {id = String.string2hex(random_string(4));} while (cfg->forms[id]);
		cfg->forms[id] = ([
			"id": id,
			"formtitle": "New Form", //Doesn't have to be unique, so I won't say "New Form #4" here
		]);
		cfg->formorder += ({id});
	});
	send_updates_all(channel, "");
	return (["cmd": "openform", "formid": id]);
}

//TODO: Allow a form's ID to be changed, subject to restrictions:
// * Must be unique (within this channel)
// * Must be an atom - -A-Za-z0-9_ and maybe a few others, notably no spaces
// * Length 1-15 characters? Maybe a bit longer but not huge.

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
