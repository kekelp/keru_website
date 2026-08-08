This blog post is about the experimental layout system in Keru. It uses a fairly unorthodox layout algorithm based on explicit dependencies between nodes.

When I first started writing Keru, I actually had no strong opinions about layout, and I implemented a very simple system inspired by some blog posts describing SwiftUI's one (it was 2024, so you couldn't just ask AI to write it). Unsurprisingly, it had some limitations, and I returned to layout some time later.

This time, I finally discovered that GUI layout is an art more than a science: a layout library offers some layout primitives that the user can compose, but when it comes to solving them and producing real rectangle coordinates, it's sort of common for libraries to do a fairly half-hearted attempt, give out a clearly inconsistent answer, and declare that particular layout unsupported.

The enlightening example is this innocent-looking giraffe layout, taken from this blog post: https://mortoray.com/why_ui_layout_calculations_are_slow/

![Giraffe](mortoray-giraffe.webp)

The multi-line paragraph fits to the width of the single-line label. The giraffe fits the height of the whole right section, and its width is half of its height, to preserve the aspect ratio of the bitmap image.

The first thing I did was trying to implement the `clay` algorithm in Keru, and despite sabotaging myself with a lot of AI assistance, I think I understood its algorithm well enough to conclude that it couldn't possibly solve this case.

To be clear, I don't think this is necessarily a problem: especially in the case of `clay`, which is a library focused on performance and simplicity, there's nothing wrong with sticking to a simpler and faster algorithm if it works for the specific application, and there's plenty of GUI programs which only use simple layouts that don't run into any of these problems. 
Maybe it could have a section on its site explaining which cases are supported and which aren't, but I don't blame them for not going through this effort.

I also did some experiments with CSS layout, and concluded that it couldn't solve it either. This is a lot harder because of how incredibly complicated CSS is: it's still entirely possible that CSS can solve this problem just fine, and I just didn't know the correct magic word for it. What I can say with certainty is that writing it in the obvious way doesn't work:

[ css giraffe? it's just empty. ] 

My conclusion for now is that most layout algorithms work by a series of top-down or bottom-up tree traversals, and the dependencies in the giraffe example just don't line up with them. As the original giraffe blog post notes, solving an arbitrary dependency graph by doing multiple passes until everything is solved leads to exponential complexity, so the algorithms cut some corners. Sometimes doing a lot of memoization helps, but sometimes they just give up.

To understand what was going on, I tried drawing the giraffe on paper and asking myself what would an ideal layout engine do to solve this layout properly.

[ photo ]

It turns out that in this case there's a fairly straightforward dependency chain:

- The single-line text determines the width of the v-stack on the right.
- The wrapping text fills the width of the v-stack, and determines its height by wrapping.
- The heights of the single-line text and the wrapping text sum up to determine the height of the h-stack.
- The giraffe fills the height of the h-stack, and determines its width by aspect-ratio.
- The widths of the giraffe and the v-stack sum up to determine the width of the outer panel.

[ graph ]

## The Algorithm

It's not that hard for an algorithm to pick up this same chain of dependencies.

The goal is to build a graph of dependencies, then solve it. Every element in the graph is a `(NodeID, Axis)` pair, and each dependency is an edge in the graph: `{ dependent: (NodeID, Axis), depends_on: (NodeID, Axis) }`.

- For each of these elements, we keep a list of elements that depend on it, and a count of elements it depends on.

    In practice, the list and the count can be stored directly on the UI node. Each UI node will have two, one for each axis.

- Do a full traversal of the UI tree:

    - For each node, compute the dependencies of both its axes based on its layout role. For example, if a node is `Fill` or `Fraction/Percent` on the `X` axis, then its `X` element depends on its parent's `X` element.

        Similarly, a `Fit` node depends on all its children. Stacks add some complication, but not much.

    - Note these dependencies into the dependent node's count and the depended node's list.


    - If the node has a determined size on an axis, such as a fixed size `Pixels`, if it contains non-wrapping text, or if it is the root node with size `(1.0, 1.0)` we also add that element to a solver queue.


- Then, go through the solver queue:

    - Solve the node's size. The initial elements can be solved trivially without dependencies.

    - Go through the solved node's list of dependants, and decrease the dependency count of that element by 1. If it reaches zero, push that element to the back of the solver queue.

- Continue until the solver queue is empty.


When you put it like this, it doesn't even sound that exciting, but it works. here is the solved giraffe:

[ solved giraffe ]

The single-line text is the starting point pushed to the queue, and the solver steps through the chain exactly as we described in words above.


## Cycles

You might be wondering, "what about cycles"? That's a fair question to have when dealing with any sort of graph. But I don't think they are much of a problem.

The first thing to keep in mind is that most expressive layout systems with primitives like `Fit`, `Fill`, `AspectRatio` etc. allow the user to logical cycles, even if they are never materialized into a real cycle in a graph. When the CSS algorithm encounters such a circle, it fills in some fairly arbitrary and inconsistent numbers, and moves on. The bar is not very here.

However, the real weakness of the graph algorithm as described above is that it can make cycles "viral". Imagine a layout with is that two nodes form a cycle, one plain node with a regular fixed size, and a `Fit` container node that depends on all of them.

An algorithm that fills all of them with best-effort values won't have any good numbers for the two cycling nodes, but it might have a pretty good guess for the container, based just on the plain node. The basic graph solver, on the other hand, will stop without solving the container, because it has dependencies that were never solved.

It's not hard to improve the algorithm to fix this, though:

- When we solve an element and decrease the dependency count of all its dependents, see if the element still has a positive count.

- If yes, add it to a deferred solver queue.

- After the main solver queue is done, go through the deferred solver queue. 

    - If there are no cycles, all those elements will already be solved. If there is an unsolved element, it means that it depends on an unsolvable node.

    - Collapse its unsolvable dependences to zero or to a fallback size. Then push the element into the main solver queue.

    - Loop back to solving the main queue. This will solve that element, and any elements that depended on it, using the regular algorithm.


Lastly, there's space to 



## Max and Min Sizes


## Data layout matters?

Keru is an experimental library that hasn't gone through any real-world testing, so there might still be many good reasons why you shouldn't do your layout like this after all. However, I was still surprised that I couldn't find anyone discussing an approach like this even in blog posts or internet discussions.
The common wisdom just seems to be that layout algorithms are implemented with a series of tree-order traversals, usually with some memoization.

One exception is the old Cassowary constraint solver. It seems to have a bit of a bad reputation as an over-engineered historical oddity compared to the modern approaches, so it's probably fair to not consider it part of the current-day common wisdom. And in any case, its constraint system didn't look much like the dependency algorithm in Keru either.

Obviously there's no single answer for why this ended up being the case, but it leads me to an interesting consideration about how the way in which the data layout of the tree may affect the choice of algorithms.

In the dark ages of programming, there was a common idea that the way to build a tree of nodes was to put each node in a separate heap allocation, and have the node's parent hold the pointer to it, because it "owns" it.

This means that a node is literally only accessible from its parent. In this situation, it's not surprising that most algorithms end up looking like a sequence of tree-order traversals!

In the style of programming that I use, on the other hand, all nodes are stored in a top-level container like a slotmap, slab, hashmap, or even a plain Vec in simpler cases. Then, parent-child relationships are encoded by non-owning `NodeI`s, which are indices of keys into the container.

This is what allows us to model dependencies as simple `{ dependent: NodeI, depends_on: NodeI }` structs, and to access and solve the nodes in arbitrary order when going through the dependencies.

More generally, the idea is to allow the programmer to always have a full bird's eye view on the whole state of the program, and to always have the freedom to access any of it. This is extremely helpful when experimenting with unusual algorithms or when debugging.

There are many other factors in this kind of decision, most importantly the impact on performance of using many separate allocations, and the loss of RAII on the other side. But this is an example that shows how a slotmap-based layout can actually improve the ergonomics, flexibility and understandability of the code as well.


## Performance

Layout is often considered to be a fairly slow part of a GUI library's pipeline, so it's natural to wonder about the performance of a new algorithm. 

Unfortunately I don't have a lot of useful information here, as I didn't run any serious benchmarks. 

From an algorithmic complexity point of view, Keru's algorithm doesn't have any major quadratic or exponential scaling on the global number of nodes, and it still boils down to the same per-node calculations, so it's reasonable to expect it to work "fine".

However, I was still curious, so I ran some unserious ones, and compared the results with the ones from this blog post from the PanGui project: https://www.pangui.io/blog/05-layout-rework-and-benchmarks/

Unfortunately, Keru's current implementation of the algorithm is not at all optimized. I usually try to use the heap responsibly, and that's often enough to get pretty good performance without much effort. In this case, I didn't even follow my own rule, and made each node hold a heap-allocated `Vec` with a list of the nodes that depend on it.
In addition, the layout algorithm runs on the full GUI nodes, which are huge structs containing a lot of information about the node's display and behavior. Of course, this is not very cache friendly.
These two factors alone are enough to conclude that the current implementation has no hope of utilizing the CPU efficiently.

Another thing to remember, of course, is that the Keru numbers were measured on a completely different CPU from the other ones.

Despite all the caveats and the handwaving, it's still reassuring to see Keru's numbers being in the same order of magnitude Yoga and Taffy.

## Total layout time

| Benchmark                  |   Nodes |      Taffy |       Yoga |       Keru |
|:---------------------------|--------:|-----------:|-----------:|-----------:|
| wide_no_wrap_simple_few    |   1,001 |  0.2507 ms |  0.1921 ms |  0.2286 ms |
| wide_no_wrap_simple_many   | 100,001 | 48.6879 ms | 28.5494 ms | 51.0822 ms |
| flex_expand_equal_weights  |  15,001 |  5.3728 ms |  4.8458 ms |  7.4206 ms |
| nested_vertical_stack      |  10,001 |  3.7867 ms |  2.9214 ms |  3.6699 ms |
| percentage_and_ratio       |  10,001 |  3.3133 ms |  2.9622 ms |  3.1916 ms |
| expand_with_max_constraint |   3,001 |  1.6222 ms |  1.6559 ms |  1.0274 ms |
| fit_nesting                | 101,111 |110.9751 ms | 60.0391 ms | 98.3934 ms |

## Time per node

| Benchmark                  |   Nodes |     Taffy |      Yoga |      Keru |
|:---------------------------|--------:|----------:|----------:|----------:|
| wide_no_wrap_simple_few    |   1,001 | 250.45 ns | 191.91 ns | 228.40 ns |
| wide_no_wrap_simple_many   | 100,001 | 486.87 ns | 285.49 ns | 510.82 ns |
| flex_expand_equal_weights  |  15,001 | 358.16 ns | 323.03 ns | 494.68 ns |
| nested_vertical_stack      |  10,001 | 378.63 ns | 292.11 ns | 366.96 ns |
| percentage_and_ratio       |  10,001 | 331.30 ns | 296.19 ns | 319.13 ns |
| expand_with_max_constraint |   3,001 | 540.55 ns | 551.78 ns | 342.36 ns |
| fit_nesting                | 101,111 |1097.56 ns | 593.79 ns | 973.12 ns |


If you clicked through to the blog post with the benchmarks, you might have noticed that the numbers for PanGui and for Clay are a full order of magnitude better than any of these! However, Clay uses a significantly less expressive algorithm, and PanGui is closed source, so there's not a lot to learn from the comparison.

Still, it's true that a new algorithm unencumbered by strict compliance with the CSS model should probably be aiming a bit higher. In the future, I'll try to see what an optimized version of the Keru algorithm can do.



