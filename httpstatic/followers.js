import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, LI} = lindt; //autoimport

function if_different(login, name) {
	if (login === name.toLowerCase()) return null;
	return " (" + login + ")";
}

let followers = [];
export function render(data) {
	if (data.newfollow) (data.followers = followers).unshift(data.newfollow);
	if (data.followers) replace_content("#followers",
		(followers = data.followers).map(f => LI({key: f.from_id}, [
			//Avatar? Maybe? Would need to have the server do the lookup for us.
			BUTTON({class: "clipbtn", "data-copyme": f.from_login,
				title: "Click to copy: " + f.from_login}, "📋"), " ",
			f.from_name, if_different(f.from_login, f.from_name),
			//Time since follow? f.followed_at
		])),
	);
}