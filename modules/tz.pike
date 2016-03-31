inherit command;

mapping timezones;

string timezone_info(string tz)
{
	if (!tz || tz=="") return "Regions are: " + sort(indices(timezones))*", ";
	mapping|string region = timezones;
	foreach (lower_case(tz)/"/", string part) if (!mappingp(region=region[part])) break;
	if (undefinedp(region))
		return "Unknown region "+tz+" - use '!tz' to list";
	if (mappingp(region))
		return "Locations in region "+tz+": "+sort(indices(region))*", ";
	if (catch {return region+" - "+Calendar.Gregorian.Second()->set_timezone(region)->format_time();})
		return "Unable to figure out the time in that location, sorry.";
}

void process(object channel, object person, string param)
{
	string tz = timezone_info(param);
	while (sizeof(tz) > 200)
	{
		sscanf(tz, "%200s%s %s", string piece, string word, tz);
		send_message(channel->name, sprintf("@%s: %s%s ...", person->nick, piece, word));
	}
	send_message(channel->name, sprintf("@%s: %s", person->nick, tz));
}

void create(string name)
{
	timezones = ([]);
	foreach (sort(Calendar.TZnames.zonenames()), string zone)
	{
		array(string) parts = lower_case(zone)/"/";
		mapping tz = timezones;
		foreach (parts[..<1], string region)
			if (!tz[region]) tz = tz[region] = ([]);
			else tz = tz[region];
		tz[parts[-1]] = zone;
	}
	::create(name);
}
