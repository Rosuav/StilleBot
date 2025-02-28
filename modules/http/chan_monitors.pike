inherit http_websocket;
inherit hook;
inherit builtin_command;

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
";

constant builtin_name = "Monitors"; //The front end may redescribe this according to the parameters
constant builtin_description = "Get information about a channel monitor";
//NOTE: The labels for parameters 1 and 2 will be replaced by the GUI editor based on monitor type.
constant builtin_param = ({"/Monitor/monitor_id", "Advancement/action", "Time (countdowns only)"});
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
	"twitchsched twitchsched_offset" / " " + TEXTFORMATTING_ATTRS;
constant retained_attributes = (<"boss_selfheal", "boss_giftrecipient">); //Attributes set externally, not editable.
constant valid_types = (<"text", "goalbar", "countdown">);

__async__ mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req) {
	mapping monitors = G->G->DB->load_cached_config(req->misc->channel->userid, "monitors");
	if (req->variables->view) {
		//Unauthenticated viewing endpoint. Depends on an existing nonce.
		string|zero nonce = req->variables->view;
		mapping info = monitors[nonce];
		if (!info) nonce = 0;
		return render_template("monitor.html", ([
			"vars": (["ws_type": ws_type, "ws_group": nonce + "#" + req->misc->channel->userid, "ws_code": "monitor"]),
			//Note that $$styles$$ is used differently in chan_subpoints which reuses monitor.html.
			"styles": monitorstyles,

		]));
	}
	if (!req->misc->is_mod) return render_template("login.md", (["msg": "moderator privileges"]) | req->misc->chaninfo);
	return render(req, ([
		"vars": (["ws_group": ""]),
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
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping monitors = G->G->DB->load_cached_config(channel->userid, "monitors");
	if (grp != "") return (["data": _get_monitor(channel, monitors, grp)]);
	if (id) return _get_monitor(channel, monitors, id);
	return (["items": _get_monitor(channel, monitors, sort(indices(monitors))[*])]);
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
		if (!has_value(info->text, var)) continue;
		mapping info = (["data": (["id": nonce, "display": channel->expand_variables(info->text)])]);
		send_updates_all(channel, nonce, info); //Send to the group for just that nonce
		info->id = nonce; send_updates_all(channel, "", info); //Send to the master group as a single-item update
	}
}

//Can overwrite an existing variable
mapping|zero websocket_cmd_createvar(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return (["cmd": "demo"]);
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "" || !msg->varname) return 0;
	sscanf(msg->varname, "%[A-Za-z]", string var);
	if (var != "") channel->set_variable(var, "0", "set");
}

//Requires that the variable exist
mapping|zero websocket_cmd_setvar(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	if (conn->session->fake) return (["cmd": "demo"]);
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "") return 0;
	string prev = G->G->DB->load_cached_config(channel->userid, "variables")["$" + msg->varname + "$"];
	if (!prev) return 0;
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
	mapping info = monitors[nonce];
	//Hack: Create a new variable for a new goal bar/countdown.
	if ((<"countdown", "goalbar">)[msg->type]) {
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
	if (!stringp(msg->text) || !monitors[nonce]) return; //Monitor doesn't exist. You can't create monitors with this.
	mapping info = monitors[nonce] = (["type": monitors[nonce]->type, "text": msg->text]) | (monitors[nonce] & retained_attributes);
	foreach (saveable_attributes, string key) if (msg[key]) info[key] = msg[key];
	if (info->needlesize == "") info->needlesize = "0";
	if (msg->varname) info->text = sprintf("$%s$:%s", msg->varname, info->text);
	textformatting_validate(info);
	await(G->G->DB->save_config(channel->userid, "monitors", monitors));
	send_updates_all(channel, nonce);
	update_one(channel, "", nonce);
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

mapping message_params(object channel, mapping person, array param) {
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
		default: return (["{type}": info->type]); //Should be "text".
	}
}

protected void create(string name) {
	::create(name);
	G->G->goal_bar_autoadvance = autoadvance;
	G->G->goal_bar_advance = advance_goalbar;
}
