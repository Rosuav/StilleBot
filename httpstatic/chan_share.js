import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, DIV, FIGCAPTION, FIGURE, INPUT, LABEL, LI} = choc; //autoimport

set_content("#user_types", user_types.map(([kwd, lbl, desc]) => LI(LABEL(
	{title: desc},
	[INPUT({type: "checkbox", "data-kwd": kwd}), lbl]
)))).classList.toggle("nonmod", !is_mod);
if (!is_mod) {
	DOM("#user_types").appendChild(LI({id: "user-nobody", title: "Art sharing is not enabled for this channel."}, "Nobody"));
	DOM("#msgformat").disabled = true;
}

const TRANSPARENT_IMAGE = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNgAAIAAAUAAen63NgAAAAASUVORK5CYII=";

//NOTE: Item rendering applies to uploaded files. Other things are handled by render() itself.
const files = { };
export const render_parent = DOM("#uploads");
export function render_item(file, obj) {
	files[file.id] = file;
	return LABEL({"data-id": file.id}, [
		FIGURE([
			DIV({className: "thumbnail", style: "background-image: url(" + (file.url || TRANSPARENT_IMAGE) + ")"}),
			FIGCAPTION([
				A({href: file.url, target: "_blank"}, file.name),
			]),
			BUTTON({type: "button", className: "confirmdelete", title: "Delete"}, "🗑"),
		]),
	]);
}

export function render(data) {
	if (data.who) {
		user_types.forEach(u => {
			const permitted = !!data.who[u[0]];
			const cb = DOM("#user_types input[data-kwd=" + u[0] + "]");
			if (!cb) return; //Unknown keyword (might be an outdated permission flag)
			if (is_mod) cb.checked = permitted;
			cb.closest("li").classList.toggle("permitted", permitted);
		});
		if (!is_mod) {
			//If absolutely nobody has permission, show the "Nobody" entry.
			const nobody = !document.querySelector("#user_types .permitted");
			DOM("#user-nobody").classList.toggle("permitted", nobody);
		}
	}
	if (data.defaultmsg) {
		set_content("#defaultmsg", data.defaultmsg);
		DOM("#msgformat").placeholder = data.defaultmsg;
	}
	if (data.msgformat) DOM("#msgformat").value = data.msgformat;
}

let deleteid = null;
on("click", ".confirmdelete", e => {
	deleteid = e.match.closest("[data-id]").dataset.id;
	const file = files[deleteid];
	DOM("#confirmdeletedlg .thumbnail").replaceWith(DIV({className: "thumbnail", style: "background-image: url(" + file.url + ")"}));
	set_content("#confirmdeletedlg a", file.name).href = file.url;
	DOM("#confirmdeletedlg").showModal();
});

on("click", "#delete", e => {
	if (deleteid) ws_sync.send({cmd: "delete", id: deleteid});
	DOM("#confirmdeletedlg").close();
});

on("click", "#user_types input", e => {
	ws_sync.send({cmd: "config", who: {[e.match.dataset.kwd]: e.match.checked}});
});

export function sockmsg_uploaderror(msg) {
	set_content("#errormsg", msg.error).classList.add("visible");
}

const uploadme = { };
export async function sockmsg_upload(msg) {
	const file = uploadme[msg.name];
	if (!file) return;
	delete uploadme[msg.name];
	const resp = await (await fetch("share?id=" + msg.id, { //The server guarantees that the ID is URL-safe
		method: "POST",
		body: file,
		credentials: "same-origin",
	})).json();
	if (resp.error) set_content("#errormsg", resp.error).classList.add("visible");
	//Otherwise, there should be a signal on the websocket shortly.
}

on("change", "input[type=file]", e => {
	console.log(e.match.files);
	set_content("#errormsg", "").classList.remove("visible");
	for (let f of e.match.files) {
		ws_sync.send({cmd: "upload", name: f.name, size: f.size});
		uploadme[f.name] = f;
	}
	e.match.value = "";
});

on("change", "#msgformat", e => ws_sync.send({cmd: "config", msgformat: e.match.value}));
