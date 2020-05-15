import choc, {set_content} from "https://rosuav.github.io/shed/chocfactory.js";
const {P} = choc;

on("click", "#streams th", e => {
	console.log("Clicked on", e.match);
});
