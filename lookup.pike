int main(int argc, array(string) argv)
{
	[mapping uid_to_name, mapping name_to_uid] = Standards.JSON.decode(Stdio.read_file("twitchbot_uids.json"));
	foreach (argv[1..], string name)
	{
		mapping seen = uid_to_name[name_to_uid[lower_case(name)]];
		if (!seen) {write(name + ": Not found\n"); continue;} //Since uid_to_name[0] is 0, this is safe
		if (sizeof(seen) == 1 && seen[name]) {write(name + ": No others seen\n"); continue;}
		array names = indices(seen), times = values(seen);
		sort(times, names);
		names -= ({"jtv", "tmi"});
		write(name + ": " + names * ", " + "\n");
	}
}
