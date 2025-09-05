inherit http_websocket;
inherit hook;
inherit builtin_command;
inherit annotated;

/* TODO:
* The "Completed" and "Inactive" states currently are fixed text only.
  - The boundary between "Active" and "Inactive" should ideally be configurable; default to one hour.
  - For timers tied to the Twitch schedule, recommend that "completed" and "inactive" be treated identically,
    as a recurring schedule will usually result in completed timers migrating to the next event, most likely
    putting them into "inactive" state.
  - Allow custom textformatting for Completed and Inactive, but have a "delete" button that leaves it unchanged
    (ie identical to Active) as this will be the most common.
*/

//Note that "#display" gets replaced with ".preview" for the preview styles
constant monitorstyles = #"
#display div {width: 33%;}
#display div:nth-of-type(2) {text-align: center;}
#display div:nth-of-type(3) {text-align: right;}
.avatar {width: 80px; max-height: 80px; padding-right: 2px; vertical-align: top;}
@property --oldpos {syntax: '<percentage>'; inherits: false; initial-value: 100%;}
@property --newpos {syntax: '<percentage>'; inherits: false; initial-value: 100%;}
@property --curpos {syntax: '<percentage>'; inherits: false; initial-value: 100%;}
#display .goalbar {
	flex-grow: 1;
	width: 100%;
	animation: .25s ease-in 0s 1 forwards damage;
	background: linear-gradient(.25turn, var(--fillcolor) var(--curpos), var(--barcolor) var(--curpos), var(--barcolor));
}
#display .bosscredit {
	color: var(--altcolor);
}
#display .waxing {animation: 1s ease-in-out 0.5s 1 both waxwane;}
#display .waning {position: absolute; top: 0; animation: 1s ease-in-out 0.5s 1 reverse both waxwane;}
@keyframes damage {
	from {--curpos: var(--oldpos);}
	to {--curpos: var(--newpos);}
}
@keyframes waxwane {
	from {opacity: 0;}
	to {opacity: 1;}
}
#imagetiles {
	display: flex;
	gap: 5px;
}
#imagetiles div {
	display: flex;
	flex-direction: column;
}
#imagetiles img {
	border: 1px solid black;
	padding: 1px;
	margin: 1px;
}
";

/* The Pile of Pics - credit to DeviCat for claiming that name!
- https://brm.io/matter-js/docs/
*/
constant pilestyles = #"
body.invisible {
	opacity: 0;
	transition: opacity 5s;
}
";

constant builtin_name = "Monitors"; //The front end may redescribe this according to the parameters
constant builtin_description = "Get information about a channel monitor";
//NOTE: The labels for parameters 1 and 2 will be replaced by the GUI editor based on monitor type.
constant builtin_param = ({"/Monitor/monitor_id", "Advancement/action", "Time/Type", "Label", "Image"});
constant vars_provided = ([
	"{type}": "Monitor type (text, goalbar, countdown)",
	//NOTE: Any values not applicable to the type in question will be blank/omitted.
	"{goal}": "Goal bar: Next goal as shown on screen",
	"{goal_raw}": "Goal bar: Next goal in raw numeric form (eg cents)",
	"{distance}": "Goal bar: Distance to next goal (negative if goal exceeded)",
	"{distance_raw}": "Goal bar: Distance in raw numeric form",
	"{value}": "Goal bar: Current value as shown (distance since the last tier reset)",
	"{value_raw}": "Goal bar: Current value in raw numeric form",
	"{percentage}": "Goal bar: Percentage of bar filled (can be above 100) as decimal number",
	"{tier}": "Goal bar: Current tier number (always 1 for non-tiered goals)",
	"{paused}": "Countdown: 1 if currently paused, 0 if counting down",
	"{timeleft}": "Countdown: Number of seconds to completion (may be negative)",
	"{targettime}": "Countdown: Unix time when the timeleft will hit zero",
]);

//Some of these attributes make sense only with certain types (eg needlesize is only for goal bars).
constant saveable_attributes = "previewbg barcolor fillcolor altcolor needlesize thresholds progressive "
	"infinitier lvlupcmd format format_style width height "
	"active bit sub_t1 sub_t2 sub_t3 exclude_gifts tip follow kofi_dono kofi_member kofi_renew kofi_shop kofi_commission "
	"fw_dono fw_member fw_shop fw_gift textcompleted textinactive startonscene startonscene_time record_leaderboard "
	"twitchsched twitchsched_offset fadeouttime wall_top wall_left wall_right wall_floor autoreset clawsize "
	"wallcolor wallalpha clawcolor clawthickness behaviour bouncemode" / " " + TEXTFORMATTING_ATTRS;
constant retained_attributes = (<"boss_selfheal", "boss_giftrecipient">); //Attributes set externally, not editable with wscmd_updatemonitor.
constant valid_types = (<"text", "goalbar", "countdown", "pile">);

constant default_thing_image = (["url": "/static/MustardMineAvatar.png", "xsize": 844, "ysize": 562]);
constant default_thing_type = ([
	"id": "default", "xsize": 50,
	"images": ({ }),
]);
//Not shared across instances.
@retain: mapping clawids_pending = ([]);

@retain: mapping bounding_box_cache = ([]);
__async__ mapping|zero get_image_dimensions(string url) {
	if (mapping em = bounding_box_cache[url]) return em;
	object res = await(Protocols.HTTP.Promise.get_url(url));
	if (res->status >= 400) return 0; //Bad URL, or server down. Don't save into the cache in case it's temporary.
	mapping img = Image.ANY._decode(res->get());
	if (!img->alpha) {
		//No alpha? Just use the box itself.
		return bounding_box_cache[url] = ([
			"url": url,
			"xsize": img->xsize, "ysize": img->ysize,
			"xoffset": 0, "yoffset": 0,
		]);
	}
	Image.Image searchme = img->alpha->threshold(5);
	[int left, int top, int right, int bottom] = searchme->find_autocrop();
	//If we need to do any more sophisticated hull-finding, here's where to do it. For now, just the box.
	//TODO: Allow the user to choose a circular hull, specifying the size and position.
	//If we're cropping at all, add an extra pixel of room for safety. Note that this
	//also protects against entirely transparent images, as it'll make a tiny box in
	//the middle instead of a degenerate non-box.
	array hull;
	int leftedge = left > 0, topedge = top > 0; //Keep track of which edges we've nudged
	int rightedge = right < img->xsize - 1, bottomedge = bottom < img->ysize - 1;
	left -= leftedge; top -= topedge; right += rightedge; bottom += bottomedge;
	int wid = right - left, hgh = bottom - top;
	if (right - left > 4 && bottom - top > 4) {
		hull = ({ });
		//Attempt to find a convex hull. We iterate through the original autocropped bounds,
		//but using the coordinate space of the nudged bounds, hence offsetting by *edge.
		//Top boundary.
		for (int x = left + leftedge; x < right - rightedge; ++x) {
			//Drop a vertical until we find non-transparency
			for (int y = top + topedge; y < bottom - bottomedge; ++y) {
				if (img->alpha->getpixel(x, y)[0] > 5) {hull += ({({x, y})}); break;}
			}
			//Note: If we never find any solid pixel - if there's a stripe of full
			//transparency - just skip that one and don't add a coordinate. We'll end
			//up scanning this one again the other direction, which is a waste, but I
			//don't really care enough to optimize that. This should not happen at the
			//far left/right of the image, as the autocrop would have detected this;
			//in the case of a fully transparent image, we're already on a too-small
			//box to be even doing this check.
		}
		//Right boundary. Instead of starting all the way at the top, we start at the corner
		//we just found. This ought to be in the correct column, so we're safe.
		for (int y = hull[-1][1] + 1; y < bottom - bottomedge; ++y) {
			for (int x = right - rightedge - 1; x >= left + leftedge; --x) {
				if (img->alpha->getpixel(x, y)[0] > 5) {hull += ({({x, y})}); break;}
			}
		}
		//Bottom boundary
		for (int x = hull[-1][1] - 1; x >= left + leftedge; --x) {
			for (int y = bottom - bottomedge - 1; y >= top + topedge; --y) {
				if (img->alpha->getpixel(x, y)[0] > 5) {hull += ({({x, y})}); break;}
			}
		}
		//Right boundary. We stop when we get back to the starting corner.
		for (int y = hull[-1][1] - 1; y > hull[0][1]; --y) {
			for (int x = left + leftedge; x < right - rightedge; ++x) {
				if (img->alpha->getpixel(x, y)[0] > 5) {hull += ({({x, y})}); break;}
			}
		}
	}
	return bounding_box_cache[url] = ([
		"url": url,
		"xsize": wid, "ysize": hgh,
		"xoffset": -left / (float)wid,
		"yoffset": -top / (float)hgh,
		"hull": hull,
	]);
}

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	mapping monitors = G->G->DB->load_cached_config(req->misc->channel->userid, "monitors");
	if (req->variables->view) {
		//Unauthenticated viewing endpoint. Depends on an existing nonce.
		string|zero nonce = req->variables->view;
		mapping info = monitors[nonce];
		if (!info) nonce = 0;
		//Pile of Pics has different code, best to isolate them.
		if (info->type == "pile") return render_template("monitor.html", ([
			"vars": ([
				"ws_type": ws_type, "ws_group": nonce + "#" + req->misc->channel->userid, "ws_code": "pile",
				"default_thing_image": default_thing_image,
			]),
			"styles": pilestyles,
		]));
		return render_template("monitor.html", ([
			"vars": (["ws_type": ws_type, "ws_group": nonce + "#" + req->misc->channel->userid, "ws_code": "monitor"]),
			"styles": monitorstyles,
		]));
	}
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]) | G->G->command_editor_vars(req->misc->channel),
		"styles": replace(monitorstyles, "#display", ".preview"),
	]) | req->misc->chaninfo);
}

__async__ void update_scheduled_timer(object channel, mapping mon) {
	array ev = await(get_stream_schedule(channel->userid, (int)mon->twitchsched_offset, 1, 86400));
	int target = 0;
	if (sizeof(ev)) //If there are no events within the next day, leave it at zero.
		target = time_from_iso(ev[0]->start_time)->unix_time() + (int)mon->twitchsched_offset;
	sscanf(mon->text, "$%s$:", string varname);
	if (varname) channel->set_variable(varname, (string)target);
}

mapping _get_monitor(object channel, mapping monitors, string id) {
	mapping text = monitors[id];
	if (!text) return 0;
	if (text->type == "countdown" && text->twitchsched) update_scheduled_timer(channel, text);
	return text | ([
		"id": id,
		"display": channel->expand_variables(text->text),
		"thresholds_rendered": channel->expand_variables(text->thresholds || ""), //In case there are variables in the thresholds
		"text_css": textformatting_css(text),
	]);
}

bool need_mod(string grp) {return grp == "";} //Require mod status for the master socket
__async__ mapping get_chan_state(object channel, string grp, string|void id, string|void type) {
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	if (grp != "") return (["data": _get_monitor(channel, monitors, grp)]);
	if (id) return _get_monitor(channel, monitors, id);
	mapping ret = (["items": _get_monitor(channel, monitors, sort(indices(monitors))[*])]);
	array files = await(G->G->DB->list_channel_files(channel->userid));
	array images = ({ });
	foreach (files; int i; mapping f)
		if (has_prefix(f->metadata->mimetype || "*/*", "image/"))
			images += ({f->metadata | (["id": f->id])});
	ret->images = images;
	return ret;
}

@hook_variable_changed: void notify_monitors(object channel, string var, string newval) {
	foreach (G->G->DB->load_cached_config(channel->userid, "monitors"); string nonce; mapping info) {
		if (has_value(info->thresholds || "", var)) {
			//These cause full updates, which are slower and potentially
			//flickier than a change to just the text.
			//TODO: Permit other attributes to also contain variables.
			send_updates_all(channel, nonce);
			update_one(channel, "", nonce);
			continue;
		}
		if (info->type == "pile" && sscanf(var, "$" + info->varname + ":%s$", string type) && type)
			send_updates_all(channel, nonce, (["newcount": ([type: (int)newval])]));
		if (!has_value(info->text, var)) continue;
		mapping info = (["data": (["id": nonce, "display": channel->expand_variables(info->text)])]);
		send_updates_all(channel, nonce, info); //Send to the group for just that nonce
		info->id = nonce; send_updates_all(channel, "", info); //Send to the master group as a single-item update
	}
}

//NOTE: Don't use wscmd for this, as it also checks for and blocks demo commands
mapping websocket_cmd_querycounts(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (!channel) return 0;
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	mapping info = monitors[conn->subgroup]; if (!info) return (["error": "Invalid nonce"]);
	string pat = "$" + info->varname + ":%s$";
	mapping vars = ([]);
	foreach (G->G->DB->load_cached_config(channel->userid, "variables"); string var; string val)
		if (sscanf(var, pat, string type) && type) vars[type] = (int)val;
	return (["cmd": "update", "newcount": vars]);
}

void wscmd_clawdone(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	mapping info = monitors[conn->subgroup]; if (!info) return;
	string prizetype = "";
	if (has_value(info->things->id, msg->prizetype)) {
		//Check for a valid thing type ID, not just the presence of one. Paranoia check even though "spend" should fail if the ID is bad.
		channel->set_variable(info->varname + ":" + msg->prizetype, 1, "spend");
		prizetype = msg->prizetype;
	}
	object prom = m_delete(clawids_pending, msg->clawid);
	sscanf(msg->label || "-", "label-%s", string lbl);
	if (prom) prom->success(([
		"{type}": "pile",
		"{prizetype}": prizetype,
		"{prizelabel}": lbl || "",
	]));
}

@"is_mod": @"demo_ok": __async__ void wscmd_interact(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	array socks = websocket_groups[msg->nonce + "#" + channel->userid] || ({ });
	//On the demo, this should only send to your own IP address. The group name is still the nonce though.
	if (!channel->userid) socks = filter(socks, socks->query_id()->remote_ip[*] == conn->remote_ip);
	switch (msg->action) {
		case "claw": _low_send_updates((["claw": String.string2hex(random_string(4))]), socks); break;
		case "shake": case "rattle": case "roll":
			_low_send_updates(([msg->action: 1]), socks); //The value is a "strength", not currently user-selectable
			break;
		default: break;
	}
}

@"is_mod": __async__ void wscmd_addactivation(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	mapping info = monitors[msg->nonce]; if (!info) return;
	string cmdname, code;
	mapping reward;
	if (msg->action == "claw") {
		cmdname = "claw";
		code = sprintf(#{chan_monitors(%O, "claw")
			if ("{prizetype}" == "") "The claw has selected nothing. The claw is our master!"
			else "The claw has selected: {prizetype}{ prizelabel}. The claw is our master!"
		#}, msg->nonce);
		reward = ([
			"title": "Claw Machine",
			"prompt": "Lower the claw into the pile and see what you can grab!",
			"cost": 500,
			"background_color": "#a0f0c0",
			"is_global_cooldown_enabled": Val.true, "global_cooldown_seconds": 60,
		]);
	} else if ((<"shake", "rattle", "roll">)[msg->action]) {
		cmdname = msg->action;
		code = sprintf("chan_monitors(%O, %O) %O", msg->nonce, msg->action, "$$ " + msg->action + "s the pile!");
		reward = ([
			"title": String.sillycaps(msg->action) + " the Pile",
			"prompt": ([
				"shake": "Shake up the pile a bit!",
				"rattle": "Rattle the things in the pile!",
				"roll": "Make the pile do a barrel roll!",
			])[msg->action],
			"cost": 250,
			"background_color": "#a0f0c0",
			"is_global_cooldown_enabled": Val.true, "global_cooldown_seconds": 60,
		]);
	} else if (msg->action == "thing" && has_value(info->things->id, msg->thingid)) {
		cmdname = "add" + msg->thingid;
		code = sprintf(#{$%s:%s$ += "1"#}, info->varname, msg->thingid);
		reward = ([
			"title": "Add " + msg->thingid,
			"prompt": "Add another "+ msg->thingid + " to the pile",
			"cost": 100,
			"background_color": "#663399",
		]);
	} else return; //Action has to be either "claw" or a valid thing type to add
	if (channel->commands[cmdname]) //Deduplicate in an ugly fashion; if the chosen invocation is "command", you will probably want to manually edit this after
		for (int i = 2; ; ++i)
			if (!channel->commands[cmdname + i]) {cmdname += i; break;}
	switch (msg->invocation) {
		case "command": break; //Commands are simple, no extra code needed
		case "reward": {
			string rewardid = await(create_channel_point_reward(channel, reward));
			code = sprintf(#{
				#access "none"
				#visibility "hidden"
				#redemption %O
				chan_pointsrewards("{rewardid}", "fulfil", "{redemptionid}") ""
			#}, rewardid) + code;
			break;
		}
		case "timer": code = #{#access "none" #visibility "hidden" #automate "10"#} + code; break;
		default: return; //Bad invocation type, do nothing
	}
	G->G->cmdmgr->update_command(channel, "", cmdname, code, (["language": "mustard"]));
}

//Can overwrite an existing variable
mapping|zero websocket_cmd_createvar(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return (["cmd": "demo"]);
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "" || !msg->varname) return 0;
	sscanf(msg->varname, "%[A-Za-z]", string var);
	if (var != "") channel->set_variable(var, "0", "set");
}

//Requires that the variable exist, unless it's a grouped var, in which case only a syntactic check is done.
mapping|zero websocket_cmd_setvar(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return (["cmd": "demo"]);
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return 0;
	if (has_value(msg->varname, ':')) {
		//Note that per-user and ephemeral variables are not supported here.
		sscanf(msg->varname, "%[A-Za-z0-9:]", string var);
		if (!has_value(var, ':')) return 0; //If there's a bad character before the first colon, bail.
		//Otherwise, we can proceed, with a potentially truncated variable name. This will give odd
		//results if you try to setvar("asdf:qwer%20zxcv"), but it will at least be sane and safe.
		msg->varname = var;
	} else {
		string prev = G->G->DB->load_cached_config(channel->userid, "variables")["$" + msg->varname + "$"];
		if (!prev) return 0;
	}
	channel->set_variable(msg->varname, (string)(int)msg->val, "set");
}

//Create a new monitor. Must have a type; may have other attributes. If all goes well, returns ({nonce, cfg});
//otherwise returns 0 and doesn't create anything.
array(string|mapping)|zero create_monitor(object channel, mapping(string:mixed) msg) {
	if (!valid_types[msg->type]) return 0;
	//Note that this is deliberately slightly shorter than the subpoints nonce
	//(by 4 base64 characters), to allow them to be distinguished for debugging.
	string nonce = replace(MIME.encode_base64(random_string(27)), (["/": "1", "+": "0"]));
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	monitors[nonce] = ([
		"type": msg->type,
		"text": msg->text || ([
			"goalbar": "Achieve a goal!",
			"countdown": "#:##",
		])[msg->type] || "",
		"previewbg": "#FFFFFF",
	]);
	if (msg->type == "goalbar") monitors[nonce] |= ([
		"thresholds": "100",
		"color": "#005500",
		"barcolor": "#DDDDFF",
		"fillcolor": "#FFFF55",
		"previewbg": "#BBFFFF", //Override the default so you can see the colours more easily
		"needlesize": "0.375",
		"active": 1,
	]);
	if (msg->type == "pile") monitors[nonce] |= ([
		"wall_top": 0, "wall_left": 100, "wall_right": 100, "wall_floor": 100,
		"things": ({default_thing_type | ([])}),
	]);
	mapping info = monitors[nonce];
	//Hack: Create a new variable for a new goal bar etc.
	if ((<"countdown", "goalbar", "pile">)[msg->type]) {
		if (msg->varname) info->varname = msg->varname; //TODO: Check that it exists too?
		else {
			mapping vars = G->G->DB->load_cached_config(channel->userid, "variables");
			void tryvar(string v) {if (!vars["$"+v+"$"]) info->varname = v;}
			for (int i = 0; i < 26 && !info->varname; ++i) tryvar(sprintf("%s%c", info->type, 'A' + i));
			for (int i = 0; i < 26*26 && !info->varname; ++i) tryvar(sprintf("%s%c%c", info->type, 'A' + i / 26, 'A' + i % 26));
			//Do I need to attempt goalbarAAA ? We get 700 options without, or 18K with.
			channel->set_variable(info->varname, "0", "set");
		}
	}
	foreach (saveable_attributes, string key) if (msg[key]) info[key] = msg[key];
	if (info->needlesize == "") info->needlesize = "0";
	if (info->varname) info->text = sprintf("$%s$:%s", info->varname, info->text);
	textformatting_validate(info);
	G->G->DB->save_config(channel->userid, "monitors", monitors)->then() {
		send_updates_all(channel, nonce);
		update_one(channel, "", nonce);
	};
	return ({nonce, info});
}

@"is_mod": __async__ void wscmd_addmonitor(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	create_monitor(channel, (["type": msg->type])); //Very restrictive. The create_monitor function trusts its args, but we don't trust the client.
}

@"is_mod": __async__ void wscmd_updatemonitor(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	string nonce = msg->nonce;
	mapping info = monitors[nonce];
	if (!info) return; //Monitor doesn't exist. You can't create monitors with this.
	if ((<"text", "goalbar", "countdown">)[info->type]) {
		//Full update every time. TODO: Consider transitioning everything to partial update mode.
		if (!stringp(msg->text)) return;
		info = monitors[nonce] = (["type": info->type, "text": msg->text]) | (monitors[nonce] & retained_attributes);
	}
	foreach (saveable_attributes, string key) if (msg[key]) info[key] = msg[key];
	if (info->needlesize == "") info->needlesize = "0";
	if (msg->varname) info->text = sprintf("$%s$:%s", msg->varname, info->text);
	textformatting_validate(info);
	await(G->G->DB->save_config(channel->userid, "monitors", monitors));
	send_updates_all(channel, nonce);
	update_one(channel, "", nonce);
}

@"is_mod": __async__ mapping|zero wscmd_upload(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	msg->autocrop = 1; //Request that the image be cropped after upload
	mapping file = await(G->G->DB->prepare_file(channel->userid, conn->session->user->id, msg, 0));
	if (file->error) return (["cmd": "uploaderror", "name": msg->name, "error": file->error]);
	return (["cmd": "upload", "name": msg->name, "id": file->id]);
}

@hook_uploaded_file_edited: __async__ void file_uploaded(mapping file) {
	//Push out notifications regarding images. With sounds and videos, only push out notifs
	//if the file has been deleted (at which point we can't tell what the mimetype was anyway).
	if (!file->metadata || has_prefix(file->metadata->mimetype || "*/*", "image/"))
		send_updates_all("#" + file->channel, (["id": file->id, "data": file->metadata && (file->metadata | (["id": file->id])), "type": "image"]));
}

@"is_mod": void wscmd_deletefile(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	G->G->DB->delete_file(channel->userid, msg->id);
	update_one(conn->group, msg->id, "image");
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

void wscmd_removed(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	mapping info = monitors[conn->subgroup]; if (!info) return;
	if (has_value(info->things->id, msg->thingtype))
		channel->set_variable(info->varname + ":" + msg->thingtype, 1, "spend");
}

@"is_mod": __async__ void wscmd_managethings(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	mapping info = monitors[msg->nonce]; if (!info) return;
	if (msg->remove) {
		info->things = filter(info->things) {return __ARGS__[0]->id != msg->remove;};
		if (!sizeof(info->things)) msg->add = 1;
	}
	if (msg->add) {
		multiset ids = (multiset)info->things->id;
		string id = "default";
		//If you remove the last category, a new "default" category will be added.
		//Otherwise, adding a cat will give it an id of "thing1", "thing2", etc.
		//You can freely rename the categories, but we will never create a "default"
		//if there are any other categories stored.
		if (sizeof(ids)) for (int i = 1; ids[id = "thing" + i]; ++i);
		info->things += ({default_thing_type | (["id": id])});
	}
	if (msg->update) {
		int idx = search(info->things->id, msg->update);
		if (idx >= 0) {
			mapping thing = info->things[idx];
			if (msg->id && msg->id != "") {
				//Ensure that the ID is valid. It MAY be okay to allow a colon here as well,
				//permitting variable names like $pileA:thing1:whatever$ but for now this is
				//disallowed for simplicity's sake.
				sscanf(msg->id, "%[A-Za-z0-9]", string newid);
				if (newid == msg->id) thing->id = newid;
			}
			foreach (({"shape"}), string key) //String attributes
				if (msg[key]) thing[key] = msg[key];
			foreach (({"xsize"}), string key) //Numeric attributes
				if (msg[key]) thing[key] = (int)msg[key];
			if (string fileid = msg->addimage) {
				mapping file = await(G->G->DB->get_file(fileid, 1));
				if (file->?channel == channel->userid && has_prefix(file->metadata->?mimetype || "*/*", "image/")) {
					mapping img; catch {img = Image.ANY._decode(file->data);};
					//TODO maybe: Trim an all-transparent border? Would require saving back a cropped image somewhere.
					//In case it's useful, img->alpha will be populated any time there's a valid alpha channel.
					if (img) thing->images += ({([
						"url": file->metadata->url,
						"xsize": img->xsize,
						"ysize": img->ysize,
					])});
				}
			}
			if (msg->delimage) {
				int idx = (int)msg->delimage;
				if (sizeof(thing->images) > idx) {
					thing->images[idx] = 0;
					thing->images -= ({0});
				}
			}
		}
	}
	await(G->G->DB->save_config(channel->userid, "monitors", monitors));
	send_updates_all(channel, msg->nonce);
	update_one(channel, "", msg->nonce);
}

//Delete the given monitor and return its previous config. If it didn't exist, returns 0.
mapping|zero delete_monitor(object channel, string nonce) {
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	if (!monitors[nonce]) return 0;
	m_delete(monitors, nonce);
	G->G->DB->save_config(channel->userid, "monitors", monitors)->then() {send_updates_all(channel, "");};
}

@"is_mod": __async__ void wscmd_deletemonitor(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	delete_monitor(channel, msg->nonce);
}

//NOTE: This is a very rare message - a mutator that does not require mod powers or even a login.
//The *only* thing you can do with it is (re)start a countdown configured to start on scene.
void wscmd_sceneactive(object channel, mapping(string:mixed) conn, mapping(string:mixed) msg) {
	mapping mon = G->G->DB->load_cached_config(channel->userid, "monitors")[conn->subgroup];
	if (!mon->?startonscene) return;
	sscanf(mon->text, "$%s$:", string varname);
	channel->set_variable(varname, (string)(time() + (int)mon->startonscene_time));
}

@hook_allmsgs:
int message(object channel, mapping person, string msg)
{
	mapping mon = G->G->DB->load_cached_config(channel->userid, "monitors");
	if (!mon || !sizeof(mon)) return 0;
	//TODO: Support other ways of recognizing donations
	if (person->user == "streamlabs") {
		//Note that the dollar amount might have a comma in it, if Mixer237237 is being insane.
		sscanf(msg - ",", "%s just tipped $%d.%d!", string user, int dollars, int cents);
		if (user && sizeof(user) > 3 && user[1] == ' ') user = user[2..]; //See related handling in vipleaders, there's a random symbol in there
		autoadvance(channel, person | (["from_name": user]), "tip", 100 * dollars + cents);
	}
}

@hook_cheer:
void cheer(object channel, mapping person, int bits, mapping extra, string msg) {
	autoadvance(channel, person, "bit", bits);
}

@hook_subscription:
int subscription(object channel, string type, mapping person, string tier, int qty, mapping extra) {
	if (type == "subbomb") return 0; //Sometimes sub bombs come through AFTER their constituent parts :( Safer to count the parts and skip the bomb.
	if (type == "subgift" || extra->msg_param_sub_plan == "Prime") extra->is_gift_or_prime = 1;
	autoadvance(channel, person, "sub_t" + tier, qty, extra);
}

void advance_goalbar(object channel, mapping|string info, mapping person, int advance, mapping|void extra) {
	//May pass the info mapping or the monitor ID
	if (stringp(info)) info = G->G->DB->load_cached_config(channel->userid, "monitors")[info];
	if (!mappingp(info)) return; //Probably wrong monitor ID
	if (!extra) extra = ([]);
	sscanf(info->text, "$%s$:%s", string varname, string txt);
	if (!txt) return;
	echoable_message lvlup = channel->commands[info->lvlupcmd];
	int prevtier = lvlup && calculate_current_goalbar_tier(channel, info)[2];
	//HACK: If it's bit boss mode, we may need to change the from_name, and we may need to
	//negate the advancement. Massive breach of encapsulation.
	string from_name = person->from_name || person->user || "Anonymous";
	if (string recip = info->boss_giftrecipient && extra->msg_param_recipient_display_name) from_name = recip;
	if (info->boss_selfheal && lower_case(from_name) == lower_case(channel->expand_variables("$bossname$"))) {
		int dmg = (int)channel->expand_variables("$bossdmg$");
		if (advance > dmg) {
			//Overheal: Healing can increase max HP
			//We delay this a bit to ensure that the monitor looks right-ish; otherwise, it's liable to lose one of the updates.
			if (info->boss_selfheal == 2) call_out(channel->set_variable, 0.25, "bossmaxhp", advance - dmg, "add");
			advance = dmg; //No healing past your max HP. Increasing max HP leaves you at zero net damage.
		}
		advance = -advance; //Heal rather than hurt.
	}
	int total = (int)channel->set_variable(varname, advance, "add"); //Abuse the fact that it'll take an int just fine for add :)
	if (advance > 0 && lvlup) {
		int newtier = calculate_current_goalbar_tier(channel, info)[2];
		while (++prevtier <= newtier) channel->send(person, lvlup, (["%s": (string)prevtier, "{from_name}": from_name]));
	}
	if (info->record_leaderboard) get_user_info(from_name, "login")->then() {
		channel->set_variable("from*" + varname, advance, "add", (["from": (string)__ARGS__[0]->id]));
	};
}

//Note: Use the builtin to advance bars from a command/trigger/special.
//Otherwise, simply assigning to the variable won't trigger the level-up command.
void autoadvance(object channel, mapping person, string key, int weight, mapping|void extra) {
	if (!extra) extra = ([]);
	foreach (G->G->DB->load_cached_config(channel->userid, "monitors"); string id; mapping info) {
		if (info->type != "goalbar" || !info->active) continue;
		if (extra->is_gift_or_prime && info->exclude_gifts) continue;
		int advance = key == "" ? weight : weight * (int)info[key];
		if (!advance) continue;
		advance_goalbar(channel, info, person, advance, extra);
	}
}

string format_plain(int value) {return (string)value;}
string format_currency(int value) {
	if (!(value % 100)) return "$" + (value / 100);
	return sprintf("$%d.%02d", value / 100, value % 100);
}
string format_subscriptions(int value) {
	if (!(value % 500)) return (string)(value / 500);
	return sprintf("%.3f", value / 500.0);
}

//Work out where we are in the goal bar. Returns [pos, goal, tier] where pos and goal
//show the basic positional stats ("43/100") and tier is the zero-based iteration of
//the goal bar, always zero for tier-less goals.
array(int) calculate_current_goalbar_tier(object channel, mapping info) {
	int pos = (int)channel->expand_variables(info->text); //The text starts with the variable, then a colon, so this will give us the current (raw) value.
	int tier, goal = 0, found;
	int prev; //For delta calculation
	foreach (channel->expand_variables(info->thresholds) / " "; tier; string th) {
		prev = goal;
		goal = (int)th;
		if (pos < goal) {
			found = 1;
			break;
		}
		else if (!info->progressive) pos -= goal;
	}
	if (!found) {
		//Beyond the last threshold. Some numbers may exceed normal
		//limits, eg percentage being above 100. Note that, for a
		//non-tiered goal bar, this simply means "goal is reached".
		//However, if we have infinite goals, we effectively have more
		//tiers, each one having the same delta, until we exceed the
		//current position.
		if (info->infinitier) {
			if (!info->progressive) {
				//With resetting goals, the goal doesn't change but the position does.
				if (goal) while (pos >= goal) {
					++tier;
					pos -= goal;
				}
			} else {
				//With progressive goals, each new tier is as far from the previous goal as the calculated delta.
				int delta = goal - prev;
				if (delta) while (pos >= goal) {
					++tier;
					goal += delta;
				}
			}
		}
		else if (!info->progressive) pos += goal; //Show that we're past the goal
	}
	return ({pos, goal, tier});
}

//Because I don't feel like making all of message_params asynchronous
__async__ mapping pile_add(object channel, mapping info, mapping person, array param) {
	string monitor = param[0];
	//NOTE: set_variable synchronously pushes out socket messages to notify the pile,
	//so multiple queued adds will all operate sequentially. The addxtra command will
	//happen first, followed by the update to the quantity. Note that, if the quantity
	//for some reason does NOT update (shouldn't happen!), the addxtra will linger,
	//potentially resulting in a future change to the qty getting this xtra; but it
	//will be overwritten by any subsequent add command.
	string label; string|mapping|zero image;
	if (sizeof(param) > 3 && param[3] != "") {
		//Set the label to a piece of text, or to "emote:{@emoted}" to get the name of the
		//first emote used. Note that, for complete reliability, set the label to "text:%s"
		//if there is any chance that the text could contain a colon.
		sscanf(param[3], "%s:%s", string code, string args);
		if (!args) {code = "text"; args = param[3];}
		switch (code) {
			case "text": label = args; break;
			case "emote": {
				sscanf(args, "%*s\ufffae%s:%s\ufffb", string emoteid, label);
				//If not found, leave label as null
				break;
			}
		}
	}
	if (sizeof(param) > 4 && param[4] != "") {
		sscanf(param[4], "%s:%s", string code, string args);
		if (!args) {code = "text"; args = param[4];} //No useful default currently. The default is *not* URL - be explicit.
		switch (code) {
			case "url": image = args; break;
			case "emote": {
				sscanf(args, "%*s\ufffae%s:%s\ufffb", string emoteid, string label);
				//TODO: Pick a size?? Might be better to use the 1.0 for smaller things.
				if (emoteid) image = "https://static-cdn.jtvnw.net/emoticons/v2/" + emoteid + "/static/light/3.0";
				break;
			}
			case "avatar":
				mapping user = await(get_user_info((int)args, "id"));
				if (user) image = user->profile_image_url;
				break;
		}
		if (image) image = await(get_image_dimensions(image));
	}
	if (label || image) send_updates_all(channel, monitor, (["addxtra": param[2], "xtra": (["label": label, "image": image])]));
	string newcount = channel->set_variable(info->varname + ":" + param[2], 1, "add");
	return (["{type}": info->type, "{value}": newcount]);
}

mapping|Concurrent.Future message_params(object channel, mapping person, array param) {
	string monitor = param[0];
	mapping info = G->G->DB->load_cached_config(channel->userid, "monitors")[monitor];
	if (!info) error("Unrecognized monitor ID - has it been deleted?\n");
	switch (info->type) {
		case "goalbar": {
			int advance = sizeof(param) > 1 && (int)param[1];
			if (advance) autoadvance(channel, person, "", advance); //FIXME: Is this really advancing ALL goal bars?? That has to be a bug right?
			[int pos, int goal, int tier] = calculate_current_goalbar_tier(channel, info);
			int percent = (int)(pos * 100.0 / goal + 0.5), distance = goal - pos;
			function fmt = this["format_" + info->format] || format_plain;
			return ([
				"{type}": info->type,
				"{goal}": fmt(goal), "{goal_raw}": (string)goal,
				"{distance}": fmt(distance), "{distance_raw}": (string)distance,
				"{value}": fmt(pos), "{value_raw}": (string)pos,
				"{percentage}": fmt(percent), "{percentage_raw}": (string)percent,
				"{tier}": (string)(tier + 1),
			]);
		}
		case "countdown": {
			sscanf(info->text, "$%s$:%s", string varname, string txt);
			string p2 = sizeof(param) > 2 && param[2];
			int pos = (int)channel->expand_variables(info->text);
			int now = time();
			switch (sizeof(param) > 1 && param[1]) {
				case "start": //Set the timer to X seconds from now
					channel->set_variable(varname, (string)(pos = time() + (int)p2));
					break;
				case "pause": //Pause the countdown
					if (pos > now) channel->set_variable(varname, (string)(pos -= now));
					break;
				case "resume": //Unpause a paused timer
					if (pos <= 1000000000) channel->set_variable(varname, (string)(pos += now));
					break;
				case "extend": //Extend a timer (use a negative number to shorten)
					channel->set_variable(varname, (string)(pos += (int)p2));
					break;
				//TODO: "set" to choose a specific Unix time, or some kind of time string that will
				//be interpreted in your time zone. Borrow from automation maybe?
				default: break; //No change requested, just get status
			}
			int paused = pos <= 1000000000;
			return ([
				"{type}": info->type,
				"{paused}": (string)paused,
				"{timeleft}": paused ? (string)pos : (string)(pos - now),
				"{targettime}": paused ? (string)(pos + now) : (string)pos,
			]);
		}
		case "pile": {
			switch (sizeof(param) > 1 && param[1]) {
				case "claw": {
					//Defer the execution of the subtree. TODO: Timeout? What if the browser source isn't active?
					string dropid = String.string2hex(random_string(4));
					object prom = clawids_pending[dropid] = Concurrent.Promise();
					send_updates_all(channel, monitor, (["claw": dropid]));
					return prom->future();
				}
				case "shake": case "rattle": case "roll":
					send_updates_all(channel, monitor, ([param[1]: (sizeof(param) > 2 && (int)param[2]) || 1]));
					break;
				case "add": return pile_add(channel, info, person, param);
				case "remove": {
					if (param[2] == "*") {
						//Remove all things.
						foreach (info->things || ({ }), mapping thing)
							channel->set_variable(info->varname + ":" + thing->id, "0", "set");
					} else send_updates_all(channel, monitor, (["remove": param[2] || "default", "label": param[3] || ""]));
					break;
				}
				default: break;
			}
			//Nothing useful to return here.
		}
		default: return (["{type}": info->type]); //Should be "text".
	}
}

@retain: mapping queued_offline_resets = ([]);
void reset_goal_bar(int broadcaster_id, string id) {
	object channel = G->G->irc->id[broadcaster_id]; if (!channel) return;
	remove_call_out(m_delete(queued_offline_resets, id + "#" + channel->userid));
	mapping info = G->G->DB->load_cached_config(channel->userid, "monitors")[id];
	switch (info->type) {
		case "pile": {
			//Zero out the variables for each active thing type
			foreach (info->things || ({ }), mapping thing)
				channel->set_variable(info->varname + ":" + thing->id, "0", "set");
			break;
		}
		case "goalbar": {
			if (info->format == "hitpoints") {
				//NOTE: When bit boss gets rejigged, this could look at varname for simplicity.
				G->G->websocket_types->chan_minigames->reset_boss(channel);
				break;
			}
			//Normal goal bar: Zero out the one variable that governs it.
			channel->set_variable(info->varname, "0", "set");
			break;
		}
		default: break; //No need to autoreset text or countdown.
	}
}

//To allow autoreset on any given period (eg weekly - but watch for Sunday first vs Sunday last),
//create a function with the name timepart_{period} which, given a timestamp, returns a string which
//will be identical all through that period and change when the period changes.
string timepart_monthly(object ts) {
	return sprintf("%d-%02d", ts->year_no(), ts->month_no());
}

void check_for_resets(int broadcaster_id, int streamreset) {
	object channel = G->G->irc->id[broadcaster_id]; if (!channel) return;
	int changed = 0;
	mapping mon = G->G->DB->load_cached_config(channel->userid, "monitors");
	foreach (mon; string id; mapping info) {
		int reset = streamreset && info->autoreset == "stream";
		//If we're past a month end, it's time to reset (eg if you went past midnight while live,
		//then the reset happens after the stream goes offline).
		if (function f = this["timepart_" + info->autoreset]) {
			string now = f(Calendar.now()->set_timezone(channel->config->timezone || "UTC"));
			if (now != info->lastreset) {
				info->lastreset = now;
				reset = changed = 1;
			}
		}
		if (reset) {
			string key = id + "#" + channel->userid;
			remove_call_out(m_delete(queued_offline_resets, key));
			//When we go offline, delay the reset by half an hour. When online, do it as quickly as possible.
			queued_offline_resets[key] = call_out(reset_goal_bar, streamreset && 1800, channel->userid, id);
		}
	}
	if (changed) G->G->DB->save_config(channel->userid, "monitors", mon);
}

@hook_channel_online: int channel_online(string chan, int uptime, int broadcaster_id) {
	//Since we're now online, make sure we don't do any pending just-went-offline checks.
	foreach (indices(queued_offline_resets), string key) {
		if (has_suffix(key, "#" + broadcaster_id)) remove_call_out(m_delete(queued_offline_resets, key));
	}
	check_for_resets(broadcaster_id, 0);
}

@hook_channel_offline: int channel_offline(string chan, int uptime, int broadcaster_id) {check_for_resets(broadcaster_id, 1);}

protected void create(string name) {
	::create(name);
	G->G->goal_bar_autoadvance = autoadvance;
	G->G->goal_bar_advance = advance_goalbar;
}
