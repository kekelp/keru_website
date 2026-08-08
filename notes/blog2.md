In the past two years, I have been working on a new GUI library for Rust.

<!-- In this blog, I want to share some of the ideas that went into it, some of the things I've learned, and give my perspective on the field of GUI programming in general.  

This first post will be a general introduction, then something about the interface, what it means for retained mode etc, then layout, blah blah.
-->

The first question, of course, is why? Why do anything at all, really? This is not an easy question to answer in general, but for the specific case of making a GUI library, there are plenty of good reasons:

- It still looks like people want more libraries. There's a few well-known ones and a lot of less-known experimental ones, but people don't really seem to be fully satisfied with them.

- nowadays, there are crates that solve most of the more annoying problems, like reliable cross-platform windowing and rendering, as well as high quality text.

- There's plenty of space for new ideas, interesting tradeoffs, and creativity. The API of the library, the primitives and components that the library provides, the default visual appearance of the GUI, are all things that matter a lot, and there's an infinite number of big and small ways in which they can be tweaked.

- It's fun to see something nice and colorful showing up.

The next question is, what's new or interesting about this library?
Most of the ideas in Keru are meant to help in one of three directions:

- Simplicity and understandability.
- Flexibility and ergonomics.
- Performance of the library internals and of the resulting program.

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
    // This is just for examples! Keru is meant to be used as part of a custom winit and wgpu loop.
    example_window_loop::run_example_loop(state, update_ui);
}
```

The `Ui` struct retains the whole state of the GUI, so this is not an "immediate mode" library (at least not in that sense.)
The `update` function runs on every update and redeclares the whole desired state of the GUI. Then, the retained tree is updated to match the declared state.

## Simplicity

Simplicity is probably the most important point. My impression is that the main reason why GUI programming isn't very popular is because the libraries just aren't very easy to get into and use. They tend to come with a lot of "concepts" and structures that the user is required to learn and internalize before starting at all.

This is not a problem just for beginners: as the programs that users try to make become more and more complicated, it becomes less and less pleasant to dedicate so much of the "complexity budget" to dealing with the GUI library rather than the program itself, and it becomes harder and harder to fit the program's natural logic and state into the structures and concepts that the library forces on us.

There's many things that end up contributing to this feeling of complexity and user unfriendlyness:

- Extra tools and workflows for packaging, compiling DSLs, etc.
- Proc macros that define a new language within the language.

- Overcomplicated generic types.
- Too many distinct types and concepts with complex connections with each other. This can end up having the same effect even if the individual types are simple.
- Callbacks and anything that takes control of the program's main loop away from the user. Unfortunately winit already does this, but it's still good to refrain from adding yet another layer of indirection.
- Special rules about when the user is allowed to access their state, when to mutate it, etc.

While most the points above apply to libraries in different fields as well, the last two tend to be specific to GUI libraries. In a sense, they are ultimate form of poisonous library complexity: they don't just get in your way while you try to use the library, but they affect EVERYTHING that the user's program is trying to do.


The solution is to try to build the library out of the simpler building blocks that the language already provides: simple structs and functions. Reviewing the Keru example above: 

- the program's state is a regular Rust struct, and we can access and mutate it through a regular mutable reference.
- `Ui` is a single struct that contains the whole state of the GUI.
- A `Node` is a simple value struct that describes the appearance and behavior of a GUI element. The user creates it on the stack as a normal variable.
- The vertical stack container, the label and the button are all `Node`s. There's only one `Node` that covers all elements of the GUI.
- The NodeKey is created by a proc macro, but it's still a simple value struct that works as an id. The proc macro just rolls a random `u64` at compile time and saves us the hassle of using manually synced ids.
- The `is_clicked` function allows us to run effects in response to GUI events without using callbacks.


Most people recognize the value of simplicity, but is there a downside? Are we sacrificing something for it?

Nowadays it's fairly popular to spend an afternoon throwing together a half-baked library that claims to solve some problem, and then showing everyone how much simpler it is compared to the full-featured alternatives.

I won't try to claim that Keru is a "full-featured GUI library", but I think that it has enough features to convince people that it should be possible to scale up all the way without sacrificing the original simplicity.

Keru's more advanced features include components with encapsulated state, advanced layout and grids, drag and drop, canvas drawing, optional imperative tree manipulation, integration with custom wgpu rendering, etc.


## Flexibility

In some ways, flexibility comes together with simplicity: a simple library with simple building blocks will automatically tend to be more flexible, because the programming language natively offers a lot of flexibility and freedom in how we can organize variables and functions.

<!-- - Freedom to organize the code however you want. -->
    - use keys to separate effects (still easily linked by go-to-definition.). 
    - use regular rust variables and constants to separate styling and other node params.
    - let the nesting structure be readable.
    - if you don't want, you're free to inline everything, or just write the effect right below, or even fall back to imgui style if you really want.

<!-- - freedom to separate code in helper functions. hint at key scopes and Components for even cleaner separation. -->


<!-- - Stateful Components can help with "state management" if you want. But totally optional. centralized-state is probably the best default. But if you want a button to have a fancy stateful animation, you can have that state be managed by the library, one instance for every button, cleaned up when the button disappears.  -->

<!-- - No "big idea" about the elm architecture or similar things. Still flexible enough to use the elm architecture if you want. -->

<!-- - Or even to make it retained/imperative mode. Tasteful hint at how literally nobody else does this. And how it can be used to make advanced components like the drag and drop thing. -->

<!-- - Not reactive by default, which means full flexibility about where to store state. If the program does anything interesting at all with the state besides displaying it in the gui, chances are that it won't be happy about having to fetch it from the GUI library's weird reactive containers! Full control over the data layout is also the #1 important thing for performance. -->

<!-- - manual reactivity with readd_branch, and how doing manual change tracking isn't that hard to do at a component boundary, and how you can even make the component implicitly hold some state like a hash of the previous arguments. -->

<!-- - Finally, Don't give up the winit loop, access all advanced winit features and wgpu rendering directly. Winit and wgpu are already wrappers! We can't go on wrapping things N times over. -->
<!-- Although this might become harder when I finally add multi-window. but hopefully we can find a way. -->

Also, nothing other than winit/wgpu. This is definitely mixed for flexibility, but hey, it's hard. Utopianism.

## Performance

I claimed that performance is another of Keru's primary focuses. But Keru code sort of looks like "immediate mode". Isn't that wasteful and slow?

People mean a lot of different things when they say "immediate mode". In this section, I will use the term in the way I think most Rust programmers understand it, even if that's not what it originally used to mean.

Anyway, even if Keru code sort of looks like it, it's not immediate mode in the sense that it keeps recomputing a lot of things needlessly. As mentioned before, the full state of the GUI is always retained inside `Ui` struct, and the declarative code just updates it as needed.

However, it's true that Keru is usually rerunning the user's full declaration code on every update. Note that "every update" means every time the UI receives an input that it cares about, not every frame. But according to some of the biggest fans of the "reactive" concept, even this is an unforgivable mistake, and the only efficient architecture is one where the user declares the GUI only once at the beginning. Otherwise, the cost of redeclaring things on every update will just get out of control.

First, Keru does actually have some experimental ways to skip redeclaring: after all, the whole tree is always retained, so if we know that a branch will stay unchanged, we can just keep it as it is. But doing this automatically and transparently requires complicated dependency tracking which tends to come at great cost in terms of flexibility and simplicity.

Second, we have to keep in mind that many systems already redeclare everything on every update, and it's really not a problem. For example, Iced does it. If people aren't up in arms about it like they are about Egui, it seems to be just because the code looks different enough from the dreaded "immediate mode" to not raise suspicion.

Besides the abstract arguments, we should look at what the declaration code is actually doing. Many of the people who assume that code like that is expensive probably got their impression from the early discussions around React, which was creating a brand new tree from scratch to represent the desired state of the GUI, and then comparing it to the retained one to know what to update. Both trees probably also happened to be sprawling pointer jungles on the Javascript garbage-collected heap.

What if we didn't do that, and applied some common sense? In Keru, whenever we `add()` a node, the function reaches into the retained tree, and it either finds the old version of the node, or creates it from scratch. If it finds an old node, it "refreshes" it, and updates its parameters. The properties of the new node are immediately diffed against the old one.

Then, at the end, we have to do a quick linear scan over the nodes to remove any "untouched" ones.

How efficient do we expect this to be? To give a rough idea of the order of magnitude, the N hashmap lookups to find the old node in the tree account for about 50% of the whole redeclaration time in the profiling that I've done.

Even reasoning in absolute terms, it's easy to feel like one or two hashmap lookups for each GUI node shouldn't be something that we should be scared of, if it buys us something significant in terms of flexibility or simplicity. But the most important thing is how this compares to all the other work that the GUI has to do every time something happens:

- recompute the layout,
- update animations,
- rasterize new glyphs and relayout new text,
- rebuild the render data,
- and finally rerender the pixels on the screen.

This all scales with N as well, and it's all internal, so it can be optimized or pessimized regardless of the shape of the user-facing API. If all of this work is done inefficiently, the library will be slow regardless of any advanced reactive architecture. If it's done efficiently, it will be fine either way. At the end of the day, rerunning some declaration code just won't be what makes the difference between an snappy and efficient library and a slow or wasteful one.

What should we do to optimize all of that?

For glyph rasterization, text shaping and layout, Keru uses Parley, so there's not much to do other than not needlessly recomputing things, and skipping work for offscreen text when possible.

For everything else, it just boils down to some basic data-oriented-programming and being disciplined about short-lived allocations.

It turns out that it's plenty enough: here is an example (`ten_thousands.rs`) showing a non-virtualized list of 10k elements. 
With the Ryzen 7 5800H in my laptop from 2021, I can scroll and interact with it at the full 165 Hz of my display without any issues. 10k is not a big number for a computer!

[ example video ]

There's also space for more optimizations to improve cache efficiency, but I don't want to get to them while the code is still in flux. With a bit more optimization and maybe a newer CPU, we can definitely go much higher than 10k.

Keru also uses a custom `wgpu` renderer, but I don't have a precise idea of how much that helps. In the example above it doesn't matter, because most elements are far offscreen and can be efficiently culled by any renderer. It's only testing the redeclaration, layout, animation updates, and the rest of the CPU-side code that can't be trivially skipped.

It's a very simple and efficient renderer that can draw plenty of shapes, including rounded rectangles, circles, triangles, hexagons, line segments, and quadratic Bézier curves. But it does cut some corners: it can't do arbitrary path fills, non-rectangular clipping, or "layered blending" (I'm not sure what the real term for this is).

It would be cool to have a more modern compute-based renderer that can do all these effects, but I'm probably not writing another renderer from scratch any time soon. The most realistic option would be to switch to `vello` in the future, which would also be a great way to get a cpu-software backend almost for free.
