import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {AUDIO, DIV, FIGCAPTION, FIGURE, IMG} = choc; //autoimport

function THUMB(file) {
	if (!file.url) return DIV({className: "thumbnail"}, "uploading...");
	if (!file.mimetype) return DIV({className: "thumbnail"}, "legacy"); //Old data, won't happen long-term
	if (file.mimetype.startsWith("audio/")) return DIV({className: "thumbnail"}, AUDIO({src: file.url, controls: true}));
	return DIV({className: "thumbnail", style: "background-image: url(" + file.url + ")"});
}

//NOTE: Item rendering applies to uploaded files. Other things are handled by render() itself.
//NOTE: Since newly-uploaded files will always go to the end, this should always be sorted by
//order added, as a documented feature. The server will need to ensure this.
export const render_parent = DOM("#uploads");
export function render_item(file, obj) {
	return FIGURE({"data-id": file.id}, [
		THUMB(file),
		FIGCAPTION(file.name),
	]);
}

export function render(data) {
}

const uploadme = { };
export async function sockmsg_upload(msg) {
	const file = uploadme[msg.name];
	if (!file) return;
	delete uploadme[msg.name];
	const resp = await (await fetch("alertbox?id=" + msg.id, { //The server guarantees that the ID is URL-safe
		method: "POST",
		body: file,
		credentials: "same-origin",
	})).json();
	console.log(resp);
}

on("change", "input[type=file]", e => {
	console.log(e.match.files);
	for (let f of e.match.files) {
		ws_sync.send({cmd: "upload", name: f.name, size: f.size, mimetype: f.type});
		uploadme[f.name] = f;
	}
	e.match.value = "";
});
