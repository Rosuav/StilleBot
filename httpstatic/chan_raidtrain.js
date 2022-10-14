import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, ABBR, BUTTON, CODE, TR, TD, LABEL, INPUT, SPAN} = choc; //autoimport

export function render(data) {
}

on("click", "#editconfig", e => DOM("#configdlg").showModal());
