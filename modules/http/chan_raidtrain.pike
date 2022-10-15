inherit http_websocket;
constant markdown = #"# Raid train organized by $$channel$$

## Raid train settings
{:#cfg_title}

<div id=cfg_description markdown=1>
$$description||The owner can fill out a description here.$$
</div>

Raid call: <textarea readonly id=cfg_raidcall></textarea>

Schedule:
* <span id=cfg_dates></span>
* Slot size: <span id=cfg_slotsize>1 hour</span>
* Unique streamers: <span id=streamer_count>(unknown)</span>

$$save_or_login$$

## Schedule

This is who's going to be part of the train when. They may be live earlier than this.

Streamer | Start time
---------|-----------
loading  | -

> ### Configuration
> Plan out your raid train!
>
> Configuration | -
> - | -
> loading... | loading...
>
> [Save](:#save type=submit) [Close](:.dialog_close)
{: tag=formdialog #configdlg}

<style>
time {font-weight: bold;}
</style>
";

/* Raid train organization
- Everything starts with one Owner/Organizer who must be using this bot.
- Go to https://sikorsky.rosuav.com/channels/demo/raidtrain
- Owner can configure everything:
- Title, description, raid call
- Start/end date and time
- Slot size (eg 1 hour)
- Maximum slots per streamer?
- Requests visible (y/n)
- The time period from start to end, divided into slots, is tabulated (with a
  scroll bar if necessary) for everyone, and is shown in both the user's TZ and
  the "canonical" TZ (== the owner's).
- Anyone can request a slot. If requests are visible, they will be able to see
  everyone else who's put in a request.
- Owner can approve any (one) request for a slot. This makes that user name and
  avatar visible to everyone who looks at the tabulated schedule.
- Owner and slot holder may edit comments shown in one column on the schedule.
- If the current time is within the raid train period, highlight "NOW".
- If the current user is on the schedule, highlight "YOU".

All configuration is stored in persist_status->raidtrain->USERID, with public
info (anything that can be shared with any client regardless of authentication)
in ->cfg; this should include the vast majority of information.
*/

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	mapping trn = persist_status->path("raidtrain", (string)req->misc->channel->userid);
	req->misc->chaninfo->autoform = req->misc->chaninfo->autoslashform = "";
	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : "view"]),
		"save_or_login": "[Edit](:#editconfig)",
		"description": trn->cfg->?description, //Because it will be parsed as Markdown
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	mapping cfg = persist_status->path("raidtrain", (string)channel->userid, "cfg");
	return ([
		"cfg": cfg,
		"desc_html": Tools.Markdown.parse(cfg->description || "", ([
			"renderer": Renderer, "lexer": Lexer,
		])),
	]);
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	//TODO: Allow updates of your own slot's comments, if you have a slot
	object channel = G->G->irc->channels["#" + chan];
	if (grp != "control" || !channel) return;
	if (conn->session->fake) return;
	mapping trn = persist_status->path("raidtrain", (string)channel->userid);
	foreach ("title description raidcall" / " ", string str)
		if (msg[str]) trn->cfg[str] = msg[str];
	foreach ("startdate enddate slotsize" / " ", string num)
		if ((int)msg[num]) trn->cfg[num] = (int)msg[num];

	if (trn->cfg->startdate && trn->cfg->enddate > trn->cfg->startdate) {
		int slotwidth = (trn->cfg->slotsize || 1) * 3600;
		if (!trn->cfg->slots || !sizeof(trn->cfg->slots))
			trn->cfg->slots = ({(["start": trn->cfg->startdate])});
		if (trn->cfg->startdate < trn->cfg->slots[0]->start) {
			//TODO: Extend the array to the left
		}
		if (trn->cfg->enddate > trn->cfg->slots[-1]->start + slotwidth) {
			//TODO: Extend the array to the right
		}
		//TODO: Trim the array to the limits, but only removing empty slots.
		//That way, if someone has claimed a slot, you won't unclaim it for
		//them simply by miskeying something. Or looking at it the other way
		//around: any reduction of the date span can be undone safely.
	}
	persist_config->save();
	send_updates_all("control#" + chan);
	send_updates_all("view#" + chan);
}
