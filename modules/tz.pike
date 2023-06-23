inherit builtin_command;

mapping(string:string) timezones = ([]);

constant command_description = "Show the current time in a particular, or your default, timezone";
constant builtin_description = "Get the current date and time in a particular timezone"; //TODO: Or convert date/time
constant builtin_name = "Date/Time";
constant builtin_param = "Timezone name"; //TODO: And optional date
constant vars_provided = ([
	"{tz}": "Timezone in canonical form eg Australia/Melbourne",
	"{unix}": "Unix time right now", //TODO: Or the date/time converted
	"{year}": "Date in specified timezone: Year (4 digits)",
	"{month}": "Date in specified timezone: Month (2 digits)",
	"{day}": "Date in specified timezone: Day (2 digits)",
	"{hour}": "Time in specified timezone: Hour (2 digits)",
	"{minute}": "Time in specified timezone: Minute (2 digits)",
	"{second}": "Time in specified timezone: Second (2 digits)",
	"{weekday}": "Weekday name (in English, full word, eg 'Monday')",
	"{weekday_short}": "Weekday name (in English, abbr, eg 'Mon')",
	"{monthname}": "Month name (in English, full word, eg 'September')",
	"{monthname_short}": "Weekday name (in English, abbr, eg 'Sep')",
]);

mapping message_params(object channel, mapping person, string param)
{
	string tz = replace(param, " ", "_");
	tz = timezones[lower_case(tz)] || tz; //If you enter "Melbourne", use "Australia/Melbourne" automatically.
	object t = Calendar.Gregorian.Second()->set_timezone(tz);
	mapping info = (["{tz}": tz, "{unix}": (string)t->unix_time()]);
	foreach ("year month hour minute second" / " ", string twodigit) //Yes, year too, since a four digit number will still render correctly
		info["{" + twodigit + "}"] = sprintf("%02d", t[twodigit + "_no"]());
	info["{day}"] = sprintf("%02d", t->month_day());
	info["{weekday}"] = t->week_day_name();
	info["{weekday_short}"] = t->week_day_shortname();
	info["{monthname}"] = t->month_name();
	info["{monthname_short}"] = t->month_shortname();
	return info;
}

protected void create(string name)
{
	//Map the last part of a timezone name to the full name, eg "Melbourne" ==> "Australia/Melbourne"
	//but compatible with weirder names like Salta ==> America/Argentina/Salta
	foreach (Calendar.TZnames.zonenames(), string zone)
		timezones[(lower_case(zone) / "/")[-1]] = zone;
	::create(name);
}
