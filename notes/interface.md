This is a blog post about Keru's main library interface and its architecture.

By "library interface" I mean, what does it look like to use the library? 

The post show how the interface looks, but it will also go in some detail about how is this structure implemented, why does it look like this, and the advantages and tradeoffs.

This is how it looks:

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
    let state = State::default();
    // Use a wrapper that sets up a winit/wgpu loop, runs our `update_ui` on every update.
    // This is just for examples! Keru is meant to be used as part of a custom winit and wgpu loop.
    example_window_loop::run_example_loop(state, update_ui);
}
```

The `Ui` struct retains the whole state of the GUI, so this is not an "immediate mode" library (at least not in that sense.)
The `update` function runs on every update and redeclares the whole desired state of the GUI. Then, the retained tree is updated to match the declared state.


`example_window_loop::run_example_loop()` is a function that sets up a `winit` window loop and a `wgpu` renderer and calls the `update_ui` function when needed. This is just a helper, and the "intended" way to use Keru is actually with a `winit` loop and `wgpu`.



Back to the interface: 

# Node Keys

The first line is a tiny proc macro that defines an unique compile-time ID for a GUI node.

`#[node_key] const INCREASE: NodeKey;`

Internally, the `#[node_key];` macro just rolls a random `u64` and uses it to fill in value of the `const`.

Rust proc macros get a lot of hate, but here they give us a great way to define IDs in a simple and straightforward way. In many other libraries, the user has to provide IDs by providing unique strings manually, with no compile-time check for their uniqueness. 

Note that this doesn't mean that ALL nodes need an explicit `NodeKey`: Keru uses most of the tricks in the book at once, and can generate implicit keys from location in the source code, position in the runtime GUI tree, and more. However, since it's so convenient to create explicit keys, it leans on them quite a bit as a general-purpose way to refer to GUI nodes from anywhere in the code. 


# Nodes

    let increase_button: Node = BUTTON
        .color(Color::RED)
        .text("Increase")
        .key(INCREASE);

`increase_button` is a `Node`, a struct that describes a node in the GUI. In Keru, "everything is a node", and by setting the `Node''s fields we can turn it into a button, a text element, and image, a stack container, a grid container, or any of the supported primitives.
We also stick in the `INCREASE` key to associate the key with the node.

# The Tree

    // Place the nodes into the tree and define the layout
    ui.add(V_STACK).nest(|| {
        ui.add(increase_button);
        ui.add(LABEL.text(&state.count.to_string()));
    });

The `Ui` is the struct that holds the full retained state of the whole GUI. Every frame, we call `add()` and `nest()` to redeclare what nodes should be part of the tree, and the parent-child relationships among them.

Since `increase_button` is a plain `Copy` struct, we choose to keep it separate it from this part of the code, so that the tree structure remains understandable at a glance. Of course, nothing is stopping us from inlining the `V_STACK` and the `LABEL`.

The `nest` closure doesn't have a `|ui|` parameter, and uses a thread-local value to keep track of the current parent. Many Egui users are probably familiar to the kind of borrow errors that are caused by the need to continuously reborrow the Egui `ui`: a plain `||` closure avoids these problems entirely.

That being said, using a closure at all comes with many downsides. For example, this doesn't work:  

    let result;
    ui.add(V_STACK).nest(|| {
        result = add_component(&mut ui);
    });
    return result;

The compiler has no idea about what happens inside `nest`. It might as well return immediately without ever calling the closure at all. So we'll get an error about `result` being potentially uninitialized.

For more complicated reasons, it also prevents us to implement the `nest()` API at the same time as the familiar immediate-mode `is_clicked()`:

    // We can't have nice syntax for both `nest` and `is_clicked()` at the same time.
    // if ui.add(BUTTON).is_clicked() { println!("Hello"); }
    // If we want to keep `nest()` clean, we have to awkwardly pass back the `ui` reference into `is_clicked()`.
    if ui.add(BUTTON).is_clicked(ui) { println!("Hello"); }

All we do inside `nest` is to call `push_parent()` before the closure, and `pop_parent()` after it.
It would be much better to have a dedicated language construct to do this sort of thing, like Python's `with` or C#'s `using`.

As is often the case in life, we can derive confort by looking at the suffering of others: for example, see the advanced macro tricks 
used by `clay`, the C layout library. The GUI library used by RadDbg uses a very funny solution: a macro that wraps the code in a `for` statement, sticking the `push_parent` in the loop initialization and the `pop_parent()` in the increment clause. Calling `break` inside the body breaks it completely. in some Zig libraries, this sort of thing is done using `defer`, which I think looks quite bad.

It's a bit strange how many people seem to agree on the value of this sort of thing, but even modern languages completely ignore it. Even in the languages that do have the construct like Python and C#, it was added to help with resource deallocation, definitely not for something as lowbrow as programming GUIs.


## Events

    // Change the state in response to events
    if ui.is_clicked(INCREASE) {
        state.count += 1;
    }

Events run in immediate-mode style, and don't use callbacks. Callbacks are incompatible with any sort of architecture where the Ui can read and write arbitrarily shaped data. That means that they are essentially incompatible with any sort of GUI program that does anything useful other than the GUI itself. Who would want to write a serious program and go through the pain to insert every state variable in the GUI library's dedicated Arc'ed cloneable state wrapper? Any GUI library that asks its users to do this has some serious issues with main-character-syndrome.

But it's not as inflexible as the usual immediate-mode situation, thanks to the power of `NodeKeys' and the fact that the `Ui` is actually fully retained.

This code can be ran from anywhere, even from another function. This can allow us to separate the effects from the presentation, to avoid mucking up the nested layout calls, etc. As always, nothing is stopping us from putting it very close instead. Dedicated immediate mode fans can fall back to the familiar `if ui.add(BUTTON).is_clicked(ui)` form, as mentioned above, if they can stomach having to pass in the `ui`.

