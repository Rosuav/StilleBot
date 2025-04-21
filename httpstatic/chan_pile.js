import choc, {set_content, DOM, on} from "https://rosuav.github.io/choc/factory.js";
const {A, BR, BUTTON, CODE, DIV, FIELDSET, INPUT, LABEL, LEGEND, OPTGROUP, OPTION, P, SELECT, SPAN, TABLE, TD, TEXTAREA, TH, TR} = choc; //autoimport

//Physics engine. TODO: Do we need one for each page or one for each pile?
const engine = Matter.Engine.create();
const renderer = Matter.Render.create({element: document.body, engine, options: {
	background: "#0000",
}});
const Rectangle = Matter.Bodies.rectangle;
//The ground
Matter.Composite.add(engine.world, Rectangle(400, 610, 810, 60, {isStatic: true, render: {fillStyle: "transparent", lineWidth: 0}}));
Matter.Render.run(renderer);
Matter.Runner.run(Matter.Runner.create(), engine);
renderer.options.wireframes = false;

export const render_parent = DOM("main"); //fixme
export function render_item(msg, obj) {
}
export function render(data) { }

setInterval(() => {
	const img = emotes[Math.floor(Math.random() * emotes.length)];
	
	Matter.Composite.add(engine.world, Rectangle(Math.floor(Math.random() * 600), Math.floor(Math.random() * 100 + 100), 56, 56, {
		render: {sprite: {texture: img}},
	}));
}, 2000);
//TODO: If stable mode is selected, then after adding something, set a quarter-second interval timer to
//check the newly created thing's speed, and if it's low enough, setStatic() on it.
//Alternatively, set everything to Sleeping? Wake them up when something new is added?
