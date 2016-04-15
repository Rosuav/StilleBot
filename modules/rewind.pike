inherit command;
constant require_allcmds = 1;

int last_added = 0;

string process(object channel, object person, string param)
{
	if (param != "" && channel->mods[person->user])
	{
		if (param == "undo" && sizeof(persist["rewind"]))
		{
			//Remove the last rewind
			[mapping info, persist["rewind"]] = Array.pop(persist["rewind"]);
			return sprintf("Removed rewind #%d: %s", sizeof(persist["rewind"])+1, info->msg);
		}
		//Add a rewind
		int t = time();
		if (t - last_added < 5) return 0; //Someone else just got it.
		mapping info = ([
			"recorder": person->nick,
			"msg": param,
			"timestamp": t,
		]);
		persist["rewind"] += ({info});
		return sprintf("Rewind #%d: %s", sizeof(persist["rewind"]), param);
	}
	array rw = persist["rewind"];
	if (!sizeof(rw)) return "@$$: Rewinds: 0";
	return sprintf("@$$: Rewinds: %d  Last rewind: %s", sizeof(rw), rw[-1]->msg);
}

void create(string|void name)
{
	::create(name);
	if (!persist["rewind"]) persist["rewind"] = ({ });
}
