Practical Dependent Types in Haskell: Type-Safe Neural Networks (Part 2)
========================================================================

> Originally posted by [Justin Le](https://blog.jle.im/).
> [Read online!](https://blog.jle.im/entry/practical-dependent-types-in-haskell-2.html)

We’re back to continue on [our
journey](https://blog.jle.im/entries/series/+practical-dependent-types-in-haskell.html)
in using practical dependent types to write type-safe neural networks! In [Part
1](https://blog.jle.im/entry/practical-dependent-types-in-haskell-1.html), we
wrote things out in normal, untyped Haskell, and looked at red flags and general
design principles that nudged us in the direction of adding dependent types to
our program. We learned to appreciate what dependent types offered in terms of
guiding us in writing our code, helping the compiler check our correctness,
providing a better interface for users, and more.

We also learned how to use singletons to work around some of Haskell’s
fundamental limitations to let us “pattern match” on the structure of types, and
how to use typeclasses to generate singletons reflecting the structure of types
we are dealing with.

(If you read [Part
1](https://blog.jle.im/entry/practical-dependent-types-in-haskell-1.html)
*before* the singletons section was re-written to use the
[singletons](https://hackage.haskell.org/package/singletons) library, [here’s a
link to the
section](https://blog.jle.im/entry/practical-dependent-types-in-haskell-1.html#singletons-and-induction)
in specific. This tutorial will assume familiarity with what is discussed
there!)

All of what we’ve dealt with so far has essentially been with types that are
fixed at compile-time. All the networks we’ve made have had “static” types, with
their sizes in their types indicated directly in the source code.

Today, we’re going to dive into the world of types that *depend* on factors
unknown until runtime, and see how dependent types in a strongly typed language
like Haskell helps us write safer, more correct, and more maintainable code.
Along the way, we’ll encounter and learn first-hand about techniques and guiding
high-level principles that we can apply to our other dependently typed coding
endeavours.

This post was written for GHC 8 on stackage snapshot
[nightly-2016-06-28](https://www.stackage.org/nightly-2016-06-28), but should
work with GHC 7.10 for the most part. All of the set-up instructions and caveats
are the same as for [part 1’s
setup](https://blog.jle.im/entry/practical-dependent-types-in-haskell-1.html#setup).

Run-time Types
--------------

Recall the type we had for our neural networks:

``` {.haskell}
ghci> :k Network
Network :: Nat -> [Nat] -> Nat -> *
```

They’re of the form `Network i hs o`, where `i` is the size of the input vector
it expects, `hs` is the list of hidden layer sizes, and `o` is the size of the
output vector it produces. Something of type `Network 10 '[6, 4] 3` is a network
with 10 input nodes, two input layers of size 6 and 4, and 3 output nodes.

This is great and all, but there’s an apparent severe limitation to this:
Haskell is a statically typed language, right? So doesn’t this mean that using a
network requires that you know the entire structure of the network at
compile-time?

It’s conceivable that you might be able to have the input and output sizes known
at compile-time, but it’s probably likely that you *don’t* know the what you
want your hidden layer structure to be in advance. You might want to load it
from a configuration file, or have it depend on user input. But can a type
really depend on things that you can’t know until runtime?

To illustrate more clearly:

``` {.haskell}
main :: IO ()
main = do
    putStrLn "What hidden layer structure do you want?"
    hs  <- readLn        :: IO [Integer]
    net <- randomNetwork :: IO 10 ??? 3   -- what is ???
    -- ...?
```

You would *want* to put `hs` there where `???` is, but…`???` has to be a type
(of kind `[Nat]`). `hs` is a value (of type `[Integer]`). It’s clear here that
the *type* of our network depends on something we can’t write down or decide
until runtime.

### An Existential Crisis

There are a couple of ways to go about this, actually — we’ll go through them,
and we’ll also see at the end how they are all really fundamentally the same
thing.

#### Types hiding behind constructors

Now, having the entire structure of your neural network in the type is nice and
all for cool tricks like `randomNet`…but do you *really* want to work with this
directly? After all, from the user’s perspective, the user really only ever
needs to know `i` and `o`: What vectors the network *expects*, and what vectors
the network *outputs*. In the end, all a (feed-forward) Neural Network really is
is an abstraction over a function `R i -> R o`.

Remember, the main benefits of having the entire structure in the type was to
help us *implement* our functions more safely, with the compiler’s help, and
also for cute return type polymorphism tricks like `randomNet` and `getNet`. The
first type of benefit really doesn’t benefit the *user* of the network.

Imagine that we had written a `Network` type that *didn’t* have the internal
structure in the type —

``` {.haskell}
data OpaqueNet i o
```

Recall that our issue earlier was that we had to write `Network i ??? o`, but we
had no idea what to put in for `???`. But, what if we worked with an
`OpaqueNet i o`, we wouldn’t even care! We wouldn’t have to tell GHC what the
internal structure is.

We can implement it as an “existential” wrapper over `Network`, actually:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L88-89
data OpaqueNet :: Nat -> Nat -> * where
    ONet :: Network i hs o -> OpaqueNet i o

```

So, if you have `net :: Network 6 '[10,6,3] 2`, you can create
`ONet net :: OpaqueNet 6 2`. When you use the `ONet` constructor, the structure
of the hidden layers disappears from the type!

How do we use this type? We *pattern match* on `ONet` to get the net back, and
we can use them:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L91-96
numHiddens :: OpaqueNet i o -> Int
numHiddens = \case ONet n -> go n
  where
    go :: Network i hs o -> Int
    go = \case O _      -> 0
               _ :&~ n' -> 1 + go n'

```

With the *ScopedTypeVariables* extension, we can even bring `hs` back into
scope, as in `ONet (n :: Network i hs o) -> ...`

This pattern is sometimes called the **dependent pair**, because pattern
matching on `ONet` gives yields the hidden existential (`hs`) and also a type
that is based on it (`Network i hs o`). It’s like `hs` “paired” with
`Network i hs o`. Pattern match on the results to give both the type (`hs`)
*and* the data structure. (If we had implemented it as
`ONet :: Sing hs -> Network i hs o -> OpaqueNet i o`, this would be slightly
clearer!)

And here’s the key to making this all work: once you *do* pattern match on
`ONet`, you have to handle the `hs` in a *completely polymorphic way*. You’re
not allowed to assume anything about `hs`…you have to provide a completely
parametrically polymorphic way of dealing with it!

For example, this function is completely *not* ok:

``` {.haskell}
bad :: OpaqueNet i o -> Network i hs o
bad = \case ONet n -> n          -- nope, not ok at all.
```

Why not? Well, a type signature like `OpaqueNet i o -> Network i hs o` means
that the *caller* can decide what `hs` can be — just like
`read :: Read a => String -> a`, where the caller decides what `a` is.

Of course, this *isn’t* the case with the way we’ve written the function…the
function only returns a *specific* `hs` that the *function* decides. The
*caller* has to accommodate whatever is inside `ONet`.

#### The Universal and the Existential

We just brushed here on something at the heart of using existential types in
Haskell: the issue of who has the power to decide what the types will be
instantiated as.

Most polymorphic functions you work with in Haskell are “universally qualified”.
For example, for a function like

``` {.haskell}
map :: (a -> b) -> [a] -> [b]
```

`a` and `b` are universally quantified, which means that the person who *uses*
`map` gets to decide what `a` and `b` are. To be more explicit, that type
signature can be written as:

``` {.haskell}
map :: forall a b. (a -> b) -> [a] -> [b]
```

This means that `map` is defined in a way that will work for *any* `a` and `b`
that the *caller* wants. As a caller, you can request:

``` {.haskell}
map :: (Int -> Bool)    -> [Int]    -> [Bool]
map :: (Double -> Void) -> [Double] -> [Void]
map :: (String -> (Bool -> Char)) -> [String] -> [Bool -> Char]
```

Consequentially, the function has to be implemented in a way that will work for
*any* `a` and `b`. The function’s implementation has the burden of being
flexible enough to handle whatever the caller asks for.

But, for a function like:

``` {.haskell}
foo :: [Int] -> OpaqueNet i o
```

While the caller can choose what `i` and `o` are, the *function* gets to choose
what `hs` (in the hidden `Network i hs o`) is.

If I want to *use* the thing that `foo` returns…then *I* have to be flexible.
*I* have the burden of being flexible enough to handle whatever the *function*
returns.

In summary:

-   For universally quantified types, the *caller* chooses the type being
    instanced, and the *function’s implementation* has to accommodate
    any choice.

-   For existentially quantified types, the *function’s implementation* chooses
    the type being instanced, and the *caller* has to accommodate any choice.

Indeed, we saw earlier that if we ever wanted to *use* the `Network i hs o`
inside the `OpaqueNet i o`, we were forced to deal with it in a parametrically
polymorphic way. We had to be able to handle *any* `hs` that the `ONet` could
throw at us!

#### A familiar friend

I called `OpaqueNet i o` a “dependent pair” earlier, which existentially
quantifies over `hs`. But there’s another common term for it: a **dependent
sum**.

People familiar with Haskell might recognize that “sum types” are `Either`-like
types that can be one thing or another. Sum types are one of the first things
you learn about in Haskell — heck, even `Maybe a` is the sum of `a` and `()`.
Dependent pairs/existential types actually are very similar to `Either`/sum
types, in spirit, and it might help to see the parallel so that you can see that
they’re nothing scary, and that the fundamentals/intuition of working with
existential types in Haskell is no different than working with `Either`!

If I had:

``` {.haskell}
foo :: String -> Either Int Bool
```

I have to handle the result…but I have to handle it for both the case where I
get an `Int` and the case where I get a `Bool`. The *function* gets to pick what
type I have to handle (`Int` or `Bool`), and *I* have to adapt to whatever it
returns. Sound familiar? In fact, you can even imagine that `OpaqueNet i o` as
being just a recursive *Either* over `'[]`, `'[1]`, `'[1,2]`, etc.[^1]

And, remember that the basic way of handling an `Either` and figuring out what
the type of the value is inside is through *pattern matching* on it. You can’t
know if an `Either Int Bool` contains an `Int` or `Bool` until you pattern
match. But, once you do, all is revealed, and GHC lets you take advantage of
knowing the type.

For `OpaqueNet i o`, it’s the same! You don’t know the actual type of the
`Network i hs o` it contains until you *pattern match* on the `Sing hs`! (Or
potentially, the network itself) But, once you pattern match on it, all is
revealed…and GHC lets you take advantage of knowing the type!

### Reification

Time to pull it all together.

For simplicity, let’s re-write `randomNet` the more sensible way — with the
explicit singleton input style:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L60-67
randomNet' :: forall m i hs o. (MonadRandom m, KnownNat i, KnownNat o)
           => Sing hs -> m (Network i hs o)
randomNet' = \case SNil            ->     O <$> randomWeights
                   SNat `SCons` ss -> (:&~) <$> randomWeights <*> randomNet' ss

randomNet :: forall m i hs o. (MonadRandom m, KnownNat i, SingI hs, KnownNat o)
          => m (Network i hs o)
randomNet = randomNet' sing

```

We use `sing :: SingI hs => Sing hs` to go call the `Sing hs ->`-style function
from the `SingI hs =>` one.

Recall that I recommend (personally, and subjectively) a style where your
external API functions (and typeclass instances) are implemented in `SingI a =>`
style, and your internal ones in `Sing a ->` style. This lets all of your
internal functions fit together more nicely (`Sing a ->` style tends to be
easier to write in, especially if you stay in it the entire time) while at the
same time removing the burden of calling with explicit singletons from people
using the functionality externally.[^2] A `Sing a` is a normal Haskell value,
but `SingI hs` is a typeclass instance, and typeclasses in Haskell are magical,
global, potentially incoherent, and not really fun to work with!

Now, we still need to somehow get our list of integers to the type level, so we
can create a `Network i hs o` to stuff into our `ONet`. And for that, the
*singletons* library offers the necessary tooling. It gives us `SomeSing`, which
is a lot like our `OpaqueNet` above, wrapping the `Sing a` inside an existential
data constructor. `toSing` takes the term-level value (for us, an `[Integer]`)
and returns a `SomeSing` wrapping the type-level value (for us, a `[Nat]`). When
we pattern match on the `SomeSing` constructor, we get `a` in scope!

In an ideal world, `SomeSing` would look like this:

``` {.haskell}
data SomeSing :: * -> * where
    SomeSing :: Sing (a :: k) -> SomeSing k
```

And you can have

``` {.haskell}
foo :: SomeSing Bool
foo = SomeSing STrue

bar :: SomeSing Nat
bar = SomeSing (SNat :: Sing 10)
```

But because *singletons* was implemented before the *TypeInType* extension in
GHC 8, it has to be implemented with clunky “Kind Proxies”. In a future version
of *singletons*, they’ll be implemented this way. Right now, in the current
system, `SomeSing STrue :: SomeSing (KProxy :: KProxy Bool)`, and
`bar :: SomeSing (KProxy :: KProxy Nat)`.[^3] However, for the most part, the
actual *usage* of `SomeSing`, so we can ignore this slight wart when we are
actually writing code.

Pattern matching looks like:

``` {.haskell}
main :: IO ()
main = do
    putStrLn "How many cats do you own?"
    c <- readLn :: IO Integer
    case toSing c of
      SomeSing (SNat :: Sing n) -> -- ...
```

Now, inside the case statement branch (the `...`), we have *type* `n :: Nat` in
scope! And by pattern matching on the `SNat` constructor, we also have a
`KnownNat n` instance (As discussed in [previous
part](https://blog.jle.im/entry/practical-dependent-types-in-haskell-1.html#singletons-and-induction)).

(`toSing` works using a simple typeclass mechanism with associated types whose
job is to associate *value*’s types with the kinds of their singletons. It
associates `Bool` the type with `Bool` the kind, `Integer` the type with `Nat`
the kind, `[Integer]` the type with `[Nat]` the kind, etc., and it does it with
straightforward plane jane applications of type families — here’s a [nice
tutorial on type
families](https://ocharles.org.uk/blog/posts/2014-12-12-type-families.html)
courtesy of Oliver Charles.)

We now have enough to write our `randomONet`:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L98-102
randomONet :: (MonadRandom m, KnownNat i, KnownNat o)
           => [Integer]
           -> m (OpaqueNet i o)
randomONet hs = case toSing hs of
                  SomeSing ss -> ONet <$> randomNet' ss

```

This process of bringing a term-level value into the type level is known in
Haskell as **reification**. With this, our original goal is (finally) within
reach:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L157-163
main :: IO ()
main = do
    putStrLn "What hidden layer structure do you want?"
    hs <- readLn
    ONet (net :: Network 10 hs 3) <- randomONet hs
    print net
    -- blah blah stuff with our dynamically generated net

```

#### The Boundary

With the power of existentially quantified types (like in `SomeSing`), we
essentially gained the ability to work with types that depend on runtime
results.

In a way, you can consider the `toSing` and the `SomeSing` as our “boundary”
between the “untyped world” and the “typed world”. This layer (and the process
of reification) cleanly separates the two.

This “boundary” can be thought of as a lot like the boundary we talk about
between “pure” functions and values and “impure” (IO, etc.) ones. We say to
always write as much of your program as possible in the “pure” world, and to
separate and pull out as much logic as you can to be pure logic. That’s sort of
one of the first things you learn about as a Haskell programmer: how to separate
logic that *can* be pure from logic that is “impure” (IO, etc.), and then
“combine them” at the very end, as late as possible.

The common response to this is: “Well, if the final program is going to be IO in
the end anyway, why bother separating out pure and impure parts of your logic?”

But, we know that we gain separation of concerns, the increased ability to
reason with your code and analyze what it does, the compiler’s ability to check
what you write, the limitation of implementations, etc. … all reasons any
Haskeller should be familiar with reciting.

You can think of the general philosophy of working with typed/untyped worlds as
being the same thing. You can write as much of your program as possible in the
“typed” world, like we did in Part 1. Take advantage of the increased ability to
reason with your code, parametric polymorphism helping you *write* your code,
limit your implementations, nab you compiler help, etc. All of those are
benefits of working in the typed world.

Then, write what you must in your “untyped” world, such as dealing with values
that pop up at runtime like the `[Integer]` above.

Finally, at the end, *unite* them at the boundary. Pass the control football
from the untyped world to the typed world!

### Continuation-Based Existentials

There’s another way in Haskell that we work with existential types that can be
more natural and easy to work with in a lot of cases.

Remember that when we pattern match on an existential data type, you have to
work with the values in the constructor in a parametrically polymorphic way. For
example, if we had:

``` {.haskell}
oNetToFoo :: OpaqueNet i o -> Foo
oNetToFoo = \case ONet n -> f n
```

`f` has to take a `Sing hs` and a `Network i hs o`, but deal with it in a way
that works *for all* `hs`. It has to be:

``` {.haskell}
f :: forall hs. Network i hs o -> Foo
```

That is, it can’t be written for *only* `'[5]` or *only* `'[6,3]`…it has to work
for *any* `hs`. That’s the whole “existential vs. universal quantification”
thing we just talked about.

Well, we could really also just skip the data type together and represent an
existential type as something *taking* the continuation `f` and giving it what
it needs.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L125-125
type OpaqueNet' i o r = (forall hs. Network i hs o -> r) -> r

```

“Tell me how you would make an `r` if you had a `Network i hs o` (that works for
any `hs`) and I’ll make it for you!”

(This takes advantage of Rank-N types. If you’re unfamiliar with it, Gregor
Riegler has a [nice
tutorial](http://sleepomeno.github.io/blog/2014/02/12/Explaining-Haskell-RankNTypes-for-all/)
on it.)

This “continuation transformation” is known as formally **skolemization**.[^4]
We can “wrap” a `Network i hs o` into an `OpaqueNet' i o r` pretty
straightforwardly:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L127-128
oNet' :: Network i hs o -> OpaqueNet' i o r
oNet' n = \f -> f n

```

Let’s write a version of `randomONet` that returns a continuation-style
existential, instead:

``` {.haskell}
withRandomONet' :: (MonadRandom m, KnownNat i, KnownNat o)
                => [Integer]
                -> (forall hs. Sing hs -> Network i hs o -> m r)
                -> m r
--         aka, => [Integer]
--              -> OpaqueNet' i o (m r)
withRandomONet' hs f = case toSing hs of
                         SomeSing ss -> do
                           net <- randomNet' ss
                           f ss net
```

But, hey, because we’re skolemizing everything, let’s do it with the skolemized
version of `toSing`, `withSomeSing`:

``` {.haskell}
-- a version of `toSing` that returns a skolemized `SomeSing`
withSomeSing :: [Integer]
             -> (forall (hs :: [Nat]). Sing hs -> r)
             -> r
```

Because why not? Skolemize all the things!

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L130-138
withRandomONet' :: (MonadRandom m, KnownNat i, KnownNat o)
                => [Integer]
                -> (forall hs. Network i hs o -> m r)
                -> m r
--         aka, => [Integer]
--              -> OpaqueNet' i o (m r)
withRandomONet' hs f = withSomeSing hs $ \ss -> do
                         net <- randomNet' ss
                         f net

```

We can use it to do the same things we used the constructor-based existential
for, as well…and, in a way, it actually seems (oddly) more natural.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L165-171
main' :: IO ()
main' = do
    putStrLn "What hidden layer structure do you want?"
    hs <- readLn
    withRandomONet' hs $ \(net :: Network 10 hs 3) -> do
      print net
      -- blah blah stuff with our dynamically generated net

```

You can sort of see that, like the case statement pattern match represented the
lexical “wall”/“boundary” between the untyped and typed world when using
constructor-style existentials, the `... $ \net -> ...` can be thought of the
“wall” for the continuation-style existentials.

A Tale of Two Styles
--------------------

So, we’ve just discussed two ways of doing the same thing, essentially. Two
styles of representing/working with existential types. The two are equivalent,
in that you can always “convert” between one or the other, but the choice of
which one you use/reach for/offer can make a difference in code clarity.

I don’t have much general advice for which one to provide. After working with
both styles a lot (sometimes, libraries only offer one style), you sort of start
to get a feel for which one you like more in which situations. In the end, I
don’t think there are any hard or fast rules. Just use whichever one you feel is
more readable!

That being said, here are some general Pros and Cons that I’ve encountered over
the years. This list is by no means exhaustive.

-   Most obviously, continuation-style doesn’t require you to define a throwaway
    data type/constructor. While new types are cheap in Haskell, they force your
    users to learn a new set of types and constructors for every single
    existential type you return. If you or the library you’re writing
    uses/returns a *lot* of different existentially qualified types, all those
    extra dumb wrappers are a huge hassle.

-   When you have to use several existentials at once, continuation-style is
    much better because each nested existential doesn’t force another level of
    indentation:

    ``` {.haskell}
    foo = withSomeSing x $ \sx ->
          withSomeSing y $ \sy ->
          withSomeSing z $ \sz ->
            -- ...
    ```

    vs.

    ``` {.haskell}
    foo = case toSing x of
            SomeSing sx ->
              case toSing y of
                SomeSing sy ->
                  case toSing z of
                    SomeSing sz ->
                      -- ...
    ```

    Every time you nest a case statement, you actually waste *two* levels of
    indentation, which can be annoying even at 2-space indentation. But you
    don’t need *any* to nest in the continuation style!

-   If you’re working monadically, though, you can take advantage of do notation
    and *ScopedTypeVariables* for a nicer style that doesn’t require any nesting
    at all:

    ``` {.haskell}
    main = do
        ONet n1 <- randomONet [7,5,3] :: IO (OpaqueNet 10 1)
        ONet n2 <- randomONet [5,5,5] :: IO (OpaqueNet 10 1)
        ONet n3 <- randomONet [5,4,3] :: IO (OpaqueNet 10 1)
        hs <- readLn
        ONet (n4 :: Network 10 hs 1) <- randomONet hs
        -- ...
    ```

    Which is arguably nicer than

    ``` {.haskell}
    main = withRandomONet' [7,5,3] $ \n1 ->
           withRandomONet' [5,5,5] $ \n2 ->
           withRandomONet' [5,4,3] $ \n3 -> do
             hs <- readLn
             withRandomONet' hs $ \(n4 :: Network 10 hs 1) -> do
               -- ...
    ```

    A lot of libraries return existentials in `Maybe`’s ([base is
    guilty](http://hackage.haskell.org/package/base-4.9.0.0/docs/GHC-TypeLits.html#v:someNatVal)),
    so it can be useful for those, too!

    This is less useful for things like `toSing` where things are *not* returned
    in a monad. You could wrap it in Identity, but that’s kind of silly:

    ``` {.haskell}
    foo = runIdentity $ do
            SomeSing sx <- Identity $ toSing x
            SomeSing sy <- Identity $ toSing y
            SomeSing sz <- Identity $ toSing z
            return $ -- ...
    ```

-   Constructor-style is necessary for writing typeclass instances. You can’t
    write a `Show` instance for `(forall hs. Network i hs o -> r) -> r`, but you
    can write one for `OpaqueNet i o`. We’ll also be writing `Binary` instances
    later for serialization/deserialization, and we’ll need the wrapper
    for sure.

-   When writing functions that *take* existentials as inputs, the
    constructor-style is arguably more natural.

    For example, we wrote a function to find the number of hidden layers in a
    network earlier:

    ``` {.haskell}
    numHiddens :: OpaqueNet i o -> Int
    ```

    But the continuation-style version would have a slightly messier type:

    ``` {.haskell}
    numHiddens' :: ((forall hs. Network i hs o -> Int) -> Int)
                -> Int
    ```

    Even with with the type synonym, it’s a little weird.

    ``` {.haskell}
    numHiddens' :: OpaqueNet' i o Int -> Int
    ```

    This is why you’ll encounter more functions *returning* continuation-style
    existentials than *taking* them in the wild, for the most part.

These are just general principals, not hard-fast rules. This list reflects my
current progress in my journey towards a dependently typed lifestyle and also
the things come to mind as I write this blog post. If you come back in a month,
you might see more things listed here!

All said, I do find myself very happy when I see that a library I’m using offers
*both* styles for me to use. And I’ve been known to submit PR’s to a library to
have it offer one style or another, if it’s lacking.

Be judicious. If you’re writing a library, don’t spam it with too many throwaway
constructors. If you’re writing an application, be wary of indentation creep.
After a while, you’ll begin to intuitively see which style shines in which
situations! (And, in some case, there might not even be a definitive “better”
style to use.)

Serializing Networks
--------------------

Let’s apply what we learned about existential types and reification to another
simple application: serialization.

### Recap on the Binary Library

Serializing networks of *known* size — whose sizes are statically in their types
— is pretty straightforward. I’m going to be using the
*[binary](https://hackage.haskell.org/package/binary)* library, which offers a
very standard typeclass-based approach for serializing and deserializing data.
There are a lot of tutorials online (and I even [wrote a small
one](https://blog.jle.im/entry/streaming-huffman-compression-in-haskell-part-2-binary.html)
myself a few years ago), but a very high-level view is that the library offers a
typeclass for describing serialization schemes for different types.

In practice, we usually don’t write our own instances from scratch. Instead, we
use GHC’s generics features to give us instances for free:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L24-29
data Weights i o = W { wBiases :: !(R o)
                     , wNodes  :: !(L o i)
                     }
  deriving (Show, Generic)

instance (KnownNat i, KnownNat o) => Binary (Weights i o)

```

For simple types like `Weights`, which simply “contain” serializable things, the
*binary* library is smart enough to write your instances automatically for you!

### Serializing `Network`

Writing `putNet` and `getNet` to put/get `Network`s is pretty nice because the
entire structure is already known ahead of time:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L69-73
putNet :: (KnownNat i, KnownNat o)
       => Network i hs o
       -> Put
putNet = \case O w     -> put w
               w :&~ n -> put w *> putNet n

```

If it’s an `O w`, just serialize the `w`. If it’s a `w :&~ net`, serialize the
`w` then the rest of the `net`. The reason we can get away without any flags is
because we already *know* how many `:&~` layers to expect *just from the type*.
If we want to deserialize/load a `Network 5 '[10,6,3] 2`, we *know* we want
three `(:&~)`’s and one `O` — no need for dynamically sized networks like we had
to handle for lists.

We’ll write `getNet` similarly to how wrote
[`randomNet'`](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L60-63):

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L75-79
getNet :: forall i hs o. (KnownNat i, KnownNat o)
       => Sing hs
       -> Get (Network i hs o)
getNet = \case SNil            ->     O <$> get
               SNat `SCons` ss -> (:&~) <$> get <*> getNet ss

```

We have to “pattern match” on `hs` using singletons to see what constructor we
are expecting to deserialize.

Let’s write our `Binary` instance for `Network`. Of course, we can’t have `put`
or `get` take a `Sing hs` (that’d change the arity/type of the function), so we
have to switch to `SingI`-style had have their `Binary` instances require a
`SingI hs` constraint.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L81-83
instance (KnownNat i, SingI hs, KnownNat o) => Binary (Network i hs o) where
    put = putNet
    get = getNet sing

```

### Serializating `OpaqueNet`

Armed with all that we learned during our long and winding journey through
“run-time types”, writing a serializing plan for `OpaqueNet` is straightforward.
(We are doing it for `OpaqueNet`, the constructor-style existential, because we
can’t directly write instances for the continuation-style one)

Because the complete structure of the network is not in the type, we have to
encode it as a flag in the binary serialization. We can write a simple function
to get the `[Integer]` of a network’s structure:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L54-58
hiddenStruct :: Network i hs o -> [Integer]
hiddenStruct = \case O _    -> []
                     _ :&~ (n' :: Network h hs' o)
                            -> natVal (Proxy @h)
                             : hiddenStruct n'

```

Recall that `natVal :: KnownNat n => Proxy n -> Integer` returns the value-level
`Integer` corresponding to the type-level `n :: Nat`. (I’m also using GHC 8’s
fancy *TypeApplications* syntax, and `Proxy @h` is the same as
`Proxy :: Proxy h`).

It is interesting to note that `natVal` and `hiddenStruct` take type-level
information (`n`, `hs`) and turns them into term-level values (`Integer`s,
`[Integer]`s). In fact, they are kind of the opposites of our reification
functions like `toSing`. Going from the “type level” to the “value level” is
known in Haskell as **reflection**, and is the dual concept of reification. (The
*singletons* library offers reflectors for all of its singletons, as
`fromSing`.)

And that’s all we need!

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L104-109
putONet :: (KnownNat i, KnownNat o)
        => OpaqueNet i o
        -> Put
putONet = \case ONet net -> do
                  put (hiddenStruct net)
                  putNet net

```

Put the structure (as a flag), and then put the network itself.

Now, to deserialize, we want to *load* the list of `Integer`s and reify it back
to the type level to know what type of network we’re expecting to load:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L111-116
getONet :: (KnownNat i, KnownNat o)
        => Get (OpaqueNet i o)
getONet = do
    hs <- get
    withSomeSing hs $ \ss ->
      ONet <$> getNet ss

```

We load our flag, reify it, and once we’re back in the typed land again, we can
do our normal business.

Our final instance:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L118-120
instance (KnownNat i, KnownNat o) => Binary (OpaqueNet i o) where
    put = putONet
    get = getONet

```

#### Exercises

Here are some fun exercises you can try, if you want to test your understanding!
Links are to the solutions.

1.  Implement
    [`putONet'`](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L140-145)
    and
    [`getONet'`](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L147-155)
    using the continuation-style existentials, instead.

2.  Work with an existential wrapper over the *entire* network structure (inputs
    and outputs, too):

    ``` {.haskell}
    !!!dependent-haskell/NetworkTyped2.hs "data SomeNet"
    ```

    (We need the `KnownNat` constraints because of type erasure, to recover the
    original input/output dimensions back once we pattern match)

    And write:

    -   [`randomSNet`](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L181-190)
    -   The [binary
        instance](https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkTyped2.hs#L192-206)
        for `SomeNet`

    Hint: Remember that `toSomeSing` also works for `Integer`s, to get `Sing`s
    for `Nat`s, too!

Dealing with Runtime Types
--------------------------

<!-- sameNat and existentials -->

[^1]: A bit of a stretch, because the set of all `[Nat]`s is non-enumerable and
    uncountable, but you get the picture, right?

[^2]: This is a completely personal style, and I can’t claim to speak for all of
    the Haskell dependent typing community. In fact, I’m not even sure that you
    could even say that there is a consensus at all. But this is the style that
    has worked personally for me in both writing and using libraries! And hey,
    some libraries I’ve seen in the wild even offer *both* styles in their
    external API.

[^3]: Gross, right? Hopefully some day this will be as far behind us as that
    whole Monad/Functor debacle is now!

[^4]: Skolemization is probably one of the coolest words you’ll encounter when
    learning/using Haskell, and sometimes just knowing that you’re “skolemizing”
    something makes you feel cooler. Thank you [Thoralf
    Skolem](https://en.wikipedia.org/wiki/Thoralf_Skolem). If you ever see a
    “rigid, skolem” error in GHC, you can thank him for that too! He is also the
    inspiration behind my decision to name my first-born son Thoralf. (My second
    son’s name will be Curry)
