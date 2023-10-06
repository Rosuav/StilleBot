inherit http_websocket;
inherit hook;
inherit annotated;
constant markdown = #"# Giveaway - $$giveaway_title||win things with channel points$$

<div id=errormessage class=hidden></div>

<div id=master_status>$$error||Loading giveaway status...$$</div>

<ul id=ticketholders></ul>

$$login$$

> <summary>Set up rewards</summary>
>
> <form id=configform>
>
> - | - | -
> --|---|--
> <label for=ga_title>Giveaway title</label> | <input id=ga_title name=title size=40 placeholder=\"an awesome thing\"> | What are people winning?
> <label for=ga_cost>Cost per ticket</label> | <input id=ga_cost name=cost type=number min=1 value=1></label> | Loyal viewers can earn a thousand points in a 2-3 hour stream. [See details.](https://help.twitch.tv/s/article/channel-points-guide)
> <label for=ga_desc>Description</label> | <input id=ga_desc name=desc size=40 maxlength=40 placeholder=\"Buy # tickets\"> | Put a <code>#</code> symbol for multibuy count
> <label for=ga_multi>Multibuy options</label> | <input id=ga_multi name=multi size=40 placeholder=\"1 5 10 25 50\"> | Allow people to buy tickets in these quantities. If omitted, you'll get 1, 10, 100, 1000, etc.
> <label for=ga_max>Max tickets</label> | <input id=ga_max name=max type=number min=0 value=0> | Purchases that would put you over this limit will be cancelled
> <label for=ga_pausemode>Redemption hiding</label> | <select id=ga_pausemode name=pausemode><option value=disable>Disable, hiding them from users</option><option value=pause>Pause and leave visible</option></select> | When there's no current giveaway, should redemptions remain visible (but unpurchaseable), or vanish entirely?
> Multi-win | <label><input type=checkbox name=allow_multiwin value=yes> Allow one person to win multiple times</label> | By default, the winner's tickets will be removed in case of a reroll or second winner.
> <label for=ga_duration>Time before giveaway closes</label> | <input id=ga_duration name=duration type=number min=0 max=3600> (seconds) | How long should the giveaway be open? 0 leaves it until explicitly closed.
> Non-binding purchases | <label><input type=checkbox name=refund_nonwinning value=yes> Refund non-winning tickets at end of giveaway</label> | By default, all ticket purchases are counted as claimed (channel points spent) when the giveaway is ended.
>
> <button>Save/reconfigure</button>
>
> Giveaway notifications are handled through [special triggers](specials#Giveaways) and can be customized there.<br>
> [Create default notifications (replacing existing ones)](: #makenotifs)
>
> </form>
{: tag=details .modonly}

[Master Control](:#showmaster)
{: .modonly}

> ### Master Control
> * [Open giveaway](:.master #open) and allow people to buy tickets
> * [Close giveaway](:.master #close) so no more tickets will be bought
> * [Choose winner](:.master #pick) and remove that person's tickets
> * [Cancel and refund](:.master #cancel) all points spent on tickets
> * [End giveaway](:.master #end) <span id=refund_nonwinning_desc>clearing out</span> tickets
>
{: tag=dialog #master}

<style>
details {border: 1px solid black; padding: 0.5em; margin: 0.5em;}
#master li {
	margin-top: 0.5em;
	margin-right: 40px;
	list-style-type: none;
}
#master li.next {list-style-type: \"=> \";}
#master li.next::marker {font-weight: bold;}
#master_status {
	width: 350px;
	background: aliceblue;
	border: 3px solid blue;
	margin: auto;
	padding: 1em;
	font-size: 125%;
}
#master_status.is_open {
	background: #a0f0c0;
	border-color: green;
}
#master_status h3 {
	font-size: 125%;
	margin: 0 auto 0.5em;
}
.winner_name {
	background-color: #ffe;
	font-weight: bold;
}
.modonly {$$modonly||display: none$$;}
#errormessage {
	background: #fdd;
	border: 3px solid red;
	max-width: fit-content;
	padding: 5px;
	margin: 10px;
}
.hidden {display: none;}
</style>
";

inherit builtin_command;
constant visibility = "hidden";
constant access = "none";
@retain: mapping giveaway_tickets = ([]);
@retain: multiset giveaway_purchases = (<>);

constant NOTIFICATION_SPECIALS = ([
	"started": "A giveaway for {title} is now open - use your channel points to purchase tickets!",
	"toomany": ([
		"conditional": "string", "expr1": "{tickets_max}", "expr2": "1",
		"message": ([
			"conditional": "string", "expr1": "{tickets_total}", "expr2": "0",
			"message": "$$: You can't buy {tickets_bought} tickets - maximum is 1.",
			"otherwise": "$$: You already have a ticket and your points have been refunded.",
		]),
		"otherwise": ([
			"conditional": "string", "expr1": "{tickets_total}", "expr2": "0",
			"message": "$$: Can't buy {tickets_bought} tickets - the maximum is {tickets_max}",
			"otherwise": "$$: Can't buy {tickets_bought} tickets as you already have {tickets_total} (max {tickets_max})",
		])
	]),
	"winner": "Congratulations to {winner_name} for winning the {title}!",
]);

Concurrent.Future set_redemption_status(mapping redem, string status) {
	return complete_redemption(redem->broadcaster_login || redem->broadcaster_user_login,
		redem->reward->id, redem->id, status);
}

void update_ticket_count(mapping cfg, mapping redem, int|void removal) {
	if (!cfg->giveaway) return;
	mapping values = cfg->giveaway->rewards || ([]);
	if (!values[redem->reward->id]) return; //No value assigned to this reward, so it's presumably not a giveaway ticket redemption
	string chan = redem->broadcaster_login || redem->broadcaster_user_login;
	mapping people = giveaway_tickets[chan];
	if (!people) people = giveaway_tickets[chan] = ([]);
	if (!people[redem->user_id]) people[redem->user_id] = ([
		"name": redem->user_name,
		"position": sizeof(people) + 1, //First person to buy a ticket gets position 1
		"redemptions": ([]), //Map redemption IDs to their info.
		"tickets": 0, //== sum(values[redemptions->reward->id[*]])
	]);
	mapping person = people[redem->user_id];
	if (removal == !person->redemptions[redem->id]) ; //Already (not) there, do nothing.
	else if (removal) {
		m_delete(person->redemptions, redem->id);
		person->tickets -= values[redem->reward->id];
	}
	else {
		int now = person->tickets + values[redem->reward->id];
		mapping status = persist_status->path("giveaways", chan);
		int max = cfg->giveaway->max_tickets || (1<<100); //Hack: Max max tickets is a big number, not infinite. Whatever.
		int too_late = 0;
		if (!status->is_open) {
			//If anything snuck in while we were closing the giveaway, refund it as soon as we notice.
			too_late = 1;
			if (status->last_opened < status->last_closed) {
				//It's possible that the giveaway was recently closed, and that you bought tickets
				//while it was open. If so, honour those purchases.
				int redemption_time = time_from_iso(redem->redeemed_at)->unix_time();
				if (status->last_opened <= redemption_time && redemption_time <= status->last_closed)
					too_late = 0;
			}
		}
		if ((too_late || now > max) && !giveaway_purchases[redem->id]) {
			//If we previously saw this as acceptable, don't refund it.
			//This means that if you change the max tickets during a giveaway, any excess will
			//still be kept, unless/until they get explicitly refunded.
			set_redemption_status(redem, "CANCELED")->then(lambda(mixed resp) {
				catch {
					object ts = time_from_iso(redem->redeemed_at);
					int redemption_time = ts->unix_time();
					array timestamps = ({redemption_time, status->last_opened, status->last_closed});
					array ts_labels = ({"Bought", "Opened", "Closed"});
					sort(timestamps, ts_labels);
					foreach (timestamps; int i; int ts)
						write("%s: %d (%+d)\n", ts_labels[i], ts, ts - time());
				};
				write("Cancelled (%d/%d): %O\n", now, max, resp);
				object channel = G->G->irc->channels["#" + chan];
				//If max is zero, you were probably too late. Should there be a different message?
				if (max) channel->trigger_special("!giveaway_toomany", (["user": redem->user_name]), ([
					"{title}": cfg->giveaway->title || "",
					"{tickets_bought}": (string)values[redem->reward->id],
					"{tickets_total}": (string)person->tickets,
					"{tickets_max}": (string)cfg->giveaway->max_tickets,
				]));
			});
		}
		else {
			person->tickets = now;
			person->redemptions[redem->id] = redem;
			if (!giveaway_purchases[redem->id]) {
				//Only announce a given purchase once, even if we do a full recalc of giveaway_tickets
				giveaway_purchases[redem->id] = 1;
				object channel = G->G->irc->channels["#" + chan];
				write("GIVEAWAY: %s bought %d, now %d/%d\n", redem->user_name,
					values[redem->reward->id], now, cfg->giveaway->max_tickets);
				channel->trigger_special("!giveaway_ticket", (["user": redem->user_name]), ([
					"{title}": cfg->giveaway->title || "",
					"{tickets_bought}": (string)values[redem->reward->id],
					"{tickets_total}": (string)now,
					"{tickets_max}": (string)cfg->giveaway->max_tickets,
				]));
			}
		}
	}
}

array tickets_in_order(string chan) {
	array tickets = ({ });
	foreach (giveaway_tickets[chan] || ([]); ; mapping person)
		if (person->tickets) tickets += ({person});
	sort(tickets->position, tickets);
	return tickets;
}

//Send an update based on cached data rather than forcing a full recalc every time
void notify_websockets(string chan) {
	mapping status = persist_status->has_path("giveaways", chan) || ([]);
	send_updates_all("control#" + chan, ([
		"tickets": tickets_in_order(chan),
		"last_opened": status->last_opened, "last_closed": status->last_closed,
		"is_open": status->is_open, "end_time": status->end_time,
		"last_winner": status->last_winner,
	]));
	send_updates_all("view#" + chan, ([
		"last_opened": status->last_opened, "last_closed": status->last_closed,
		"is_open": status->is_open, "end_time": status->end_time,
		"last_winner": status->last_winner,
	]));
}

@hook_point_redemption:
void redemption(string chan, string rewardid, int(0..1) refund, mapping data) {
	mapping cfg = get_channel_config(chan); if (!cfg) return;
	update_ticket_count(cfg, data, refund);
	notify_websockets(chan);
}

//List all redemptions for a particular reward ID
Concurrent.Future list_redemptions(int broadcaster_id, string chan, string id) {
	return get_helix_paginated("https://api.twitch.tv/helix/channel_points/custom_rewards/redemptions",
		([
			"broadcaster_id": (string)broadcaster_id,
			"reward_id": id,
			"status": "UNFULFILLED",
			"first": "50",
		]),
		(["Authorization": "Bearer " + token_for_user_login(chan)[0]]), //TODO: Switch to user_id once that's the fundamental
	);
}

continue mapping(string:mixed)|Concurrent.Future http_request(Protocols.HTTP.Server.Request req)
{
	mapping cfg = req->misc->channel->config;
	string chan = req->misc->channel->name[1..];
	string login = "[Broadcaster login](:.twitchlogin data-scopes=channel:manage:redemptions)";
	if (string scopes = ensure_bcaster_token(req, "channel:manage:redemptions")) return render(req, ([
		"error": "This page will become available once the broadcaster has logged in and configured redemptions.",
		"login": "[Broadcaster login](:.twitchlogin data-scopes=" + replace(scopes, " ", "%20") + ")",
	]) | req->misc->chaninfo);
	string token = yield(token_for_user_login_async(chan))[0];
	login += " [Mod login](:.twitchlogin)"; //TODO: If logged in as wrong user, allow logout
	int broadcaster_id = yield(get_user_id(chan));
	Concurrent.Future call(string method, string query, mixed body) {
		return twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id + "&" + query,
			(["Authorization": "Bearer " + token]),
			(["method": method, "json": body, "return_status": !body]),
		);
	}
	if (req->misc->is_mod && req->request_type == "PUT") {
		mixed body = Standards.JSON.decode(req->body_raw);
		if (!body || !mappingp(body)) return (["error": 400]);
		if (int cost = (int)body->cost) {
			//Master reconfiguration
			array qty = (array(int))(replace(body->multi || "1 10 100 1000 10000 100000 1000000", ",", " ") / " ") - ({0});
			if (!has_value(qty, 1)) qty = ({1}) + qty;
			if (!cfg->giveaway) cfg->giveaway = ([]);
			mapping status = persist_status->path("giveaways", chan);
			cfg->giveaway->title = body->title;
			if (int max = cfg->giveaway->max_tickets = (int)body->max)
				qty = filter(qty) {return __ARGS__[0] <= max;};
			cfg->giveaway->desc_template = body->desc;
			cfg->giveaway->multibuy = body->multi;
			cfg->giveaway->cost = cost;
			cfg->giveaway->pausemode = body->pausemode == "pause";
			cfg->giveaway->allow_multiwin = body->allow_multiwin == "yes";
			cfg->giveaway->duration = min(max((int)body->duration, 0), 3600);
			cfg->giveaway->refund_nonwinning = body->refund_nonwinning == "yes";
			mapping existing = cfg->giveaway->rewards;
			if (!existing) existing = cfg->giveaway->rewards = ([]);
			int numcreated = 0, numupdated = 0, numdeleted = 0;
			//Prune any that we no longer need
			foreach (existing; string id; int tickets) {
				if (!has_value(qty, tickets)) {
					m_delete(existing, id);
					++numdeleted;
					mixed _ = yield(call("DELETE", "id=" + id, 0));
				}
				else {
					++numupdated;
					if (catch (yield(call("PATCH", "id=" + id, ([
						"title": replace(body->desc || "Buy # tickets", "#", (string)tickets),
						"cost": cost * tickets,
						"is_enabled": status->is_open || cfg->giveaway->pausemode,
						"is_paused": !status->is_open && cfg->giveaway->pausemode,
					]))))) {m_delete(existing, id); continue;} //And let it get recreated
				}
				qty -= ({tickets});
			}
			//Create any that we don't yet have
			foreach (qty, int tickets) {
				mapping info = yield(call("POST", "", ([
					"title": replace(body->desc || "Buy # tickets", "#", (string)tickets),
					"cost": cost * tickets,
					"is_enabled": status->is_open || cfg->giveaway->pausemode,
					"is_paused": !status->is_open && cfg->giveaway->pausemode,
				])));
				existing[info->data[0]->id] = tickets;
				++numcreated;
			}
			req->misc->channel->config_save();
			//TODO: Notify the front end what's been changed, not just counts. What else needs to be pushed out?
			send_updates_all(chan, (["title": cfg->giveaway->title]));
			return jsonify((["ok": 1, "created": numcreated, "updated": numupdated, "deleted": numdeleted]));
		}
		if (body->new_dynamic) { //TODO: Migrate this to chan_pointsrewards as "create manageable reward". It doesn't necessarily have to have dynamic pricing.
			if (!cfg->dynamic_rewards) cfg->dynamic_rewards = ([]);
			mapping copyfrom = body->copy_from || ([]); //Whatever we get from the front end, pass to Twitch. Good idea? Not sure.
			//Titles must be unique (among all rewards). To simplify rapid creation of
			//multiple rewards, add a numeric disambiguator on conflict.
			string deftitle = copyfrom->title || "Example Dynamic Reward";
			mapping rwd = (["basecost": copyfrom->cost || 1000, "availability": "{online}", "formula": "PREV * 2"]);
			array have = filter((G->G->pointsrewards[chan]||({}))->title, has_prefix, deftitle);
			copyfrom |= (["title": deftitle + " #" + (sizeof(have) + 1), "cost": rwd->basecost]);
			string id = yield(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id,
				(["Authorization": "Bearer " + token]),
				(["method": "POST", "json": copyfrom]),
			))->data[0]->id;
			//write("Created new dynamic: %O\n", info->data[0]);
			cfg->dynamic_rewards[id] = rwd;
			req->misc->channel->config_save();
			return jsonify((["ok": 1, "reward": rwd | (["id": id])]));
		}
		if (string id = body->dynamic_id) { //TODO: Ditto, move to pointsrewards
			if (!cfg->dynamic_rewards || !cfg->dynamic_rewards[id]) return (["error": 400]);
			mapping rwd = cfg->dynamic_rewards[id];
			m_delete(rwd, "title"); //Clean out old data (can get rid of this once we're not saving that any more)
			if (!undefinedp(body->basecost)) rwd->basecost = (int)body->basecost;
			if (body->formula) rwd->formula = body->formula;
			if (body->availability) rwd->availability = body->availability;
			if (rwd->availability == "" && rwd->formula == "") m_delete(cfg->dynamic_rewards, id); //Hack: Delete by blanking the values. Will be replaced later.
			if (body->title || body->curcost) {
				//Currently fire-and-forget - there's no feedback if you get something wrong.
				twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id + "&id=" + id,
					(["Authorization": "Bearer " + token]),
					(["method": "PATCH", "json": (["title": body->title, "cost": (int)body->curcost])]),
				);
			}
			req->misc->channel->config_save();
			return jsonify((["ok": 1]));
		}
		if (body->activate) { //TODO: As above, move to pointsrewards on the ws
			channel_on_off(chan, -1); //TODO: If an ID is given, just activate/deactivate that reward
			return jsonify((["ok": 1]));
		}
		return jsonify((["ok": 1]));
	}
	mapping config = ([]);
	mapping g = cfg->giveaway || ([]);
	config->title = g->title || ""; //Give this one even to non-mods
	if (req->misc->is_mod) {
		config->cost = g->cost || 1;
		config->max = g->max_tickets;
		config->desc = g->desc_template || "";
		config->pausemode = g->pausemode ? "pause" : "disable";
		config->allow_multiwin = g->allow_multiwin ? "yes" : "no";
		config->duration = g->duration;
		config->refund_nonwinning = g->refund_nonwinning ? "yes" : "no";
		//TODO: Show the actual existing rewards somewhere?
		//if (mapping existing = g->rewards)
		//	config->multi = ((array(string))sort(values(existing))) * " ";
		//else config->multi = "";
		config->multi = g->multibuy;
	}
	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : "view", "config": config]),
		"giveaway_title": g->title, //Prepopulate the heading and the page title so it doesn't have to load and redraw
		"modonly": req->misc->is_mod && "",
		"login": req->misc->is_mod ? "" : login,
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
continue mapping|Concurrent.Future get_chan_state(object channel, string grp)
{
	string chan = channel->name[1..];
	mapping status = persist_status->has_path("giveaways", chan) || ([]);
	if (grp == "view") return ([
		"title": channel->config->giveaway->?title,
		"is_open": status->is_open, "end_time": status->end_time,
		"last_winner": status->last_winner,
	]);
	if (grp != "control") return 0;
	int broadcaster_id = yield(get_user_id(chan));
	array rewards;
	if (mixed ex = catch {rewards = yield(twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?only_manageable_rewards=true&broadcaster_id=" + broadcaster_id,
		(["Authorization": "Bearer " + token_for_user_id(broadcaster_id)[0]])))->data;
	}) {
		if (arrayp(ex) && stringp(ex[0]) && has_value(ex[0], "Error from Twitch") && has_value(ex[0], "401")) {
			m_delete(persist_status->path("bcaster_token"), chan);
			//TODO: Return a message informing the user
			//TODO: Notify the broadcaster of the need to re-login
			return 0;
		}
		werror("Unexpected error listing channel rewards: %s\n", describe_backtrace(ex));
		return 0;
	}
	array(array) redemptions = yield(Concurrent.all(list_redemptions(broadcaster_id, chan, rewards->id[*])));
	//Every time a new websocket is established, fully recalculate. Guarantee fresh data.
	giveaway_tickets[chan] = ([]);
	foreach (redemptions * ({ }), mapping redem) update_ticket_count(channel->config, redem);
	return ([
		"title": channel->config->giveaway->?title,
		"rewards": rewards, "tickets": tickets_in_order(chan),
		"is_open": status->is_open, "end_time": status->end_time,
		"last_winner": status->last_winner,
	]);
}

mapping(string:mixed) autoclose = ([]);
void open_close(string chan, int broadcaster_id, int want_open) {
	mapping cfg = get_channel_config(broadcaster_id) || ([]);
	if (!cfg->giveaway) return; //No rewards, nothing to open/close
	mapping status = persist_status->path("giveaways", chan);
	string token = token_for_user_login(chan)[0];
	if (!token) {werror("Can't open/close giveaway w/o bcaster token\n"); return;}
	status->is_open = want_open;
	status[want_open ? "last_opened" : "last_closed"] = time();
	if (mixed id = m_delete(autoclose, chan)) remove_call_out(id);
	if (int d = want_open && cfg->giveaway->duration) {
		status->end_time = time() + d;
		autoclose[chan] = call_out(open_close, d, chan, broadcaster_id, 0);
	}
	else m_delete(status, "end_time");
	//Note: Updates reward status in fire and forget mode.
	foreach (cfg->giveaway->rewards || ([]); string id;)
		twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id=" + broadcaster_id + "&id=" + id,
			(["Authorization": "Bearer " + token]),
			(["method": "PATCH", "json": ([
				"is_enabled": want_open || cfg->giveaway->pausemode,
				"is_paused": !want_open && cfg->giveaway->pausemode,
			])]),
		);
	persist_status->save();
	notify_websockets(chan);
	object channel = G->G->irc->channels["#" + chan];
	array people = values(giveaway_tickets[chan]);
	int tickets = `+(0, @people->tickets), entrants = sizeof(people->tickets - ({0}));
	if (status->is_open) channel->trigger_special("!giveaway_started", (["user": chan]), ([
		"{title}": cfg->giveaway->title || "",
		"{duration}": (string)cfg->giveaway->duration,
		"{duration_hms}": describe_time_short(cfg->giveaway->duration),
		"{duration_english}": describe_time(cfg->giveaway->duration),
	]));
	else channel->trigger_special("!giveaway_closed", (["user": chan]), ([
		"{title}": cfg->giveaway->title || "",
		"{tickets_total}": (string)tickets,
		"{entries_total}": (string)entrants,
	]));
}

void websocket_cmd_makenotifs(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return 0;
	foreach (NOTIFICATION_SPECIALS; string kwd; mapping resp)
		make_echocommand(sprintf("!giveaway_%s%s", kwd, channel->name), resp);
}

void websocket_cmd_master(mapping(string:mixed) conn, mapping(string:mixed) msg) {spawn_task(master_control(conn, msg));}
continue Concurrent.Future master_control(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	[object channel, string grp] = split_channel(conn->group);
	if (grp != "control") return 0;
	string chan = channel->name[1..];
	mapping cfg = get_channel_config(chan) || ([]);
	if (!cfg->giveaway) return 0; //No rewards, nothing to activate or anything
	int broadcaster_id = yield(get_user_id(chan));
	switch (msg->action) {
		case "open":
		case "close": {
			int want_open = msg->action == "open";
			mapping status = persist_status->path("giveaways", chan);
			if (want_open == status->is_open) {
				send_update(conn, (["message": "Giveaway is already " + (want_open ? "open" : "closed")]));
				return 0;
			}
			open_close(chan, broadcaster_id, want_open);
			break;
		}
		case "pick": {
			//NOTE: This is subject to race conditions if the giveaway is open
			//at the time of drawing. Close the giveaway first.
			array people = (array)(giveaway_tickets[chan] || ([]));
			int tot = 0;
			array partials = ({ });
			foreach (people, [mixed id, mapping person]) partials += ({tot += person->tickets});
			if (!tot) {
				send_update(conn, (["message": "No tickets bought!"]));
				return 0;
			}
			int ticket = random(tot);
			//I could binary search but I doubt there'll be enough entrants to make a difference.
			array winner;
			foreach (partials; int i; int last) if (ticket < last) {winner = people[i]; break;}
			mapping status = persist_status->path("giveaways", chan);
			status->last_winner = ({winner[0], winner[1]->name, winner[1]->tickets, tot}); //ID, name, ticket count, out of total
			if (!cfg->giveaway->allow_multiwin)
			{
				foreach (values(winner[1]->redemptions), mapping redem)
					set_redemption_status(redem, "FULFILLED");
				//This will eventually be done by the event hook, but the
				//front end updates faster if we force it immediately.
				winner[1]->redemptions = ([]);
				winner[1]->tickets = 0;
			}
			notify_websockets(chan);
			persist_status->save();
			channel->trigger_special("!giveaway_winner", (["user": chan]), ([
				"{title}": cfg->giveaway->title || "",
				"{winner_name}": status->last_winner[1],
				"{winner_tickets}": (string)status->last_winner[2],
				"{tickets_total}": (string)status->last_winner[3],
				"{entries_total}": (string)sizeof(people[*][1]->tickets - ({0})),
			]));
			break;
		}
		case "cancel":
		case "end": {
			mapping existing = cfg->giveaway->rewards;
			if (!existing) break; //No rewards, nothing to cancel
			mapping status = persist_status->path("giveaways", chan);
			m_delete(status, "last_winner");
			//Clear out the front end's view of ticket purchases to reduce flicker
			foreach (values(giveaway_tickets[chan] || ([])), mapping p) {
				p->redemptions = ([]);
				p->tickets = 0;
			}
			notify_websockets(chan);
			persist_status->save();
			if (cfg->giveaway->refund_nonwinning) msg->action = "cancel";
			array(array) redemptions = yield(Concurrent.all(list_redemptions(broadcaster_id, chan, indices(existing)[*])));
			foreach (redemptions * ({ }), mapping redem)
				set_redemption_status(redem, msg->action == "cancel" ? "CANCELED" : "FULFILLED");
			array people = values(giveaway_tickets[chan]);
			int tickets = sizeof(people->tickets) && `+(@people->tickets), entrants = sizeof(people->tickets - ({0}));
			channel->trigger_special("!giveaway_ended", (["user": chan]), ([
				"{title}": cfg->giveaway->title || "",
				"{tickets_total}": (string)tickets,
				"{entries_total}": (string)entrants,
				"{giveaway_cancelled}": (string)(msg->action == "cancel"),
			]));
		}
	}
}

//TODO: Migrate the dynamic reward management to pointsrewards, keeping the giveaway management here
void channel_on_off(string channel, int just_went_online)
{
	mapping cfg = get_channel_config(channel);
	mapping dyn = cfg->dynamic_rewards || ([]);
	mapping rewards = (cfg->giveaway && cfg->giveaway->rewards) || ([]);
	if (!sizeof(dyn) && !sizeof(rewards)) return; //Nothing to do
	object chan = G->G->irc->channels["#" + channel]; if (!chan) return;
	object ts = G->G->stream_online_since[channel] || Calendar.now();
	if (cfg->timezone && cfg->timezone != "") ts = ts->set_timezone(cfg->timezone) || ts;
	string date = sprintf("%d %s %d", ts->month_day(), ts->month_name(), ts->year_no());
	mapping args = ([
		//Is "1" or "0" based on whether you are probably online. It's possible for this to be wrong
		//if you just went live or shut down.
		"{online}": (string)(just_went_online == -1 ? !!G->G->stream_online_since[channel] : just_went_online),
		//Date/time info is in your timezone or UTC if not set, and is the time the stream went online
		//or (approximately) offline.
		"{year}": (string)ts->year_no(), "{month}": (string)ts->month_no(), "{day}": (string)ts->month_day(),
		"{hour}": (string)ts->hour_no(), "{min}": (string)ts->minute_no(), "{sec}": (string)ts->second_no(),
		"{dow}": (string)ts->week_day(), //1 = Monday, 7 = Sunday
	]);
	get_user_id(channel)->then(lambda(int broadcaster_id) {
		string token = token_for_user_login(channel)[0];
		if (token != "") foreach (dyn; string reward_id; mapping info) {
			int active = 0;
			mapping params = ([]);
			//If we just went online/offline, reset to base cost (if there is one).
			if (just_went_online != -1 && info->basecost) params->cost = info->basecost;
			if (mixed ex = info->availability && catch {
				//write("Evaluating: %O\n", info->availability);
				active = G->G->evaluate_expr(chan->expand_variables(info->availability, args));
				//write("Result: %O\n", active);
				params->is_enabled = active ? Val.true : Val.false;
			}) werror("ERROR ACTIVATING REWARD:\n%s\n", describe_backtrace(ex)); //TODO: Report to the streamer
			twitch_api_request("https://api.twitch.tv/helix/channel_points/custom_rewards?broadcaster_id="
					+ broadcaster_id + "&id=" + reward_id,
				(["Authorization": "Bearer " + token]),
				(["method": "PATCH", "json": params]),
			);
		}
	});
}
@hook_channel_online: int channel_online(string channel) {channel_on_off(channel, 1);}
@hook_channel_offline: int channel_offline(string channel) {channel_on_off(channel, 0);}

constant command_description = "Giveaway tools. Use subcommand 'status' or 'refund'.";
constant builtin_description = "Handle giveaways via channel point redemptions"; //The subcommands are mandated by the parameter type
constant builtin_name = "Giveaway tools";
constant builtin_param = "/Action/refund/status";
constant vars_provided = ([
	"{error}": "Error message, if any",
	"{action}": "Action taken - same as subcommand, or 'none' if there was nothing to do",
	"{tickets}": "Number of tickets you have (or had)",
]);
constant command_suggestions = ([
	"!tickets": ([
		"_description": "Giveaways - show number of tickets you have (any user)",
		"builtin": "chan_giveaway", "builtin_param": "status",
		"message": "@$$: You have {tickets} tickets.",
	]),
	"!refund": ([
		"_description": "Giveaways - refund all your tickets (any user)",
		"builtin": "chan_giveaway", "builtin_param": "refund",
		"message": "@$$: All your tickets have been refunded.",
	]),
	//TODO: Mod-only refund command (maybe the same one??) to refund other person's tickets
]);

mapping|Concurrent.Future message_params(object channel, mapping person, string param)
{
	if (param == "") return (["{error}": "Need a subcommand"]);
	sscanf(param, "%[^ ]%*[ ]%s", string cmd, string arg);
	if (cmd != "refund" && cmd != "status") return (["{error}": "Invalid subcommand"]);
	if (!channel->config->giveaway) return (["{error}": "Giveaways not active"]); //Not the same as "giveaway not open", this one will not normally be seen
	string chan = channel->name[1..];
	mapping people = giveaway_tickets[chan] || ([]);
	mapping you = people[(string)person->uid] || ([]);
	if (cmd == "refund") {
		mapping status = persist_status->path("giveaways", chan);
		if (!you->tickets) return (["{error}": "", "{action}": "none", "{tickets}": "0"]);
		if (!status->is_open) return (["{error}": "The giveaway is closed and you can't refund tickets, sorry!"]);
		foreach (values(you->redemptions), mapping redem)
			set_redemption_status(redem, "CANCELED");
	}
	return ([
		"{tickets}": (string)you->tickets,
		"{action}": cmd,
		"{error}": "",
	]);
}

//This really doesn't belong here. But where DOES it belong? (I can't send it back to Dr Bumby either.)
continue Concurrent.Future check_bcaster_tokens() {
	mapping tokscopes = persist_status->path("bcaster_token_scopes");
	foreach (persist_status->path("bcaster_token"); string chan; string token) {
		mixed resp = yield(twitch_api_request("https://id.twitch.tv/oauth2/validate",
			(["Authorization": "Bearer " + token])));
		string scopes = sort(resp->scopes || ({ })) * " ";
		if (tokscopes[chan] != scopes) {tokscopes[chan] = scopes; persist_status->save();}
	}
}

protected void create(string name)
{
	::create(name);
	spawn_task(check_bcaster_tokens());
}
