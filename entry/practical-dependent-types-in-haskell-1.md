Practical Dependent Types in Haskell: Type-Safe Neural Networks
===============================================================

(Originally posted by Justin Le [https://blog.jle.im/])

Whether you like it or not, programming with dependent types in Haskell
moving slowly but steadily to the mainstream of Haskell programming. In
the current state of Haskell education, dependent types are often
considered topics for “advanced” Haskell users. However, I can
definitely foresee a day where the ease of use of modern Haskell
libraries relying on dependent types as well as their ubiquitousness
forces programming with dependent types to be an integral part of
regular intermediate (or even beginner) Haskell education, as much as
Traversable or Maps.

However, I feel like most “dependent typing” tutorials I see around the
internet focus on things like proofs and theorems, instead of directly
jumping into how they can be used to help you in your current coding
now.

So, the point of this post is to show some practical examples of using
dependent types in the real world, and to also walk through the “why”
and high-level philosophy of the way you structure your Haskell
programs. It’ll also hopefully instill an intuition of a dependently
typed work flow of “exploring” how dependent types can help your current
programs.

The first project in this series will build up to type-safe
**[artificial neural
network](https://en.wikipedia.org/wiki/Artificial_neural_network)**
implementations. Hooray!

There are other great tutorials I’d recommend online if you want to
explore dependent types in Haskell further, including [this great
servant
“tutorial”](http://www.well-typed.com/blog/2015/11/implementing-a-minimal-version-of-haskell-servant/).
Also, I should provide a disclaimer — I’m also currently exploring all
of this as I’m going along too. It’s a wild world out there. Join me and
let’s be a part of the frontier!

Neural Networks
---------------

[Artificial neural
networks](https://en.wikipedia.org/wiki/Artificial_neural_network) have
been somewhat of a hot topic in computing recently. At their core they
involve matrix multiplication and manipulation, so they do seem like a
good candidate for a dependent types. Most importantly, implementations
of training algorithms (like back-propagation) are tricky to implement
correctly — despite being simple, there are many locations where
accidental bugs might pop up when multiplying the wrong matrices, for
example.

However, it’s not always easy to gauge before-the-fact what would or
would not be a good candidate for adding dependent types to, and often
times, it can be considered premature to start off with “as powerful
types as you can”. So we’ll walk through a simple implementation
*without*, and see all of the red flags that hint that you might want to
start considering stronger types.

Vanilla Types
-------------

![Feed-forward ANN
architecture](/img/entries/dependent-haskell-1/ffneural.png "Feed-forward ANN architecture")

We’re going to be implementing a feed-forward neural network, with
back-propagation training. A feed-forward neural network consists
structurally of layers of “nodes”, each connected to the each of the
nodes of the previous layer and each of the nodes of the next layer. The
most important feature of the network itself is the “strength” of these
connections, called “weights”. To make a prediction, each node takes, as
an input, the weighted sum of all of the outputs of the previous layer,
weighted by the connection weights (plus an additional “bias” shift). It
then outputs a function of this weighted sum, $f(x)$, to be used by all
of the nodes of the next layer. At the high-level, the user feeds in an
input vector to the top-level nodes, the network processes these
layer-by-layer, and the result of the final nodes is what is taken as
the network’s output. The “goal” of designing/training a network is to
somehow pick the right set of weights that will give the output that you
want for the given input.

A picture is worth a thousand words, so the following equation
demonstrates things nicely:

$$
y_j = b_j + \sum_i^m w_{ij} x_i
$$

$$
o_j = f(y_j)
$$

Which says that the *j*-th result of the output vector comes from the
*j\_*-th bias term, and a sum of all of the outputs of the previous
layer (the *x*-s). After adding the bias and previous layer’s output,
you apply the logistic function to the result.

Stated as matrices and vectors, the formula for $\mathbf{y}$ looks like
this:

$$
\mathbf{y} = \mathbf{b} + \hat{W} \mathbf{x}
$$

While it’s nice to think about neural networks in terms of their nodes,
it makes more sense computationally to only identify a network by simply
the matrices of weights alone — let’s imagine one “layer”, which is
actually a matrix of weights from one layer to another:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkUntyped.hs#L0-0
Key not found: data Weights
```

Now, a `Weights` linking a layer of $n$ nodes to a layer of $m$ nodes
will have a bias vector of size $m$ (the bias shift for each of the
output nodes) and a weight matrix of size $m \times n$.

(We’re using the `Matrix` type from the awesome
*[hmatrix](http://hackage.haskell.org/package/hmatrix)* library for
linear algebra, implemented using blas/lapack under the hood)

Now let’s represent a feed-forward network:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkUntyped.hs#L10-13
data Network = O !(Matrix Double)
             | !(Matrix Double) :&~ !Network
  deriving (Show, Eq)
infixr 5 :&~

```

So a network with one input layer, two inner layers, and one output
layer would look like:

``` {.haskell}
i2h :&~ h2h :&~ O h2o
```

Where the first component is the weights from the input to the first
hidden layer, the second is the weights from the first hidden layer to
the second, and the final is the weights from the second hidden layer to
the outputs.

TODO: graphs using diagrams?

We can write simple procedures, like generating random networks:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkUntyped.hs#L28-35
randomWeights :: MonadRandom m => Int -> Int -> m (Matrix Double)
randomWeights i o = do
    s <- getRandom
    return $ uniformSample s o (replicate i (-1, 1))

randomNet :: MonadRandom m => Int -> [Int] -> Int -> m Network
randomNet i [] o     =     O <$> randomWeights i o
randomNet i (h:hs) o = (:&~) <$> randomWeights i h <*> randomNet h hs o

```

(`randomVector` and `uniformSample` are from the *hmatrix* library,
generating random vectors and matrices from a random `Int` seed. We
configure them to generate them with numbers between -1 and 1)

And now a function to “run” our network on a given input vector:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/dependent-haskell/NetworkUntyped.hs#L0-26
logistic :: Double -> Double
logistic x = 1 / (1 + exp (-x))

Key not found: runLayer
runNet :: Network -> Vector Double -> Vector Double
runNet (O w)      !v = logistic `cmap` (w #> v)
runNet (w :&~ n') !v = let v' = logistic `cmap` (w #> v)
                       in  runNet n' v'

```

(`#>` is matrix-vector multiplication)

TODO: examples of running

If you’re a normal programmer, this might seem perfectly fine. If you
are a Haskell programmer, you should already be having heart attacks.
Let’s imagine all of the bad things that could happen:

-   How do we even know that each subsequent matrix in the network is
    “compatible”? We want the outputs of one matrix to line up with the
    inputs of the next, but there’s no way to know unless we have “smart
    constructors” to check while we add things. But it’s possible to
    build a bad network, and things will just explode at runtime.

-   How do we know the size vector the network expects? What stops you
    from sending in a bad vector at run-time and having everything
    explode?

-   How do we verify that we have implemented `runLayer` and `runNet` in
    a way that they won’t suddenly fail at runtime? We write `l #> v`,
    but how do we know that it’s even correct? We can it prove
    ourselves, but the compiler won’t help us.

Now, let’s try implementing back-propagation:

``` {.haskell}
train :: Vector Double -> Vector Double -> Network -> Network
train i o = go i
  where
    go :: Vector Double -> Network -> (Vector Double, Network)
    go = undefined
```
