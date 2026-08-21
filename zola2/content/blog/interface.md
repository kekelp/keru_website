+++
title = "GUI library Interface"
date = 2026-08-21
+++

This is a blog post about the main library interface in Keru, the GUI library that I'm writing. It will show how the code for writing GUIs with Keru looks, and explain some of the goals and the implementation constraints that determine the shape of the interface. 

It might seem shallow to focus on the syntax, but in practice, the library interface is a big part of what determines whether a library is easy to use and to learn, whether it's flexible enough to be used in different kinds of projects, whether it's smooth or painful to integrate it into a bigger program, and so on.

An important thing to remember is that while UI can be one of the most important parts of a program from the end user's point of view, the writer of the program usually has plenty of other things to worry about. If a GUI library is trying to help with the hard problems, and not just with the easy ones, it should be a relatively unobtrusive layer that can be easily laid on top of an already complicated program. The GUI is there so that the user accesses a program that can hopefully do something useful.

For this reason, it's very important that a GUI library imposes as few restrictions as possible on the rest of the program's code. It shouldn't force the programmer to structure the program's data in a certain way, impose rules on when it can be accessed or mutated, or complicate the program's control flow with too many callbacks and indirections.

This argument is a bit abstract, but it's why the interface tries to be as simple and minimal as possible.

This is [Keru's `minimal` example:](https://github.com/kekelp/keru/blob/master/examples/minimal.rs)

```rust
use keru::*;
use keru::node_library::*;

pub struct State {
    pub count: i32,
}

fn update_ui(state: &mut State, ui: &mut Ui) {
    // Define a unique identity for the button
    #[node_key] const INCREASE: NodeKey;
    
    // Create a Node struct describing a button
    let increase_button: Node = BUTTON
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
    let state = State { count: 0 };
    // Use a wrapper that sets up a winit/wgpu loop and runs our `update_ui` on every update.
    // This is just for examples! Keru is meant to be used as part of a user-controlled winit/wgpu loop.
    // Setting up a winit/wgpu loop is less than 100 lines of boilerplate.
    example_window_loop::run_example_loop(state, update_ui);
}
```

Looking at the syntax, you might be reminded of "immediate-mode" GUI. However, this is not an immediate-mode library, at least not in the sense in which most people use the term. The `Ui` struct retains the node tree and the whole state of the GUI across frames.

When the `update_ui` function runs, it redeclares the desired state of the whole GUI. While this happens, the `Ui` updates the retained state to match the declared one, and schedules relayouts or repaints as needed.


Back to the syntax:

## Node Keys

The first line in `update_ui` is a tiny proc macro that defines a unique compile-time ID for a GUI node.

```rust
#[node_key] const INCREASE: NodeKey;
```

Internally, the `#[node_key]` macro just rolls a random `u64` and uses it to fill in the value of the `const`. 

Rust proc macros get a lot of hate, but they work great here. In some other libraries, users have to create IDs themselves by manually providing unique strings.

Note that this doesn't mean that ALL nodes need an explicit key: Keru can also generate implicit keys from source code location, position in the runtime GUI tree, and more. But since it's so convenient to create explicit ones, it leans on them quite a bit as a general-purpose way to refer to GUI nodes from anywhere in the code.

## Nodes

```rust
let increase_button: Node = BUTTON
    .color(Color::RED)
    .text("Increase")
    .key(INCREASE);
```

`increase_button` is a `Node`, a struct that describes a node in the GUI. In Keru, "everything is a node", and the `Node`'s fields can be configured to turn it into a button, a text element, an image, a stack container, a grid container, a vector shape, etc.

In this case, we start with `BUTTON`, which is a preset `Node` constant, and use builder methods to configure it.

We also stick the `INCREASE` key in, to associate the node with the key.

The fact that "everything is a node" helps a lot in making the library easier to learn and understand. Except for the largely optional `Component` trait, Keru's interface is basically all contained in the above example: 
all GUIs are built by `add()`ing and `nest()`ing different kinds of `Node`s.

## The Tree

```rust
// Place the nodes into the tree and define the layout
ui.add(V_STACK).nest(|| {
    ui.add(increase_button);
    ui.add(LABEL.text(&state.count.to_string()));
});
```

The `Ui` is the struct that holds the full retained state of the whole GUI. When `update_ui` runs, we call `add()` and `nest()` to redeclare what nodes should be part of the tree, and the parent-child relationships between them.

Since `increase_button` is a plain value struct, we choose to keep it separate from this part of the code, so that the tree structure remains understandable at a glance. Of course, nothing is stopping us from inlining the `V_STACK` and the `LABEL`.

The `nest` closure doesn't have a `|ui|` parameter, and uses a thread-local value to keep track of the current parent. Many `egui` users are probably familiar with the kind of borrow errors that arise when the user needs to continuously reborrow the `ui` on each level of nesting. A plain `||` closure avoids these errors entirely.

That said, using a closure still comes with some downsides. For example, this doesn't work:  

```rust
let result;
ui.add(V_STACK).nest(|| {
    result = add_component(ui);
});
return result;
```

For all the compiler knows, `nest()` might decide to return without doing anything with our closure, so it can't tell if the code for our nested elements is going to be executed at all. So we'll get an error about `result` being potentially uninitialized. We can work around this by returning the value from the closure or making result and `Option`, but it sure would be nicer if it worked out of the box.

For more complicated reasons, it also gets in the way when trying to implement the familiar immediate-mode pattern `ui.add(BUTTON).is_clicked()`.
We can't have nice syntax for both `nest` and `is_clicked()` at the same time. In Keru, we have to awkwardly pass the `ui` reference back into it: `if ui.add(BUTTON).is_clicked(ui) { ... }`

All we're trying to do with the closure is to call a `push_parent()` function before the inner code, and `pop_parent()` after. Closures can do this, but it would be much better to have a dedicated language construct to do this sort of thing, like Python's `with` or C#'s `using`.

As is often the case in life, we can derive comfort by looking at the misfortunes of others. Few languages provide good tools for this, so library authors use all sorts of creative workarounds. Some Zig libraries ask the user to open a block and call `defer node.close()` manually after adding a node. C libraries like `clay` use complicated macro tricks. The C GUI library used for the RAD debugger project uses an especially funny solution: a macro that wraps the code in a `for` statement, sticking the `push_parent` in the loop initialization and the `pop_parent()` in the increment clause. Calling `break` inside the body breaks it completely.
Even in the languages that do have a dedicated construct, like Python and C#, it's interesting to note that it was added to help with resource deallocation, not for something as lowbrow as programming GUIs.

All in all, the `||` closure doesn't look like a bad solution if we look at the bigger picture, and there's some value in using a "regular" language construct like a closure rather than a more ad-hoc one or a macro.

## Events

```rust
// Change the state in response to events
if ui.is_clicked(INCREASE) {
    state.count += 1;
}
```

Events run in immediate-mode style, without callbacks. We just ask the `Ui` if a node was clicked in the last frame, and run some code as a response. This happens at the same time as we redeclare the GUI.

In callback-based systems, there's usually no safe way for the program to truly own its data. The data either is owned by the GUI library directly, or it has to be wrapped into `Rc`/`Arc`-based containers that allow callbacks to hold references to it. There are some escape hatches here, but I've never seen it done in a way that wasn't very complicated and limiting.

Even if that wasn't the case, I'd probably still try to avoid callbacks either way just for the sake of not complicating the control flow.

However, Keru's solution is not as inflexible as in most immediate-mode libraries, thanks to the power of `NodeKey`s and to the fact that the `Ui` is actually fully retained.

This code can be run from anywhere in the program. We can move it into another function entirely to separate the effects from the presentation, or move it just a couple lines to avoid mucking up the nested `add()` calls that define the layout. And of course we can choose to not separate it at all and write it right below the `add()`.

Dedicated immediate-mode fans can even fall back to the familiar `if ui.add(BUTTON).is_clicked(ui)` form, as mentioned above, if they can stomach having to pass in the `ui`.

## Consequences on the architecture

Whether a library embraces or denies them, callbacks are probably the most significant example of how the interface ends up deeply influencing the internal architecture. When using callbacks, all the extra complexity in managing the state usually ends up leaking into the interface, either in the form of the user having to manually clone their state handles, or in other ways.

Generally, not using callbacks also means that the library has to be ready to re-execute all or most of the user's redeclaration code whenever something important happens, so that all the event-response code written inline can be executed as well.

This doesn't mean that we have to become "immediate mode": we're just redeclaring the GUI and updating it, not necessarily rebuilding it from scratch. Also, it doesn't mean that we have to do that "on every frame": nodes annotate the types of events that they care about, so if a click lands on a node not set to listen to it, or if the user is just moving the mouse around or scrolling, the Ui knows that nothing needs to be rerun.

For this reason, we can also spare ourselves the headache of considering a truly reactive architecture, where the GUI would detect the dependencies of GUI elements on individual state variables and update them without a full redeclaration step. This would be very complicated, and it would have deep consequences of its own for the user's ability to manage his state freely and to write the GUI code in a simple and flexible way. But such an architecture would almost surely require callbacks anyway, so as long as we remain convinced that callbacks are already incompatible with our goals, we can discard it with this simpler argument.

That being said, proponents of reactive GUI don't always insist on fully automatic dependency tracking. It's also common to implement some partial reactivity on top of a mostly redeclaration-based system, where the user annotates a part of the code and possibly does some manual change-tracking, then the library simply skips re-executing it if it can. This sort of thing is not incompatible with Keru's model. The library has some experimental code to do this, even though I think it's generally still not worth the effort. 

Hopefully these arguments about the interface are enough to justify Keru's decision of not embracing reactivity. In the future I will write a new blog post analyzing this topic in more detail, going through how the declaration code, the diffing and the updates to the retained state are implemented in Keru.

In the meantime, it helps to remember that many existing libraries like Iced are mostly non-reactive and rerun the whole GUI declaration code on every interaction, and it doesn't seem to be a problem. The code just happens to look different enough from naive immediate-mode that it doesn't raise suspicion.

## The Component trait

The minimal example above shows the basic primitives of the library, and it's possible to create fairly complicated GUIs by composing them with regular functions, variables and constants. However, there's also an experimental `Component` trait that's meant to streamline the sort of composition that's common for self-contained GUI widgets, such as a reusable color picker or rich text edit box.

Besides helping with composition, `Component`s can also hold their own local state. For example, a color picker might not want to logically "own" the color that it sets, but it makes sense for it to own some specific local settings about the color space that it's using or its shape. That way, the user can add multiple color pickers each with its own independent settings without worrying about making space for all of them in the main program state.

This ability to hold local state is the only feature that's currently only accessible through `Component`s, and not when composing nodes manually. 

I won't go into any more detail here, partly because `Component`s are still experimental and I don't consider them part of the library's core interface, at least not yet. However, here's a [commented example showing how they work.](https://github.com/kekelp/keru/blob/master/examples/03_components.rs)


## Thanks for Reading

If you would like to learn more and see what Keru looks like beyond the basic "Hello world" code, you can check out [Keru's github page](https://github.com/kekelp/keru/) and explore the examples, which show advanced layout and grids, animations, drag and drop, canvas drawing, components with local state, optional imperative tree manipulation, integration with custom wgpu rendering, etc.

Keru is a pure Rust library and uses `winit` and `wgpu`, so trying it out should be relatively easy on most systems.

If you are interested in a more technical discussion, the next blog post will be about Keru's unique layout algorithm, which is completely experimental and different from most GUI libraries.
