//Persistent data, stored to a JSON file in the current directory.
#if !constant(persist) //On reload, don't update this.
class Persist(string savefn)
{
	//Persistent storage (when this dies, bring it back with a -1/-1 counter on it).
	//It's also undying storage. When it dies, bring it back one way or the other. :)
	/* Usage:
	 * persist["some/string/identifier"]=any_value;
	 * retrieved_value=persist["some/string/identifier"];
	 * old_value=m_delete(persist,"some/string/identifier");
	 * Saves to disk after every change, or on persist->save() calls.
	 * Loads from disk only on initialization - /update this file to reload.
	 * Note that saving is done with a call_out(0), so you can freely batch mutations
	 * without grinding the disk too much - saving will happen next idleness, probably.
	 **/

	mapping(string:mixed) data=([]);
	int saving;

	void create()
	{
		catch //Ignore any errors, just have no saved data.
		{
			mixed decode=Standards.JSON.decode_utf8(Stdio.read_file(savefn));
			if (mappingp(decode)) data=decode;
		};
	}

	//Retrievals and mutations work as normal; mutations trigger a save().
	mixed `[](string idx) {return data[idx];}
	mixed `[]=(string idx,mixed val) {save(); return data[idx]=val;}
	mixed _m_delete(string idx) {save(); return m_delete(data,idx);}

	//Like the Python dict method of the same name, will save a default back in if it wasn't defined.
	//Best used with simple defaults such as an empty mapping/array, or a string. Ensures that the
	//persist key will exist and be usefully addressable.
	mixed setdefault(string idx,mixed def)
	{
		mixed ret=data[idx];
		if (undefinedp(ret)) return this[idx]=def;
		return ret;
	}

	//Dig deep into persist[] according to a path
	//Returns a regular mapping, *not* something that autosaves.
	mapping path(string ... parts)
	{
		mapping ret = data;
		foreach (parts, string idx)
		{
			if (undefinedp(ret[idx])) {ret[idx] = ([]); save();}
			ret = ret[idx];
		}
		return ret;
	}

	//Call this after any "deep update" that doesn't directly mutate persist[]
	void save() {if (!saving) {saving=1; call_out(dosave,0);}}
	
	void dosave()
	{
		//TODO: Is this costly? I've been noticing that an otherwise-idle StilleBot is
		//showing up in 'top'; check where the actual load is (eg by testing on a slow
		//VM, so the load actually makes a difference).
		string enc = Standards.JSON.encode(data, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL);
		if (mixed ex=catch
		{
			Stdio.write_file(savefn+".1",string_to_utf8(enc));
			mv(savefn+".1",savefn); //Depends on atomic mv, otherwise this might run into issues.
			saving=0;
		})
		{
			//TODO: Show the "danger state" somewhere on the GUI too.
			werror("Unable to save %s: %s\nWill retry in 60 seconds.\n",savefn,describe_error(ex));
			call_out(dosave,60);
		}
	}
}
//TODO: Migrate fast-moving or user-data persisted info out of persist into status
//The idea is that twitchbot_config.json should become a stable file that can be
//git-managed.
object config = Persist("twitchbot_config.json");
object status = Persist("twitchbot_status.json");

void create()
{
	add_constant("persist", config); //Deprecated. Use one of the others.
	add_constant("persist_config", config);
	add_constant("persist_status", status);
}
#endif
