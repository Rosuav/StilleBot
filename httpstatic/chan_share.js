import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BUTTON, DIV, FIGCAPTION, FIGURE, LABEL} = choc; //autoimport

//NOTE: Item rendering applies to uploaded files. Other things are handled by render() itself.
const files = { };
export const render_parent = DOM("#uploads");
export function render_item(file, obj) {
	console.log("render_item", file, obj);
	files[file.id] = file;
	return LABEL({"data-id": file.id}, [
		FIGURE([
			DIV({className: "thumbnail", style: "background-image: url(" + file.url + ")"}),
			FIGCAPTION([
				A({href: file.url, target: "_blank"}, file.name),
			]),
			BUTTON({type: "button", className: "confirmdelete", title: "Delete"}, "🗑"),
		]),
	]);
}

export function render(data) {
	if (data.who) {
		console.log("Who may upload?", data.who);
	}
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
