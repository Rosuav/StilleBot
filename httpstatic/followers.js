import {lindt, replace_content, DOM} from "https://rosuav.github.io/choc/factory.js";
const {LI} = lindt; //autoimport

function if_different(login, name) {
	if (login === name.toLowerCase()) return null;
	return " (" + login + ")";
}

export function render(data) {
	replace_content("#followers",
		data.followers.map(f => LI({key: f.from_id}, [
			//Avatar? Maybe? Would need to have the server do the lookup for us.
			f.from_name, if_different(f.from_login, f.from_name),
			//Time since follow? f.followed_at
		])),
	);
}
