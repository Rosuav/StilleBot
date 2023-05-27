//Persistent data, stored to a JSON file in the current directory.
#if !constant(persist_config) //On reload, don't update this. Some things retain references regardless of updates, so don't break that.
class Persist(string savefn, int flip_save)
{
	//Persistent storage (when this dies, bring it back with a -1/-1 counter on it).
	//It's also undying storage. When it dies, bring it back one way or the other. :)

	mapping(string:mixed) data=([]);
	int saving;

	protected void create()
	{
		#if constant(INTERACTIVE)
		saving = 1; //Prevent saving of persisted content in interactive mode
		#endif
		catch //Ignore any errors, just have no saved data.
		{
			mixed decode=Standards.JSON.decode_utf8(Stdio.read_file(savefn));
			if (mappingp(decode)) data=decode;
		};
	}

	//Retrievals and mutations work as normal; mutations trigger a save().
	protected mixed `[](string idx) {return data[idx];}
	protected mixed `[]=(string idx,mixed val) {save(); return data[idx]=val;}
	protected mixed _m_delete(string idx) {save(); return m_delete(data,idx);}

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
		if (mixed ex=catch
		{
			//Creep the open file limit up by one while we save, to ensure that we aren't rlimited
			array lim;
			catch {lim = System.getrlimit("nofile"); if (lim[0] < lim[1]) System.setrlimit("nofile", lim[0] + 1, lim[1]);};
			string enc = Standards.JSON.encode(data, Standards.JSON.HUMAN_READABLE|Standards.JSON.PIKE_CANONICAL);
			if (flip_save)
			{
				//Safer against breakage
				Stdio.write_file(savefn+".1",string_to_utf8(enc));
				mv(savefn+".1",savefn); //Depends on atomic mv, otherwise this might run into issues.
			}
			else
			{
				//Compatible with symlinked files
				Stdio.write_file(savefn, string_to_utf8(enc));
			}
			if (lim) catch {System.setrlimit("nofile", @lim);};
			saving=0;
		})
		{
			//TODO: Show the "danger state" somewhere on the GUI too.
			werror("Unable to save %s: %s\nWill retry in 60 seconds.\n",savefn,describe_error(ex));
			call_out(dosave,60);
		}
	}
}
object config = Persist("twitchbot_config.json", 0);
object status = Persist("twitchbot_status.json", 1);

protected void create() {
	add_constant("persist_config", config);
	add_constant("persist_status", status);
}
#endif
