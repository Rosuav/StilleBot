import choc, {set_content} from "https://rosuav.github.io/shed/chocfactory.js";
const {OPTION, SELECT, INPUT, LABEL, UL, LI, BUTTON, TR, TH, TD, SPAN} = choc;

console.log("Quote editing activated.");
on("click", "li", e => {
	let idx = [...e.match.parentNode.children].indexOf(e.match);
	let quote = quotes[idx]; if (!quote) return;
	console.log(quote)
});
