import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, IMG, INPUT, TD, TIME, TR} = lindt; //autoimport

function if_different(login, name) {
	if (login === name.toLowerCase()) return null;
	return " (" + login + ")";
}

function recent_time(basis, iso) {
	//If this represents a fairly recent time, say "1 hour ago" or something.
	const tm = new Date(iso);
	const sec = Math.floor((basis - tm) / 1000);
	let desc;
	if (sec > 7 * 24 * 3600)
		//More than a week ago? Time is irrelevant, just show date.
		desc = tm.toLocaleDateString();
	else if (sec > 48 * 3600)
		//More than two day ago? Give the day of week and time in your local timezone.
		desc = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][tm.getDay()] + " " + tm.toLocaleTimeString();
	else if (sec > 24 * 3600)
		desc = "Yesterday " + tm.toLocaleTimeString();
	else if (sec > 3600)
		desc = Math.floor(sec / 3600) + " hours ago";
	else {
		//I wish JS had an easy way to convert seconds into mm:ss... sprintf rocks...
		const m = Math.floor(sec / 60), s = sec % 60;
		desc = ("0" + m).slice(-2) + ":" + ("0" + s).slice(-2) + " ago";
	}
	return TIME({datetime: tm, title: tm.toLocaleString()}, desc);
}

export function render(data) {
	if (data.newfollow) current_followers.unshift(data.newfollow);
	const basis = new Date; //Get a consistent comparison basis for "X minutes ago" (not that it's going to take THAT much time)
	replace_content("#followers tbody",
		current_followers.map(f => TR({key: f.user_id}, [
			TD(INPUT({type: "checkbox"})),
			TD([
				IMG({src: f.details?.profile_image_url || "", class: "avatar"}),
				BUTTON({class: "clipbtn", "data-copyme": f.user_login,
					title: "Click to copy: " + f.user_login}, "📋"), " ",
				f.user_name, if_different(f.user_login, f.user_name),
			]),
			TD(recent_time(basis, f.followed_at)),
			TD(f.details && recent_time(basis, f.details.created_at)),
			TD(f.details?.description),
		])),
	);
}
