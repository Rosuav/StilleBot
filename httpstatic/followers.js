import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, LI} = lindt; //autoimport

function if_different(login, name) {
	if (login === name.toLowerCase()) return null;
	return " (" + login + ")";
}

export function render(data) {
	if (data.newfollow) current_followers.unshift(data.newfollow);
	replace_content("#followers",
		current_followers.map(f => LI({key: f.user_id}, [
			//Avatar? Maybe? Would need to have the server do the lookup for us.
			BUTTON({class: "clipbtn", "data-copyme": f.user_login,
				title: "Click to copy: " + f.user_login}, "📋"), " ",
			f.user_name, if_different(f.user_login, f.user_name),
			//Time since follow? f.followed_at
		])),
	);
}
