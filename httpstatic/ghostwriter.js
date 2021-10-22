import choc, {set_content, DOM, fix_dialogs} from "https://rosuav.github.io/shed/chocfactory.js";
const {LI, SPAN} = choc;

export function render(state) {
	//If we have a socket connection, enable the primary control buttons
	document.querySelectorAll("button").forEach(b => b.disabled = false);
}
