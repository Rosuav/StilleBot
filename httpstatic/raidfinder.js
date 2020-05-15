import choc, {set_content} from "https://rosuav.github.io/shed/chocfactory.js";
const {DIV, IMG, P, UL, LI} = choc;

on("click", "#streams th", e => {
	console.log("Clicked on", e.match);
});

console.log(follows);
function build_follow_list() {
	set_content("#streams", follows.map(stream => DIV([
		IMG({src: stream.preview.medium}),
		UL([LI(stream.channel.status), LI(stream.channel.display_name), LI(stream.game)]),
	])));
}
build_follow_list();
