const engine = Matter.Engine.create();
const width = window.innerWidth - 20, height = window.innerHeight - 20;
console.log(width, height)
const renderer = Matter.Render.create({element: document.getElementById("display"), engine, options: {
	background: "aliceblue", width, height,
}});
const Rectangle = Matter.Bodies.rectangle;
//The ground. TODO: Size this to the available space.
//???? The x position of this rectangle confuses me. Setting it to 0 has the floor
//run way off the left edge, having it at (roughly) half the width works. Why?
Matter.Composite.add(engine.world, Rectangle(width / 2, height + 10, width + 10, 60,
	{isStatic: true, render: {fillStyle: "rebeccapurple", lineWidth: 0}}));
Matter.Render.run(renderer);
Matter.Runner.run(Matter.Runner.create(), engine);
renderer.options.wireframes = false;
window.renderer = renderer; //For debugging, eg toggle wireframes mode

export function render(data) { }

setInterval(() => {
	const cat = thingtypes.emotes; //TODO: User selection from the available categories
	const img = cat[Math.floor(Math.random() * cat.length)];
	const obj = Rectangle(Math.floor(Math.random() * width), Math.floor(Math.random() * 100 + 10), img.xsize, img.ysize, {
		render: {sprite: {texture: img.fn, xOffset: img.xoffset, yOffset: img.yoffset}},
	});
	//Angles are measured in radians. Angular velocity seems to be rad/frame and we're at
	//60Hz physics rate, meaning that 0.01 will rotate you by 0.60 rad/sec (before friction is
	//taken into account). Provide each newly-added element with a bit of rotation, either direction.
	Matter.Body.setAngularVelocity(obj, Math.random() * .2 - .1);
	Matter.Composite.add(engine.world, obj);
}, 2000);
//TODO: If stable mode is selected, then after adding something, set a quarter-second interval timer to
//check the newly created thing's speed, and if it's low enough, setStatic() on it.
//Alternatively, set everything to Sleeping? Wake them up when something new is added?
