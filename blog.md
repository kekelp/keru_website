# Against Reactive GUI

This a blog post about the concept of "Reactive" GUI and its relevance in the design of GUI library.

My opinions on this topic were formed in the last two years as I was working on a new GUI library for Rust, which I named [Keru](https://github.com/kekelp/keru). Nowadays, the standards for calling a GUI library "complete" are quite high, and some people would probably say that it's not complete until it comes bundled together with a full browser engine. I haven't gotten there yet, but I still think that it's a good time to start sharing the library and the ideas behind it.


Keru is a "declarative" library, but as you can probably guess by the title, it's not "reactive". 

This post will try to define all the relevant terms, and give an overview of how the different axes in the design space interact with each other. Then, it will do some considerations on performance and usability, bringing in examples from Keru.

It will try to argue that it's not worth it to make it a fundamental part of a library's programming model. However, it's still great to make space *some* degree of opt-in reactivity,  and it will show Keru's approach on this.


To start off with something concrete before getting into the definitions, I will show some Keru code. This is what it looks like:

```rust
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
    example_window_loop::run_example_loop(State::default(), update_ui);
}
```

All this code in `update_ui` is run on every update. Is this a bad thing?
There's probably many people who would say yes. They might be thinking things like these:

- Oldschool imperative/retained-mode GUI systems were just better, because you'd just write the code for what you want to happen, instead of writing a high level declaration of what you want and having the library diff things to figure it out for you.

- Anything that looks like "immediate mode" is especially bad, because you're rerunning a bunch of code on every update.

- If anything, you should use a "reactive" system, where the library can keep track of which parts of your state affect which parts of your declarative model. And it better be "fine grained reactivity"!

What they're saying is that you have to make your system "reactive" if you want to be "incremental".

# Definitions

But we can't go on without defining the precise sense in which we're using these words. Unfortunately, many of these words are used with very different meanings by different people.

## Retained

This is a property of how a GUI system is implemented internally.

A system is retained when it retains a lot of state between frames. We might be tempted to say that "Immediate" is the opposite of that. However, the word "Immediate" has been used with so many different and confusing meanings, that it's better to use it as little as possible.

In this sense, Keru is retained: you can see that there's a `Ui` object that holds all the state. It never throws away anything.


## Declarative / Imperative

This is a property of how the library user's code looks like.

In a declarative system, the user writes a single description of the whole GUI, that uses control flow or control-flow-like structures to express the whole dynamic state of the whole GUI.

Keru's code above is declarative, using the Rust's real control flow. Other examples are Angular, SolidJS, SwiftUI, `egui`, Iced, React... probably hundreds more. It's pretty popular.

In contrast, in an imperative system, the user sets up a static initial state, and then manually writes the imperative changes that should happen as a result of input or other events.

In the current year, this is not very popular anymore. It feels a bit like opening a coffin with cobwebs all over it. The obvious downside is that after enough imperative mutations, the state of the GUI gets farther and farther from anything written in your code. To understand what's going on, you have to track of all the mutations and play them back inside your head. But for a GUI that never strays very far from its initial state, maybe it's fine.

Even in the old days, this was never very popular, so people wrote plenty of user-level abstractions to try to hide it. But under the hood, you'd still find explicit changes to the retained tree.

## Reactive / Redeclare-On-Every-Update

This is the most important distinction, between two ways of building declarative GUI systems.

Maybe someone can come up with a better term, but for now, I will use the term "Redeclare-On-Every-Update" to describe the systems where the GUI declaration is written in real code, and that whole code is re-executed on every update, to get a fresh new declaration of the target state of the GUI.

Keru's code above fits in this category, as well as egui and Dear Imgui and React. In this kind of system, you can use real language-level control flow to express the dynamic range of states of your GUI: a simple `if` for a conditionally-visible element, or a simple `for` for a dynamic list of elements.

On the other hand, I will use the term "Reactive" to describe the systems like SwiftUI or SolidJS.

In these systems, when you write a declaration of the GUI, the system will try go through it ahead of time, ideally just once, and analyze the dependencies between the data and the elements of the GUI. Then, it will wire up a system of observers and callbacks so that every change in the state can automatically trigger the desired change in the GUI.

In this kind of system, the declarative form will have some sort of pseudo-control-flow structures that get compiled down statically, like how SolidJS's `<Show> ... </Show>` works as a pseudo-`if`. In SwiftUI, there's compiler magic that can turn language-level `if`s and `for`s into those kind of structures.

Note that despite the name, vanilla React is Redeclare-On-Every-Update, not Reactive. It's still unequivocally re-executing the declaration code: the fact that it creates a virtual tree is just an implementation detail of how it goes from a fresh redeclaration to an updated state.

While this is a useful distinction to keep in mind, the muddy reality is that many of the "Reactive" systems actually sit in the middle ground. While there are a few purist systems like SolidJS or Leptos, it's fairly common for reactive libraries to start with a Redeclare-On-Every-Update base and add some reactive elements on top of it. Usually this boils down to a system
that still goes through the declaration code on every update, but is usually able to skip some or most of it.

In this kind of hybrid system, there's also the option of doing an equality-based reactive system rather than one based on signals or observables. In that case, it starts to look more like regular memoization. If you go far enough in this direction, you can get to a place where you're doing some non-intrusive opt-in optimizations on top of a simple Redeclare-On-Every-Update, which I don't think is a bad idea.

In practice, I think that the Reactive / Redeclare-On-Every-Update distinction is still quite strong. Even if the code itself is somewhere in the middle, you can usually feel that a library is on one side or the other of the ideological divide, and usually it does reflect in the experience of the library user.
Ultimately, a good test for a sincerely Redeclare-On-Every-Update system might be that it should always let the user decide when he wants to run his own declaration code and when to skip it. As overused as the term is, a Redeclare-On-Every-Update is one that doesn't feel like a "framework".

## Incremental

A system is incremental when a small change to the program's state results in a small amount of recomputation.

If a system doesn't retain any state, it probably won't be able to be very incremental. But any system that retains some of its state can be more or less incremental, depending on its architecture and its other design choices.

Incrementality is a property of the system's performance, and it's the one that the strawmanned arguments at the beginning are referring to.
If the previous properties are the "axes" of the design space, incrementality is the value of the function we're trying to optimize. The point of this post is to see how much incrementality we can achieve from different points in the declarative/imperative, retained/non-retained, and especially reactive/redeclare-on-every-update space.


# The Basics

Actually, before getting into that, we should note that there's some basic layer of incrementality that we should expect to get regardless of all those other properties.

- It's easy for even the most naive immediate-mode libraries to just do nothing where no input is being received at all. We can pick any combination of non-retained or non-reactive library, that will *never* justify a GUI program burning CPU for no reason while it's completely idle.
If that happens, it's not because of any design decision or architectural choice: you're probably using a library that was only meant to be used inside a game. Or maybe the author of the library forgot an `if`.

- It's also easy to annotate which GUI elements should react to which input. So if the user is clicking on a non-interactive background element, or just moves the mouse around, that still shouldn't result in any needless work.

So, the incrementality that we're talking about here applies only to the situation where the GUI is composed of multiple independent parts. When the user does a meaningful interaction which causes in a part of the GUI changing, but that leaves all the other parts static, then we want to be able to update just that part.


# How to be incremental

Now let's finally look at how the properties defined at the start affect incrementality.

We won't actually consider retainedness very much, because it's an implementation detail, and it doesn't actually have many tradeoffs other than some memory usage. We'll just assume that if a system can retain more some state to be more incremental or more efficient, it will figure out a good way to do so without bothering anybody.

What does the program do when the user interacts with the GUI and changes some state?
At a very abstract level, we might say that it has to figure out what the library user wants to happen, then make it happen.
Looking at the remaining properties, we can consider three different classes of GUI, and see what they would do:


1) Oldschool imperative GUI.
    
    - In an imperative system, the library user's code will literally be a step by step description of what needs to be changed in the tree. So the system just runs that code, and does nothing else.

2) Reactive declarative GUI.
    
    - In a reactive system, the library will have pre-computed a dependency graph that will immediately tell it what GUI elements it should update.

3) Redeclare-On-Every-Update declarative GUI.
    
    - In a Redeclare-On-Every-Update system, the library will have to rerun all the declarative code that the library user provided. Then it will do some sort of diffing to see what to update.


So, after all this time, we finally got to the obvious reason why nonRedeclare-On-Every-Update libraries are considered bad for incrementality: because they have to rerun that redeclaration code on every update, and the other systems don't.

But what does that code even do? How slow is it? How does it compare to everything else? Since we went through all these preambles anyway, let's continue, and try to get a better idea.

The first thing to notice is that the library's job doesn't end there. And after this first step, all three kinds of libraries will end up in the same position. They updated the internal element tree, they still have to:

- recompute the layout
- rasterize new glyphs or relayout text that changed
- rebuild the render data (triangles, paths or other gpu primitives)
- rerender the pixels on the screen.

Again, all these are completely independent of the library's architecture! That's a ton of incrementality that actually doesn't depends on our opinion on reactivity. (Or non-incrementality: as far as I know, partial relayouts are not a fairly popular thing. And most modern GPU-based renderer probably won't bother with a whole lot of incrementality, they'll just have the overpowered GPUs of the current age blast through their handful of shapes in microseconds.)

# The Redeclaration Code

With all the considerations above, we can see that the redeclaration code that non-reactive libraries have to rerun occupies a fairly small place in the big picture of everything that a GUI library has to do. It probably won't be the thing that makes or breaks the incrementality or the performance of a library, unless it's doing something really slow.

Let's see how expensive the redeclaration code is by looking at how Keru handles it.

It turns out that there's really not that much to do.

Looking back at the code above, this is what the code is doing:

- Creating some `Node`s on the stack.
- Formatting a string.
- Calling `ui.add()`. This does three things:

    - Do a lookup on a small HashMap to figure out what GUI node we're redeclaring. 
    - Access that node and compare it the new one that we passed. If it's different, it schedules a relayout.
    - Reset the tree links according to the structure of the `nest()` calls.

- Then, hidden in the `run_example_loop`, `ui.finish_frame()` checks that no old nodes disappeared, does some minor cleanup, and then actually recompute the layout and rerender. But as we said before, that's the part that would work the same way regardless of the architecture. 






`ui.add()` is the sort of function that we can expect to run many thousands of times before we ever get close to showing up in a profiler:
- it doesn't do any heap allocations.
- it's decently cache friendly: all the internal InnerNodes are stored in a contiguous Slab. Right now, the `InnerNode` struct is probably a big too big to be able to claim that it's really cache-friendly, but if that turns out to be measurably slow, it could be optimized, moving all the stuff that's not needed for `ui.add()` in a separate place.

In a typical benchmark in Keru, the flamegraph of the redeclaration code breaks down roughly like this:

- Hashmap lookups: 50%.
- Diffing Nodes (visual and layout parameters): 20%.
- Diffing text: 20%.
- Setting tree links: 5%.
- Whole-tree diffing and cleanup: 5%.

So, for a GUI with N nodes, the whole redeclaration ordeal is of the order of magnitude of 2N hashmap lookups.

If it's that simple, why did the Redeclare-On-Every-Update even end up with such a bad reputation in the first place? There's a few things that we can blame:

- The infamous "Immediate" name. I won't go into the details into the history of this word, but the result is that many people ended up assuming that when doing Redeclare-On-Every-Update, you'd also necessarily be in a system where there's no retained element tree at all. So you'd have to rebuild it from scratch as you re-executed the declarative code.

- The idea that it would be a good idea to recreate a whole new tree and compare it with the old one, rather than comparing each redeclared nodes with the old version of itself.

- The idea that every sort of tree or list needs to be a horrifically pointer-heavy and cache-inefficient structure spread across N separate heap allocations, rather than a slab and a handful of indices.

These are hopefully all relics of the past. However, there's a scarier one: even though the redeclaration code is usually just a few ui.add() calls, it's still the library user's custom code. The user can always make it arbitrarily bad. Then, he'd be right to complain that the library is slowing their program by reexecuting that code too many times.

I wasn't really there to see it with my own eyes, but it's not hard to imagine something like this happening to React. When you have a billion people writing React components in Javascript that keeps allocating all sort of crap and having the GC clean it up, you can see why some of these assumptions start to break, and why people start caring about component memoization, state management, or give up on Redeclare-On-Every-Update altogether and move to a reactive system.

Is this something that we should worry about in Rust? Well, yes. There's no GC, but doing a lot of needless heap allocations is still sort of common in Rust code. In fact, my example code above is allocating a string on the heap for no good reason.

In the blog post that explains the Xilem architecture, this is the example that justifies its reactivity/memoization scheme:

> Going back to the counter, every time the app logic is called, it allocates a string for the label, even if it’s the same value as before. That’s not too bad if it’s the only thing going on, but as the UI scales it is potentially wasted work. [[1]](https://raphlinus.github.io/rust/gui/2022/05/07/ui-architecture.html)

But many years have passed since then. Now all the cool programmers on Twitter won't shut up about arenas, and the Bumpalo crate has been out for more than seven years. Maybe it's fine to just ask the library users to think of the planet and use that.
To make this easier, Keru exposes its own Bumpalo arena through a closure:

```rust
with_arena(|arena| {
    let count = bumpalo::format!(in arena, "Count: {:.2}", state.count);

    ui.add(V_STACK).nest(|| {
        ui.add(increase_button);
        ui.add(LABEL.text(&count));
    });
});
```

With the power of arenas and the common sense of the average non-Javascript programmer, we're probably in a solid spot.
We can expect most programs to redeclare their GUI in microseconds.

# The cost-benefit analysis

With this post, I hope to have made the case that despite the very high prevalence of the concept of "reactivity", it probably shouldn't be the first thing to focus on when evaluating GUI systems.

Well, actually, all I did was explain why redeclaring on every update doesn't have to be expensive. The other part of the message is that just like how most people naturally prefer writing GUI code in declarative style rather than imperative, I expect that most people will naturally prefer the simpler programming model of non-reactive systems ("Redeclare-On-Every-Update").

At the end of the day, that's a subjective thing: a matter of aesthetics. However, I feel like these aesthetic concerns are still very important. 

At this point, there's really no shortage of experimental GUI libraries in Rust, trying out all sorts of programming models. But none has really caught on, and none really seems to generate the sort of enthusiasm that people have for other libraries or for Rust itself. There's probably many different reasons for this, but one of the main ones is that the user-friendliness of many of these libraries remains low.

The library users are expected to internalize many concepts about "contexts" or "registers", to lay out all their state into special library-provided containers, or to write all their logic inside closures or trait impls. 

Often they are told that they should read many pages of abstract descriptions so that they can grasp the bigger picture, or maybe even that they shouldn't expect the documentation to hold their hand and they should figure out these complicated systems on their own.

There might be valid reasons for this sort of complexity, but "reactivity" is probably not one of them.


# Next Post: Can we have reactivity anyway, just for fun?

Even if we don't make it a core part of our programming model, it turns out that it's not hard to add some level of opt-in reactivity anyway, by skipping some redeclarations or with memoization. This is what happened in the React world.

In Keru, the "Component" trait allows to define reusable blocks of GUI code. Components can also manage their own state. The next post will show some examples of using Components to make pseudo-reactive components.





