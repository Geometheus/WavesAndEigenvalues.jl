```@meta
EditURL = "<unknown>/tutorial_01_rijke_tube.jl"
```

# Tutorial 01 Rijke Tube

A Rijke tube is the most simple thermo-acoustic configuration. It comprises a
tube with an unsteady heat source somewhere inside the tube. This example will
walk you through the basic steps of setting up a Rijke tube in a
Helmholtz-solver stability analysis.

!!! note
    The tutorial reproduces the validation case found in [1].
    To run it yourself you will need the `"Rijke_mm.msh`" file.
    Download it [here](Rijke_mm.msh).

## The Helmholtz equation
The Helmholtz equation is the Fourier transform of the acoustic wave equation.
Given that there is a heat source, it reads:
```math
\nabla\cdot(c^2\nabla \hat p) + \omega^2\hat p = - i \omega (\gamma -1)\hat q
```
Here ``c`` is speed-of-sound-field, ``\hat p`` the (complex) pressure fluctuation
amplitude ``\omega`` the (complex) frequency of the problem, ``i`` the imaginary
unit, ``\gamma`` the ratio of specific heats, and ``\hat q`` the amplitude of the
heat release fluctuation.

(Note that the Fourier transform here follows a ``f'(t) \rightarrow \hat f(\omega)\exp(+i\omega t)`` convention.)

Together with some boundary conditions the Helmholtz equation models
thermo-acoustic resonance in a cavity. The minimum required inputs to specify
a problem are

1. the shape of the domain
2. the speed-of-sound field
3. the boundary conditions

In case of an active flame (``\hat q \neq 0``). We will also need

4. some additional gas properties and
5. a flame response model linking the heat release fluctuations ``\hat q`` to the pressure fluctuations ``\hat p``

Once you completed this tutorial you will know the basic steps of how to
conduct a thermo-acoustic stability analysis

## Header
First you will need to load the Helmholtz solver. The following line brings all
necessary tools into scope:

```@example tutorial_01_rijke_tube
using WavesAndEigenvalues.Helmholtz
```

## Mesh
Now we can load the mesh file. It is the essential piece of information
defining the domain shape . This tutorial's mesh has been specified in mm
which is why we scale it by `0.001` to load the coordinates as m:

```@example tutorial_01_rijke_tube
mesh=Mesh("Rijke_mm.msh",scale=0.001)
```

The displayed info tells us that the mesh features `1006` points as vertices
`1562` (addressable) triangles on its surface and `3380` tetrahedra forming
the tube. Note, that there are currently no lines stored. This is because
line information is only needed when using second-order finite elements. To
save memory this information is only assembled and stored when explicitly
requested. We will come back to this aspect in a later tutorial.

You can also see that the mesh features several named domains such as
`"Interior"`,`"Flame"`, `"Inlet"` and `"Outlet"`. These domains are used to
specify certain conditions for our model.

A model descriptor is always given as a dictionary featureng domain names
as keys and tuples as values. The first tuple entry is a Julia symbol
specifying the operator to be build on the associated domain, while the second
entry is again a tuple holding information that is specific to the chosen
operator.

## Model set-up
For instance, we certainly want to build the wave operator on the entire mesh.
So first, we initialize an empty dictionary

```@example tutorial_01_rijke_tube
dscrp=Dict()
```

And then specify that the wave operator should be build everywhere. For the
given mesh the domain-specifier to address the entire resonant cavity is
`"Interior"` and in general the symbol to create the wave operator is
`:interior`. It requires no options so the options tuple remains empty.

```@example tutorial_01_rijke_tube
dscrp["Interior"]=(:interior, ())
```

## Boundary Conditions
The tube should have a pressure node at its outlet, in order to model an
open-end boundary condition. Boundary conditions are specified in terms of
admittance values. A pressure note corresponds to an infinite admittance.
To represent this on a computer we just give it a crazily high value like
`1E15`. We will also need to specify a variable name for our admittance value.
This will allow to quickly change the value after discretization of the
model by addressing it by this very name. This feature is one of the core
concepts of the solver. As will be demonstrated later.

The complete description of our boundary condition reads

```@example tutorial_01_rijke_tube
dscrp["Outlet"]=(:admittance, (:Y,1E15))
```

You may wonder why we do not specify conditions for the other boundaries of
the model. This is because the discretization is based on Bubnov-Galerkin
finite elements. All unspecified, boundaries will therefore *naturally* be
discretized as solid walls.

## Flame
The Rijke tube's main feature is a domain of heat release. In the current
mesh there is a designated domain `"Flame"` addressing a thin volume at the
center of the tube. We can use this key to specify a flame with simple
n-tau-dynamics. Therefore, we first need to define some basic gas properties.

```@example tutorial_01_rijke_tube
γ=1.4 #ratio of specific heats
ρ=1.225 #density at the reference location upstream to the flame in kg/m^3
Tu=300.0    #K unburnt gas temperature
Tb=1200.0    #K burnt gas temperature
P0=101325.0 # ambient pressure in Pa
A=pi*0.025^2 # cross sectional area of the tube
Q02U0=P0*(Tb/Tu-1)*A*γ/(γ-1) #the ratio of mean heat release to mean velocity Q02U0
```

We will also need to provide the position where the reference velocity has
been taken and the direction of that velocity

```@example tutorial_01_rijke_tube
x_ref=[0.0; 0.0; -0.00101]
n_ref=[0.0; 0.0; 1.00] #must be a unit vector
```

And of course, we need some values for n and tau

```@example tutorial_01_rijke_tube
n=0.0 #interaction index
τ=0.001 #time delay
```

With these values the specification of the flame reads

```@example tutorial_01_rijke_tube
dscrp["Flame"]=(:flame,(γ,ρ,Q02U0,x_ref,n_ref,:n,:τ,n,τ))
```

Note that the order of the values in the options tuple is important. Also note
that we assign the symbols `:n`and `:τ` for later analysis.

## Speed of Sound
The description of the Rijke tube model is nearly complete. We just need to
specify the speed of sound field.  For this example, the field is fairly
simple and can be specified analytically, using the `generate_field` function
and a custom three-parameter function.

```@example tutorial_01_rijke_tube
R=287.05 # J/(kg*K) specific gas constant (air)
function speedofsound(x,y,z)
    if z<0.
        return sqrt(γ*R*Tu)#m/s
    else
        return sqrt(γ*R*Tb)#m/s
    end
end
c=generate_field(mesh,speedofsound)
```

Note that in more elaborate models, you may read the field `c` from a file
containing simulation or experimental data, rather than specifying it
analytically.

## Model Discretization
Now we have all ingredients together and we can discretize the model.

```@example tutorial_01_rijke_tube
L=discretize(mesh,dscrp,c)
```

The return value `L` here is a family of linear operators. The shown info
is an algebraic representation of the family plus a list of associated
parameters. You might have noticed that the list contains all parameters that
have been specified during the model description (`n`,`τ`,`Y`). However,
there are also two parameters that were added by default: `ω` and `λ`. `ω` is
the complex frequency of the model and `λ` an auxiliary value that is
important for the eigenfrequency computation.
## Solving the Model
### Global Solver
We can solve the model for some eigenvalues using one of the eigenvalue
solvers. The package provides you with two types of eigenvalue solvers. A global
contour-integration-based solver. That finds you all eigenvalues inside of a
specified contour Γ in the complex plane.

```@example tutorial_01_rijke_tube
Γ=[150.0+5.0im, 150.0-5.0im, 1000.0-5.0im, 1000.0+5.0im].*2*pi #corner points for the contour (in this case a rectangle)
Ω, P = beyn(L,Γ,l=5,N=256, output=true)
```

The found eigenvalues are stored in the array `Ω`. The corresponding
eigenvectors are the columns of `P`.
The huge advantage of the global eigenvalue solver is that it finds you
multiple eigenvalues. Nonetheless, its accuracy may be low and sometimes it
provides you with outright wrong solutions.
However, for the current case the method works as we can verify that in our
search window there are two eigenmodes oscilating at 272 and 695 Hz
respectively:

```@example tutorial_01_rijke_tube
for ω in Ω
    println("Frequency: $(ω/2/pi)")
end
```

### Local Solver
To get high accuracy eigenvalues , there are also local iterative eigenvalue
solvers. Based on an initial guess, they only find you one eigenvalue at a time
but with machine-precise accuracy. One of these solvers is based on the method
of successive linear problems (mslp). You call it as follows:

```@example tutorial_01_rijke_tube
sol,nn,flag=mslp(L,250*2*pi,output=true);
nothing #hide
```

The return values of this solver are a solution object `sol`, the number of
iterations `nn` performed by the solver and an error flag `flag` providing
information on the quality of the solution. If `flag==0` the solution has
converged. If `flag<0` something went wrong. And if `flag>0`... well, probably
the solution is fine but you should check it.

In the current case the flag is 1 indicating that the maximum number of
iterations has been reached. This is because we haven't specified a stopping
criterion and the iteration just ran for the maximum number of iterations.
Nevertheless, the 272 Hz mode is correct. Indeed, as you can see from the
printed output it already converged to machine-precision after 5 iterations.

## Changing a specified parameter.

Remember that we have specified the parameters `Y`,`n`, and `τ`?. We can change
these easily without rediscretizing our model. For instance currently `n==0.0`
so the solution is purely acoustic. The effect of the flame just enters the
problem via the speed of sound field (this is known as passive flame). By
setting the interaction index to `1.0` we activate the flame.

```@example tutorial_01_rijke_tube
L.params[:n]=1
```

Now we can just solve the model again to get the active solutions

```@example tutorial_01_rijke_tube
sol_actv,nn,flag=mslp(L,245*2*pi-82im*2*pi,output=true,order=3);
nothing #hide
```

The eigenfrequency is now complex:

```@example tutorial_01_rijke_tube
sol_actv.params[:ω]/2/pi
```

with a growth rate `-imag(sol_actv.params[:ω]/2/pi)≈  59.22`

Instead of recomputing the eigenvalue by one of the solvers. We can also
approximate the eigenvalue as a function of one of the model parameters
utilizing high-order perturbation theory. For instance this gives you
the 30th order diagonal Padé estimate expanded from the passive solution.

```@example tutorial_01_rijke_tube
perturb_fast!(sol,L,:n,16) #compute the coefficients
freq(n)=sol(:n,n,8,8)/2/pi #create some function for convenience
freq(1) #evaluate the function at any value for `n` you are interested in.
```

The method is slow when only computing one eigenvalue. But its computational
costs are almost constant when computing multiple eigenvalues. Therefore,
for larger parametric studies this is clearly the method of choice.

## VTK Output for Paraview

To visualize your solutions you can store them as `"*.vtu"` files to open
them with paraview. Just, create a dictionary, where your modes are stored as
fields.

```@example tutorial_01_rijke_tube
data=Dict()
data["speed_of_sound"]=c
data["abs"]=abs.(sol_actv.v)/maximum(abs.(sol_actv.v)) #normalize so that max=1
data["phase"]=angle.(sol_actv.v)

vtk_write("tutorial_01", mesh, data) # Write the solution to paraview
```

The `vtk_write` function automatically sorts your data by its interpolation
scheme. Data that is constant on a tetrahedron will be written to a file
`*_const.vtu`, data that is linearly interpolated on a tetrahedron will go
to `*_lin.vtu`, and data that is quadratically interpolated to `*_quad.vtu`.
The current example uses constant speed of sound on a tetrahedron and linear
finite elements for the discretization of p. Therefore, two files are
generated, namely `tutorial_01_const.vtu` containing the speed-of-sound field
and `tutorial_01_lin.vtu` containing the mode shape. Open them with paraview
and have a look!.

## Summary

You learnt how to set-up a simple Rijke-tube study. This  already introduced
all basic steps that are needed to work with the Helmholtz solver. However,
there are a lot of details you can fine tune and even features that weren't
mentioned in this tutorial. The next tutorials will introduce these aspects in
more detail.

## References

[1] F. Nicoud, L. Benoit, and C. Sensiau, Acoustic Modes in Combustors with Complex Impedances and Multidimensional Active Flames, AIAA, 2007, [doi:10.2514/1.24933](https://doi.org/10.2514/1.24933)

---

*This page was generated using [Literate.jl](https://github.com/fredrikekre/Literate.jl).*

