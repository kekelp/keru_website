In the past two years, I have been working on a new GUI library for Rust. I'm quite happy with how it turned out, and it's
been a great way to experiment with all sorts of ideas about GUI and library design. 

In this blog post, I want to talk a bit about the library and share some of the ideas that went into it.

The first question, of course, is why? Why do anything at all, really? This is not an easy question to answer in general, but for the specific case of making a GUI library, there are plenty of good reasons:

- It looks like people want more libraries. "What GUI library should I use" is probably one of the most asked question about Rust, but at the same time, the space doesn't feel very crowded at all. There's a few well-known ones, but people don't really seem to be fully satisfied with them.

- nowadays, there are crates that solve most of the more annoying problems, like reliable cross-platform windowing and rendering, as well as high quality text.

- There's plenty of space for new ideas, interesting tradeoffs, and creativity. The API of the library, the primitives and components that the library provides, the default visual appearance of the GUI, are all things that matter a lot, and there's an infinite number of big and small ways in which they can be tweaked.

- It's fun to see something nice and colorful showing up.

The next question is, what's new or interesting about this library?
Most of the ideas in Keru are meant to help in one of three directions:

- Simplicity and understandability of the architecture and of the library as a whole.
- Flexibility and ergonomics of the library interface.
- Performance of the library internals.

Before getting into it, here's an example of how the code for a counter looks like in Keru: (`minimal.rs`)

```rust
use keru::*;
use keru::node_library::*;

#[derive(Default)]
pub struct State {
    pub count: i32,
}

fn update_ui(state: &mut State, ui: &mut Ui) {
    // Define a unique identity for the button
    #[node_key] const INCREASE: NodeKey;
    
    // Create a Node struct describing a button
    let increase_button = BUTTON
        .color(Color::RED)
        .text("Increase")
        .key(INCREASE);

    // Place the nodes into the tree and define the layout
    ui.add(V_STACK).nest(|| {
        ui.add(increase_button);
        ui.add(LABEL.text(&state.count.to_string()));
    });

    // Change the state in response to events
    if ui.is_clicked(INCREASE) {
        state.count += 1;
    }
}

fn main() {
    let state = State::default();
    // Use a wrapper that sets up a winit/wgpu loop, runs our `update_ui` on every update.
    example_window_loop::run_example_loop(state, update_ui);
}
```

The `Ui` struct retains the whole state of the GUI, so this is not an "immediate mode" library (at least not in that sense.)
The `update` function runs on every update and redeclares the whole desired state of the GUI. Then, the retained tree is updated to match the declared state.

## Simplicity


<!-- - Simplicity is the most important thing. Nobody is using all these libraries because they're too hard to use. You can't require hours of study from a user to even get started, just to then hit them "you can't even have properly rendered text, btw". Let's try to be a bit more humble! -->

- In the keru minimal example, the basic concepts there are basically all that you need.
- single Ui struct for the whole state.
- single Node concept that covers everything.

Nowadays it's fairly popular to spend an afternoon to throw together a half-baked library that claims to solve some problem, then show everyone how much simpler it is compared to the full-featured alternatives. But at the same time, I think most people would agree by now that the software world has accumulated a lot of complexity that in an ideal world we'd do without.

I won't try to claim that Keru is a "full-featured GUI library", because that probably includes things like bundling an entire web browser or a webview. But I think that it has enough features to demonstrate that it's possible to scale up all the way without sacrificing the original simplicity. "Simple things should be simple, complex things should be possible".

Keru's more advanced features include components with encapsulated state, advanced layout and grids, drag and drop, canvas drawing, optional imperative tree manipulation, integration with custom winit and wgpu code, etc.


## Flexibility

- Don't give up the winit loop, access all advanced winit features and wgpu rendering directly. Winit and wgpu are already wrappers! We can't go on wrapping things N times over.
- but actually we use a wrapper for the example.

- Freedom to organize the code however you want.
    - use keys to separate effects (still easily linked by go-to-definition.). 
    - use regular rust variables and constants to separate styling and other node params.
    - let the nesting structure be readable.
    - if you don't want, you're free to inline everything, or just write the effect right below, or even fall back to imgui style if you really want.

- freedom to separate code in helper functions. hint at key scopes and Components for even cleaner separation.

- Stateful Components can help with "state management" if you want. But totally optional. centralized-state is probably the best default. But if you want a button to have a fancy stateful animation, you can have that state be managed by the library, one instance for every button, cleaned up when the button disappears. 

- No "big idea" about the elm architecture or similar things. Still flexible enough to use the elm architecture if you want.

- Or even to make it retained/imperative mode. Tasteful hint at how literally nobody else does this. And how it can be used to make advanced components like the drag and drop thing.

- Not reactive by default, which means full flexibility about where to store state. If the program does anything interesting at all with the state besides displaying it in the gui, chances are that it won't be happy about having to fetch it from the GUI library's weird reactive containers! Full control over the data layout is also the #1 important thing for performance.

- manual reactivity with readd_branch, and how doing manual change tracking isn't that hard to do at a component boundary, and how you can even make the component implicitly hold some state like a hash of the previous arguments.


## Performance

Keru code sort of looks like "immediate mode". Isn't that extremely wasteful and slow?

People mean a lot of different things when they say "immediate mode". In this section, I will use the term in the way I think most Rust programmers understand it, even if that's not what it originally used to mean.

Anyway, even if Keru code sort of looks like it, it's not immediate mode in the sense that it keeps recomputing a lot of things needlessly. As mentioned before, the full state of the GUI is always retained inside `Ui` struct, and the declarative code just updates it as needed.

However, it's true that Keru is usually rerunning the user's full declaration code on every update (not on every frame). According to some of the biggest fans of the "reactive" concept, even this is an unforgivable mistake, and the only efficient architecture is one where the user declares the GUI only once at the beginning. Otherwise, the cost of redeclaring things on every update will just get out of control.

First, Keru does actually have some experimental ways to skip redeclaring: after all, the whole tree is always retained, so if we know that a branch will stay unchanged, we can just keep it as it is. But doing this automatically and transparently requires complicated dependency tracking which tends to come at great cost in terms of flexibility and simplicity, as mentioned in the last section.

Second, we have to keep in mind that many systems already redeclare everything on every update, and it's really not a problem. For example, Iced does it. The reason why people aren't mad about it seems to be just that the code looks different enough from the dreaded "immediate mode" to not raise suspicion.

Besides the abstract arguments, it's useful to look at what the declaration code is actually doing. Many of the people who assume that this is expensive probably got their impression from the early discussions around React, which was creating a brand new tree to represent the state of the GUI, and then comparing it to the retained one to know what to update. Both trees probably also happened to be sprawling pointer jungles on the Javascript garbage-collected heap.

What if we didn't do that, and applied some common sense? In Keru, whenever we `add()` a node, the function reaches into the retained tree, and it either finds the old version of the node, or creates it from scratch. If it finds an old node, it "touches" it, and updates its parameters. The properties of the new node are immediately diffed against the old one.

Then, at the end, we have to do a quick linear scan over the nodes to remove any "untouched" ones.

How efficient do we expect this to be? To give a rough idea of the order of magnitude, the N hashmap lookups to find the old node in the tree account for about 50% of the whole redeclaration time in the profiling that I've done.

Even reasoning in absolute terms, it's easy to feel like one or two hashmap lookups for each GUI node shouldn't be something that we should be scared of, if it buys us something significant in terms of flexibility or simplicity. But the most important thing is how this compares to all the other work that the GUI has to do every time something happens:

- recompute the layout,
- update animations,
- rasterize new glyphs and relayout new text,
- rebuild the render data,
- and finally rerender the pixels on the screen.

This all scales with N as well, and it's all internal, so it can be optimized or pessimized regardless of the shape of the user-facing API. If all of this work is done inefficiently, the library will be slow regardless of any advanced reactive architecture. If it's done efficiently, it will be fine either way. At the end of the day, rerunning some declaration code just won't be what makes the difference between an snappy and efficient library and a slow or wasteful one.

What should we do to optimize all of that? Well, because it's not linked to anything about the library that's visible from outside, it's not very interesting to go into the details.

For glyph rasterization, text shaping and layout, Keru uses Parley and Swash, so there's not much to do other than not needlessly recomputing things, and skipping work for offscreen text when possible.

For everything else, it just boils down to some basic data-oriented-programming and being disciplined about short-lived allocations.

It turns out that it's plenty enough: here is an example (`ten_thousands.rs`) showing a non-virtualized list of 10k elements. 
With the Ryzen 7 5800H in my laptop from 2021, I can scroll and interact with it at the full 165 Hz of my display without any issues. 10k is not a big number for a computer!

[ example video ]

There's also space for more optimizations to improve cache efficiency, but I don't want to get to them while the code is still in flux. With a bit more optimization and maybe a newer CPU, we can probably go much higher than 10k.

Keru also uses a custom `wgpu` renderer, but I don't have a precise idea of how much that helps. In the example above it doesn't matter, because most elements are far offscreen and can be efficiently culled by any renderer. It's only testing the redeclaration, layout, animation updates, and the rest of the CPU-side code that can't be trivially skipped.

It's a very simple and efficient renderer that can draw plenty of shapes, including rounded rectangles, circles, triangles, hexagons, line segments, and quadratic Bézier curves. But it does cut some corners: it can't do arbitrary path fills, non-rectangular clipping, or "layered blending" (I'm not sure what the real term for this is).

It would be cool to have a more modern compute-based renderer that can do all these effects, but I'm probably not writing another renderer from scratch any time soon. The most realistic option would be to switch to `vello` in the future, which would also be a great way to get a cpu-software backend.
