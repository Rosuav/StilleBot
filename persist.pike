//Persistent data, stored to a JSON file in the current directory.
#if !constant(persist_config) //On reload, don't update this. Some things retain references regardless of updates, so don't break that.
class Persist(string savefn)
{
	//Persistent storage (when this dies, bring it back with a -1/-1 counter on it).
	//It's also undying storage. When it dies, bring it back one way or the other. :)

	mapping(string:mixed) data=([]);

	protected void create()
	{
		catch //Ignore any errors, just have no saved data.
		{
			mixed decode=Standards.JSON.decode_utf8(Stdio.read_file(savefn));
			if (mappingp(decode)) data=decode;
		};
	}

	protected mixed `[](string idx) {return data[idx];}

	void save() {
		if (mixed ex=catch
		{
			string enc = Standards.JSON.encode(data, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL);
			Stdio.write_file(savefn, string_to_utf8(enc));
		})
		{
			//TODO: Show the "danger state" somewhere on the GUI too.
			werror("Unable to save %s: %s\nWill retry in 60 seconds.\n",savefn,describe_error(ex));
			call_out(save, 60);
		}
	}
}
object config = Persist("twitchbot_config.json");

protected void create() {
	add_constant("persist_config", config);
	//Bootstrapping: Ensure that we know the bot's UID.
	G->G->bot_uid = (int)config["bot_uid"] || 49497888; //Hack: Use my ID if it isn't set.
}
#endif
