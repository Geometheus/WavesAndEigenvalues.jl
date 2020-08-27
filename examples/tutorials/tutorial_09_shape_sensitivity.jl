#Simple tube example.
using WavesAndEigenvalues.Helmholtz

##
mesh=Mesh("Rijke_mm.msh",scale=0.001)
case="Rijke_test"
h=1E-13
#mesh=octosplit(mesh);case*="_fine"  #activate this line to refine the mesh

dscrp=Dict()
dscrp["Interior"]=(:interior,())
dscrp["Outlet"]=(:admittance, (:Y,1E15))
hot=false
hot=true
if !hot
    c=ones(length(mesh.tetrahedra))*347.0
    case*="_cold"
    init=510.0
else
    dscrp["Outlet"]=(:admittance, (:Y,1E15)) #specify outlet BC
    γ=1.4 #ratio of specific heats
    ρ=1.225 #density at the reference location upstream to the flame in kg/m^3
    Tu=300.0    #K unburnt gas temperature
    Tb=1200.0    #K burnt gas temperature
    P0=101325.0 # ambient pressure in Pa
    A=pi*0.025^2 # cross sectional area of the tube
    Q02U0=P0*(Tb/Tu-1)*A*γ/(γ-1) #the ratio of mean heat release to mean velocity Q02U0
    x_ref=[0.0; 0.0; -0.00101] #reference point
    n_ref=[0.0; 0.0; 1.00] #directional unit vector of reference velocity
    n=0.01 #interaction index
    τ=0.001 #time delay
    dscrp["Flame"]=(:flame,(γ,ρ,Q02U0,x_ref,n_ref,:n,:τ,n,τ)) #flame dynamics
    R=287.05 # J/(kg*K) specific gas constant (air)
    speedofsound(x,y,z) = z<0. ? sqrt(γ*R*Tu) : sqrt(γ*R*Tb)
    c=generate_field(mesh,speedofsound)
    case*="_hot"
    init=170.0
end




##
L=discretize(mesh, dscrp, c)

##
sol, n, flag = householder(L,init*2*pi,maxiter=14, tol=1E-11,output = true, n_eig_val=3)




##
# identify surface points
surface_points, tri_mask, tet_mask =get_surface_points(mesh)
# compute normal vectors on surface triangles
normal_vectors=get_normal_vectors(mesh)
## DA approach
sens=discrete_adjoint_shape_sensitivity(mesh,dscrp,c,surface_points,tri_mask,tet_mask,L,sol,h=h)
# normalize point sensitivity with directed surface triangle area
normed_sens=normalize_sensitivity(surface_points,normal_vectors,tri_mask,sens)
# boundary-mass-based-normalizations
nsens = bound_mass_normalize(surface_points,normal_vectors,tri_mask,mesh,sens)
# compute sensitivity in unit normal direction
normal_sens = normal_sensitivity(normal_vectors, normed_sens)



## save data
DD=Dict()
DD["real normed_sens1"]=real.(normed_sens[1,:])
DD["real normed_sens2"]=real.(normed_sens[2,:])
DD["real normed_sens3"]=real.(normed_sens[3,:])
DD["real normal_sens"]=real.(normal_sens)
DD["imag normed_sens1"]=imag.(normed_sens[1,:])
DD["imag normed_sens2"]=imag.(normed_sens[2,:])
DD["imag normed_sens3"]=imag.(normed_sens[3,:])
DD["imag normal_sens"]=imag.(normal_sens)
vtk_write_tri(case*"_tri",mesh,DD)


##
mode="[$(string(round((sol.params[:ω]/2/pi),digits=2)))]Hz"
data=Dict()
data["abs_p"*mode]=abs.(sol.v)./maximum(abs.(sol.v))
data["phase_p"*mode]=angle.(sol.v)
data["abs_p_adj"*mode]=abs.(sol.v_adj)./maximum(abs.(sol.v_adj))
data["phase_p_adj"*mode]=angle.(sol.v_adj)
data["real DA x"*mode]=real.(sens[1,:])
data["real DA y"*mode]=real.(sens[2,:])
data["real DA z"*mode]=real.(sens[3,:])
data["imag DA x"*mode]=imag.(sens[1,:])
data["imag DA y"*mode]=imag.(sens[2,:])
data["imag DA z"*mode]=imag.(sens[3,:])
data["real nDA x"*mode]=real.(nsens[1,:])
data["real nDA y"*mode]=real.(nsens[2,:])
data["real nDA z"*mode]=real.(nsens[3,:])
data["imag nDA x"*mode]=imag.(nsens[1,:])
data["imag nDA y"*mode]=imag.(nsens[2,:])
data["imag nDA z"*mode]=imag.(nsens[3,:])
#data["finite difference"*mode]=real.(sens_FD)
#data["central finite difference"]=real.(sens_CFD)
#data["diff DA -- FD"*mode]=abs.((sens.-sens_FD))
vtk_write(case, mesh, data)
## FD approach
fd_sens=forward_finite_differences_shape_sensitivity(mesh,dscrp,c,surface_points,tri_mask,tet_mask,L,sol,h=h)
## write output
mode="[$(string(round((sol.params[:ω]/2/pi),digits=2)))]Hz"
data=Dict()
data["abs_p"*mode]=abs.(sol.v)./maximum(abs.(sol.v))
data["phase_p"*mode]=angle.(sol.v)
data["abs_p_adj"*mode]=abs.(sol.v_adj)./maximum(abs.(sol.v_adj))
data["phase_p_adj"*mode]=angle.(sol.v_adj)
data["real DA x"*mode]=real.(fd_sens[1,:])
data["real DA y"*mode]=real.(fd_sens[2,:])
data["real DA z"*mode]=real.(fd_sens[3,:])
data["imag DA x"*mode]=imag.(fd_sens[1,:])
data["imag DA y"*mode]=imag.(fd_sens[2,:])
data["imag DA z"*mode]=imag.(fd_sens[3,:])
#data["finite difference"*mode]=real.(fd_sens_FD)
#data["central finite difference"]=real.(sens_CFD)
#data["diff DA -- FD"*mode]=abs.((sens.-sens_FD))
vtk_write(case*"_fd", mesh, data)
