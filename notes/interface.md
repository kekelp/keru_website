This is a blog post about Keru's main library interface.

It might seem shallow to focus on the syntax, but in practice, the shape of the library interface is a big part of what determines whether a library is easy to use and to learn, whether it's smooth or painful to integrate it into a bigger project, and so on.

An important thing to remember is that while UI is one of the most important parts of a program from the end user's point of view, the writer of the program usually has plenty of other things to worry about. If a GUI library is trying to help with the hard problems, and not just with the easy ones, it should be a relatively unobtrusive layer that can be easily laid on top of the other part of the program, the one that does the actual computation, simulation, networking, or whatever it's doing and wants to make accessible through the GUI.

For this reason, besides being easy to use and learn, it's very important that a GUI library tries as hard as possible to avoid leaking its complexity in the rest of the program, and imposes as few restrictions as possible on the rest of the code. It shouldn't force the programmer to structure the program's data in certain way, impose rules on when it can be accessed or mutated, or complicate the program's control flow with too many callbacks and indirections.

But rather than more theoretical considerations, it's probably more useful to get into the syntax. Then, the later sections will go in some detail about the advantages and tradeoffs of this structure, the way in which it is implemented. A future post will talk a bit about the implications that the syntax has on the architecture.

This is Keru's `minimal` example:

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

The `Ui` struct retains the whole state of the GUI, so this is not an "immediate-mode" library (at least not in that sense.)
The `update` function runs on every update and redeclares the whole desired state of the GUI. While this happens, the `Ui` updates the retained state to match the declared one, and schedules relayouts or repaints as needed.

## Node Keys

The first line in `update_ui` is a tiny proc macro that defines an unique compile-time ID for a GUI node.

    #[node_key] const INCREASE: NodeKey;

Internally, the `#[node_key];` macro just rolls a random `u64` and uses it to fill in the value of the `const`.

Rust proc macros get a lot of hate, but they work great here. In many other libraries, the user has to create IDs manually by providing strings, with no compile-time check for their uniqueness. 

Note that this doesn't mean that ALL nodes need an explicit `NodeKey`: Keru can also generate implicit keys from source code location, position in the runtime GUI tree, and more. However, since it's so convenient to create explicit ones, it leans on them quite a bit as a general-purpose way to refer to GUI nodes from anywhere in the code.

There's also a system for reusable components. When using it, `NodeKey`s only have to be unique within the component and not globally in the whole program.


## Nodes

    let increase_button: Node = BUTTON
        .color(Color::RED)
        .text("Increase")
        .key(INCREASE);

`increase_button` is a `Node`, a struct that describes a node in the GUI. In Keru, "everything is a node", and by setting the `Node''s fields we can turn it into a button, a text element, and image, a stack container, a grid container, or any of the supported primitives.
We also stick the `INCREASE` key in to associate it with the node.

The fact that "everything is a node" has some minor disadvantages, but it helps a lot in making the library easier to learn and understand. Except for the largely optional `Component` trait, Keru's interface is basically all contained in the above example: 
all GUIs are built by `add()`ing and `nest()`ing different kinds of `Nodes`s.

## The Tree

    // Place the nodes into the tree and define the layout
    ui.add(V_STACK).nest(|| {
        ui.add(increase_button);
        ui.add(LABEL.text(&state.count.to_string()));
    });

The `Ui` is the struct that holds the full retained state of the whole GUI. When `update_ui` runs, we call `add()` and `nest()` to redeclare what nodes should be part of the tree, and the parent-child relationships among them.

Since `increase_button` is a plain value struct, we choose to keep it separate it from this part of the code, so that the tree structure remains understandable at a glance. Of course, nothing is stopping us from inlining the `V_STACK` and the `LABEL`.

The `nest` closure doesn't have a `|ui|` parameter, and uses a thread-local value to keep track of the current parent. Many Egui users are probably familiar to the kind of borrow errors that arise when the user needs to continuously reborrow the `ui`. A plain `||` closure avoids these problems entirely.

That said, using a closure still comes with some downsides. For example, this doesn't work:  

    let result;
    ui.add(V_STACK).nest(|| {
        result = add_component(&mut ui);
    });
    return result;

The compiler has no idea about what happens inside `nest()`, so it can't reason about this code very well. For all it knows,`nest()` might as well return immediately without calling the closure at all. So we'll get an error about `result` being potentially uninitialized.

For more complicated reasons, it also gets in the way when trying to implement the familiar immediate-mode `ui.add(BUTTON).is_clicked()` 
We can't have nice syntax for both `nest` and `is_clicked()` at the same time. In Keru, we have to awkwardly pass back the `ui` reference back into it: `if ui.add(BUTTON).is_clicked(ui) { ... }`

All we're trying to do with the closure is to call `push_parent()` before the inner code, and `pop_parent()` after.
It would be much better to have a dedicated language construct to do this sort of thing, like Python's `with` or C#'s `using`.

As is often the case in life, we can derive confort by looking at the misfortunes of others. Few languages provide good tools for this, so library authors use all sorts of creative workarounds. Some Zig libraries ask the user to open a block and call `defer node.close()` manually. C libraries like `clay` use complicated macro tricks. The C GUI library used for the RadDbg debugger uses an especially funny solution: a macro that wraps the code in a `for` statement, sticking the `push_parent` in the loop initialization and the `pop_parent()` in the increment clause. Calling `break` inside the body breaks it completely.

Even in the languages that do have a dedicated construct, like Python and C#, it's interesting to note that it was added to help with resource deallocation, and certainly not for something as lowbrow as programming GUIs.

All in all, the `||` closure is probably not a bad solution if we look at the bigger picture, and there's some value in doing this with a "regular" language construct rather than with a more ad-hoc one or a macro.

## Events

    // Change the state in response to events
    if ui.is_clicked(INCREASE) {
        state.count += 1;
    }

Events run in immediate-mode style, without callbacks. We just ask the `Ui` if a node was clicked in the last frame.

In callback-based systems, there's usually no safe way for the program to truly own its data. The data either is owned by the GUI library directly, or it has to be wrapped into `Arc` based containers, which allow callbacks to hold references to it. As anticipated in the beginning of the post, I think this is an unacceptable compromise. And even if that wasn't the case, I'd probably still do my best to avoid callbacks anyway, just for the sake of not complicating the control flow.

However, Keru's solution is not as inflexible as in most immediate-mode libraries, thanks to the power of `NodeKey's and to the fact that the `Ui` is actually fully retained.

This code can be ran from anywhere else in the program. We can move it into another function entirely to separate the effects from the presentation, or move it just a couple lines to avoid mucking up the nested `add()` calls that define the layout. As always, nothing is stopping us from not separating it at all and writing it right below the `add()`.

Dedicated immediate-mode fans can even fall back to the familiar `if ui.add(BUTTON).is_clicked(ui)` form, as mentioned above, if they can stomach having to pass in the `ui`.

While this style is perfectly compatible with a `Ui` that retains as much state as it wants, it's true that it generally means that the redeclaration code has to be rerun on every frame, so that the code that reacts to events can rerun as well. But this is still not the same as "immediate-mode" in the negative sense in which many people use the word. Nodes can annotate the types of events that they care about, so if a click lands on a element without the `CLICK` sense, the Ui knows that nothing has to be reran at all.



## Thanks for Reading

If you would like to learn more and see what Keru looks like beyond the basic "Hello world" code, you can check out [Keru's github page](https://github.com/kekelp/keru/) and explore the examples, which show advanced layout and grids, animations, drag and drop, canvas drawing, components with encapsulated state, optional imperative tree manipulation, integration with custom wgpu rendering, etc.

Keru is a pure Rust library and uses `winit` and `wgpu`, so trying it out should be relatively easy on most systems.

If you are interested in a more technical discussion, you can read this blog post about Keru's unique (and experimental) layout algorithm.
