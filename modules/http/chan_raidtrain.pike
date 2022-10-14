inherit http_websocket;
constant markdown = #"# Raid train organized by $$channel$$

## $$title$$
{:#cfg_title}

$$description||The owner can fill out a description here$$
{:#cfg_description}

Raid call: <textarea readonly id=cfg_raidcall></textarea>

Schedule:
* <span id=dates></span>
* Slot size: <span id=cfg_slotsize>1 hour</span>

$$save_or_login$$

## Schedule

This is who's going to be part of the train when. They may be live earlier than this.

Streamer | Start time
---------|-----------
loading  | -

> ### Configuration
>
> Plan out your raid train!
>
> Configuration | -
> - | -
> loading... | loading...
>
> [Save](:#save) [Close](:.dialog_close)
{: tag=dialog #configdlg}

<style>
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
*/

mapping(string:mixed) http_request(Protocols.HTTP.Server.Request req)
{
	return render(req, ([
		"vars": (["ws_group": req->misc->is_mod ? "control" : "view"]),
		"save_or_login": "[Edit](:#editconfig)",
		"title": "(title)",
	]) | req->misc->chaninfo);
}

bool need_mod(string grp) {return grp == "control";}
mapping get_chan_state(object channel, string grp, string|void id) {
	return ([
		"config": ([]),
		"schedule": ({ }),
	]);
}

void websocket_cmd_update(mapping(string:mixed) conn, mapping(string:mixed) msg) {
	sscanf(conn->group, "%s#%s", string grp, string chan);
	//TODO: Allow updates of your own slot's comments, if you have a slot
	if (grp != "control" || !G->G->irc->channels["#" + chan]) return;
	if (conn->session->fake) return;

	persist_config->save();
	update_one("control#" + chan, msg->id);
	update_one("view#" + chan, msg->id);
}
