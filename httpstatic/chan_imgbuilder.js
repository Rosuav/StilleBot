import {lindt, replace_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {BUTTON, FIGCAPTION, FIGURE, IMG} = lindt; //autoimport
import {upload_to_library, simpleconfirm} from "$$static||utils.js$$";

export function render(data) {
	if (data.files) replace_content("#files", data.files.map(f => FIGURE({"data-fileid": f.id, "data-filename": f.metadata.name}, [
		IMG({src: "/upload/" + f.id}),
		FIGCAPTION([
			f.metadata.name,
			" ",
			BUTTON({type: "button", class: "renamefile", title: "Rename"}, "📝"),
			BUTTON({type: "button", class: "confirmdelete", title: "Delete"}, "🗑"),
		]),
	])));
}

upload_to_library({});

on("click", ".renamefile", e => {
	const elem = DOM("#renameform").elements;
	elem.id.value = e.match.closest_data("fileid");
	elem.name.value = e.match.closest_data("filename");
	DOM("#renamefiledlg").showModal();
});

on("submit", "#renameform", e => {
	e.preventDefault();
	const msg = {cmd: "renamefile"};
	for (let el of e.match.elements)
		if (el.name) msg[el.name] = el.type === "checkbox" ? el.checked : el.value;
	ws_sync.send(msg);
	DOM("#renamefiledlg").close();
});

on("click", ".confirmdelete", simpleconfirm("Delete this file?", e => ws_sync.send({cmd: "deletefile", id: e.match.closest_data("fileid")})));

on("click", "#download", e => ws_sync.send({cmd: "download"}));
export function sockmsg_download(msg) {
	choc.A({href: msg.url, download: "image.png"}).click();
}
