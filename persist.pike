//Persistent data, stored to a JSON file in the current directory.
#if !constant(persist_config) //On reload, don't update this.
class Persist(string savefn, int flip_save)
{
	//Persistent storage (when this dies, bring it back with a -1/-1 counter on it).
	//It's also undying storage. When it dies, bring it back one way or the other. :)

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

//Migrate one entry from config to status
//Will not merge if it already exists in status.
void migrate(string ... path)
{
	mapping source = config->data;
	mapping dest = status->data;
	//Step through all the prior path components
	foreach (path[..<1], string step)
	{
		source = source[step];
		if (undefinedp(source)) return; //The thing to migrate doesn't exist - nothing to do
		if (!mappingp(source)) error("Migration source %O has non-mapping at %O!\n", path*"/", step);
		if (undefinedp(dest[step])) dest = dest[step] = ([]); //Not triggering a save yet - if it's lost, nbd
		else if (mappingp(dest[step])) dest = dest[step];
		else error("Migration destination %O has non-mapping at %O!\n", path*"/", step);
	}
	string target = path[-1];
	if (undefinedp(source[target])) return; //Nothing to migrate (maybe already migrated, or new start)
	if (!undefinedp(dest[target])) error("Migration destination %O already exists - cannot merge\n", path*"/");
	//And after massive preliminaries, the actual migration is trivially easy.
	dest[target] = m_delete(source, target);
	config->save(); status->save();
}

void create()
{
	//Compat: Migrate ephemeral info from config into status
	migrate("wealth");
	migrate("viewertime");
	migrate("songrequests");
	migrate("songrequest_meta");
	add_constant("persist_config", config);
	add_constant("persist_status", status);
}
#endif
