import choc, {set_content, DOM, on} from "https://rosuav.github.io/shed/chocfactory.js";
const {A, ABBR, BUTTON, CODE, TR, TD, LABEL, INPUT, SPAN} = choc; //autoimport

//NOTE: Item rendering applies to uploaded files. Other things are handled by render() itself.
//NOTE: Since newly-uploaded files will always go to the end, this should always be sorted by
//order adde, as a documented feature. The server will need to ensure this.
export const render_parent = DOM("#uploads");
export function render_item(file, obj) {
	return DIV({"data-id": file.id}, [
		"[Thumbnail]",
		file.name,
	]);
}

export function render(data) {
}
