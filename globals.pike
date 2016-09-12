void create(string n)
{
	foreach (indices(this),string f) if (f!="create" && f[0]!='_') add_constant(f,this[f]);
	//TODO: Have some way to 'declare' these down below, rather than
	//coding them here.
	if (!G->G->commands) G->G->commands=([]);
}

mapping G_G_(string ... path)
{
	mapping ret = G->G;
	foreach (path, string part)
	{
		if (!ret[part]) ret[part] = ([]);
		ret = ret[part];
	}
	return ret;
}
