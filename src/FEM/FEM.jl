#local coordinate transformation type
struct CooTrafo
        trafo
        inv
        det
        orig
end
#constructor
function CooTrafo(X)
        dim=size(X)
        J=Array{Float64}(undef,dim[1],dim[1])
        orig=X[:,end]
        J[:,1:dim[2]-1]=X[:,1:end-1].-X[:,end]
        if dim[2]==3 #surface triangle #TODO:implement lines and all dimensions
                n=LinearAlgebra.cross(J[:,1],J[:,2])
                J[:,end]=n./LinearAlgebra.norm(n)
        end
        Jinv=LinearAlgebra.inv(J)
        det=LinearAlgebra.det(J)
        CooTrafo(J,Jinv,det,orig)
end
function create_indices(smplx)
    ii=Array{Int64}(undef,length(smplx),length(smplx))
    for i=1:length(smplx)
        for j=1:length(smplx)
            ii[i,j]=smplx[i]
        end
    end

    jj=ii'
    return ii, jj
end
function create_indices(elmnt1,elmnt2)
    ii=Array{Int64}(undef,length(elmnt1),length(elmnt2))
    jj=Array{Int64}(undef,length(elmnt1),length(elmnt2))
    for i=1:length(elmnt1)
        for j=1:length(elmnt2)
            ii[i,j]=elmnt1[i]
            jj[i,j]=elmnt2[j]
        end
    end
    return ii, jj
end



## the following two functions should be eventually moved to meshutils once the revision of FEM is done.
import ..Meshutils: get_line_idx, find_smplx, insert_smplx!
function collect_triangles(mesh::Mesh)
    inner_triangles=[]
    for tet in mesh.tetrahedra
        for tri in [tet[[1,2,3]],tet[[1,2,4]],tet[[1,3,4]],tet[[2,3,4]] ]
            idx=find_smplx(mesh.triangles,tri) #returns 0 if triangle is not in mesh.triangles
            #this mmay be misleading. Better strategy is to count the occurence of all triangles
            # if they occure once its an inner, if they occure twice its outer.
            #This can be done quite easily. By populating a list of innertriangles and moving
            # an inner triangle to a list of outer triangles when its detected to be already in the list
            #of inner triangles. Avoiding three (or higher multiples) of occurence
            # in a sanity check can be done by first checking the list on inner triangles
            # for no occurence.
            # Best moment to do this is after reading the raw lists from file.
            if idx==0
                insert_smplx!(inner_triangles,tri)
            end
        end
    end
    return inner_triangles
end

##

#TODO: write function aggregate_elements(mesh, idx el_type=:lin) for a single element
# and integrate this as method to the Mesh type
##
"""
    triangles, tetrahedra, dim = aggregate_elements(mesh,el_type)

Agregate lists (`triangles` and `tetrahedra`) of lists of indexed degrees of freedom
for unstructured tetrahedral meshes. `dim` is the total number of DoF in the
mesh featured by the requested element-type (`el_type`). Available element types
are `:lin` for first order elements (the default), `:quad` for second order elements,
and `:herm` for  Hermitian elements.
"""
function aggregate_elements(mesh::Mesh, el_type=:lin)
    N_points=size(mesh.points)[2]
    if (el_type in (:quad,:herm) ) &&  length(mesh.lines)==0
        collect_lines!(mesh)
    end

    if el_type==:lin
        tetrahedra=mesh.tetrahedra
        triangles=mesh.triangles
        dim=N_points
    elseif el_type==:quad
        triangles=Array{Array{UInt32,1}}(undef,length(mesh.triangles))
        tetrahedra=Array{Array{UInt32,1}}(undef,length(mesh.tetrahedra))
        tet=Array{UInt32}(undef,10)
        tri=Array{UInt32}(undef,6)
        for (idx,smplx) in enumerate(mesh.tetrahedra)
            tet[1:4]=smplx[:]
            tet[5]=get_line_idx(mesh,smplx[[1,2]])+N_points#find_smplx(mesh.lines,smplx[[1,2]])+N_points #TODO: type stability
            tet[6]=get_line_idx(mesh,smplx[[1,3]])+N_points
            tet[7]=get_line_idx(mesh,smplx[[1,4]])+N_points
            tet[8]=get_line_idx(mesh,smplx[[2,3]])+N_points
            tet[9]=get_line_idx(mesh,smplx[[2,4]])+N_points
            tet[10]=get_line_idx(mesh,smplx[[3,4]])+N_points
            tetrahedra[idx]=copy(tet)
        end
        for (idx,smplx) in enumerate(mesh.triangles)
            tri[1:3]=smplx[:]
            tri[4]=get_line_idx(mesh,smplx[[1,2]])+N_points
            tri[5]=get_line_idx(mesh,smplx[[1,3]])+N_points
            tri[6]=get_line_idx(mesh,smplx[[2,3]])+N_points
            triangles[idx]=copy(tri)
        end
        dim=N_points+length(mesh.lines)
    elseif el_type==:herm
        #if mesh.tri2tet[1]==0xffffffff
        #    link_triangles_to_tetrahedra!(mesh)
        #end
        inner_triangles=collect_triangles(mesh) #TODO integrate into mesh structure
        triangles=Array{Array{UInt32,1}}(undef,length(mesh.triangles))
        tetrahedra=Array{Array{UInt32,1}}(undef,length(mesh.tetrahedra))
        tet=Array{UInt32}(undef,20)
        tri=Array{UInt32}(undef,13)
        for (idx,smplx) in enumerate(mesh.triangles)
            tri[1:3]  =  smplx[:]
            tri[4:6]  =  smplx[:].+N_points
            tri[7:9]  =  smplx[:].+2*N_points
            tri[10:12]  =  smplx[:].+3*N_points
            fcidx     =  find_smplx(mesh.triangles,smplx)
            if fcidx !=0
                tri[13]   =  fcidx+4*N_points
            else
                tri[13]   =  find_smplx(inner_triangles,smplx)+4*N_points+length(mesh.triangles)
            end
            triangles[idx]=copy(tri)
        end
        for (idx, smplx) in enumerate(mesh.tetrahedra)
            tet[1:4] = smplx[:]
            tet[5:8] = smplx[:].+N_points
            tet[9:12] = smplx[:].+2*N_points
            tet[13:16]= smplx[:].+3*N_points

            for (jdx,tria) in enumerate([smplx[[2,3,4]],smplx[[1,3,4]],smplx[[1,2,4]],smplx[[1,2,3]]])
                fcidx     =  find_smplx(mesh.triangles,tria)
                if fcidx !=0
                    tet[16+jdx]   =  fcidx+4*N_points
                else
                    fcidx=find_smplx(inner_triangles,tria) #TODO: Use the new int_triangles field in mesh
                    if fcidx==0
                        println("Error, face not found!!!")
                        return nothing
                    end
                    tet[16+jdx]   =  fcidx+4*N_points+length(mesh.triangles)
                end
            end
            tetrahedra[idx]=copy(tet)
        end
        dim=4*N_points+length(mesh.triangles)+length(inner_triangles)
    else
        println("Error: element order $(:el_type) not defined!")
        return nothing
    end
    return triangles, tetrahedra, dim
end
##



function recombine_hermite(J::CooTrafo,M)
        A=zeros(ComplexF64,size(M))
        J=J.trafo
        if size(M)==(20,20)
                valpoints=[1,2,3,4,17,18,19,20] #point indices where value is 1 NOT the derivative!
                # entires that are based on these points only need no recombination
                for i =valpoints
                        for j=valpoints
                                A[i,j]=copy(M[i,j]) #TODO: Chek whetehr copy is needed or even deepcopy
                        end
                end

                #now recombine entries that are based on derivativ points with value points
                for k=0:3
                        A[5+k,valpoints]+=M[5+k,valpoints].*J[1,1]+M[9+k,valpoints].*J[1,2]+M[13+k,valpoints].*J[1,3]
                        A[9+k,valpoints]+=M[5+k,valpoints].*J[2,1]+M[9+k,valpoints].*J[2,2]+M[13+k,valpoints].*J[2,3]
                        A[13+k,valpoints]+=M[5+k,valpoints].*J[3,1]+M[9+k,valpoints].*J[3,2]+M[13+k,valpoints].*J[3,3]

                        A[valpoints,5+k]+=M[valpoints,5+k].*J[1,1]+M[valpoints,9+k].*J[1,2]+M[valpoints,13+k].*J[1,3]
                        A[valpoints,9+k]+=M[valpoints,5+k].*J[2,1]+M[valpoints,9+k].*J[2,2]+M[valpoints,13+k].*J[2,3]
                        A[valpoints,13+k]+=M[valpoints,5+k].*J[3,1]+M[valpoints,9+k].*J[3,2]+M[valpoints,13+k].*J[3,3]
                end

                #finally recombine entries based on derivative points with derivative points
                for i = 5:16
                        if i in (5,6,7,8) #dx
                                Ji=J[1,:]
                        elseif i in (9,10,11,12) #dy
                                Ji=J[2,:]
                        elseif i in (13,14,15,16) #dz
                                Ji=J[3,:]
                        end
                        if i in (5,9,13)
                                idcs=[5,9,13]
                        elseif i in (6,10,14)
                                idcs=[6,10,14]
                        elseif i in (7,11,15)
                                idcs=[7,11,15]
                        elseif i in (8,12,16)
                                idcs=[8,12,16]
                        end
                        for j = 5:16
                                if j in (5,6,7,8) #dx
                                        Jj=J[1,:]
                                elseif j in (9,10,11,12) #dy
                                        Jj=J[2,:]
                                elseif j in (13,14,15,16) #dz
                                        Jj=J[3,:]
                                end
                                if j in (5,9,13)
                                        jdcs=[5,9,13]
                                elseif j in (6,10,14)
                                        jdcs=[6,10,14]
                                elseif j in (7,11,15)
                                        jdcs=[7,11,15]
                                elseif j in (8,12,16)
                                        jdcs=[8,12,16]
                                end

                                #actual recombination
                                for (idk,k) in enumerate(idcs)
                                        for (idl,l) in enumerate(jdcs)
                                                A[i,j]+=Ji[idk]*Jj[idl]*M[k,l]
                                        end
                                end
                        end

                end
                return A
        elseif length(M)==20
                valpoints=[1,2,3,4,17,18,19,20] #point indices where value is 1 NOT the derivative!
                # entires that are based on these points only need no recombination
                for i =valpoints
                        A[i]=copy(M[i]) #TODO: Chek whether copy is needed or even deepcopy
                end
                #now recombine entries that are based on derivativ points with value points
                for k=0:3
                        A[5+k]+=M[5+k].*J[1,1]+M[9+k].*J[1,2]+M[13+k].*J[1,3]
                        A[9+k]+=M[5+k].*J[2,1]+M[9+k].*J[2,2]+M[13+k].*J[2,3]
                        A[13+k]+=M[5+k].*J[3,1]+M[9+k].*J[3,2]+M[13+k].*J[3,3]
                end
                return A
        elseif size(M)==(13,13)
                valpoints=[1,2,3,13]#point indices where value is 1 NOT the derivative!
                # entires that are based on these points only need no recombination
                for i =valpoints
                        for j=valpoints
                                A[i,j]=copy(M[i,j]) #TODO: Chek whetehr copy is needed or even deepcopy
                        end
                end
                #now recombine entries that are based on derivative points with value points
                for k=0:2
                        A[4+k,valpoints]+=M[4+k,valpoints].*J[1,1]+M[7+k,valpoints].*J[1,2]
                        A[7+k,valpoints]+=M[4+k,valpoints].*J[2,1]+M[7+k,valpoints].*J[2,2]
                        A[10+k,valpoints]+=M[4+k,valpoints].*J[3,1]+M[7+k,valpoints].*J[3,2]

                        A[valpoints,4+k]+=M[valpoints,4+k].*J[1,1]+M[valpoints,7+k].*J[1,2]
                        A[valpoints,7+k]+=M[valpoints,4+k].*J[2,1]+M[valpoints,7+k].*J[2,2]
                        A[valpoints,10+k]+=M[valpoints,4+k].*J[3,1]+M[valpoints,7+k].*J[3,2]
                end
                #finally recombine entries based on derivative points with derivative points
                for i = 4:12
                        if i in (4,5,6) #dx
                                Ji=J[1,:]
                        elseif i in (7,8,9) #dy
                                Ji=J[2,:]
                        elseif i in (10,11,12) #dz
                                Ji=J[3,:]
                        end
                        if i in (4,7,10)
                                idcs=[4,7]
                        elseif i in (5,8,11)
                                idcs=[5,8]
                        elseif i in (6,9,12)
                                idcs=[6,9]
                        #elseif i in (8,12,16)
                        #        idcs=[8,12,16]
                        end
                        for j = 4:12
                                if j in (4,5,6) #dx
                                        Jj=J[1,:]
                                elseif j in (7,8,9) #dy
                                        Jj=J[2,:]
                                elseif j in (10,11,12) #dz
                                       Jj=J[3,:]
                                end
                                if j in (4,7,10)
                                        jdcs=[4,7]
                                elseif j in (5,8,11)
                                        jdcs=[5,8]
                                elseif j in (6,9,12)
                                        jdcs=[6,9]
                                #elseif j in (8,12,16)
                                #        jdcs=[8,12,16]
                                end

                                #actual recombination
                                for (idk,k) in enumerate(idcs)
                                        for (idl,l) in enumerate(jdcs)
                                                A[i,j]+=Ji[idk]*Jj[idl]*M[k,l]
                                        end
                                end
                        end

                end

                return A


        elseif length(M)==13
                valpoints=(1,2,3,13)
                for i in valpoints
                        A[i]=copy(M[i])
                end

                #diffpoints=(4,5,6,7,8,9)
                for k in 0:2
                        A[4+k]=J[1,1]*M[4+k]+J[1,2]*M[7+k]
                        A[7+k]=J[2,1]*M[4+k]+J[2,2]*M[7+k]
                        A[10+k]=J[3,1]*M[4+k]+J[3,2]*M[7+k]
                end
                return A
        end

        return nothing #force crash if input format is not supported
end

function s43diffc1(J::CooTrafo,c,d)
        c1,c2,c3,c4=c
        return (c1-c4)*J.inv[d,1]+(c2-c4)*J.inv[d,2]+(c3-c4)*J.inv[d,3]
end
function s43diffc2(J::CooTrafo,c,d)
        dx = [3.0 0.0 0.0 1.0 0.0 0.0 -4.0 0.0 0.0 0.0 ;
        -1.0 0.0 0.0 1.0 4.0 0.0 0.0 0.0 -4.0 0.0 ;
        -1.0 0.0 0.0 1.0 0.0 4.0 0.0 0.0 0.0 -4.0 ;
        -1.0 0.0 0.0 -3.0 0.0 0.0 4.0 0.0 0.0 0.0 ;
        ]

        dy = [0.0 -1.0 0.0 1.0 4.0 0.0 -4.0 0.0 0.0 0.0 ;
        0.0 3.0 0.0 1.0 0.0 0.0 0.0 0.0 -4.0 0.0 ;
        0.0 -1.0 0.0 1.0 0.0 0.0 0.0 4.0 0.0 -4.0 ;
        0.0 -1.0 0.0 -3.0 0.0 0.0 0.0 0.0 4.0 0.0 ;
        ]

        dz = [0.0 0.0 -1.0 1.0 0.0 4.0 -4.0 0.0 0.0 0.0 ;
        0.0 0.0 -1.0 1.0 0.0 0.0 0.0 4.0 -4.0 0.0 ;
        0.0 0.0 3.0 1.0 0.0 0.0 0.0 0.0 0.0 -4.0 ;
        0.0 0.0 -1.0 -3.0 0.0 0.0 0.0 0.0 0.0 4.0 ;
        ]

        return dx*c*J.inv[d,1]+dy*c*J.inv[d,2]+dz*c*J.inv[d,3]
end

function s43diffch(J::CooTrafo,c,d)
        dx= [0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        3.25 1.75 0.0 1.75 -0.75 0.5 0.0 0.25 0.75 -0.5 0.0 0.25 0.0 0.0 0.0 0.0 0.0 0.0 -6.75 0.0 ;
        3.25 0.0 1.75 1.75 -0.75 0.0 0.5 0.25 0.0 0.0 0.0 0.0 0.75 0.0 -0.5 0.25 0.0 -6.75 0.0 0.0 ;
        1.5 0.0 0.0 -1.5 -0.25 0.0 0.0 -0.25 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        -1.75 0.0 0.0 1.75 0.5 0.0 0.0 0.0 -0.25 0.0 0.0 0.25 -0.25 0.0 0.0 0.25 -6.75 0.0 0.0 6.75 ;
        -1.75 -1.75 0.0 -3.25 0.5 0.0 0.0 0.0 -0.25 0.5 0.0 -0.75 0.0 0.0 0.0 0.0 0.0 0.0 6.75 0.0 ;
        -1.75 0.0 -1.75 -3.25 0.5 0.0 0.0 0.0 0.0 0.0 0.0 0.0 -0.25 0.0 0.5 -0.75 0.0 6.75 0.0 0.0 ;
        ]

        dy=[0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        1.75 3.25 0.0 1.75 -0.5 0.75 0.0 0.25 0.5 -0.75 0.0 0.25 0.0 0.0 0.0 0.0 0.0 0.0 -6.75 0.0 ;
        0.0 -1.75 0.0 1.75 0.0 -0.25 0.0 0.25 0.0 0.5 0.0 0.0 0.0 -0.25 0.0 0.25 0.0 -6.75 0.0 6.75 ;
        -1.75 -1.75 0.0 -3.25 0.5 -0.25 0.0 -0.75 0.0 0.5 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 6.75 0.0 ;
        0.0 3.25 1.75 1.75 0.0 0.0 0.0 0.0 0.0 -0.75 0.5 0.25 0.0 0.75 -0.5 0.25 -6.75 0.0 0.0 0.0 ;
        0.0 1.5 0.0 -1.5 0.0 0.0 0.0 0.0 0.0 -0.25 0.0 -0.25 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        0.0 -1.75 -1.75 -3.25 0.0 0.0 0.0 0.0 0.0 0.5 0.0 0.0 0.0 -0.25 0.5 -0.75 6.75 0.0 0.0 0.0 ;
        ]

        dz=[0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 0.0 ;
        0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 0.0 ;
        0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 1.0 0.0 0.0 0.0 0.0 ;
        0.0 0.0 -1.75 1.75 0.0 0.0 -0.25 0.25 0.0 0.0 -0.25 0.25 0.0 0.0 0.5 0.0 0.0 0.0 -6.75 6.75 ;
        1.75 0.0 3.25 1.75 -0.5 0.0 0.75 0.25 0.0 0.0 0.0 0.0 0.5 0.0 -0.75 0.25 0.0 -6.75 0.0 0.0 ;
        -1.75 0.0 -1.75 -3.25 0.5 0.0 -0.25 -0.75 0.0 0.0 0.0 0.0 0.0 0.0 0.5 0.0 0.0 6.75 0.0 0.0 ;
        0.0 1.75 3.25 1.75 0.0 0.0 0.0 0.0 0.0 -0.5 0.75 0.25 0.0 0.5 -0.75 0.25 -6.75 0.0 0.0 0.0 ;
        0.0 -1.75 -1.75 -3.25 0.0 0.0 0.0 0.0 0.0 0.5 -0.25 -0.75 0.0 0.0 0.5 0.0 6.75 0.0 0.0 0.0 ;
        0.0 0.0 1.5 -1.5 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 0.0 -0.25 -0.25 0.0 0.0 0.0 0.0 ;
        ]

        for i=1:10
                dx[i,:]=recombine_hermite(J,dx)
                dy[i,:]=recombine_hermite(J,dy)
                dz[i,:]=recombine_hermite(J,dz)
        end

        return dx*c*J.inv[d,1]+dy*c*J.inv[d,2]+dz*c*J.inv[d,3]
end
# Functions to compute local finite element matrices on simplices. The function
# names follow the pattern `sAB[D]vC[D]uC[[D]cE]`. Where
# - `A`: is the number of vertices of the simplex, e.g. 4 for a tetrahedron
# - `B`: is the number of space dimension
# - `C`: the order of the ansatz functions
# - `D`: optional classificator its `d` for a partial derivative
#   (coordinate is specified in the function call), `n` for a nabla operator,
#   `x` for a dirac-delta at some point x to get the function value there, and
#   `r` for scalar multiplication with a direction vector.
# - `E`: the interpolation order of the (optional) coefficient function
#
# optional `d` indicate a partial derivative.
#
# Example: Lets assume you want to discretize the term ∂u(x,y,z)/∂x*c(x,y,z)
# Then the local weak form gives rise to the integral
# ∫∫∫_(Tet) v*∂u(x,y,z)/∂x*c(x,y,z) dxdydz  where `Tet` is the tetrahedron.
# Furthermore, trial and test functions u and v should be of second order
# while the coefficient function should be interpolated linearly.
# Then, the function that returns the local discretization matrix of this weak
# form is s43v2du2c1. (The direction of the partial derivative is specified in
# the function call.)

#TODO: multiple dispatch instead of/additionally to function names

## mass matrices
#triangles
function s33v1u1(J::CooTrafo)
     M=[1/12 1/24 1/24;
        1/24 1/12 1/24;
        1/24 1/24 1/12]

    return M*abs(J.det)
end
function s33v2u2(J::CooTrafo)
        M=[1/60 -1/360 -1/360 0 0 -1/90;
        -1/360 1/60 -1/360 0 -1/90 0;
        -1/360 -1/360 1/60 -1/90 0 0;
        0 0 -1/90 4/45 2/45 2/45;
        0 -1/90 0 2/45 4/45 2/45;
        -1/90 0 0 2/45 2/45 4/45]
        return M*abs(J.det)
end

function s33vhuh(J::CooTrafo)
        M=[313/5040 1/720 1/720 -53/5040 17/10080 17/10080 53/10080 -1/2520 -13/10080 0 0 0 3/112;
        1/720 313/5040 1/720 -1/2520 53/10080 -13/10080 17/10080 -53/5040 17/10080 0 0 0 3/112;
        1/720 1/720 313/5040 -1/2520 -13/10080 53/10080 -13/10080 -1/2520 53/10080 0 0 0 3/112;
        -53/5040 -1/2520 -1/2520 1/504 -1/2520 -1/2520 -1/1008 1/10080 1/3360 0 0 0 -3/560;
        17/10080 53/10080 -13/10080 -1/2520 1/1260 -1/5040 1/2016 -1/1008 -1/10080 0 0 0 3/1120;
        17/10080 -13/10080 53/10080 -1/2520 -1/5040 1/1260 -1/10080 1/3360 1/5040 0 0 0 3/1120;
        53/10080 17/10080 -13/10080 -1/1008 1/2016 -1/10080 1/1260 -1/2520 -1/5040 0 0 0 3/1120;
        -1/2520 -53/5040 -1/2520 1/10080 -1/1008 1/3360 -1/2520 1/504 -1/2520 0 0 0 -3/560;
        -13/10080 17/10080 53/10080 1/3360 -1/10080 1/5040 -1/5040 -1/2520 1/1260 0 0 0 3/1120;
        0 0 0 0 0 0 0 0 0 0 0 0 0;
        0 0 0 0 0 0 0 0 0 0 0 0 0;
        0 0 0 0 0 0 0 0 0 0 0 0 0;
        3/112 3/112 3/112 -3/560 3/1120 3/1120 3/1120 -3/560 3/1120 0 0 0 81/560]
        return recombine_hermite(J,M)*abs(J.det)
end

function s33v1u1c1(J::CooTrafo,c)
        c1,c2,c4=c
        M=Array{ComplexF64}(undef,3,3)
        M[1,1]=c1/20 + c2/60 + c4/60
        M[1,2]=c1/60 + c2/60 + c4/120
        M[1,3]=c1/60 + c2/120 + c4/60
        M[2,2]=c1/60 + c2/20 + c4/60
        M[2,3]=c1/120 + c2/60 + c4/60
        M[3,3]=c1/60 + c2/60 + c4/20
        M[2,1]=M[1,2]
        M[3,1]=M[1,3]
        M[3,2]=M[2,3]
        return M*abs(J.det)
end


function s33v2u2c1(J::CooTrafo,c)
        c1,c2,c4=c
        M=Array{ComplexF64}(undef,6,6)
        M[1,1]=c1/84 + c2/420 + c4/420
        M[1,2]=-c1/630 - c2/630 + c4/2520
        M[1,3]=-c1/630 + c2/2520 - c4/630
        M[1,4]=c1/210 - c2/315 - c4/630
        M[1,5]=c1/210 - c2/630 - c4/315
        M[1,6]=-c1/630 - c2/210 - c4/210
        M[2,2]=c1/420 + c2/84 + c4/420
        M[2,3]=c1/2520 - c2/630 - c4/630
        M[2,4]=-c1/315 + c2/210 - c4/630
        M[2,5]=-c1/210 - c2/630 - c4/210
        M[2,6]=-c1/630 + c2/210 - c4/315
        M[3,3]=c1/420 + c2/420 + c4/84
        M[3,4]=-c1/210 - c2/210 - c4/630
        M[3,5]=-c1/315 - c2/630 + c4/210
        M[3,6]=-c1/630 - c2/315 + c4/210
        M[4,4]=4*c1/105 + 4*c2/105 + 4*c4/315
        M[4,5]=2*c1/105 + 4*c2/315 + 4*c4/315
        M[4,6]=4*c1/315 + 2*c2/105 + 4*c4/315
        M[5,5]=4*c1/105 + 4*c2/315 + 4*c4/105
        M[5,6]=4*c1/315 + 4*c2/315 + 2*c4/105
        M[6,6]=4*c1/315 + 4*c2/105 + 4*c4/105
        M[2,1]=M[1,2]
        M[3,1]=M[1,3]
        M[4,1]=M[1,4]
        M[5,1]=M[1,5]
        M[6,1]=M[1,6]
        M[3,2]=M[2,3]
        M[4,2]=M[2,4]
        M[5,2]=M[2,5]
        M[6,2]=M[2,6]
        M[4,3]=M[3,4]
        M[5,3]=M[3,5]
        M[6,3]=M[3,6]
        M[5,4]=M[4,5]
        M[6,4]=M[4,6]
        M[6,5]=M[5,6]
        return M*abs(J.det)
end

function s33vhuhc1(J::CooTrafo,c)
        c1,c2,c4=c
        M=Array{ComplexF64}(undef,13,13)
        M[1,1]=31*c1/720 + c2/105 + c4/105
        M[1,2]=c1/672 + c2/672 - c4/630
        M[1,3]=c1/672 - c2/630 + c4/672
        M[1,4]=-17*c1/2520 - 19*c2/10080 - 19*c4/10080
        M[1,5]=c1/1120 + c2/1260
        M[1,6]=c1/1120 + c4/1260
        M[1,7]=17*c1/5040 + c2/720 + c4/2016
        M[1,8]=-c1/2520 - c2/2520 + c4/2520
        M[1,9]=-c1/2016 - c2/2520 - c4/2520
        M[1,10]=0
        M[1,11]=0
        M[1,12]=0
        M[1,13]=c1/56 + c2/224 + c4/224
        M[2,2]=c1/105 + 31*c2/720 + c4/105
        M[2,3]=-c1/630 + c2/672 + c4/672
        M[2,4]=-c1/2520 - c2/2520 + c4/2520
        M[2,5]=c1/720 + 17*c2/5040 + c4/2016
        M[2,6]=-c1/2520 - c2/2016 - c4/2520
        M[2,7]=c1/1260 + c2/1120
        M[2,8]=-19*c1/10080 - 17*c2/2520 - 19*c4/10080
        M[2,9]=c2/1120 + c4/1260
        M[2,10]=0
        M[2,11]=0
        M[2,12]=0
        M[2,13]=c1/224 + c2/56 + c4/224
        M[3,3]=c1/105 + c2/105 + 31*c4/720
        M[3,4]=-c1/2520 + c2/2520 - c4/2520
        M[3,5]=-c1/2520 - c2/2520 - c4/2016
        M[3,6]=c1/720 + c2/2016 + 17*c4/5040
        M[3,7]=-c1/2520 - c2/2520 - c4/2016
        M[3,8]=c1/2520 - c2/2520 - c4/2520
        M[3,9]=c1/2016 + c2/720 + 17*c4/5040
        M[3,10]=0
        M[3,11]=0
        M[3,12]=0
        M[3,13]=c1/224 + c2/224 + c4/56
        M[4,4]=c1/840 + c2/2520 + c4/2520
        M[4,5]=-c1/5040 - c2/5040
        M[4,6]=-c1/5040 - c4/5040
        M[4,7]=-c1/1680 - c2/3360 - c4/10080
        M[4,8]=c1/10080 + c2/10080 - c4/10080
        M[4,9]=c1/10080 + c2/10080 + c4/10080
        M[4,10]=0
        M[4,11]=0
        M[4,12]=0
        M[4,13]=-c1/280 - c2/1120 - c4/1120
        M[5,5]=c1/3780 + c2/2160 + c4/15120
        M[5,6]=-c1/15120 - c2/15120 - c4/15120
        M[5,7]=c1/4320 + c2/4320 + c4/30240
        M[5,8]=-c1/3360 - c2/1680 - c4/10080
        M[5,9]=-c1/30240 - c2/30240 - c4/30240
        M[5,10]=0
        M[5,11]=0
        M[5,12]=0
        M[5,13]=c1/1120 + c2/560
        M[6,6]=c1/3780 + c2/15120 + c4/2160
        M[6,7]=-c1/30240 - c2/30240 - c4/30240
        M[6,8]=c1/10080 + c2/10080 + c4/10080
        M[6,9]=c1/30240 + c2/30240 + c4/7560
        M[6,10]=0
        M[6,11]=0
        M[6,12]=0
        M[6,13]=c1/1120 + c4/560
        M[7,7]=c1/2160 + c2/3780 + c4/15120
        M[7,8]=-c1/5040 - c2/5040
        M[7,9]=-c1/15120 - c2/15120 - c4/15120
        M[7,10]=0
        M[7,11]=0
        M[7,12]=0
        M[7,13]=c1/560 + c2/1120
        M[8,8]=c1/2520 + c2/840 + c4/2520
        M[8,9]=-c2/5040 - c4/5040
        M[8,10]=0
        M[8,11]=0
        M[8,12]=0
        M[8,13]=-c1/1120 - c2/280 - c4/1120
        M[9,9]=c1/15120 + c2/3780 + c4/2160
        M[9,10]=0
        M[9,11]=0
        M[9,12]=0
        M[9,13]=c2/1120 + c4/560
        M[10,10]=0
        M[10,11]=0
        M[10,12]=0
        M[10,13]=0
        M[11,11]=0
        M[11,12]=0
        M[11,13]=0
        M[12,12]=0
        M[12,13]=0
        M[13,13]=27*c1/560 + 27*c2/560 + 27*c4/560
        M[2,1]=M[1,2]
        M[3,1]=M[1,3]
        M[4,1]=M[1,4]
        M[5,1]=M[1,5]
        M[6,1]=M[1,6]
        M[7,1]=M[1,7]
        M[8,1]=M[1,8]
        M[9,1]=M[1,9]
        M[10,1]=M[1,10]
        M[11,1]=M[1,11]
        M[12,1]=M[1,12]
        M[13,1]=M[1,13]
        M[3,2]=M[2,3]
        M[4,2]=M[2,4]
        M[5,2]=M[2,5]
        M[6,2]=M[2,6]
        M[7,2]=M[2,7]
        M[8,2]=M[2,8]
        M[9,2]=M[2,9]
        M[10,2]=M[2,10]
        M[11,2]=M[2,11]
        M[12,2]=M[2,12]
        M[13,2]=M[2,13]
        M[4,3]=M[3,4]
        M[5,3]=M[3,5]
        M[6,3]=M[3,6]
        M[7,3]=M[3,7]
        M[8,3]=M[3,8]
        M[9,3]=M[3,9]
        M[10,3]=M[3,10]
        M[11,3]=M[3,11]
        M[12,3]=M[3,12]
        M[13,3]=M[3,13]
        M[5,4]=M[4,5]
        M[6,4]=M[4,6]
        M[7,4]=M[4,7]
        M[8,4]=M[4,8]
        M[9,4]=M[4,9]
        M[10,4]=M[4,10]
        M[11,4]=M[4,11]
        M[12,4]=M[4,12]
        M[13,4]=M[4,13]
        M[6,5]=M[5,6]
        M[7,5]=M[5,7]
        M[8,5]=M[5,8]
        M[9,5]=M[5,9]
        M[10,5]=M[5,10]
        M[11,5]=M[5,11]
        M[12,5]=M[5,12]
        M[13,5]=M[5,13]
        M[7,6]=M[6,7]
        M[8,6]=M[6,8]
        M[9,6]=M[6,9]
        M[10,6]=M[6,10]
        M[11,6]=M[6,11]
        M[12,6]=M[6,12]
        M[13,6]=M[6,13]
        M[8,7]=M[7,8]
        M[9,7]=M[7,9]
        M[10,7]=M[7,10]
        M[11,7]=M[7,11]
        M[12,7]=M[7,12]
        M[13,7]=M[7,13]
        M[9,8]=M[8,9]
        M[10,8]=M[8,10]
        M[11,8]=M[8,11]
        M[12,8]=M[8,12]
        M[13,8]=M[8,13]
        M[10,9]=M[9,10]
        M[11,9]=M[9,11]
        M[12,9]=M[9,12]
        M[13,9]=M[9,13]
        M[11,10]=M[10,11]
        M[12,10]=M[10,12]
        M[13,10]=M[10,13]
        M[12,11]=M[11,12]
        M[13,11]=M[11,13]
        M[13,12]=M[12,13]

        return recombine_hermite(J,M)*abs(J.det)
end

#tetrahedra
function s43v1u1(J::CooTrafo)
    M = [1/60 1/120 1/120 1/120;
          1/120 1/60 1/120 1/120;
          1/120 1/120 1/60 1/120;
          1/120 1/120 1/120 1/60]
    return M*abs(J.det)
end

function s43v2u1(J::CooTrafo)
   M =  [0 -1/360 -1/360 -1/360;
        -1/360 0 -1/360 -1/360;
        -1/360 -1/360 0 -1/360;
        -1/360 -1/360 -1/360 0;
        1/90 1/90 1/180 1/180;
        1/90 1/180 1/90 1/180;
        1/90 1/180 1/180 1/90;
        1/180 1/90 1/90 1/180;
        1/180 1/90 1/180 1/90;
        1/180 1/180 1/90 1/90]
        return M*abs(J.det)
end

function s43v2u2(J::CooTrafo)
    M = [1/420 1/2520 1/2520 1/2520 -1/630 -1/630 -1/630 -1/420 -1/420 -1/420;
            1/2520 1/420 1/2520 1/2520 -1/630 -1/420 -1/420 -1/630 -1/630 -1/420;
            1/2520 1/2520 1/420 1/2520 -1/420 -1/630 -1/420 -1/630 -1/420 -1/630;
            1/2520 1/2520 1/2520 1/420 -1/420 -1/420 -1/630 -1/420 -1/630 -1/630;
            -1/630 -1/630 -1/420 -1/420 4/315 2/315 2/315 2/315 2/315 1/315;
            -1/630 -1/420 -1/630 -1/420 2/315 4/315 2/315 2/315 1/315 2/315;
            -1/630 -1/420 -1/420 -1/630 2/315 2/315 4/315 1/315 2/315 2/315;
            -1/420 -1/630 -1/630 -1/420 2/315 2/315 1/315 4/315 2/315 2/315;
            -1/420 -1/630 -1/420 -1/630 2/315 1/315 2/315 2/315 4/315 2/315;
            -1/420 -1/420 -1/630 -1/630 1/315 2/315 2/315 2/315 2/315 4/315]
    return M*abs(J.det)
end

function s43vhuh(J::CooTrafo)
        M=[253/30240 -23/45360 -23/45360 -23/45360 -97/60480 1/12960 1/12960 1/12960 97/181440 1/11340 -1/12096 -1/12096 97/181440 -1/12096 1/11340 -1/12096 -1/320 1/6720 1/6720 1/6720;
        -23/45360 253/30240 -23/45360 -23/45360 1/11340 97/181440 -1/12096 -1/12096 1/12960 -97/60480 1/12960 1/12960 -1/12096 97/181440 1/11340 -1/12096 1/6720 -1/320 1/6720 1/6720;
        -23/45360 -23/45360 253/30240 -23/45360 1/11340 -1/12096 97/181440 -1/12096 -1/12096 1/11340 97/181440 -1/12096 1/12960 1/12960 -97/60480 1/12960 1/6720 1/6720 -1/320 1/6720;
        -23/45360 -23/45360 -23/45360 253/30240 1/11340 -1/12096 -1/12096 97/181440 -1/12096 1/11340 -1/12096 97/181440 -1/12096 -1/12096 1/11340 97/181440 1/6720 1/6720 1/6720 -1/320;
        -97/60480 1/11340 1/11340 1/11340 1/3024 -1/45360 -1/45360 -1/45360 -1/9072 -1/90720 1/60480 1/60480 -1/9072 1/60480 -1/90720 1/60480 1/1120 1/6720 1/6720 1/6720;
        1/12960 97/181440 -1/12096 -1/12096 -1/45360 1/15120 -1/90720 -1/90720 1/30240 -1/9072 -1/181440 -1/181440 -1/181440 1/45360 1/60480 0 -1/6720 -1/3360 0 0;
        1/12960 -1/12096 97/181440 -1/12096 -1/45360 -1/90720 1/15120 -1/90720 -1/181440 1/60480 1/45360 0 1/30240 -1/181440 -1/9072 -1/181440 -1/6720 0 -1/3360 0;
        1/12960 -1/12096 -1/12096 97/181440 -1/45360 -1/90720 -1/90720 1/15120 -1/181440 1/60480 0 1/45360 -1/181440 0 1/60480 1/45360 -1/6720 0 0 -1/3360;
        97/181440 1/12960 -1/12096 -1/12096 -1/9072 1/30240 -1/181440 -1/181440 1/15120 -1/45360 -1/90720 -1/90720 1/45360 -1/181440 1/60480 0 -1/3360 -1/6720 0 0;
        1/11340 -97/60480 1/11340 1/11340 -1/90720 -1/9072 1/60480 1/60480 -1/45360 1/3024 -1/45360 -1/45360 1/60480 -1/9072 -1/90720 1/60480 1/6720 1/1120 1/6720 1/6720;
        -1/12096 1/12960 97/181440 -1/12096 1/60480 -1/181440 1/45360 0 -1/90720 -1/45360 1/15120 -1/90720 -1/181440 1/30240 -1/9072 -1/181440 0 -1/6720 -1/3360 0;
        -1/12096 1/12960 -1/12096 97/181440 1/60480 -1/181440 0 1/45360 -1/90720 -1/45360 -1/90720 1/15120 0 -1/181440 1/60480 1/45360 0 -1/6720 0 -1/3360;
        97/181440 -1/12096 1/12960 -1/12096 -1/9072 -1/181440 1/30240 -1/181440 1/45360 1/60480 -1/181440 0 1/15120 -1/90720 -1/45360 -1/90720 -1/3360 0 -1/6720 0;
        -1/12096 97/181440 1/12960 -1/12096 1/60480 1/45360 -1/181440 0 -1/181440 -1/9072 1/30240 -1/181440 -1/90720 1/15120 -1/45360 -1/90720 0 -1/3360 -1/6720 0;
        1/11340 1/11340 -97/60480 1/11340 -1/90720 1/60480 -1/9072 1/60480 1/60480 -1/90720 -1/9072 1/60480 -1/45360 -1/45360 1/3024 -1/45360 1/6720 1/6720 1/1120 1/6720;
        -1/12096 -1/12096 1/12960 97/181440 1/60480 0 -1/181440 1/45360 0 1/60480 -1/181440 1/45360 -1/90720 -1/90720 -1/45360 1/15120 0 0 -1/6720 -1/3360;
        -1/320 1/6720 1/6720 1/6720 1/1120 -1/6720 -1/6720 -1/6720 -1/3360 1/6720 0 0 -1/3360 0 1/6720 0 9/560 9/1120 9/1120 9/1120;
        1/6720 -1/320 1/6720 1/6720 1/6720 -1/3360 0 0 -1/6720 1/1120 -1/6720 -1/6720 0 -1/3360 1/6720 0 9/1120 9/560 9/1120 9/1120;
        1/6720 1/6720 -1/320 1/6720 1/6720 0 -1/3360 0 0 1/6720 -1/3360 0 -1/6720 -1/6720 1/1120 -1/6720 9/1120 9/1120 9/560 9/1120;
        1/6720 1/6720 1/6720 -1/320 1/6720 0 0 -1/3360 0 1/6720 0 -1/3360 0 0 1/6720 -1/3360 9/1120 9/1120 9/1120 9/560]
        return recombine_hermite(J,M)*abs(J.det)
end

function s43v1u1c1(J::CooTrafo,c)
        c1,c2,c3,c4=c
        M=Array{ComplexF64}(undef,4,4)
        M[1,1]=c1/120 + c2/360 + c3/360 + c4/360
        M[1,2]=c1/360 + c2/360 + c3/720 + c4/720
        M[1,3]=c1/360 + c2/720 + c3/360 + c4/720
        M[1,4]=c1/360 + c2/720 + c3/720 + c4/360
        M[2,2]=c1/360 + c2/120 + c3/360 + c4/360
        M[2,3]=c1/720 + c2/360 + c3/360 + c4/720
        M[2,4]=c1/720 + c2/360 + c3/720 + c4/360
        M[3,3]=c1/360 + c2/360 + c3/120 + c4/360
        M[3,4]=c1/720 + c2/720 + c3/360 + c4/360
        M[4,4]=c1/360 + c2/360 + c3/360 + c4/120
        M[2,1]=M[1,2]
        M[3,1]=M[1,3]
        M[4,1]=M[1,4]
        M[3,2]=M[2,3]
        M[4,2]=M[2,4]
        M[4,3]=M[3,4]
        return M*abs(J.det)
end

function s43v2u2c1(J::CooTrafo,c)
        c1,c2,c3,c4=c
        M=Array{ComplexF64}(undef,10,10)
        M[1,1]=c1/840 + c2/2520 + c3/2520 + c4/2520
        M[1,2]=c3/5040 + c4/5040
        M[1,3]=c2/5040 + c4/5040
        M[1,4]=c2/5040 + c3/5040
        M[1,5]=-c2/1260 - c3/2520 - c4/2520
        M[1,6]=-c2/2520 - c3/1260 - c4/2520
        M[1,7]=-c2/2520 - c3/2520 - c4/1260
        M[1,8]=-c1/2520 - c2/1260 - c3/1260 - c4/2520
        M[1,9]=-c1/2520 - c2/1260 - c3/2520 - c4/1260
        M[1,10]=-c1/2520 - c2/2520 - c3/1260 - c4/1260
        M[2,2]=c1/2520 + c2/840 + c3/2520 + c4/2520
        M[2,3]=c1/5040 + c4/5040
        M[2,4]=c1/5040 + c3/5040
        M[2,5]=-c1/1260 - c3/2520 - c4/2520
        M[2,6]=-c1/1260 - c2/2520 - c3/1260 - c4/2520
        M[2,7]=-c1/1260 - c2/2520 - c3/2520 - c4/1260
        M[2,8]=-c1/2520 - c3/1260 - c4/2520
        M[2,9]=-c1/2520 - c3/2520 - c4/1260
        M[2,10]=-c1/2520 - c2/2520 - c3/1260 - c4/1260
        M[3,3]=c1/2520 + c2/2520 + c3/840 + c4/2520
        M[3,4]=c1/5040 + c2/5040
        M[3,5]=-c1/1260 - c2/1260 - c3/2520 - c4/2520
        M[3,6]=-c1/1260 - c2/2520 - c4/2520
        M[3,7]=-c1/1260 - c2/2520 - c3/2520 - c4/1260
        M[3,8]=-c1/2520 - c2/1260 - c4/2520
        M[3,9]=-c1/2520 - c2/1260 - c3/2520 - c4/1260
        M[3,10]=-c1/2520 - c2/2520 - c4/1260
        M[4,4]=c1/2520 + c2/2520 + c3/2520 + c4/840
        M[4,5]=-c1/1260 - c2/1260 - c3/2520 - c4/2520
        M[4,6]=-c1/1260 - c2/2520 - c3/1260 - c4/2520
        M[4,7]=-c1/1260 - c2/2520 - c3/2520
        M[4,8]=-c1/2520 - c2/1260 - c3/1260 - c4/2520
        M[4,9]=-c1/2520 - c2/1260 - c3/2520
        M[4,10]=-c1/2520 - c2/2520 - c3/1260
        M[5,5]=c1/210 + c2/210 + c3/630 + c4/630
        M[5,6]=c1/420 + c2/630 + c3/630 + c4/1260
        M[5,7]=c1/420 + c2/630 + c3/1260 + c4/630
        M[5,8]=c1/630 + c2/420 + c3/630 + c4/1260
        M[5,9]=c1/630 + c2/420 + c3/1260 + c4/630
        M[5,10]=c1/1260 + c2/1260 + c3/1260 + c4/1260
        M[6,6]=c1/210 + c2/630 + c3/210 + c4/630
        M[6,7]=c1/420 + c2/1260 + c3/630 + c4/630
        M[6,8]=c1/630 + c2/630 + c3/420 + c4/1260
        M[6,9]=c1/1260 + c2/1260 + c3/1260 + c4/1260
        M[6,10]=c1/630 + c2/1260 + c3/420 + c4/630
        M[7,7]=c1/210 + c2/630 + c3/630 + c4/210
        M[7,8]=c1/1260 + c2/1260 + c3/1260 + c4/1260
        M[7,9]=c1/630 + c2/630 + c3/1260 + c4/420
        M[7,10]=c1/630 + c2/1260 + c3/630 + c4/420
        M[8,8]=c1/630 + c2/210 + c3/210 + c4/630
        M[8,9]=c1/1260 + c2/420 + c3/630 + c4/630
        M[8,10]=c1/1260 + c2/630 + c3/420 + c4/630
        M[9,9]=c1/630 + c2/210 + c3/630 + c4/210
        M[9,10]=c1/1260 + c2/630 + c3/630 + c4/420
        M[10,10]=c1/630 + c2/630 + c3/210 + c4/210
        M[2,1]=M[1,2]
        M[3,1]=M[1,3]
        M[4,1]=M[1,4]
        M[5,1]=M[1,5]
        M[6,1]=M[1,6]
        M[7,1]=M[1,7]
        M[8,1]=M[1,8]
        M[9,1]=M[1,9]
        M[10,1]=M[1,10]
        M[3,2]=M[2,3]
        M[4,2]=M[2,4]
        M[5,2]=M[2,5]
        M[6,2]=M[2,6]
        M[7,2]=M[2,7]
        M[8,2]=M[2,8]
        M[9,2]=M[2,9]
        M[10,2]=M[2,10]
        M[4,3]=M[3,4]
        M[5,3]=M[3,5]
        M[6,3]=M[3,6]
        M[7,3]=M[3,7]
        M[8,3]=M[3,8]
        M[9,3]=M[3,9]
        M[10,3]=M[3,10]
        M[5,4]=M[4,5]
        M[6,4]=M[4,6]
        M[7,4]=M[4,7]
        M[8,4]=M[4,8]
        M[9,4]=M[4,9]
        M[10,4]=M[4,10]
        M[6,5]=M[5,6]
        M[7,5]=M[5,7]
        M[8,5]=M[5,8]
        M[9,5]=M[5,9]
        M[10,5]=M[5,10]
        M[7,6]=M[6,7]
        M[8,6]=M[6,8]
        M[9,6]=M[6,9]
        M[10,6]=M[6,10]
        M[8,7]=M[7,8]
        M[9,7]=M[7,9]
        M[10,7]=M[7,10]
        M[9,8]=M[8,9]
        M[10,8]=M[8,10]
        M[10,9]=M[9,10]
        return M*abs(J.det)
end

function s43vhuhc1(J::CooTrafo,c)
        c1,c2,c3,c4=c
        M=Array{ComplexF64}(undef,20,20)
        M[1,1]=31*c1/6300 + 521*c2/453600 + 521*c3/453600 + 521*c4/453600
        M[1,2]=-73*c1/302400 - 73*c2/302400 - 11*c3/907200 - 11*c4/907200
        M[1,3]=-73*c1/302400 - 11*c2/907200 - 73*c3/302400 - 11*c4/907200
        M[1,4]=-73*c1/302400 - 11*c2/907200 - 11*c3/907200 - 73*c4/302400
        M[1,5]=-43*c1/50400 - 227*c2/907200 - 227*c3/907200 - 227*c4/907200
        M[1,6]=c1/43200 + 31*c2/907200 + c3/100800 + c4/100800
        M[1,7]=c1/43200 + c2/100800 + 31*c3/907200 + c4/100800
        M[1,8]=c1/43200 + c2/100800 + c3/100800 + 31*c4/907200
        M[1,9]=43*c1/151200 + 23*c2/181440 + c3/16200 + c4/16200
        M[1,10]=11*c1/181440 + 11*c2/302400 - c3/226800 - c4/226800
        M[1,11]=-19*c1/453600 - c2/64800 - c3/28350 + c4/100800
        M[1,12]=-19*c1/453600 - c2/64800 + c3/100800 - c4/28350
        M[1,13]=43*c1/151200 + c2/16200 + 23*c3/181440 + c4/16200
        M[1,14]=-19*c1/453600 - c2/28350 - c3/64800 + c4/100800
        M[1,15]=11*c1/181440 - c2/226800 + 11*c3/302400 - c4/226800
        M[1,16]=-19*c1/453600 + c2/100800 - c3/64800 - c4/28350
        M[1,17]=-3*c1/11200 - c2/1050 - c3/1050 - c4/1050
        M[1,18]=3*c1/2800 - 3*c2/11200 - 11*c3/33600 - 11*c4/33600
        M[1,19]=3*c1/2800 - 11*c2/33600 - 3*c3/11200 - 11*c4/33600
        M[1,20]=3*c1/2800 - 11*c2/33600 - 11*c3/33600 - 3*c4/11200
        M[2,2]=521*c1/453600 + 31*c2/6300 + 521*c3/453600 + 521*c4/453600
        M[2,3]=-11*c1/907200 - 73*c2/302400 - 73*c3/302400 - 11*c4/907200
        M[2,4]=-11*c1/907200 - 73*c2/302400 - 11*c3/907200 - 73*c4/302400
        M[2,5]=11*c1/302400 + 11*c2/181440 - c3/226800 - c4/226800
        M[2,6]=23*c1/181440 + 43*c2/151200 + c3/16200 + c4/16200
        M[2,7]=-c1/64800 - 19*c2/453600 - c3/28350 + c4/100800
        M[2,8]=-c1/64800 - 19*c2/453600 + c3/100800 - c4/28350
        M[2,9]=31*c1/907200 + c2/43200 + c3/100800 + c4/100800
        M[2,10]=-227*c1/907200 - 43*c2/50400 - 227*c3/907200 - 227*c4/907200
        M[2,11]=c1/100800 + c2/43200 + 31*c3/907200 + c4/100800
        M[2,12]=c1/100800 + c2/43200 + c3/100800 + 31*c4/907200
        M[2,13]=-c1/28350 - 19*c2/453600 - c3/64800 + c4/100800
        M[2,14]=c1/16200 + 43*c2/151200 + 23*c3/181440 + c4/16200
        M[2,15]=-c1/226800 + 11*c2/181440 + 11*c3/302400 - c4/226800
        M[2,16]=c1/100800 - 19*c2/453600 - c3/64800 - c4/28350
        M[2,17]=-3*c1/11200 + 3*c2/2800 - 11*c3/33600 - 11*c4/33600
        M[2,18]=-c1/1050 - 3*c2/11200 - c3/1050 - c4/1050
        M[2,19]=-11*c1/33600 + 3*c2/2800 - 3*c3/11200 - 11*c4/33600
        M[2,20]=-11*c1/33600 + 3*c2/2800 - 11*c3/33600 - 3*c4/11200
        M[3,3]=521*c1/453600 + 521*c2/453600 + 31*c3/6300 + 521*c4/453600
        M[3,4]=-11*c1/907200 - 11*c2/907200 - 73*c3/302400 - 73*c4/302400
        M[3,5]=11*c1/302400 - c2/226800 + 11*c3/181440 - c4/226800
        M[3,6]=-c1/64800 - c2/28350 - 19*c3/453600 + c4/100800
        M[3,7]=23*c1/181440 + c2/16200 + 43*c3/151200 + c4/16200
        M[3,8]=-c1/64800 + c2/100800 - 19*c3/453600 - c4/28350
        M[3,9]=-c1/28350 - c2/64800 - 19*c3/453600 + c4/100800
        M[3,10]=-c1/226800 + 11*c2/302400 + 11*c3/181440 - c4/226800
        M[3,11]=c1/16200 + 23*c2/181440 + 43*c3/151200 + c4/16200
        M[3,12]=c1/100800 - c2/64800 - 19*c3/453600 - c4/28350
        M[3,13]=31*c1/907200 + c2/100800 + c3/43200 + c4/100800
        M[3,14]=c1/100800 + 31*c2/907200 + c3/43200 + c4/100800
        M[3,15]=-227*c1/907200 - 227*c2/907200 - 43*c3/50400 - 227*c4/907200
        M[3,16]=c1/100800 + c2/100800 + c3/43200 + 31*c4/907200
        M[3,17]=-3*c1/11200 - 11*c2/33600 + 3*c3/2800 - 11*c4/33600
        M[3,18]=-11*c1/33600 - 3*c2/11200 + 3*c3/2800 - 11*c4/33600
        M[3,19]=-c1/1050 - c2/1050 - 3*c3/11200 - c4/1050
        M[3,20]=-11*c1/33600 - 11*c2/33600 + 3*c3/2800 - 3*c4/11200
        M[4,4]=521*c1/453600 + 521*c2/453600 + 521*c3/453600 + 31*c4/6300
        M[4,5]=11*c1/302400 - c2/226800 - c3/226800 + 11*c4/181440
        M[4,6]=-c1/64800 - c2/28350 + c3/100800 - 19*c4/453600
        M[4,7]=-c1/64800 + c2/100800 - c3/28350 - 19*c4/453600
        M[4,8]=23*c1/181440 + c2/16200 + c3/16200 + 43*c4/151200
        M[4,9]=-c1/28350 - c2/64800 + c3/100800 - 19*c4/453600
        M[4,10]=-c1/226800 + 11*c2/302400 - c3/226800 + 11*c4/181440
        M[4,11]=c1/100800 - c2/64800 - c3/28350 - 19*c4/453600
        M[4,12]=c1/16200 + 23*c2/181440 + c3/16200 + 43*c4/151200
        M[4,13]=-c1/28350 + c2/100800 - c3/64800 - 19*c4/453600
        M[4,14]=c1/100800 - c2/28350 - c3/64800 - 19*c4/453600
        M[4,15]=-c1/226800 - c2/226800 + 11*c3/302400 + 11*c4/181440
        M[4,16]=c1/16200 + c2/16200 + 23*c3/181440 + 43*c4/151200
        M[4,17]=-3*c1/11200 - 11*c2/33600 - 11*c3/33600 + 3*c4/2800
        M[4,18]=-11*c1/33600 - 3*c2/11200 - 11*c3/33600 + 3*c4/2800
        M[4,19]=-11*c1/33600 - 11*c2/33600 - 3*c3/11200 + 3*c4/2800
        M[4,20]=-c1/1050 - c2/1050 - c3/1050 - 3*c4/11200
        M[5,5]=c1/6300 + 13*c2/226800 + 13*c3/226800 + 13*c4/226800
        M[5,6]=-c1/151200 - c2/113400 - c3/302400 - c4/302400
        M[5,7]=-c1/151200 - c2/302400 - c3/113400 - c4/302400
        M[5,8]=-c1/151200 - c2/302400 - c3/302400 - c4/113400
        M[5,9]=-c1/18900 - 13*c2/453600 - 13*c3/907200 - 13*c4/907200
        M[5,10]=-c1/113400 - c2/113400 + c3/302400 + c4/302400
        M[5,11]=c1/129600 + c2/302400 + c3/113400 - c4/302400
        M[5,12]=c1/129600 + c2/302400 - c3/302400 + c4/113400
        M[5,13]=-c1/18900 - 13*c2/907200 - 13*c3/453600 - 13*c4/907200
        M[5,14]=c1/129600 + c2/113400 + c3/302400 - c4/302400
        M[5,15]=-c1/113400 + c2/302400 - c3/113400 + c4/302400
        M[5,16]=c1/129600 - c2/302400 + c3/302400 + c4/113400
        M[5,17]=c1/11200 + 3*c2/11200 + 3*c3/11200 + 3*c4/11200
        M[5,18]=-c1/5600 + c2/11200 + c3/8400 + c4/8400
        M[5,19]=-c1/5600 + c2/8400 + c3/11200 + c4/8400
        M[5,20]=-c1/5600 + c2/8400 + c3/8400 + c4/11200
        M[6,6]=c1/50400 + c2/30240 + c3/151200 + c4/151200
        M[6,7]=-c1/302400 - c2/226800 - c3/226800 + c4/907200
        M[6,8]=-c1/302400 - c2/226800 + c3/907200 - c4/226800
        M[6,9]=c1/75600 + c2/75600 + c3/302400 + c4/302400
        M[6,10]=-13*c1/453600 - c2/18900 - 13*c3/907200 - 13*c4/907200
        M[6,11]=-c1/907200 - c2/302400 - c3/453600 + c4/907200
        M[6,12]=-c1/907200 - c2/302400 + c3/907200 - c4/453600
        M[6,13]=-c1/302400 - c2/453600 - c3/907200 + c4/907200
        M[6,14]=c1/226800 + c2/100800 + c3/226800 + c4/302400
        M[6,15]=c1/302400 + c2/113400 + c3/129600 - c4/302400
        M[6,16]=c1/907200 - c2/907200 + c3/907200 - c4/907200
        M[6,17]=-c1/33600 - c3/16800 - c4/16800
        M[6,18]=-c1/11200 - c2/33600 - c3/11200 - c4/11200
        M[6,19]=c2/11200 - c3/33600 - c4/16800
        M[6,20]=c2/11200 - c3/16800 - c4/33600
        M[7,7]=c1/50400 + c2/151200 + c3/30240 + c4/151200
        M[7,8]=-c1/302400 + c2/907200 - c3/226800 - c4/226800
        M[7,9]=-c1/302400 - c2/907200 - c3/453600 + c4/907200
        M[7,10]=c1/302400 + c2/129600 + c3/113400 - c4/302400
        M[7,11]=c1/226800 + c2/226800 + c3/100800 + c4/302400
        M[7,12]=c1/907200 + c2/907200 - c3/907200 - c4/907200
        M[7,13]=c1/75600 + c2/302400 + c3/75600 + c4/302400
        M[7,14]=-c1/907200 - c2/453600 - c3/302400 + c4/907200
        M[7,15]=-13*c1/453600 - 13*c2/907200 - c3/18900 - 13*c4/907200
        M[7,16]=-c1/907200 + c2/907200 - c3/302400 - c4/453600
        M[7,17]=-c1/33600 - c2/16800 - c4/16800
        M[7,18]=-c2/33600 + c3/11200 - c4/16800
        M[7,19]=-c1/11200 - c2/11200 - c3/33600 - c4/11200
        M[7,20]=-c2/16800 + c3/11200 - c4/33600
        M[8,8]=c1/50400 + c2/151200 + c3/151200 + c4/30240
        M[8,9]=-c1/302400 - c2/907200 + c3/907200 - c4/453600
        M[8,10]=c1/302400 + c2/129600 - c3/302400 + c4/113400
        M[8,11]=c1/907200 + c2/907200 - c3/907200 - c4/907200
        M[8,12]=c1/226800 + c2/226800 + c3/302400 + c4/100800
        M[8,13]=-c1/302400 + c2/907200 - c3/907200 - c4/453600
        M[8,14]=c1/907200 - c2/907200 + c3/907200 - c4/907200
        M[8,15]=c1/302400 - c2/302400 + c3/129600 + c4/113400
        M[8,16]=c1/226800 + c2/302400 + c3/226800 + c4/100800
        M[8,17]=-c1/33600 - c2/16800 - c3/16800
        M[8,18]=-c2/33600 - c3/16800 + c4/11200
        M[8,19]=-c2/16800 - c3/33600 + c4/11200
        M[8,20]=-c1/11200 - c2/11200 - c3/11200 - c4/33600
        M[9,9]=c1/30240 + c2/50400 + c3/151200 + c4/151200
        M[9,10]=-c1/113400 - c2/151200 - c3/302400 - c4/302400
        M[9,11]=-c1/226800 - c2/302400 - c3/226800 + c4/907200
        M[9,12]=-c1/226800 - c2/302400 + c3/907200 - c4/226800
        M[9,13]=c1/100800 + c2/226800 + c3/226800 + c4/302400
        M[9,14]=-c1/453600 - c2/302400 - c3/907200 + c4/907200
        M[9,15]=c1/113400 + c2/302400 + c3/129600 - c4/302400
        M[9,16]=-c1/907200 + c2/907200 + c3/907200 - c4/907200
        M[9,17]=-c1/33600 - c2/11200 - c3/11200 - c4/11200
        M[9,18]=-c2/33600 - c3/16800 - c4/16800
        M[9,19]=c1/11200 - c3/33600 - c4/16800
        M[9,20]=c1/11200 - c3/16800 - c4/33600
        M[10,10]=13*c1/226800 + c2/6300 + 13*c3/226800 + 13*c4/226800
        M[10,11]=-c1/302400 - c2/151200 - c3/113400 - c4/302400
        M[10,12]=-c1/302400 - c2/151200 - c3/302400 - c4/113400
        M[10,13]=c1/113400 + c2/129600 + c3/302400 - c4/302400
        M[10,14]=-13*c1/907200 - c2/18900 - 13*c3/453600 - 13*c4/907200
        M[10,15]=c1/302400 - c2/113400 - c3/113400 + c4/302400
        M[10,16]=-c1/302400 + c2/129600 + c3/302400 + c4/113400
        M[10,17]=c1/11200 - c2/5600 + c3/8400 + c4/8400
        M[10,18]=3*c1/11200 + c2/11200 + 3*c3/11200 + 3*c4/11200
        M[10,19]=c1/8400 - c2/5600 + c3/11200 + c4/8400
        M[10,20]=c1/8400 - c2/5600 + c3/8400 + c4/11200
        M[11,11]=c1/151200 + c2/50400 + c3/30240 + c4/151200
        M[11,12]=c1/907200 - c2/302400 - c3/226800 - c4/226800
        M[11,13]=-c1/453600 - c2/907200 - c3/302400 + c4/907200
        M[11,14]=c1/302400 + c2/75600 + c3/75600 + c4/302400
        M[11,15]=-13*c1/907200 - 13*c2/453600 - c3/18900 - 13*c4/907200
        M[11,16]=c1/907200 - c2/907200 - c3/302400 - c4/453600
        M[11,17]=-c1/33600 + c3/11200 - c4/16800
        M[11,18]=-c1/16800 - c2/33600 - c4/16800
        M[11,19]=-c1/11200 - c2/11200 - c3/33600 - c4/11200
        M[11,20]=-c1/16800 + c3/11200 - c4/33600
        M[12,12]=c1/151200 + c2/50400 + c3/151200 + c4/30240
        M[12,13]=-c1/907200 + c2/907200 + c3/907200 - c4/907200
        M[12,14]=c1/907200 - c2/302400 - c3/907200 - c4/453600
        M[12,15]=-c1/302400 + c2/302400 + c3/129600 + c4/113400
        M[12,16]=c1/302400 + c2/226800 + c3/226800 + c4/100800
        M[12,17]=-c1/33600 - c3/16800 + c4/11200
        M[12,18]=-c1/16800 - c2/33600 - c3/16800
        M[12,19]=-c1/16800 - c3/33600 + c4/11200
        M[12,20]=-c1/11200 - c2/11200 - c3/11200 - c4/33600
        M[13,13]=c1/30240 + c2/151200 + c3/50400 + c4/151200
        M[13,14]=-c1/226800 - c2/226800 - c3/302400 + c4/907200
        M[13,15]=-c1/113400 - c2/302400 - c3/151200 - c4/302400
        M[13,16]=-c1/226800 + c2/907200 - c3/302400 - c4/226800
        M[13,17]=-c1/33600 - c2/11200 - c3/11200 - c4/11200
        M[13,18]=c1/11200 - c2/33600 - c4/16800
        M[13,19]=-c2/16800 - c3/33600 - c4/16800
        M[13,20]=c1/11200 - c2/16800 - c4/33600
        M[14,14]=c1/151200 + c2/30240 + c3/50400 + c4/151200
        M[14,15]=-c1/302400 - c2/113400 - c3/151200 - c4/302400
        M[14,16]=c1/907200 - c2/226800 - c3/302400 - c4/226800
        M[14,17]=-c1/33600 + c2/11200 - c4/16800
        M[14,18]=-c1/11200 - c2/33600 - c3/11200 - c4/11200
        M[14,19]=-c1/16800 - c3/33600 - c4/16800
        M[14,20]=-c1/16800 + c2/11200 - c4/33600
        M[15,15]=13*c1/226800 + 13*c2/226800 + c3/6300 + 13*c4/226800
        M[15,16]=-c1/302400 - c2/302400 - c3/151200 - c4/113400
        M[15,17]=c1/11200 + c2/8400 - c3/5600 + c4/8400
        M[15,18]=c1/8400 + c2/11200 - c3/5600 + c4/8400
        M[15,19]=3*c1/11200 + 3*c2/11200 + c3/11200 + 3*c4/11200
        M[15,20]=c1/8400 + c2/8400 - c3/5600 + c4/11200
        M[16,16]=c1/151200 + c2/151200 + c3/50400 + c4/30240
        M[16,17]=-c1/33600 - c2/16800 + c4/11200
        M[16,18]=-c1/16800 - c2/33600 + c4/11200
        M[16,19]=-c1/16800 - c2/16800 - c3/33600
        M[16,20]=-c1/11200 - c2/11200 - c3/11200 - c4/33600
        M[17,17]=9*c1/5600 + 27*c2/5600 + 27*c3/5600 + 27*c4/5600
        M[17,18]=9*c1/5600 + 9*c2/5600 + 27*c3/11200 + 27*c4/11200
        M[17,19]=9*c1/5600 + 27*c2/11200 + 9*c3/5600 + 27*c4/11200
        M[17,20]=9*c1/5600 + 27*c2/11200 + 27*c3/11200 + 9*c4/5600
        M[18,18]=27*c1/5600 + 9*c2/5600 + 27*c3/5600 + 27*c4/5600
        M[18,19]=27*c1/11200 + 9*c2/5600 + 9*c3/5600 + 27*c4/11200
        M[18,20]=27*c1/11200 + 9*c2/5600 + 27*c3/11200 + 9*c4/5600
        M[19,19]=27*c1/5600 + 27*c2/5600 + 9*c3/5600 + 27*c4/5600
        M[19,20]=27*c1/11200 + 27*c2/11200 + 9*c3/5600 + 9*c4/5600
        M[20,20]=27*c1/5600 + 27*c2/5600 + 27*c3/5600 + 9*c4/5600
        M[2,1]=M[1,2]
        M[3,1]=M[1,3]
        M[4,1]=M[1,4]
        M[5,1]=M[1,5]
        M[6,1]=M[1,6]
        M[7,1]=M[1,7]
        M[8,1]=M[1,8]
        M[9,1]=M[1,9]
        M[10,1]=M[1,10]
        M[11,1]=M[1,11]
        M[12,1]=M[1,12]
        M[13,1]=M[1,13]
        M[14,1]=M[1,14]
        M[15,1]=M[1,15]
        M[16,1]=M[1,16]
        M[17,1]=M[1,17]
        M[18,1]=M[1,18]
        M[19,1]=M[1,19]
        M[20,1]=M[1,20]
        M[3,2]=M[2,3]
        M[4,2]=M[2,4]
        M[5,2]=M[2,5]
        M[6,2]=M[2,6]
        M[7,2]=M[2,7]
        M[8,2]=M[2,8]
        M[9,2]=M[2,9]
        M[10,2]=M[2,10]
        M[11,2]=M[2,11]
        M[12,2]=M[2,12]
        M[13,2]=M[2,13]
        M[14,2]=M[2,14]
        M[15,2]=M[2,15]
        M[16,2]=M[2,16]
        M[17,2]=M[2,17]
        M[18,2]=M[2,18]
        M[19,2]=M[2,19]
        M[20,2]=M[2,20]
        M[4,3]=M[3,4]
        M[5,3]=M[3,5]
        M[6,3]=M[3,6]
        M[7,3]=M[3,7]
        M[8,3]=M[3,8]
        M[9,3]=M[3,9]
        M[10,3]=M[3,10]
        M[11,3]=M[3,11]
        M[12,3]=M[3,12]
        M[13,3]=M[3,13]
        M[14,3]=M[3,14]
        M[15,3]=M[3,15]
        M[16,3]=M[3,16]
        M[17,3]=M[3,17]
        M[18,3]=M[3,18]
        M[19,3]=M[3,19]
        M[20,3]=M[3,20]
        M[5,4]=M[4,5]
        M[6,4]=M[4,6]
        M[7,4]=M[4,7]
        M[8,4]=M[4,8]
        M[9,4]=M[4,9]
        M[10,4]=M[4,10]
        M[11,4]=M[4,11]
        M[12,4]=M[4,12]
        M[13,4]=M[4,13]
        M[14,4]=M[4,14]
        M[15,4]=M[4,15]
        M[16,4]=M[4,16]
        M[17,4]=M[4,17]
        M[18,4]=M[4,18]
        M[19,4]=M[4,19]
        M[20,4]=M[4,20]
        M[6,5]=M[5,6]
        M[7,5]=M[5,7]
        M[8,5]=M[5,8]
        M[9,5]=M[5,9]
        M[10,5]=M[5,10]
        M[11,5]=M[5,11]
        M[12,5]=M[5,12]
        M[13,5]=M[5,13]
        M[14,5]=M[5,14]
        M[15,5]=M[5,15]
        M[16,5]=M[5,16]
        M[17,5]=M[5,17]
        M[18,5]=M[5,18]
        M[19,5]=M[5,19]
        M[20,5]=M[5,20]
        M[7,6]=M[6,7]
        M[8,6]=M[6,8]
        M[9,6]=M[6,9]
        M[10,6]=M[6,10]
        M[11,6]=M[6,11]
        M[12,6]=M[6,12]
        M[13,6]=M[6,13]
        M[14,6]=M[6,14]
        M[15,6]=M[6,15]
        M[16,6]=M[6,16]
        M[17,6]=M[6,17]
        M[18,6]=M[6,18]
        M[19,6]=M[6,19]
        M[20,6]=M[6,20]
        M[8,7]=M[7,8]
        M[9,7]=M[7,9]
        M[10,7]=M[7,10]
        M[11,7]=M[7,11]
        M[12,7]=M[7,12]
        M[13,7]=M[7,13]
        M[14,7]=M[7,14]
        M[15,7]=M[7,15]
        M[16,7]=M[7,16]
        M[17,7]=M[7,17]
        M[18,7]=M[7,18]
        M[19,7]=M[7,19]
        M[20,7]=M[7,20]
        M[9,8]=M[8,9]
        M[10,8]=M[8,10]
        M[11,8]=M[8,11]
        M[12,8]=M[8,12]
        M[13,8]=M[8,13]
        M[14,8]=M[8,14]
        M[15,8]=M[8,15]
        M[16,8]=M[8,16]
        M[17,8]=M[8,17]
        M[18,8]=M[8,18]
        M[19,8]=M[8,19]
        M[20,8]=M[8,20]
        M[10,9]=M[9,10]
        M[11,9]=M[9,11]
        M[12,9]=M[9,12]
        M[13,9]=M[9,13]
        M[14,9]=M[9,14]
        M[15,9]=M[9,15]
        M[16,9]=M[9,16]
        M[17,9]=M[9,17]
        M[18,9]=M[9,18]
        M[19,9]=M[9,19]
        M[20,9]=M[9,20]
        M[11,10]=M[10,11]
        M[12,10]=M[10,12]
        M[13,10]=M[10,13]
        M[14,10]=M[10,14]
        M[15,10]=M[10,15]
        M[16,10]=M[10,16]
        M[17,10]=M[10,17]
        M[18,10]=M[10,18]
        M[19,10]=M[10,19]
        M[20,10]=M[10,20]
        M[12,11]=M[11,12]
        M[13,11]=M[11,13]
        M[14,11]=M[11,14]
        M[15,11]=M[11,15]
        M[16,11]=M[11,16]
        M[17,11]=M[11,17]
        M[18,11]=M[11,18]
        M[19,11]=M[11,19]
        M[20,11]=M[11,20]
        M[13,12]=M[12,13]
        M[14,12]=M[12,14]
        M[15,12]=M[12,15]
        M[16,12]=M[12,16]
        M[17,12]=M[12,17]
        M[18,12]=M[12,18]
        M[19,12]=M[12,19]
        M[20,12]=M[12,20]
        M[14,13]=M[13,14]
        M[15,13]=M[13,15]
        M[16,13]=M[13,16]
        M[17,13]=M[13,17]
        M[18,13]=M[13,18]
        M[19,13]=M[13,19]
        M[20,13]=M[13,20]
        M[15,14]=M[14,15]
        M[16,14]=M[14,16]
        M[17,14]=M[14,17]
        M[18,14]=M[14,18]
        M[19,14]=M[14,19]
        M[20,14]=M[14,20]
        M[16,15]=M[15,16]
        M[17,15]=M[15,17]
        M[18,15]=M[15,18]
        M[19,15]=M[15,19]
        M[20,15]=M[15,20]
        M[17,16]=M[16,17]
        M[18,16]=M[16,18]
        M[19,16]=M[16,19]
        M[20,16]=M[16,20]
        M[18,17]=M[17,18]
        M[19,17]=M[17,19]
        M[20,17]=M[17,20]
        M[19,18]=M[18,19]
        M[20,18]=M[18,20]
        M[20,19]=M[19,20]
        return recombine_hermite(J,M)*abs(J.det)
end

## partial derivatives
function s43v1du1(J,d)
        M1=     [1/24 0 0 -1/24;
                1/24 0 0 -1/24;
                1/24 0 0 -1/24;
                1/24 0 0 -1/24]

        M2=     [0 1/24 0 -1/24;
                0 1/24 0 -1/24;
                0 1/24 0 -1/24;
                0 1/24 0 -1/24]

        M3=     [0 0 1/24 -1/24;
                0 0 1/24 -1/24;
                0 0 1/24 -1/24;
                0 0 1/24 -1/24]
        return (M1.*J.inv[1,d].+M2.*J.inv[2,d].+M3.*J.inv[3,d])*abs(J.det)
end

s43dv1u1(J,d)=s43v1du1(J,d)'

function s43v1du1c1(J::CooTrafo,c,d)
        c1,c2,c3,c4=c
        M1=Array{ComplexF64}(undef,4,4)
        M2=Array{ComplexF64}(undef,4,4)
        M3=Array{ComplexF64}(undef,4,4)

        M1[1,1]=c1/60 + c2/120 + c3/120 + c4/120
        M1[1,2]=0
        M1[1,3]=0
        M1[1,4]=-c1/60 - c2/120 - c3/120 - c4/120
        M1[2,1]=c1/120 + c2/60 + c3/120 + c4/120
        M1[2,2]=0
        M1[2,3]=0
        M1[2,4]=-c1/120 - c2/60 - c3/120 - c4/120
        M1[3,1]=c1/120 + c2/120 + c3/60 + c4/120
        M1[3,2]=0
        M1[3,3]=0
        M1[3,4]=-c1/120 - c2/120 - c3/60 - c4/120
        M1[4,1]=c1/120 + c2/120 + c3/120 + c4/60
        M1[4,2]=0
        M1[4,3]=0
        M1[4,4]=-c1/120 - c2/120 - c3/120 - c4/60

        M2[1,1]=0
        M2[1,2]=c1/60 + c2/120 + c3/120 + c4/120
        M2[1,3]=0
        M2[1,4]=-c1/60 - c2/120 - c3/120 - c4/120
        M2[2,1]=0
        M2[2,2]=c1/120 + c2/60 + c3/120 + c4/120
        M2[2,3]=0
        M2[2,4]=-c1/120 - c2/60 - c3/120 - c4/120
        M2[3,1]=0
        M2[3,2]=c1/120 + c2/120 + c3/60 + c4/120
        M2[3,3]=0
        M2[3,4]=-c1/120 - c2/120 - c3/60 - c4/120
        M2[4,1]=0
        M2[4,2]=c1/120 + c2/120 + c3/120 + c4/60
        M2[4,3]=0
        M2[4,4]=-c1/120 - c2/120 - c3/120 - c4/60

        M3[1,1]=0
        M3[1,2]=0
        M3[1,3]=c1/60 + c2/120 + c3/120 + c4/120
        M3[1,4]=-c1/60 - c2/120 - c3/120 - c4/120
        M3[2,1]=0
        M3[2,2]=0
        M3[2,3]=c1/120 + c2/60 + c3/120 + c4/120
        M3[2,4]=-c1/120 - c2/60 - c3/120 - c4/120
        M3[3,1]=0
        M3[3,2]=0
        M3[3,3]=c1/120 + c2/120 + c3/60 + c4/120
        M3[3,4]=-c1/120 - c2/120 - c3/60 - c4/120
        M3[4,1]=0
        M3[4,2]=0
        M3[4,3]=c1/120 + c2/120 + c3/120 + c4/60
        M3[4,4]=-c1/120 - c2/120 - c3/120 - c4/60

        return (M1.*J.inv[1,d].+M2.*J.inv[2,d].+M3.*J.inv[3,d])*abs(J.det)
end

s43dv1u1c1(J::CooTrafo,c,d)=s43v1du1c1(J::CooTrafo,c,d)'

function s43v2du1(J::CooTrafo,d)
  M1 = [-1/120 0 0 1/120;
        -1/120 0 0 1/120;
        -1/120 0 0 1/120;
        -1/120 0 0 1/120;
        1/30 0 0 -1/30;
        1/30 0 0 -1/30;
        1/30 0 0 -1/30;
        1/30 0 0 -1/30;
        1/30 0 0 -1/30;
        1/30 0 0 -1/30]

  M2 = [0 -1/120 0 1/120;
        0 -1/120 0 1/120;
        0 -1/120 0 1/120;
        0 -1/120 0 1/120;
        0 1/30 0 -1/30;
        0 1/30 0 -1/30;
        0 1/30 0 -1/30;
        0 1/30 0 -1/30;
        0 1/30 0 -1/30;
        0 1/30 0 -1/30]

  M3 = [0 0 -1/120 1/120;
        0 0 -1/120 1/120;
        0 0 -1/120 1/120;
        0 0 -1/120 1/120;
        0 0 1/30 -1/30;
        0 0 1/30 -1/30;
        0 0 1/30 -1/30;
        0 0 1/30 -1/30;
        0 0 1/30 -1/30;
        0 0 1/30 -1/30]

        return (M1.*J.inv[1,d].+M2.*J.inv[2,d].+M3.*J.inv[3,d])*abs(J.det)
end

s43dv1u2(J::CooTrafo,d)=s43v2du1(J::CooTrafo,d)'

function s43v2du2c1(J::CooTrafo,c,d)
        c1,c2,c3,c4 = c
        M1=Array{ComplexF64}(undef,10,10)
        M2=Array{ComplexF64}(undef,10,10)
        M3=Array{ComplexF64}(undef,10,10)

        M1[1,1]=c1/210 + c2/840 + c3/840 + c4/840
        M1[1,2]=0
        M1[1,3]=0
        M1[1,4]=c1/630 - c2/2520 - c3/2520 + c4/504
        M1[1,5]=-c1/630 - c2/210 - c3/420 - c4/420
        M1[1,6]=-c1/630 - c2/420 - c3/210 - c4/420
        M1[1,7]=-2*c1/315 - c2/1260 - c3/1260 - c4/315
        M1[1,8]=0
        M1[1,9]=c1/630 + c2/210 + c3/420 + c4/420
        M1[1,10]=c1/630 + c2/420 + c3/210 + c4/420
        M1[2,1]=-c1/504 - c2/630 + c3/2520 + c4/2520
        M1[2,2]=0
        M1[2,3]=0
        M1[2,4]=-c1/2520 + c2/630 - c3/2520 + c4/504
        M1[2,5]=-c1/630 + c2/210 - c3/630 - c4/630
        M1[2,6]=-c1/420 - c2/630 - c3/210 - c4/420
        M1[2,7]=c1/420 - c4/420
        M1[2,8]=0
        M1[2,9]=c1/630 - c2/210 + c3/630 + c4/630
        M1[2,10]=c1/420 + c2/630 + c3/210 + c4/420
        M1[3,1]=-c1/504 + c2/2520 - c3/630 + c4/2520
        M1[3,2]=0
        M1[3,3]=0
        M1[3,4]=-c1/2520 - c2/2520 + c3/630 + c4/504
        M1[3,5]=-c1/420 - c2/210 - c3/630 - c4/420
        M1[3,6]=-c1/630 - c2/630 + c3/210 - c4/630
        M1[3,7]=c1/420 - c4/420
        M1[3,8]=0
        M1[3,9]=c1/420 + c2/210 + c3/630 + c4/420
        M1[3,10]=c1/630 + c2/630 - c3/210 + c4/630
        M1[4,1]=-c1/504 + c2/2520 + c3/2520 - c4/630
        M1[4,2]=0
        M1[4,3]=0
        M1[4,4]=-c1/840 - c2/840 - c3/840 - c4/210
        M1[4,5]=-c1/420 - c2/210 - c3/420 - c4/630
        M1[4,6]=-c1/420 - c2/420 - c3/210 - c4/630
        M1[4,7]=c1/315 + c2/1260 + c3/1260 + 2*c4/315
        M1[4,8]=0
        M1[4,9]=c1/420 + c2/210 + c3/420 + c4/630
        M1[4,10]=c1/420 + c2/420 + c3/210 + c4/630
        M1[5,1]=c1/126 + c2/630 + c3/1260 + c4/1260
        M1[5,2]=0
        M1[5,3]=0
        M1[5,4]=c1/210 + c2/210 + c3/420 - c4/1260
        M1[5,5]=4*c1/315 + 2*c2/105 + 2*c3/315 + 2*c4/315
        M1[5,6]=2*c1/315 + 2*c2/315 + 2*c3/315 + c4/315
        M1[5,7]=-4*c1/315 - 2*c2/315 - c3/315
        M1[5,8]=0
        M1[5,9]=-4*c1/315 - 2*c2/105 - 2*c3/315 - 2*c4/315
        M1[5,10]=-2*c1/315 - 2*c2/315 - 2*c3/315 - c4/315
        M1[6,1]=c1/126 + c2/1260 + c3/630 + c4/1260
        M1[6,2]=0
        M1[6,3]=0
        M1[6,4]=c1/210 + c2/420 + c3/210 - c4/1260
        M1[6,5]=2*c1/315 + 2*c2/315 + 2*c3/315 + c4/315
        M1[6,6]=4*c1/315 + 2*c2/315 + 2*c3/105 + 2*c4/315
        M1[6,7]=-4*c1/315 - c2/315 - 2*c3/315
        M1[6,8]=0
        M1[6,9]=-2*c1/315 - 2*c2/315 - 2*c3/315 - c4/315
        M1[6,10]=-4*c1/315 - 2*c2/315 - 2*c3/105 - 2*c4/315
        M1[7,1]=c1/126 + c2/1260 + c3/1260 + c4/630
        M1[7,2]=0
        M1[7,3]=0
        M1[7,4]=-c1/630 - c2/1260 - c3/1260 - c4/126
        M1[7,5]=2*c1/315 + 2*c2/315 + c3/315 + 2*c4/315
        M1[7,6]=2*c1/315 + c2/315 + 2*c3/315 + 2*c4/315
        M1[7,7]=-2*c1/315 + 2*c4/315
        M1[7,8]=0
        M1[7,9]=-2*c1/315 - 2*c2/315 - c3/315 - 2*c4/315
        M1[7,10]=-2*c1/315 - c2/315 - 2*c3/315 - 2*c4/315
        M1[8,1]=c1/1260 - c2/210 - c3/210 - c4/420
        M1[8,2]=0
        M1[8,3]=0
        M1[8,4]=c1/420 + c2/210 + c3/210 - c4/1260
        M1[8,5]=2*c1/315 + 2*c2/105 + 4*c3/315 + 2*c4/315
        M1[8,6]=2*c1/315 + 4*c2/315 + 2*c3/105 + 2*c4/315
        M1[8,7]=-c1/315 + c4/315
        M1[8,8]=0
        M1[8,9]=-2*c1/315 - 2*c2/105 - 4*c3/315 - 2*c4/315
        M1[8,10]=-2*c1/315 - 4*c2/315 - 2*c3/105 - 2*c4/315
        M1[9,1]=c1/1260 - c2/210 - c3/420 - c4/210
        M1[9,2]=0
        M1[9,3]=0
        M1[9,4]=-c1/1260 - c2/630 - c3/1260 - c4/126
        M1[9,5]=2*c1/315 + 2*c2/105 + 2*c3/315 + 4*c4/315
        M1[9,6]=c1/315 + 2*c2/315 + 2*c3/315 + 2*c4/315
        M1[9,7]=2*c2/315 + c3/315 + 4*c4/315
        M1[9,8]=0
        M1[9,9]=-2*c1/315 - 2*c2/105 - 2*c3/315 - 4*c4/315
        M1[9,10]=-c1/315 - 2*c2/315 - 2*c3/315 - 2*c4/315
        M1[10,1]=c1/1260 - c2/420 - c3/210 - c4/210
        M1[10,2]=0
        M1[10,3]=0
        M1[10,4]=-c1/1260 - c2/1260 - c3/630 - c4/126
        M1[10,5]=c1/315 + 2*c2/315 + 2*c3/315 + 2*c4/315
        M1[10,6]=2*c1/315 + 2*c2/315 + 2*c3/105 + 4*c4/315
        M1[10,7]=c2/315 + 2*c3/315 + 4*c4/315
        M1[10,8]=0
        M1[10,9]=-c1/315 - 2*c2/315 - 2*c3/315 - 2*c4/315
        M1[10,10]=-2*c1/315 - 2*c2/315 - 2*c3/105 - 4*c4/315

        M2[1,1]=0
        M2[1,2]=-c1/630 - c2/504 + c3/2520 + c4/2520
        M2[1,3]=0
        M2[1,4]=c1/630 - c2/2520 - c3/2520 + c4/504
        M2[1,5]=c1/210 - c2/630 - c3/630 - c4/630
        M2[1,6]=0
        M2[1,7]=-c1/210 + c2/630 + c3/630 + c4/630
        M2[1,8]=-c1/630 - c2/420 - c3/210 - c4/420
        M2[1,9]=c2/420 - c4/420
        M2[1,10]=c1/630 + c2/420 + c3/210 + c4/420
        M2[2,1]=0
        M2[2,2]=c1/840 + c2/210 + c3/840 + c4/840
        M2[2,3]=0
        M2[2,4]=-c1/2520 + c2/630 - c3/2520 + c4/504
        M2[2,5]=-c1/210 - c2/630 - c3/420 - c4/420
        M2[2,6]=0
        M2[2,7]=c1/210 + c2/630 + c3/420 + c4/420
        M2[2,8]=-c1/420 - c2/630 - c3/210 - c4/420
        M2[2,9]=-c1/1260 - 2*c2/315 - c3/1260 - c4/315
        M2[2,10]=c1/420 + c2/630 + c3/210 + c4/420
        M2[3,1]=0
        M2[3,2]=c1/2520 - c2/504 - c3/630 + c4/2520
        M2[3,3]=0
        M2[3,4]=-c1/2520 - c2/2520 + c3/630 + c4/504
        M2[3,5]=-c1/210 - c2/420 - c3/630 - c4/420
        M2[3,6]=0
        M2[3,7]=c1/210 + c2/420 + c3/630 + c4/420
        M2[3,8]=-c1/630 - c2/630 + c3/210 - c4/630
        M2[3,9]=c2/420 - c4/420
        M2[3,10]=c1/630 + c2/630 - c3/210 + c4/630
        M2[4,1]=0
        M2[4,2]=c1/2520 - c2/504 + c3/2520 - c4/630
        M2[4,3]=0
        M2[4,4]=-c1/840 - c2/840 - c3/840 - c4/210
        M2[4,5]=-c1/210 - c2/420 - c3/420 - c4/630
        M2[4,6]=0
        M2[4,7]=c1/210 + c2/420 + c3/420 + c4/630
        M2[4,8]=-c1/420 - c2/420 - c3/210 - c4/630
        M2[4,9]=c1/1260 + c2/315 + c3/1260 + 2*c4/315
        M2[4,10]=c1/420 + c2/420 + c3/210 + c4/630
        M2[5,1]=0
        M2[5,2]=c1/630 + c2/126 + c3/1260 + c4/1260
        M2[5,3]=0
        M2[5,4]=c1/210 + c2/210 + c3/420 - c4/1260
        M2[5,5]=2*c1/105 + 4*c2/315 + 2*c3/315 + 2*c4/315
        M2[5,6]=0
        M2[5,7]=-2*c1/105 - 4*c2/315 - 2*c3/315 - 2*c4/315
        M2[5,8]=2*c1/315 + 2*c2/315 + 2*c3/315 + c4/315
        M2[5,9]=-2*c1/315 - 4*c2/315 - c3/315
        M2[5,10]=-2*c1/315 - 2*c2/315 - 2*c3/315 - c4/315
        M2[6,1]=0
        M2[6,2]=-c1/210 + c2/1260 - c3/210 - c4/420
        M2[6,3]=0
        M2[6,4]=c1/210 + c2/420 + c3/210 - c4/1260
        M2[6,5]=2*c1/105 + 2*c2/315 + 4*c3/315 + 2*c4/315
        M2[6,6]=0
        M2[6,7]=-2*c1/105 - 2*c2/315 - 4*c3/315 - 2*c4/315
        M2[6,8]=4*c1/315 + 2*c2/315 + 2*c3/105 + 2*c4/315
        M2[6,9]=-c2/315 + c4/315
        M2[6,10]=-4*c1/315 - 2*c2/315 - 2*c3/105 - 2*c4/315
        M2[7,1]=0
        M2[7,2]=-c1/210 + c2/1260 - c3/420 - c4/210
        M2[7,3]=0
        M2[7,4]=-c1/630 - c2/1260 - c3/1260 - c4/126
        M2[7,5]=2*c1/105 + 2*c2/315 + 2*c3/315 + 4*c4/315
        M2[7,6]=0
        M2[7,7]=-2*c1/105 - 2*c2/315 - 2*c3/315 - 4*c4/315
        M2[7,8]=2*c1/315 + c2/315 + 2*c3/315 + 2*c4/315
        M2[7,9]=2*c1/315 + c3/315 + 4*c4/315
        M2[7,10]=-2*c1/315 - c2/315 - 2*c3/315 - 2*c4/315
        M2[8,1]=0
        M2[8,2]=c1/1260 + c2/126 + c3/630 + c4/1260
        M2[8,3]=0
        M2[8,4]=c1/420 + c2/210 + c3/210 - c4/1260
        M2[8,5]=2*c1/315 + 2*c2/315 + 2*c3/315 + c4/315
        M2[8,6]=0
        M2[8,7]=-2*c1/315 - 2*c2/315 - 2*c3/315 - c4/315
        M2[8,8]=2*c1/315 + 4*c2/315 + 2*c3/105 + 2*c4/315
        M2[8,9]=-c1/315 - 4*c2/315 - 2*c3/315
        M2[8,10]=-2*c1/315 - 4*c2/315 - 2*c3/105 - 2*c4/315
        M2[9,1]=0
        M2[9,2]=c1/1260 + c2/126 + c3/1260 + c4/630
        M2[9,3]=0
        M2[9,4]=-c1/1260 - c2/630 - c3/1260 - c4/126
        M2[9,5]=2*c1/315 + 2*c2/315 + c3/315 + 2*c4/315
        M2[9,6]=0
        M2[9,7]=-2*c1/315 - 2*c2/315 - c3/315 - 2*c4/315
        M2[9,8]=c1/315 + 2*c2/315 + 2*c3/315 + 2*c4/315
        M2[9,9]=-2*c2/315 + 2*c4/315
        M2[9,10]=-c1/315 - 2*c2/315 - 2*c3/315 - 2*c4/315
        M2[10,1]=0
        M2[10,2]=-c1/420 + c2/1260 - c3/210 - c4/210
        M2[10,3]=0
        M2[10,4]=-c1/1260 - c2/1260 - c3/630 - c4/126
        M2[10,5]=2*c1/315 + c2/315 + 2*c3/315 + 2*c4/315
        M2[10,6]=0
        M2[10,7]=-2*c1/315 - c2/315 - 2*c3/315 - 2*c4/315
        M2[10,8]=2*c1/315 + 2*c2/315 + 2*c3/105 + 4*c4/315
        M2[10,9]=c1/315 + 2*c3/315 + 4*c4/315
        M2[10,10]=-2*c1/315 - 2*c2/315 - 2*c3/105 - 4*c4/315

        M3[1,1]=0
        M3[1,2]=0
        M3[1,3]=-c1/630 + c2/2520 - c3/504 + c4/2520
        M3[1,4]=c1/630 - c2/2520 - c3/2520 + c4/504
        M3[1,5]=0
        M3[1,6]=c1/210 - c2/630 - c3/630 - c4/630
        M3[1,7]=-c1/210 + c2/630 + c3/630 + c4/630
        M3[1,8]=-c1/630 - c2/210 - c3/420 - c4/420
        M3[1,9]=c1/630 + c2/210 + c3/420 + c4/420
        M3[1,10]=c3/420 - c4/420
        M3[2,1]=0
        M3[2,2]=0
        M3[2,3]=c1/2520 - c2/630 - c3/504 + c4/2520
        M3[2,4]=-c1/2520 + c2/630 - c3/2520 + c4/504
        M3[2,5]=0
        M3[2,6]=-c1/210 - c2/630 - c3/420 - c4/420
        M3[2,7]=c1/210 + c2/630 + c3/420 + c4/420
        M3[2,8]=-c1/630 + c2/210 - c3/630 - c4/630
        M3[2,9]=c1/630 - c2/210 + c3/630 + c4/630
        M3[2,10]=c3/420 - c4/420
        M3[3,1]=0
        M3[3,2]=0
        M3[3,3]=c1/840 + c2/840 + c3/210 + c4/840
        M3[3,4]=-c1/2520 - c2/2520 + c3/630 + c4/504
        M3[3,5]=0
        M3[3,6]=-c1/210 - c2/420 - c3/630 - c4/420
        M3[3,7]=c1/210 + c2/420 + c3/630 + c4/420
        M3[3,8]=-c1/420 - c2/210 - c3/630 - c4/420
        M3[3,9]=c1/420 + c2/210 + c3/630 + c4/420
        M3[3,10]=-c1/1260 - c2/1260 - 2*c3/315 - c4/315
        M3[4,1]=0
        M3[4,2]=0
        M3[4,3]=c1/2520 + c2/2520 - c3/504 - c4/630
        M3[4,4]=-c1/840 - c2/840 - c3/840 - c4/210
        M3[4,5]=0
        M3[4,6]=-c1/210 - c2/420 - c3/420 - c4/630
        M3[4,7]=c1/210 + c2/420 + c3/420 + c4/630
        M3[4,8]=-c1/420 - c2/210 - c3/420 - c4/630
        M3[4,9]=c1/420 + c2/210 + c3/420 + c4/630
        M3[4,10]=c1/1260 + c2/1260 + c3/315 + 2*c4/315
        M3[5,1]=0
        M3[5,2]=0
        M3[5,3]=-c1/210 - c2/210 + c3/1260 - c4/420
        M3[5,4]=c1/210 + c2/210 + c3/420 - c4/1260
        M3[5,5]=0
        M3[5,6]=2*c1/105 + 4*c2/315 + 2*c3/315 + 2*c4/315
        M3[5,7]=-2*c1/105 - 4*c2/315 - 2*c3/315 - 2*c4/315
        M3[5,8]=4*c1/315 + 2*c2/105 + 2*c3/315 + 2*c4/315
        M3[5,9]=-4*c1/315 - 2*c2/105 - 2*c3/315 - 2*c4/315
        M3[5,10]=-c3/315 + c4/315
        M3[6,1]=0
        M3[6,2]=0
        M3[6,3]=c1/630 + c2/1260 + c3/126 + c4/1260
        M3[6,4]=c1/210 + c2/420 + c3/210 - c4/1260
        M3[6,5]=0
        M3[6,6]=2*c1/105 + 2*c2/315 + 4*c3/315 + 2*c4/315
        M3[6,7]=-2*c1/105 - 2*c2/315 - 4*c3/315 - 2*c4/315
        M3[6,8]=2*c1/315 + 2*c2/315 + 2*c3/315 + c4/315
        M3[6,9]=-2*c1/315 - 2*c2/315 - 2*c3/315 - c4/315
        M3[6,10]=-2*c1/315 - c2/315 - 4*c3/315
        M3[7,1]=0
        M3[7,2]=0
        M3[7,3]=-c1/210 - c2/420 + c3/1260 - c4/210
        M3[7,4]=-c1/630 - c2/1260 - c3/1260 - c4/126
        M3[7,5]=0
        M3[7,6]=2*c1/105 + 2*c2/315 + 2*c3/315 + 4*c4/315
        M3[7,7]=-2*c1/105 - 2*c2/315 - 2*c3/315 - 4*c4/315
        M3[7,8]=2*c1/315 + 2*c2/315 + c3/315 + 2*c4/315
        M3[7,9]=-2*c1/315 - 2*c2/315 - c3/315 - 2*c4/315
        M3[7,10]=2*c1/315 + c2/315 + 4*c4/315
        M3[8,1]=0
        M3[8,2]=0
        M3[8,3]=c1/1260 + c2/630 + c3/126 + c4/1260
        M3[8,4]=c1/420 + c2/210 + c3/210 - c4/1260
        M3[8,5]=0
        M3[8,6]=2*c1/315 + 2*c2/315 + 2*c3/315 + c4/315
        M3[8,7]=-2*c1/315 - 2*c2/315 - 2*c3/315 - c4/315
        M3[8,8]=2*c1/315 + 2*c2/105 + 4*c3/315 + 2*c4/315
        M3[8,9]=-2*c1/315 - 2*c2/105 - 4*c3/315 - 2*c4/315
        M3[8,10]=-c1/315 - 2*c2/315 - 4*c3/315
        M3[9,1]=0
        M3[9,2]=0
        M3[9,3]=-c1/420 - c2/210 + c3/1260 - c4/210
        M3[9,4]=-c1/1260 - c2/630 - c3/1260 - c4/126
        M3[9,5]=0
        M3[9,6]=2*c1/315 + 2*c2/315 + c3/315 + 2*c4/315
        M3[9,7]=-2*c1/315 - 2*c2/315 - c3/315 - 2*c4/315
        M3[9,8]=2*c1/315 + 2*c2/105 + 2*c3/315 + 4*c4/315
        M3[9,9]=-2*c1/315 - 2*c2/105 - 2*c3/315 - 4*c4/315
        M3[9,10]=c1/315 + 2*c2/315 + 4*c4/315
        M3[10,1]=0
        M3[10,2]=0
        M3[10,3]=c1/1260 + c2/1260 + c3/126 + c4/630
        M3[10,4]=-c1/1260 - c2/1260 - c3/630 - c4/126
        M3[10,5]=0
        M3[10,6]=2*c1/315 + c2/315 + 2*c3/315 + 2*c4/315
        M3[10,7]=-2*c1/315 - c2/315 - 2*c3/315 - 2*c4/315
        M3[10,8]=c1/315 + 2*c2/315 + 2*c3/315 + 2*c4/315
        M3[10,9]=-c1/315 - 2*c2/315 - 2*c3/315 - 2*c4/315
        M3[10,10]=-2*c3/315 + 2*c4/315

        return (M1.*J.inv[1,d].+M2.*J.inv[2,d].+M3.*J.inv[3,d])*abs(J.det)
end


#this function is unnescessary
function s43v1u1dc1(J::CooTrafo,c,d)
        c1,c2,c3,c4=c
        M = [1/60 1/120 1/120 1/120;
              1/120 1/60 1/120 1/120;
              1/120 1/120 1/60 1/120;
              1/120 1/120 1/120 1/60]

        return ([c1-c4, c2-c4, c3-c4]*J.inv[:,d]).*M*abs(J.det)
end

# nabla operations aka stiffness matrices
function s43nv1nu1(J::CooTrafo)
        A=J.inv*J.inv'
        M=Array{Float64}(undef,4,4)
        M[1,1]=A[1,1]/6
        M[1,2]=A[1,2]/6
        M[1,3]=A[1,3]/6
        M[1,4]=-A[1,1]/6 - A[1,2]/6 - A[1,3]/6
        M[2,2]=A[2,2]/6
        M[2,3]=A[2,3]/6
        M[2,4]=-A[1,2]/6 - A[2,2]/6 - A[2,3]/6
        M[3,3]=A[3,3]/6
        M[3,4]=-A[1,3]/6 - A[2,3]/6 - A[3,3]/6
        M[4,4]=A[1,1]/6 + A[1,2]/3 + A[1,3]/3 + A[2,2]/6 + A[2,3]/3 + A[3,3]/6
        M[2,1]=M[1,2]
        M[3,1]=M[1,3]
        M[4,1]=M[1,4]
        M[3,2]=M[2,3]
        M[4,2]=M[2,4]
        M[4,3]=M[3,4]
        return M*abs(J.det)
end


function s43nv2nu2(J::CooTrafo)
        A=J.inv*J.inv'
        M=Array{Float64}(undef,10,10)

        M[1,1]=A[1,1]/10
        M[1,2]=-A[1,2]/30
        M[1,3]=-A[1,3]/30
        M[1,4]=A[1,1]/30 + A[1,2]/30 + A[1,3]/30
        M[1,5]=-A[1,1]/30 + A[1,2]/10
        M[1,6]=-A[1,1]/30 + A[1,3]/10
        M[1,7]=-2*A[1,1]/15 - A[1,2]/10 - A[1,3]/10
        M[1,8]=-A[1,2]/30 - A[1,3]/30
        M[1,9]=A[1,1]/30 + A[1,3]/30
        M[1,10]=A[1,1]/30 + A[1,2]/30
        M[2,2]=A[2,2]/10
        M[2,3]=-A[2,3]/30
        M[2,4]=A[1,2]/30 + A[2,2]/30 + A[2,3]/30
        M[2,5]=A[1,2]/10 - A[2,2]/30
        M[2,6]=-A[1,2]/30 - A[2,3]/30
        M[2,7]=A[2,2]/30 + A[2,3]/30
        M[2,8]=-A[2,2]/30 + A[2,3]/10
        M[2,9]=-A[1,2]/10 - 2*A[2,2]/15 - A[2,3]/10
        M[2,10]=A[1,2]/30 + A[2,2]/30
        M[3,3]=A[3,3]/10
        M[3,4]=A[1,3]/30 + A[2,3]/30 + A[3,3]/30
        M[3,5]=-A[1,3]/30 - A[2,3]/30
        M[3,6]=A[1,3]/10 - A[3,3]/30
        M[3,7]=A[2,3]/30 + A[3,3]/30
        M[3,8]=A[2,3]/10 - A[3,3]/30
        M[3,9]=A[1,3]/30 + A[3,3]/30
        M[3,10]=-A[1,3]/10 - A[2,3]/10 - 2*A[3,3]/15
        M[4,4]=A[1,1]/10 + A[1,2]/5 + A[1,3]/5 + A[2,2]/10 + A[2,3]/5 + A[3,3]/10
        M[4,5]=A[1,1]/30 + A[1,2]/15 + A[1,3]/30 + A[2,2]/30 + A[2,3]/30
        M[4,6]=A[1,1]/30 + A[1,2]/30 + A[1,3]/15 + A[2,3]/30 + A[3,3]/30
        M[4,7]=-2*A[1,1]/15 - A[1,2]/6 - A[1,3]/6 - A[2,2]/30 - A[2,3]/15 - A[3,3]/30
        M[4,8]=A[1,2]/30 + A[1,3]/30 + A[2,2]/30 + A[2,3]/15 + A[3,3]/30
        M[4,9]=-A[1,1]/30 - A[1,2]/6 - A[1,3]/15 - 2*A[2,2]/15 - A[2,3]/6 - A[3,3]/30
        M[4,10]=-A[1,1]/30 - A[1,2]/15 - A[1,3]/6 - A[2,2]/30 - A[2,3]/6 - 2*A[3,3]/15
        M[5,5]=4*A[1,1]/15 + 4*A[1,2]/15 + 4*A[2,2]/15
        M[5,6]=2*A[1,1]/15 + 2*A[1,2]/15 + 2*A[1,3]/15 + 4*A[2,3]/15
        M[5,7]=-4*A[1,2]/15 - 2*A[1,3]/15 - 4*A[2,2]/15 - 4*A[2,3]/15
        M[5,8]=2*A[1,2]/15 + 4*A[1,3]/15 + 2*A[2,2]/15 + 2*A[2,3]/15
        M[5,9]=-4*A[1,1]/15 - 4*A[1,2]/15 - 4*A[1,3]/15 - 2*A[2,3]/15
        M[5,10]=-2*A[1,1]/15 - 4*A[1,2]/15 - 2*A[2,2]/15
        M[6,6]=4*A[1,1]/15 + 4*A[1,3]/15 + 4*A[3,3]/15
        M[6,7]=-2*A[1,2]/15 - 4*A[1,3]/15 - 4*A[2,3]/15 - 4*A[3,3]/15
        M[6,8]=4*A[1,2]/15 + 2*A[1,3]/15 + 2*A[2,3]/15 + 2*A[3,3]/15
        M[6,9]=-2*A[1,1]/15 - 4*A[1,3]/15 - 2*A[3,3]/15
        M[6,10]=-4*A[1,1]/15 - 4*A[1,2]/15 - 4*A[1,3]/15 - 2*A[2,3]/15
        M[7,7]=4*A[1,1]/15 + 4*A[1,2]/15 + 4*A[1,3]/15 + 4*A[2,2]/15 + 8*A[2,3]/15 + 4*A[3,3]/15
        M[7,8]=-2*A[2,2]/15 - 4*A[2,3]/15 - 2*A[3,3]/15
        M[7,9]=4*A[1,2]/15 + 2*A[1,3]/15 + 2*A[2,3]/15 + 2*A[3,3]/15
        M[7,10]=2*A[1,2]/15 + 4*A[1,3]/15 + 2*A[2,2]/15 + 2*A[2,3]/15
        M[8,8]=4*A[2,2]/15 + 4*A[2,3]/15 + 4*A[3,3]/15
        M[8,9]=-2*A[1,2]/15 - 4*A[1,3]/15 - 4*A[2,3]/15 - 4*A[3,3]/15
        M[8,10]=-4*A[1,2]/15 - 2*A[1,3]/15 - 4*A[2,2]/15 - 4*A[2,3]/15
        M[9,9]=4*A[1,1]/15 + 4*A[1,2]/15 + 8*A[1,3]/15 + 4*A[2,2]/15 + 4*A[2,3]/15 + 4*A[3,3]/15
        M[9,10]=2*A[1,1]/15 + 2*A[1,2]/15 + 2*A[1,3]/15 + 4*A[2,3]/15
        M[10,10]=4*A[1,1]/15 + 8*A[1,2]/15 + 4*A[1,3]/15 + 4*A[2,2]/15 + 4*A[2,3]/15 + 4*A[3,3]/15
        M[2,1]=M[1,2]
        M[3,1]=M[1,3]
        M[4,1]=M[1,4]
        M[5,1]=M[1,5]
        M[6,1]=M[1,6]
        M[7,1]=M[1,7]
        M[8,1]=M[1,8]
        M[9,1]=M[1,9]
        M[10,1]=M[1,10]
        M[3,2]=M[2,3]
        M[4,2]=M[2,4]
        M[5,2]=M[2,5]
        M[6,2]=M[2,6]
        M[7,2]=M[2,7]
        M[8,2]=M[2,8]
        M[9,2]=M[2,9]
        M[10,2]=M[2,10]
        M[4,3]=M[3,4]
        M[5,3]=M[3,5]
        M[6,3]=M[3,6]
        M[7,3]=M[3,7]
        M[8,3]=M[3,8]
        M[9,3]=M[3,9]
        M[10,3]=M[3,10]
        M[5,4]=M[4,5]
        M[6,4]=M[4,6]
        M[7,4]=M[4,7]
        M[8,4]=M[4,8]
        M[9,4]=M[4,9]
        M[10,4]=M[4,10]
        M[6,5]=M[5,6]
        M[7,5]=M[5,7]
        M[8,5]=M[5,8]
        M[9,5]=M[5,9]
        M[10,5]=M[5,10]
        M[7,6]=M[6,7]
        M[8,6]=M[6,8]
        M[9,6]=M[6,9]
        M[10,6]=M[6,10]
        M[8,7]=M[7,8]
        M[9,7]=M[7,9]
        M[10,7]=M[7,10]
        M[9,8]=M[8,9]
        M[10,8]=M[8,10]
        M[10,9]=M[9,10]

        return M*abs(J.det)
end

function s43nvhnuh(J::CooTrafo)
        A=J.inv*J.inv'
        M=Array{Float64}(undef,20,20)
        M[1,1]=433*A[1,1]/1260 + 7*A[1,2]/180 + 7*A[1,3]/180 + 7*A[2,2]/180 + 7*A[2,3]/180 + 7*A[3,3]/180
        M[1,2]=A[1,1]/12 + 43*A[1,2]/1260 + 7*A[1,3]/360 + A[2,2]/12 + 7*A[2,3]/360 + 7*A[3,3]/360
        M[1,3]=A[1,1]/12 + 7*A[1,2]/360 + 43*A[1,3]/1260 + 7*A[2,2]/360 + 7*A[2,3]/360 + A[3,3]/12
        M[1,4]=167*A[1,1]/1260 + 167*A[1,2]/1260 + 167*A[1,3]/1260 + A[2,2]/12 + 53*A[2,3]/360 + A[3,3]/12
        M[1,5]=-97*A[1,1]/1260 - A[1,2]/90 - A[1,3]/90 - A[2,2]/90 - A[2,3]/90 - A[3,3]/90
        M[1,6]=19*A[1,1]/1260 + 13*A[1,2]/630 + A[2,2]/90
        M[1,7]=19*A[1,1]/1260 + 13*A[1,3]/630 + A[3,3]/90
        M[1,8]=A[1,1]/180 + A[1,2]/630 + A[1,3]/630 + A[2,2]/90 + A[2,3]/45 + A[3,3]/90
        M[1,9]=A[1,1]/30 + A[1,2]/35 + A[2,2]/180
        M[1,10]=-A[1,1]/42 - 23*A[1,2]/2520 - A[1,3]/180 - 7*A[2,2]/360 - A[2,3]/180 - A[3,3]/180
        M[1,11]=-A[1,2]/168 - 11*A[1,3]/1260 + A[2,2]/360 + A[2,3]/180 + A[3,3]/180
        M[1,12]=A[1,1]/70 + A[1,2]/120 + 5*A[1,3]/252 + A[2,2]/360 + A[2,3]/180 + A[3,3]/180
        M[1,13]=A[1,1]/30 + A[1,3]/35 + A[3,3]/180
        M[1,14]=-11*A[1,2]/1260 - A[1,3]/168 + A[2,2]/180 + A[2,3]/180 + A[3,3]/360
        M[1,15]=-A[1,1]/42 - A[1,2]/180 - 23*A[1,3]/2520 - A[2,2]/180 - A[2,3]/180 - 7*A[3,3]/360
        M[1,16]=A[1,1]/70 + 5*A[1,2]/252 + A[1,3]/120 + A[2,2]/180 + A[2,3]/180 + A[3,3]/360
        M[1,17]=-3*A[1,1]/280 - 3*A[1,2]/40 - 3*A[1,3]/40 - 3*A[2,2]/40 - 3*A[2,3]/40 - 3*A[3,3]/40
        M[1,18]=-9*A[1,1]/28 - 93*A[1,2]/280 - 3*A[1,3]/20 - 3*A[2,3]/20 - 3*A[3,3]/20
        M[1,19]=-9*A[1,1]/28 - 3*A[1,2]/20 - 93*A[1,3]/280 - 3*A[2,2]/20 - 3*A[2,3]/20
        M[1,20]=3*A[1,1]/280 + 93*A[1,2]/280 + 93*A[1,3]/280 + 3*A[2,3]/20
        M[2,2]=7*A[1,1]/180 + 7*A[1,2]/180 + 7*A[1,3]/180 + 433*A[2,2]/1260 + 7*A[2,3]/180 + 7*A[3,3]/180
        M[2,3]=7*A[1,1]/360 + 7*A[1,2]/360 + 7*A[1,3]/360 + A[2,2]/12 + 43*A[2,3]/1260 + A[3,3]/12
        M[2,4]=A[1,1]/12 + 167*A[1,2]/1260 + 53*A[1,3]/360 + 167*A[2,2]/1260 + 167*A[2,3]/1260 + A[3,3]/12
        M[2,5]=-7*A[1,1]/360 - 23*A[1,2]/2520 - A[1,3]/180 - A[2,2]/42 - A[2,3]/180 - A[3,3]/180
        M[2,6]=A[1,1]/180 + A[1,2]/35 + A[2,2]/30
        M[2,7]=A[1,1]/360 - A[1,2]/168 + A[1,3]/180 - 11*A[2,3]/1260 + A[3,3]/180
        M[2,8]=A[1,1]/360 + A[1,2]/120 + A[1,3]/180 + A[2,2]/70 + 5*A[2,3]/252 + A[3,3]/180
        M[2,9]=A[1,1]/90 + 13*A[1,2]/630 + 19*A[2,2]/1260
        M[2,10]=-A[1,1]/90 - A[1,2]/90 - A[1,3]/90 - 97*A[2,2]/1260 - A[2,3]/90 - A[3,3]/90
        M[2,11]=19*A[2,2]/1260 + 13*A[2,3]/630 + A[3,3]/90
        M[2,12]=A[1,1]/90 + A[1,2]/630 + A[1,3]/45 + A[2,2]/180 + A[2,3]/630 + A[3,3]/90
        M[2,13]=A[1,1]/180 - 11*A[1,2]/1260 + A[1,3]/180 - A[2,3]/168 + A[3,3]/360
        M[2,14]=A[2,2]/30 + A[2,3]/35 + A[3,3]/180
        M[2,15]=-A[1,1]/180 - A[1,2]/180 - A[1,3]/180 - A[2,2]/42 - 23*A[2,3]/2520 - 7*A[3,3]/360
        M[2,16]=A[1,1]/180 + 5*A[1,2]/252 + A[1,3]/180 + A[2,2]/70 + A[2,3]/120 + A[3,3]/360
        M[2,17]=-93*A[1,2]/280 - 3*A[1,3]/20 - 9*A[2,2]/28 - 3*A[2,3]/20 - 3*A[3,3]/20
        M[2,18]=-3*A[1,1]/40 - 3*A[1,2]/40 - 3*A[1,3]/40 - 3*A[2,2]/280 - 3*A[2,3]/40 - 3*A[3,3]/40
        M[2,19]=-3*A[1,1]/20 - 3*A[1,2]/20 - 3*A[1,3]/20 - 9*A[2,2]/28 - 93*A[2,3]/280
        M[2,20]=93*A[1,2]/280 + 3*A[1,3]/20 + 3*A[2,2]/280 + 93*A[2,3]/280
        M[3,3]=7*A[1,1]/180 + 7*A[1,2]/180 + 7*A[1,3]/180 + 7*A[2,2]/180 + 7*A[2,3]/180 + 433*A[3,3]/1260
        M[3,4]=A[1,1]/12 + 53*A[1,2]/360 + 167*A[1,3]/1260 + A[2,2]/12 + 167*A[2,3]/1260 + 167*A[3,3]/1260
        M[3,5]=-7*A[1,1]/360 - A[1,2]/180 - 23*A[1,3]/2520 - A[2,2]/180 - A[2,3]/180 - A[3,3]/42
        M[3,6]=A[1,1]/360 + A[1,2]/180 - A[1,3]/168 + A[2,2]/180 - 11*A[2,3]/1260
        M[3,7]=A[1,1]/180 + A[1,3]/35 + A[3,3]/30
        M[3,8]=A[1,1]/360 + A[1,2]/180 + A[1,3]/120 + A[2,2]/180 + 5*A[2,3]/252 + A[3,3]/70
        M[3,9]=A[1,1]/180 + A[1,2]/180 - 11*A[1,3]/1260 + A[2,2]/360 - A[2,3]/168
        M[3,10]=-A[1,1]/180 - A[1,2]/180 - A[1,3]/180 - 7*A[2,2]/360 - 23*A[2,3]/2520 - A[3,3]/42
        M[3,11]=A[2,2]/180 + A[2,3]/35 + A[3,3]/30
        M[3,12]=A[1,1]/180 + A[1,2]/180 + 5*A[1,3]/252 + A[2,2]/360 + A[2,3]/120 + A[3,3]/70
        M[3,13]=A[1,1]/90 + 13*A[1,3]/630 + 19*A[3,3]/1260
        M[3,14]=A[2,2]/90 + 13*A[2,3]/630 + 19*A[3,3]/1260
        M[3,15]=-A[1,1]/90 - A[1,2]/90 - A[1,3]/90 - A[2,2]/90 - A[2,3]/90 - 97*A[3,3]/1260
        M[3,16]=A[1,1]/90 + A[1,2]/45 + A[1,3]/630 + A[2,2]/90 + A[2,3]/630 + A[3,3]/180
        M[3,17]=-3*A[1,2]/20 - 93*A[1,3]/280 - 3*A[2,2]/20 - 3*A[2,3]/20 - 9*A[3,3]/28
        M[3,18]=-3*A[1,1]/20 - 3*A[1,2]/20 - 3*A[1,3]/20 - 93*A[2,3]/280 - 9*A[3,3]/28
        M[3,19]=-3*A[1,1]/40 - 3*A[1,2]/40 - 3*A[1,3]/40 - 3*A[2,2]/40 - 3*A[2,3]/40 - 3*A[3,3]/280
        M[3,20]=3*A[1,2]/20 + 93*A[1,3]/280 + 93*A[2,3]/280 + 3*A[3,3]/280
        M[4,4]=433*A[1,1]/1260 + 817*A[1,2]/1260 + 817*A[1,3]/1260 + 433*A[2,2]/1260 + 817*A[2,3]/1260 + 433*A[3,3]/1260
        M[4,5]=-43*A[1,1]/1260 - 97*A[1,2]/2520 - 97*A[1,3]/2520 - A[2,2]/42 - 53*A[2,3]/1260 - A[3,3]/42
        M[4,6]=11*A[1,1]/1260 + 17*A[1,2]/840 + A[1,3]/168 + A[2,2]/70 + 11*A[2,3]/1260
        M[4,7]=11*A[1,1]/1260 + A[1,2]/168 + 17*A[1,3]/840 + 11*A[2,3]/1260 + A[3,3]/70
        M[4,8]=13*A[1,1]/1260 + 4*A[1,2]/105 + 4*A[1,3]/105 + A[2,2]/30 + A[2,3]/15 + A[3,3]/30
        M[4,9]=A[1,1]/70 + 17*A[1,2]/840 + 11*A[1,3]/1260 + 11*A[2,2]/1260 + A[2,3]/168
        M[4,10]=-A[1,1]/42 - 97*A[1,2]/2520 - 53*A[1,3]/1260 - 43*A[2,2]/1260 - 97*A[2,3]/2520 - A[3,3]/42
        M[4,11]=A[1,2]/168 + 11*A[1,3]/1260 + 11*A[2,2]/1260 + 17*A[2,3]/840 + A[3,3]/70
        M[4,12]=A[1,1]/30 + 4*A[1,2]/105 + A[1,3]/15 + 13*A[2,2]/1260 + 4*A[2,3]/105 + A[3,3]/30
        M[4,13]=A[1,1]/70 + 11*A[1,2]/1260 + 17*A[1,3]/840 + A[2,3]/168 + 11*A[3,3]/1260
        M[4,14]=11*A[1,2]/1260 + A[1,3]/168 + A[2,2]/70 + 17*A[2,3]/840 + 11*A[3,3]/1260
        M[4,15]=-A[1,1]/42 - 53*A[1,2]/1260 - 97*A[1,3]/2520 - A[2,2]/42 - 97*A[2,3]/2520 - 43*A[3,3]/1260
        M[4,16]=A[1,1]/30 + A[1,2]/15 + 4*A[1,3]/105 + A[2,2]/30 + 4*A[2,3]/105 + 13*A[3,3]/1260
        M[4,17]=3*A[1,1]/280 - 87*A[1,2]/280 - 87*A[1,3]/280 - 9*A[2,2]/28 - 69*A[2,3]/140 - 9*A[3,3]/28
        M[4,18]=-9*A[1,1]/28 - 87*A[1,2]/280 - 69*A[1,3]/140 + 3*A[2,2]/280 - 87*A[2,3]/280 - 9*A[3,3]/28
        M[4,19]=-9*A[1,1]/28 - 69*A[1,2]/140 - 87*A[1,3]/280 - 9*A[2,2]/28 - 87*A[2,3]/280 + 3*A[3,3]/280
        M[4,20]=-3*A[1,1]/280 + 3*A[1,2]/56 + 3*A[1,3]/56 - 3*A[2,2]/280 + 3*A[2,3]/56 - 3*A[3,3]/280
        M[5,5]=2*A[1,1]/105 + A[1,2]/315 + A[1,3]/315 + A[2,2]/315 + A[2,3]/315 + A[3,3]/315
        M[5,6]=-A[1,1]/280 - 13*A[1,2]/2520 - A[2,2]/315
        M[5,7]=-A[1,1]/280 - 13*A[1,3]/2520 - A[3,3]/315
        M[5,8]=-A[1,1]/630 - A[1,2]/840 - A[1,3]/840 - A[2,2]/315 - 2*A[2,3]/315 - A[3,3]/315
        M[5,9]=-19*A[1,1]/2520 - 13*A[1,2]/2520 - A[2,2]/630
        M[5,10]=A[1,1]/180 + A[1,2]/420 + A[1,3]/630 + A[2,2]/180 + A[2,3]/630 + A[3,3]/630
        M[5,11]=A[1,2]/840 + A[1,3]/504 - A[2,2]/1260 - A[2,3]/630 - A[3,3]/630
        M[5,12]=-A[1,1]/280 - A[1,2]/420 - 13*A[1,3]/2520 - A[2,2]/1260 - A[2,3]/630 - A[3,3]/630
        M[5,13]=-19*A[1,1]/2520 - 13*A[1,3]/2520 - A[3,3]/630
        M[5,14]=A[1,2]/504 + A[1,3]/840 - A[2,2]/630 - A[2,3]/630 - A[3,3]/1260
        M[5,15]=A[1,1]/180 + A[1,2]/630 + A[1,3]/420 + A[2,2]/630 + A[2,3]/630 + A[3,3]/180
        M[5,16]=-A[1,1]/280 - 13*A[1,2]/2520 - A[1,3]/420 - A[2,2]/630 - A[2,3]/630 - A[3,3]/1260
        M[5,17]=3*A[1,2]/140 + 3*A[1,3]/140 + 3*A[2,2]/140 + 3*A[2,3]/140 + 3*A[3,3]/140
        M[5,18]=3*A[1,1]/40 + 3*A[1,2]/40 + 3*A[1,3]/70 + 3*A[2,3]/70 + 3*A[3,3]/70
        M[5,19]=3*A[1,1]/40 + 3*A[1,2]/70 + 3*A[1,3]/40 + 3*A[2,2]/70 + 3*A[2,3]/70
        M[5,20]=-3*A[1,2]/40 - 3*A[1,3]/40 - 3*A[2,3]/70
        M[6,6]=A[1,1]/252 + 2*A[1,2]/315 + A[2,2]/210
        M[6,7]=-A[1,1]/2520 - A[1,2]/1260 - A[1,3]/1260 - A[2,3]/630
        M[6,8]=A[1,1]/2520 + A[1,2]/630 + A[1,3]/1260 + A[2,2]/630 + A[2,3]/630
        M[6,9]=A[1,1]/360 + A[1,2]/180 + A[2,2]/360
        M[6,10]=-A[1,1]/630 - 13*A[1,2]/2520 - 19*A[2,2]/2520
        M[6,11]=-A[1,3]/2520 + A[2,2]/2520 - A[2,3]/2520
        M[6,12]=A[1,1]/2520 + A[1,2]/1260 + A[1,3]/2520 + A[2,2]/1260 + A[2,3]/2520
        M[6,13]=A[1,1]/2520 - A[1,2]/2520 - A[2,3]/2520
        M[6,14]=A[1,2]/840 + A[1,3]/420 + A[2,2]/504 + A[2,3]/840
        M[6,15]=-A[1,1]/1260 - A[1,2]/630 + A[1,3]/840 - A[2,2]/630 + A[2,3]/504
        M[6,16]=A[1,1]/840 + A[1,2]/420 + A[2,2]/840
        M[6,17]=-3*A[1,1]/280 - 9*A[1,2]/280 - 3*A[2,2]/140
        M[6,18]=-3*A[1,1]/280 - 3*A[1,2]/280
        M[6,19]=-3*A[1,1]/140 - 3*A[1,2]/56 - 9*A[1,3]/280 - 3*A[2,2]/70 - 3*A[2,3]/70
        M[6,20]=3*A[1,1]/280 + 3*A[1,2]/140 + 9*A[1,3]/280 + 3*A[2,3]/70
        M[7,7]=A[1,1]/252 + 2*A[1,3]/315 + A[3,3]/210
        M[7,8]=A[1,1]/2520 + A[1,2]/1260 + A[1,3]/630 + A[2,3]/630 + A[3,3]/630
        M[7,9]=A[1,1]/2520 - A[1,3]/2520 - A[2,3]/2520
        M[7,10]=-A[1,1]/1260 + A[1,2]/840 - A[1,3]/630 + A[2,3]/504 - A[3,3]/630
        M[7,11]=A[1,2]/420 + A[1,3]/840 + A[2,3]/840 + A[3,3]/504
        M[7,12]=A[1,1]/840 + A[1,3]/420 + A[3,3]/840
        M[7,13]=A[1,1]/360 + A[1,3]/180 + A[3,3]/360
        M[7,14]=-A[1,2]/2520 - A[2,3]/2520 + A[3,3]/2520
        M[7,15]=-A[1,1]/630 - 13*A[1,3]/2520 - 19*A[3,3]/2520
        M[7,16]=A[1,1]/2520 + A[1,2]/2520 + A[1,3]/1260 + A[2,3]/2520 + A[3,3]/1260
        M[7,17]=-3*A[1,1]/280 - 9*A[1,3]/280 - 3*A[3,3]/140
        M[7,18]=-3*A[1,1]/140 - 9*A[1,2]/280 - 3*A[1,3]/56 - 3*A[2,3]/70 - 3*A[3,3]/70
        M[7,19]=-3*A[1,1]/280 - 3*A[1,3]/280
        M[7,20]=3*A[1,1]/280 + 9*A[1,2]/280 + 3*A[1,3]/140 + 3*A[2,3]/70
        M[8,8]=A[1,1]/420 + A[1,2]/315 + A[1,3]/315 + A[2,2]/210 + A[2,3]/105 + A[3,3]/210
        M[8,9]=A[1,1]/1260 + A[1,2]/1260 + A[1,3]/2520 + A[2,2]/2520 + A[2,3]/2520
        M[8,10]=-A[1,1]/1260 - A[1,2]/420 - A[1,3]/630 - A[2,2]/280 - 13*A[2,3]/2520 - A[3,3]/630
        M[8,11]=A[2,2]/840 + A[2,3]/420 + A[3,3]/840
        M[8,12]=A[1,1]/1260 + A[1,2]/252 + A[1,3]/360 + A[2,2]/1260 + A[2,3]/360 + A[3,3]/504
        M[8,13]=A[1,1]/1260 + A[1,2]/2520 + A[1,3]/1260 + A[2,3]/2520 + A[3,3]/2520
        M[8,14]=A[2,2]/840 + A[2,3]/420 + A[3,3]/840
        M[8,15]=-A[1,1]/1260 - A[1,2]/630 - A[1,3]/420 - A[2,2]/630 - 13*A[2,3]/2520 - A[3,3]/280
        M[8,16]=A[1,1]/1260 + A[1,2]/360 + A[1,3]/252 + A[2,2]/504 + A[2,3]/360 + A[3,3]/1260
        M[8,17]=-3*A[1,2]/280 - 3*A[1,3]/280 - 3*A[2,2]/140 - 3*A[2,3]/70 - 3*A[3,3]/140
        M[8,18]=-3*A[1,1]/280 - 3*A[1,2]/140 - 9*A[1,3]/280 - 3*A[2,3]/70 - 3*A[3,3]/70
        M[8,19]=-3*A[1,1]/280 - 9*A[1,2]/280 - 3*A[1,3]/140 - 3*A[2,2]/70 - 3*A[2,3]/70
        M[8,20]=3*A[1,2]/280 + 3*A[1,3]/280
        M[9,9]=A[1,1]/210 + 2*A[1,2]/315 + A[2,2]/252
        M[9,10]=-A[1,1]/315 - 13*A[1,2]/2520 - A[2,2]/280
        M[9,11]=-A[1,2]/1260 - A[1,3]/630 - A[2,2]/2520 - A[2,3]/1260
        M[9,12]=A[1,1]/630 + A[1,2]/630 + A[1,3]/630 + A[2,2]/2520 + A[2,3]/1260
        M[9,13]=A[1,1]/504 + A[1,2]/840 + A[1,3]/840 + A[2,3]/420
        M[9,14]=-A[1,2]/2520 - A[1,3]/2520 + A[2,2]/2520
        M[9,15]=-A[1,1]/630 - A[1,2]/630 + A[1,3]/504 - A[2,2]/1260 + A[2,3]/840
        M[9,16]=A[1,1]/840 + A[1,2]/420 + A[2,2]/840
        M[9,17]=-3*A[1,2]/280 - 3*A[2,2]/280
        M[9,18]=-3*A[1,1]/140 - 9*A[1,2]/280 - 3*A[2,2]/280
        M[9,19]=-3*A[1,1]/70 - 3*A[1,2]/56 - 3*A[1,3]/70 - 3*A[2,2]/140 - 9*A[2,3]/280
        M[9,20]=3*A[1,2]/140 + 3*A[1,3]/70 + 3*A[2,2]/280 + 9*A[2,3]/280
        M[10,10]=A[1,1]/315 + A[1,2]/315 + A[1,3]/315 + 2*A[2,2]/105 + A[2,3]/315 + A[3,3]/315
        M[10,11]=-A[2,2]/280 - 13*A[2,3]/2520 - A[3,3]/315
        M[10,12]=-A[1,1]/315 - A[1,2]/840 - 2*A[1,3]/315 - A[2,2]/630 - A[2,3]/840 - A[3,3]/315
        M[10,13]=-A[1,1]/630 + A[1,2]/504 - A[1,3]/630 + A[2,3]/840 - A[3,3]/1260
        M[10,14]=-19*A[2,2]/2520 - 13*A[2,3]/2520 - A[3,3]/630
        M[10,15]=A[1,1]/630 + A[1,2]/630 + A[1,3]/630 + A[2,2]/180 + A[2,3]/420 + A[3,3]/180
        M[10,16]=-A[1,1]/630 - 13*A[1,2]/2520 - A[1,3]/630 - A[2,2]/280 - A[2,3]/420 - A[3,3]/1260
        M[10,17]=3*A[1,2]/40 + 3*A[1,3]/70 + 3*A[2,2]/40 + 3*A[2,3]/70 + 3*A[3,3]/70
        M[10,18]=3*A[1,1]/140 + 3*A[1,2]/140 + 3*A[1,3]/140 + 3*A[2,3]/140 + 3*A[3,3]/140
        M[10,19]=3*A[1,1]/70 + 3*A[1,2]/70 + 3*A[1,3]/70 + 3*A[2,2]/40 + 3*A[2,3]/40
        M[10,20]=-3*A[1,2]/40 - 3*A[1,3]/70 - 3*A[2,3]/40
        M[11,11]=A[2,2]/252 + 2*A[2,3]/315 + A[3,3]/210
        M[11,12]=A[1,2]/1260 + A[1,3]/630 + A[2,2]/2520 + A[2,3]/630 + A[3,3]/630
        M[11,13]=-A[1,2]/2520 - A[1,3]/2520 + A[3,3]/2520
        M[11,14]=A[2,2]/360 + A[2,3]/180 + A[3,3]/360
        M[11,15]=-A[2,2]/630 - 13*A[2,3]/2520 - 19*A[3,3]/2520
        M[11,16]=A[1,2]/2520 + A[1,3]/2520 + A[2,2]/2520 + A[2,3]/1260 + A[3,3]/1260
        M[11,17]=-9*A[1,2]/280 - 3*A[1,3]/70 - 3*A[2,2]/140 - 3*A[2,3]/56 - 3*A[3,3]/70
        M[11,18]=-3*A[2,2]/280 - 9*A[2,3]/280 - 3*A[3,3]/140
        M[11,19]=-3*A[2,2]/280 - 3*A[2,3]/280
        M[11,20]=9*A[1,2]/280 + 3*A[1,3]/70 + 3*A[2,2]/280 + 3*A[2,3]/140
        M[12,12]=A[1,1]/210 + A[1,2]/315 + A[1,3]/105 + A[2,2]/420 + A[2,3]/315 + A[3,3]/210
        M[12,13]=A[1,1]/840 + A[1,3]/420 + A[3,3]/840
        M[12,14]=A[1,2]/2520 + A[1,3]/2520 + A[2,2]/1260 + A[2,3]/1260 + A[3,3]/2520
        M[12,15]=-A[1,1]/630 - A[1,2]/630 - 13*A[1,3]/2520 - A[2,2]/1260 - A[2,3]/420 - A[3,3]/280
        M[12,16]=A[1,1]/504 + A[1,2]/360 + A[1,3]/360 + A[2,2]/1260 + A[2,3]/252 + A[3,3]/1260
        M[12,17]=-3*A[1,2]/140 - 3*A[1,3]/70 - 3*A[2,2]/280 - 9*A[2,3]/280 - 3*A[3,3]/70
        M[12,18]=-3*A[1,1]/140 - 3*A[1,2]/280 - 3*A[1,3]/70 - 3*A[2,3]/280 - 3*A[3,3]/140
        M[12,19]=-3*A[1,1]/70 - 9*A[1,2]/280 - 3*A[1,3]/70 - 3*A[2,2]/280 - 3*A[2,3]/140
        M[12,20]=3*A[1,2]/280 + 3*A[2,3]/280
        M[13,13]=A[1,1]/210 + 2*A[1,3]/315 + A[3,3]/252
        M[13,14]=-A[1,2]/630 - A[1,3]/1260 - A[2,3]/1260 - A[3,3]/2520
        M[13,15]=-A[1,1]/315 - 13*A[1,3]/2520 - A[3,3]/280
        M[13,16]=A[1,1]/630 + A[1,2]/630 + A[1,3]/630 + A[2,3]/1260 + A[3,3]/2520
        M[13,17]=-3*A[1,3]/280 - 3*A[3,3]/280
        M[13,18]=-3*A[1,1]/70 - 3*A[1,2]/70 - 3*A[1,3]/56 - 9*A[2,3]/280 - 3*A[3,3]/140
        M[13,19]=-3*A[1,1]/140 - 9*A[1,3]/280 - 3*A[3,3]/280
        M[13,20]=3*A[1,2]/70 + 3*A[1,3]/140 + 9*A[2,3]/280 + 3*A[3,3]/280
        M[14,14]=A[2,2]/210 + 2*A[2,3]/315 + A[3,3]/252
        M[14,15]=-A[2,2]/315 - 13*A[2,3]/2520 - A[3,3]/280
        M[14,16]=A[1,2]/630 + A[1,3]/1260 + A[2,2]/630 + A[2,3]/630 + A[3,3]/2520
        M[14,17]=-3*A[1,2]/70 - 9*A[1,3]/280 - 3*A[2,2]/70 - 3*A[2,3]/56 - 3*A[3,3]/140
        M[14,18]=-3*A[2,3]/280 - 3*A[3,3]/280
        M[14,19]=-3*A[2,2]/140 - 9*A[2,3]/280 - 3*A[3,3]/280
        M[14,20]=3*A[1,2]/70 + 9*A[1,3]/280 + 3*A[2,3]/140 + 3*A[3,3]/280
        M[15,15]=A[1,1]/315 + A[1,2]/315 + A[1,3]/315 + A[2,2]/315 + A[2,3]/315 + 2*A[3,3]/105
        M[15,16]=-A[1,1]/315 - 2*A[1,2]/315 - A[1,3]/840 - A[2,2]/315 - A[2,3]/840 - A[3,3]/630
        M[15,17]=3*A[1,2]/70 + 3*A[1,3]/40 + 3*A[2,2]/70 + 3*A[2,3]/70 + 3*A[3,3]/40
        M[15,18]=3*A[1,1]/70 + 3*A[1,2]/70 + 3*A[1,3]/70 + 3*A[2,3]/40 + 3*A[3,3]/40
        M[15,19]=3*A[1,1]/140 + 3*A[1,2]/140 + 3*A[1,3]/140 + 3*A[2,2]/140 + 3*A[2,3]/140
        M[15,20]=-3*A[1,2]/70 - 3*A[1,3]/40 - 3*A[2,3]/40
        M[16,16]=A[1,1]/210 + A[1,2]/105 + A[1,3]/315 + A[2,2]/210 + A[2,3]/315 + A[3,3]/420
        M[16,17]=-3*A[1,2]/70 - 3*A[1,3]/140 - 3*A[2,2]/70 - 9*A[2,3]/280 - 3*A[3,3]/280
        M[16,18]=-3*A[1,1]/70 - 3*A[1,2]/70 - 9*A[1,3]/280 - 3*A[2,3]/140 - 3*A[3,3]/280
        M[16,19]=-3*A[1,1]/140 - 3*A[1,2]/70 - 3*A[1,3]/280 - 3*A[2,2]/140 - 3*A[2,3]/280
        M[16,20]=3*A[1,3]/280 + 3*A[2,3]/280
        M[17,17]=81*A[1,1]/140 + 81*A[1,2]/140 + 81*A[1,3]/140 + 81*A[2,2]/140 + 81*A[2,3]/140 + 81*A[3,3]/140
        M[17,18]=81*A[1,2]/140 + 81*A[1,3]/280 + 81*A[2,3]/280 + 81*A[3,3]/280
        M[17,19]=81*A[1,2]/280 + 81*A[1,3]/140 + 81*A[2,2]/280 + 81*A[2,3]/280
        M[17,20]=-81*A[1,1]/140 - 81*A[1,2]/140 - 81*A[1,3]/140 - 81*A[2,3]/280
        M[18,18]=81*A[1,1]/140 + 81*A[1,2]/140 + 81*A[1,3]/140 + 81*A[2,2]/140 + 81*A[2,3]/140 + 81*A[3,3]/140
        M[18,19]=81*A[1,1]/280 + 81*A[1,2]/280 + 81*A[1,3]/280 + 81*A[2,3]/140
        M[18,20]=-81*A[1,2]/140 - 81*A[1,3]/280 - 81*A[2,2]/140 - 81*A[2,3]/140
        M[19,19]=81*A[1,1]/140 + 81*A[1,2]/140 + 81*A[1,3]/140 + 81*A[2,2]/140 + 81*A[2,3]/140 + 81*A[3,3]/140
        M[19,20]=-81*A[1,2]/280 - 81*A[1,3]/140 - 81*A[2,3]/140 - 81*A[3,3]/140
        M[20,20]=81*A[1,1]/140 + 81*A[1,2]/140 + 81*A[1,3]/140 + 81*A[2,2]/140 + 81*A[2,3]/140 + 81*A[3,3]/140
        M[2,1]=M[1,2]
        M[3,1]=M[1,3]
        M[4,1]=M[1,4]
        M[5,1]=M[1,5]
        M[6,1]=M[1,6]
        M[7,1]=M[1,7]
        M[8,1]=M[1,8]
        M[9,1]=M[1,9]
        M[10,1]=M[1,10]
        M[11,1]=M[1,11]
        M[12,1]=M[1,12]
        M[13,1]=M[1,13]
        M[14,1]=M[1,14]
        M[15,1]=M[1,15]
        M[16,1]=M[1,16]
        M[17,1]=M[1,17]
        M[18,1]=M[1,18]
        M[19,1]=M[1,19]
        M[20,1]=M[1,20]
        M[3,2]=M[2,3]
        M[4,2]=M[2,4]
        M[5,2]=M[2,5]
        M[6,2]=M[2,6]
        M[7,2]=M[2,7]
        M[8,2]=M[2,8]
        M[9,2]=M[2,9]
        M[10,2]=M[2,10]
        M[11,2]=M[2,11]
        M[12,2]=M[2,12]
        M[13,2]=M[2,13]
        M[14,2]=M[2,14]
        M[15,2]=M[2,15]
        M[16,2]=M[2,16]
        M[17,2]=M[2,17]
        M[18,2]=M[2,18]
        M[19,2]=M[2,19]
        M[20,2]=M[2,20]
        M[4,3]=M[3,4]
        M[5,3]=M[3,5]
        M[6,3]=M[3,6]
        M[7,3]=M[3,7]
        M[8,3]=M[3,8]
        M[9,3]=M[3,9]
        M[10,3]=M[3,10]
        M[11,3]=M[3,11]
        M[12,3]=M[3,12]
        M[13,3]=M[3,13]
        M[14,3]=M[3,14]
        M[15,3]=M[3,15]
        M[16,3]=M[3,16]
        M[17,3]=M[3,17]
        M[18,3]=M[3,18]
        M[19,3]=M[3,19]
        M[20,3]=M[3,20]
        M[5,4]=M[4,5]
        M[6,4]=M[4,6]
        M[7,4]=M[4,7]
        M[8,4]=M[4,8]
        M[9,4]=M[4,9]
        M[10,4]=M[4,10]
        M[11,4]=M[4,11]
        M[12,4]=M[4,12]
        M[13,4]=M[4,13]
        M[14,4]=M[4,14]
        M[15,4]=M[4,15]
        M[16,4]=M[4,16]
        M[17,4]=M[4,17]
        M[18,4]=M[4,18]
        M[19,4]=M[4,19]
        M[20,4]=M[4,20]
        M[6,5]=M[5,6]
        M[7,5]=M[5,7]
        M[8,5]=M[5,8]
        M[9,5]=M[5,9]
        M[10,5]=M[5,10]
        M[11,5]=M[5,11]
        M[12,5]=M[5,12]
        M[13,5]=M[5,13]
        M[14,5]=M[5,14]
        M[15,5]=M[5,15]
        M[16,5]=M[5,16]
        M[17,5]=M[5,17]
        M[18,5]=M[5,18]
        M[19,5]=M[5,19]
        M[20,5]=M[5,20]
        M[7,6]=M[6,7]
        M[8,6]=M[6,8]
        M[9,6]=M[6,9]
        M[10,6]=M[6,10]
        M[11,6]=M[6,11]
        M[12,6]=M[6,12]
        M[13,6]=M[6,13]
        M[14,6]=M[6,14]
        M[15,6]=M[6,15]
        M[16,6]=M[6,16]
        M[17,6]=M[6,17]
        M[18,6]=M[6,18]
        M[19,6]=M[6,19]
        M[20,6]=M[6,20]
        M[8,7]=M[7,8]
        M[9,7]=M[7,9]
        M[10,7]=M[7,10]
        M[11,7]=M[7,11]
        M[12,7]=M[7,12]
        M[13,7]=M[7,13]
        M[14,7]=M[7,14]
        M[15,7]=M[7,15]
        M[16,7]=M[7,16]
        M[17,7]=M[7,17]
        M[18,7]=M[7,18]
        M[19,7]=M[7,19]
        M[20,7]=M[7,20]
        M[9,8]=M[8,9]
        M[10,8]=M[8,10]
        M[11,8]=M[8,11]
        M[12,8]=M[8,12]
        M[13,8]=M[8,13]
        M[14,8]=M[8,14]
        M[15,8]=M[8,15]
        M[16,8]=M[8,16]
        M[17,8]=M[8,17]
        M[18,8]=M[8,18]
        M[19,8]=M[8,19]
        M[20,8]=M[8,20]
        M[10,9]=M[9,10]
        M[11,9]=M[9,11]
        M[12,9]=M[9,12]
        M[13,9]=M[9,13]
        M[14,9]=M[9,14]
        M[15,9]=M[9,15]
        M[16,9]=M[9,16]
        M[17,9]=M[9,17]
        M[18,9]=M[9,18]
        M[19,9]=M[9,19]
        M[20,9]=M[9,20]
        M[11,10]=M[10,11]
        M[12,10]=M[10,12]
        M[13,10]=M[10,13]
        M[14,10]=M[10,14]
        M[15,10]=M[10,15]
        M[16,10]=M[10,16]
        M[17,10]=M[10,17]
        M[18,10]=M[10,18]
        M[19,10]=M[10,19]
        M[20,10]=M[10,20]
        M[12,11]=M[11,12]
        M[13,11]=M[11,13]
        M[14,11]=M[11,14]
        M[15,11]=M[11,15]
        M[16,11]=M[11,16]
        M[17,11]=M[11,17]
        M[18,11]=M[11,18]
        M[19,11]=M[11,19]
        M[20,11]=M[11,20]
        M[13,12]=M[12,13]
        M[14,12]=M[12,14]
        M[15,12]=M[12,15]
        M[16,12]=M[12,16]
        M[17,12]=M[12,17]
        M[18,12]=M[12,18]
        M[19,12]=M[12,19]
        M[20,12]=M[12,20]
        M[14,13]=M[13,14]
        M[15,13]=M[13,15]
        M[16,13]=M[13,16]
        M[17,13]=M[13,17]
        M[18,13]=M[13,18]
        M[19,13]=M[13,19]
        M[20,13]=M[13,20]
        M[15,14]=M[14,15]
        M[16,14]=M[14,16]
        M[17,14]=M[14,17]
        M[18,14]=M[14,18]
        M[19,14]=M[14,19]
        M[20,14]=M[14,20]
        M[16,15]=M[15,16]
        M[17,15]=M[15,17]
        M[18,15]=M[15,18]
        M[19,15]=M[15,19]
        M[20,15]=M[15,20]
        M[17,16]=M[16,17]
        M[18,16]=M[16,18]
        M[19,16]=M[16,19]
        M[20,16]=M[16,20]
        M[18,17]=M[17,18]
        M[19,17]=M[17,19]
        M[20,17]=M[17,20]
        M[19,18]=M[18,19]
        M[20,18]=M[18,20]
        M[20,19]=M[19,20]

        return recombine_hermite(J,M)*abs(J.det)
end

function s43nv1nu1cc1(J::CooTrafo,c)
        A=J.inv*J.inv'
        M=Array{Float64}(undef,4,4)
        cc=Array{ComplexF64}(undef,4,4)
        for i=1:4
                for j=1:4
                        cc[i,j]=c[i]*c[j]
                end
        end
        M[1,1]=A[1,1]*cc[1,1]/60 + A[1,1]*cc[1,2]/60 + A[1,1]*cc[1,3]/60 + A[1,1]*cc[1,4]/60 + A[1,1]*cc[2,2]/60 + A[1,1]*cc[2,3]/60 + A[1,1]*cc[2,4]/60 + A[1,1]*cc[3,3]/60 + A[1,
        1]*cc[3,4]/60 + A[1,1]*cc[4,4]/60
        M[1,2]=A[1,2]*cc[1,1]/60 + A[1,2]*cc[1,2]/60 + A[1,2]*cc[1,3]/60 + A[1,2]*cc[1,4]/60 + A[1,2]*cc[2,2]/60 + A[1,2]*cc[2,3]/60 + A[1,2]*cc[2,4]/60 + A[1,2]*cc[3,3]/60 + A[1,2]*cc[3,4]/60 + A[1,2]*cc[4,4]/60
        M[1,3]=A[1,3]*cc[1,1]/60 + A[1,3]*cc[1,2]/60 + A[1,3]*cc[1,3]/60 + A[1,3]*cc[1,4]/60 + A[1,3]*cc[2,2]/60 + A[1,3]*cc[2,3]/60 + A[1,3]*cc[2,4]/60 + A[1,3]*cc[3,3]/60 + A[1,3]*cc[3,4]/60 + A[1,3]*cc[4,4]/60
        M[1,4]=-A[1,1]*cc[1,1]/60 - A[1,1]*cc[1,2]/60 - A[1,1]*cc[1,3]/60 - A[1,1]*cc[1,4]/60 - A[1,1]*cc[2,2]/60 - A[1,1]*cc[2,3]/60 - A[1,1]*cc[2,4]/60 - A[1,1]*cc[3,3]/60 - A[1,1]*cc[3,4]/60 - A[1,1]*cc[4,4]/60 - A[1,2]*cc[1,1]/60 - A[1,2]*cc[1,2]/60 - A[1,2]*cc[1,3]/60 - A[1,2]*cc[1,4]/60 - A[1,2]*cc[2,2]/60 - A[1,2]*cc[2,3]/60 - A[1,2]*cc[2,4]/60 - A[1,2]*cc[3,3]/60 - A[1,2]*cc[3,4]/60 - A[1,2]*cc[4,4]/60 - A[1,3]*cc[1,1]/60 - A[1,3]*cc[1,2]/60 - A[1,3]*cc[1,3]/60 - A[1,3]*cc[1,4]/60 - A[1,3]*cc[2,2]/60 - A[1,3]*cc[2,3]/60 - A[1,3]*cc[2,4]/60 - A[1,3]*cc[3,3]/60 - A[1,3]*cc[3,4]/60 - A[1,3]*cc[4,4]/60
        M[2,2]=A[2,2]*cc[1,1]/60 + A[2,2]*cc[1,2]/60 + A[2,2]*cc[1,3]/60 + A[2,2]*cc[1,4]/60 + A[2,2]*cc[2,2]/60 + A[2,2]*cc[2,3]/60 + A[2,2]*cc[2,4]/60 + A[2,2]*cc[3,3]/60 + A[2,2]*cc[3,4]/60 + A[2,2]*cc[4,4]/60
        M[2,3]=A[2,3]*cc[1,1]/60 + A[2,3]*cc[1,2]/60 + A[2,3]*cc[1,3]/60 + A[2,3]*cc[1,4]/60 + A[2,3]*cc[2,2]/60 + A[2,3]*cc[2,3]/60 + A[2,3]*cc[2,4]/60 + A[2,3]*cc[3,3]/60 + A[2,3]*cc[3,4]/60 + A[2,3]*cc[4,4]/60
        M[2,4]=-A[1,2]*cc[1,1]/60 - A[1,2]*cc[1,2]/60 - A[1,2]*cc[1,3]/60 - A[1,2]*cc[1,4]/60 - A[1,2]*cc[2,2]/60 - A[1,2]*cc[2,3]/60 - A[1,2]*cc[2,4]/60 - A[1,2]*cc[3,3]/60 - A[1,2]*cc[3,4]/60 - A[1,2]*cc[4,4]/60 - A[2,2]*cc[1,1]/60 - A[2,2]*cc[1,2]/60 - A[2,2]*cc[1,3]/60 - A[2,2]*cc[1,4]/60 - A[2,2]*cc[2,2]/60 - A[2,2]*cc[2,3]/60 - A[2,2]*cc[2,4]/60 - A[2,2]*cc[3,3]/60 - A[2,2]*cc[3,4]/60 - A[2,2]*cc[4,4]/60 - A[2,3]*cc[1,1]/60 - A[2,3]*cc[1,2]/60 - A[2,3]*cc[1,3]/60 - A[2,3]*cc[1,4]/60 - A[2,3]*cc[2,2]/60 - A[2,3]*cc[2,3]/60 - A[2,3]*cc[2,4]/60 - A[2,3]*cc[3,3]/60 - A[2,3]*cc[3,4]/60 - A[2,3]*cc[4,4]/60
        M[3,3]=A[3,3]*cc[1,1]/60 + A[3,3]*cc[1,2]/60 + A[3,3]*cc[1,3]/60 + A[3,3]*cc[1,4]/60 + A[3,3]*cc[2,2]/60 + A[3,3]*cc[2,3]/60 + A[3,3]*cc[2,4]/60 + A[3,3]*cc[3,3]/60 + A[3,3]*cc[3,4]/60 + A[3,3]*cc[4,4]/60
        M[3,4]=-A[1,3]*cc[1,1]/60 - A[1,3]*cc[1,2]/60 - A[1,3]*cc[1,3]/60 - A[1,3]*cc[1,4]/60 - A[1,3]*cc[2,2]/60 - A[1,3]*cc[2,3]/60 - A[1,3]*cc[2,4]/60 - A[1,3]*cc[3,3]/60 - A[1,3]*cc[3,4]/60 - A[1,3]*cc[4,4]/60 - A[2,3]*cc[1,1]/60 - A[2,3]*cc[1,2]/60 - A[2,3]*cc[1,3]/60 - A[2,3]*cc[1,4]/60 - A[2,3]*cc[2,2]/60 - A[2,3]*cc[2,3]/60 - A[2,3]*cc[2,4]/60 - A[2,3]*cc[3,3]/60 - A[2,3]*cc[3,4]/60 - A[2,3]*cc[4,4]/60 - A[3,3]*cc[1,1]/60 - A[3,3]*cc[1,2]/60 - A[3,3]*cc[1,3]/60 - A[3,3]*cc[1,4]/60 - A[3,3]*cc[2,2]/60 - A[3,3]*cc[2,3]/60 - A[3,3]*cc[2,4]/60 - A[3,3]*cc[3,3]/60 - A[3,3]*cc[3,4]/60 - A[3,3]*cc[4,4]/60
        M[4,4]=A[1,1]*cc[1,1]/60 + A[1,1]*cc[1,2]/60 + A[1,1]*cc[1,3]/60 + A[1,1]*cc[1,4]/60 + A[1,1]*cc[2,2]/60 + A[1,1]*cc[2,3]/60 + A[1,1]*cc[2,4]/60 + A[1,1]*cc[3,3]/60 + A[1,1]*cc[3,4]/60 + A[1,1]*cc[4,4]/60 + A[1,2]*cc[1,1]/30 + A[1,2]*cc[1,2]/30 + A[1,2]*cc[1,3]/30 + A[1,2]*cc[1,4]/30 + A[1,2]*cc[2,2]/30 + A[1,2]*cc[2,3]/30 + A[1,2]*cc[2,4]/30 + A[1,2]*cc[3,3]/30 + A[1,2]*cc[3,4]/30 + A[1,2]*cc[4,4]/30 + A[1,3]*cc[1,1]/30 + A[1,3]*cc[1,2]/30 + A[1,3]*cc[1,3]/30 + A[1,3]*cc[1,4]/30 + A[1,3]*cc[2,2]/30 + A[1,3]*cc[2,3]/30 + A[1,3]*cc[2,4]/30 + A[1,3]*cc[3,3]/30 + A[1,3]*cc[3,4]/30 + A[1,3]*cc[4,4]/30 + A[2,2]*cc[1,1]/60 + A[2,2]*cc[1,2]/60 + A[2,2]*cc[1,3]/60 + A[2,2]*cc[1,4]/60 + A[2,2]*cc[2,2]/60 + A[2,2]*cc[2,3]/60 + A[2,2]*cc[2,4]/60 + A[2,2]*cc[3,3]/60 + A[2,2]*cc[3,4]/60 + A[2,2]*cc[4,4]/60 + A[2,3]*cc[1,1]/30 + A[2,3]*cc[1,2]/30 + A[2,3]*cc[1,3]/30 + A[2,3]*cc[1,4]/30 + A[2,3]*cc[2,2]/30 + A[2,3]*cc[2,3]/30 + A[2,3]*cc[2,4]/30 + A[2,3]*cc[3,3]/30 + A[2,3]*cc[3,4]/30 + A[2,3]*cc[4,4]/30 + A[3,3]*cc[1,1]/60 + A[3,3]*cc[1,2]/60 + A[3,3]*cc[1,3]/60 + A[3,3]*cc[1,4]/60 + A[3,3]*cc[2,2]/60 + A[3,3]*cc[2,3]/60 + A[3,3]*cc[2,4]/60 + A[3,3]*cc[3,3]/60 + A[3,3]*cc[3,4]/60 + A[3,3]*cc[4,4]/60
        M[2,1]=M[1,2]
        M[3,1]=M[1,3]
        M[4,1]=M[1,4]
        M[3,2]=M[2,3]
        M[4,2]=M[2,4]
        M[4,3]=M[3,4]

        return M*abs(J.det)
end

function s43nv2nu2cc1(J::CooTrafo,c)
    A=J.inv*J.inv'
    M=Array{Float64}(undef,10,10)
    cc=Array{ComplexF64}(undef,4,4)
    for i=1:4
            for j=1:4
                    cc[i,j]=c[i]*c[j]
            end
    end
    M[1,1]=11*A[1,1]*cc[1,1]/420 + 13*A[1,1]*cc[1,2]/1260 + 13*A[1,1]*cc[1,3]/1260 + 13*A[1,1]*cc[1,4]/1260 + A[1,1]*cc[2,2]/140 + A[1,1]*cc[2,3]/140 + A[1,1]*cc[2,4]/140 + A[1,1]*cc[3,3]/140 + A[1,1]*cc[3,4]/140 + A[1,1]*cc[4,4]/140
    M[1,2]=-11*A[1,2]*cc[1,1]/1260 - A[1,2]*cc[1,2]/420 - A[1,2]*cc[1,3]/252 - A[1,2]*cc[1,4]/252 - 11*A[1,2]*cc[2,2]/1260 - A[1,2]*cc[2,3]/252 - A[1,2]*cc[2,4]/252 + A[1,2]*cc[3,3]/1260 + A[1,2]*cc[3,4]/1260 + A[1,2]*cc[4,4]/1260
    M[1,3]=-11*A[1,3]*cc[1,1]/1260 - A[1,3]*cc[1,2]/252 - A[1,3]*cc[1,3]/420 - A[1,3]*cc[1,4]/252 + A[1,3]*cc[2,2]/1260 - A[1,3]*cc[2,3]/252 + A[1,3]*cc[2,4]/1260 - 11*A[1,3]*cc[3,3]/1260 - A[1,3]*cc[3,4]/252 + A[1,3]*cc[4,4]/1260
    M[1,4]=11*A[1,1]*cc[1,1]/1260 + A[1,1]*cc[1,2]/252 + A[1,1]*cc[1,3]/252 + A[1,1]*cc[1,4]/420 - A[1,1]*cc[2,2]/1260 - A[1,1]*cc[2,3]/1260 + A[1,1]*cc[2,4]/252 - A[1,1]*cc[3,3]/1260 + A[1,1]*cc[3,4]/252 + 11*A[1,1]*cc[4,4]/1260 + 11*A[1,2]*cc[1,1]/1260 + A[1,2]*cc[1,2]/252 + A[1,2]*cc[1,3]/252 + A[1,2]*cc[1,4]/420 - A[1,2]*cc[2,2]/1260 - A[1,2]*cc[2,3]/1260 + A[1,2]*cc[2,4]/252 - A[1,2]*cc[3,3]/1260 + A[1,2]*cc[3,4]/252 + 11*A[1,2]*cc[4,4]/1260 + 11*A[1,3]*cc[1,1]/1260 + A[1,3]*cc[1,2]/252 + A[1,3]*cc[1,3]/252 + A[1,3]*cc[1,4]/420 - A[1,3]*cc[2,2]/1260 - A[1,3]*cc[2,3]/1260 + A[1,3]*cc[2,4]/252 - A[1,3]*cc[3,3]/1260 + A[1,3]*cc[3,4]/252 + 11*A[1,3]*cc[4,4]/1260
    M[1,5]=A[1,1]*cc[1,1]/126 + A[1,1]*cc[1,2]/315 + A[1,1]*cc[1,3]/630 + A[1,1]*cc[1,4]/630 - A[1,1]*cc[2,2]/70 - A[1,1]*cc[2,3]/105 - A[1,1]*cc[2,4]/105 - A[1,1]*cc[3,3]/210 - A[1,1]*cc[3,4]/210 - A[1,1]*cc[4,4]/210 + 3*A[1,2]*cc[1,1]/70 + A[1,2]*cc[1,2]/63 + A[1,2]*cc[1,3]/63 + A[1,2]*cc[1,4]/63 + A[1,2]*cc[2,2]/630 + A[1,2]*cc[2,3]/630 + A[1,2]*cc[2,4]/630 + A[1,2]*cc[3,3]/630 + A[1,2]*cc[3,4]/630 + A[1,2]*cc[4,4]/630
    M[1,6]=A[1,1]*cc[1,1]/126 + A[1,1]*cc[1,2]/630 + A[1,1]*cc[1,3]/315 + A[1,1]*cc[1,4]/630 - A[1,1]*cc[2,2]/210 - A[1,1]*cc[2,3]/105 - A[1,1]*cc[2,4]/210 - A[1,1]*cc[3,3]/70 - A[1,1]*cc[3,4]/105 - A[1,1]*cc[4,4]/210 + 3*A[1,3]*cc[1,1]/70 + A[1,3]*cc[1,2]/63 + A[1,3]*cc[1,3]/63 + A[1,3]*cc[1,4]/63 + A[1,3]*cc[2,2]/630 + A[1,3]*cc[2,3]/630 + A[1,3]*cc[2,4]/630 + A[1,3]*cc[3,3]/630 + A[1,3]*cc[3,4]/630 + A[1,3]*cc[4,4]/630
    M[1,7]=-11*A[1,1]*cc[1,1]/315 - A[1,1]*cc[1,2]/70 - A[1,1]*cc[1,3]/70 - 4*A[1,1]*cc[1,4]/315 - 2*A[1,1]*cc[2,2]/315 - 2*A[1,1]*cc[2,3]/315 - A[1,1]*cc[2,4]/90 - 2*A[1,1]*cc[3,3]/315 - A[1,1]*cc[3,4]/90 - A[1,1]*cc[4,4]/63 - 3*A[1,2]*cc[1,1]/70 - A[1,2]*cc[1,2]/63 - A[1,2]*cc[1,3]/63 - A[1,2]*cc[1,4]/63 - A[1,2]*cc[2,2]/630 - A[1,2]*cc[2,3]/630 - A[1,2]*cc[2,4]/630 - A[1,2]*cc[3,3]/630 - A[1,2]*cc[3,4]/630 - A[1,2]*cc[4,4]/630 - 3*A[1,3]*cc[1,1]/70 - A[1,3]*cc[1,2]/63 - A[1,3]*cc[1,3]/63 - A[1,3]*cc[1,4]/63 - A[1,3]*cc[2,2]/630 - A[1,3]*cc[2,3]/630 - A[1,3]*cc[2,4]/630 - A[1,3]*cc[3,3]/630 - A[1,3]*cc[3,4]/630 - A[1,3]*cc[4,4]/630
    M[1,8]=A[1,2]*cc[1,1]/126 + A[1,2]*cc[1,2]/630 + A[1,2]*cc[1,3]/315 + A[1,2]*cc[1,4]/630 - A[1,2]*cc[2,2]/210 - A[1,2]*cc[2,3]/105 - A[1,2]*cc[2,4]/210 - A[1,2]*cc[3,3]/70 - A[1,2]*cc[3,4]/105 - A[1,2]*cc[4,4]/210 + A[1,3]*cc[1,1]/126 + A[1,3]*cc[1,2]/315 + A[1,3]*cc[1,3]/630 + A[1,3]*cc[1,4]/630 - A[1,3]*cc[2,2]/70 - A[1,3]*cc[2,3]/105 - A[1,3]*cc[2,4]/105 - A[1,3]*cc[3,3]/210 - A[1,3]*cc[3,4]/210 - A[1,3]*cc[4,4]/210
    M[1,9]=-A[1,1]*cc[1,1]/126 - A[1,1]*cc[1,2]/315 - A[1,1]*cc[1,3]/630 - A[1,1]*cc[1,4]/630 + A[1,1]*cc[2,2]/70 + A[1,1]*cc[2,3]/105 + A[1,1]*cc[2,4]/105 + A[1,1]*cc[3,3]/210 + A[1,1]*cc[3,4]/210 + A[1,1]*cc[4,4]/210 - A[1,2]*cc[1,2]/630 + A[1,2]*cc[1,4]/630 + A[1,2]*cc[2,2]/105 + A[1,2]*cc[2,3]/210 - A[1,2]*cc[3,4]/210 - A[1,2]*cc[4,4]/105 - A[1,3]*cc[1,1]/126 - A[1,3]*cc[1,2]/315 - A[1,3]*cc[1,3]/630 - A[1,3]*cc[1,4]/630 + A[1,3]*cc[2,2]/70 + A[1,3]*cc[2,3]/105 + A[1,3]*cc[2,4]/105 + A[1,3]*cc[3,3]/210 + A[1,3]*cc[3,4]/210 + A[1,3]*cc[4,4]/210
    M[1,10]=-A[1,1]*cc[1,1]/126 - A[1,1]*cc[1,2]/630 - A[1,1]*cc[1,3]/315 - A[1,1]*cc[1,4]/630 + A[1,1]*cc[2,2]/210 + A[1,1]*cc[2,3]/105 + A[1,1]*cc[2,4]/210 + A[1,1]*cc[3,3]/70 + A[1,1]*cc[3,4]/105 + A[1,1]*cc[4,4]/210 - A[1,2]*cc[1,1]/126 - A[1,2]*cc[1,2]/630 - A[1,2]*cc[1,3]/315 - A[1,2]*cc[1,4]/630 + A[1,2]*cc[2,2]/210 + A[1,2]*cc[2,3]/105 + A[1,2]*cc[2,4]/210 + A[1,2]*cc[3,3]/70 + A[1,2]*cc[3,4]/105 + A[1,2]*cc[4,4]/210 - A[1,3]*cc[1,3]/630 + A[1,3]*cc[1,4]/630 + A[1,3]*cc[2,3]/210 - A[1,3]*cc[2,4]/210 + A[1,3]*cc[3,3]/105 - A[1,3]*cc[4,4]/105
    M[2,2]=A[2,2]*cc[1,1]/140 + 13*A[2,2]*cc[1,2]/1260 + A[2,2]*cc[1,3]/140 + A[2,2]*cc[1,4]/140 + 11*A[2,2]*cc[2,2]/420 + 13*A[2,2]*cc[2,3]/1260 + 13*A[2,2]*cc[2,4]/1260 + A[2,2]*cc[3,3]/140 + A[2,2]*cc[3,4]/140 + A[2,2]*cc[4,4]/140
    M[2,3]=A[2,3]*cc[1,1]/1260 - A[2,3]*cc[1,2]/252 - A[2,3]*cc[1,3]/252 + A[2,3]*cc[1,4]/1260 - 11*A[2,3]*cc[2,2]/1260 - A[2,3]*cc[2,3]/420 - A[2,3]*cc[2,4]/252 - 11*A[2,3]*cc[3,3]/1260 - A[2,3]*cc[3,4]/252 + A[2,3]*cc[4,4]/1260
    M[2,4]=-A[1,2]*cc[1,1]/1260 + A[1,2]*cc[1,2]/252 - A[1,2]*cc[1,3]/1260 + A[1,2]*cc[1,4]/252 + 11*A[1,2]*cc[2,2]/1260 + A[1,2]*cc[2,3]/252 + A[1,2]*cc[2,4]/420 - A[1,2]*cc[3,3]/1260 + A[1,2]*cc[3,4]/252 + 11*A[1,2]*cc[4,4]/1260 - A[2,2]*cc[1,1]/1260 + A[2,2]*cc[1,2]/252 - A[2,2]*cc[1,3]/1260 + A[2,2]*cc[1,4]/252 + 11*A[2,2]*cc[2,2]/1260 + A[2,2]*cc[2,3]/252 + A[2,2]*cc[2,4]/420 - A[2,2]*cc[3,3]/1260 + A[2,2]*cc[3,4]/252 + 11*A[2,2]*cc[4,4]/1260 - A[2,3]*cc[1,1]/1260 + A[2,3]*cc[1,2]/252 - A[2,3]*cc[1,3]/1260 + A[2,3]*cc[1,4]/252 + 11*A[2,3]*cc[2,2]/1260 + A[2,3]*cc[2,3]/252 + A[2,3]*cc[2,4]/420 - A[2,3]*cc[3,3]/1260 + A[2,3]*cc[3,4]/252 + 11*A[2,3]*cc[4,4]/1260
    M[2,5]=A[1,2]*cc[1,1]/630 + A[1,2]*cc[1,2]/63 + A[1,2]*cc[1,3]/630 + A[1,2]*cc[1,4]/630 + 3*A[1,2]*cc[2,2]/70 + A[1,2]*cc[2,3]/63 + A[1,2]*cc[2,4]/63 + A[1,2]*cc[3,3]/630 + A[1,2]*cc[3,4]/630 + A[1,2]*cc[4,4]/630 - A[2,2]*cc[1,1]/70 + A[2,2]*cc[1,2]/315 - A[2,2]*cc[1,3]/105 - A[2,2]*cc[1,4]/105 + A[2,2]*cc[2,2]/126 + A[2,2]*cc[2,3]/630 + A[2,2]*cc[2,4]/630 - A[2,2]*cc[3,3]/210 - A[2,2]*cc[3,4]/210 - A[2,2]*cc[4,4]/210
    M[2,6]=-A[1,2]*cc[1,1]/210 + A[1,2]*cc[1,2]/630 - A[1,2]*cc[1,3]/105 - A[1,2]*cc[1,4]/210 + A[1,2]*cc[2,2]/126 + A[1,2]*cc[2,3]/315 + A[1,2]*cc[2,4]/630 - A[1,2]*cc[3,3]/70 - A[1,2]*cc[3,4]/105 - A[1,2]*cc[4,4]/210 - A[2,3]*cc[1,1]/70 + A[2,3]*cc[1,2]/315 - A[2,3]*cc[1,3]/105 - A[2,3]*cc[1,4]/105 + A[2,3]*cc[2,2]/126 + A[2,3]*cc[2,3]/630 + A[2,3]*cc[2,4]/630 - A[2,3]*cc[3,3]/210 - A[2,3]*cc[3,4]/210 - A[2,3]*cc[4,4]/210
    M[2,7]=A[1,2]*cc[1,1]/105 - A[1,2]*cc[1,2]/630 + A[1,2]*cc[1,3]/210 + A[1,2]*cc[2,4]/630 - A[1,2]*cc[3,4]/210 - A[1,2]*cc[4,4]/105 + A[2,2]*cc[1,1]/70 - A[2,2]*cc[1,2]/315 + A[2,2]*cc[1,3]/105 + A[2,2]*cc[1,4]/105 - A[2,2]*cc[2,2]/126 - A[2,2]*cc[2,3]/630 - A[2,2]*cc[2,4]/630 + A[2,2]*cc[3,3]/210 + A[2,2]*cc[3,4]/210 + A[2,2]*cc[4,4]/210 + A[2,3]*cc[1,1]/70 - A[2,3]*cc[1,2]/315 + A[2,3]*cc[1,3]/105 + A[2,3]*cc[1,4]/105 - A[2,3]*cc[2,2]/126 - A[2,3]*cc[2,3]/630 - A[2,3]*cc[2,4]/630 + A[2,3]*cc[3,3]/210 + A[2,3]*cc[3,4]/210 + A[2,3]*cc[4,4]/210
    M[2,8]=-A[2,2]*cc[1,1]/210 + A[2,2]*cc[1,2]/630 - A[2,2]*cc[1,3]/105 - A[2,2]*cc[1,4]/210 + A[2,2]*cc[2,2]/126 + A[2,2]*cc[2,3]/315 + A[2,2]*cc[2,4]/630 - A[2,2]*cc[3,3]/70 - A[2,2]*cc[3,4]/105 - A[2,2]*cc[4,4]/210 + A[2,3]*cc[1,1]/630 + A[2,3]*cc[1,2]/63 + A[2,3]*cc[1,3]/630 + A[2,3]*cc[1,4]/630 + 3*A[2,3]*cc[2,2]/70 + A[2,3]*cc[2,3]/63 + A[2,3]*cc[2,4]/63 + A[2,3]*cc[3,3]/630 + A[2,3]*cc[3,4]/630 + A[2,3]*cc[4,4]/630
    M[2,9]=-A[1,2]*cc[1,1]/630 - A[1,2]*cc[1,2]/63 - A[1,2]*cc[1,3]/630 - A[1,2]*cc[1,4]/630 - 3*A[1,2]*cc[2,2]/70 - A[1,2]*cc[2,3]/63 - A[1,2]*cc[2,4]/63 - A[1,2]*cc[3,3]/630 - A[1,2]*cc[3,4]/630 - A[1,2]*cc[4,4]/630 - 2*A[2,2]*cc[1,1]/315 - A[2,2]*cc[1,2]/70 - 2*A[2,2]*cc[1,3]/315 - A[2,2]*cc[1,4]/90 - 11*A[2,2]*cc[2,2]/315 - A[2,2]*cc[2,3]/70 - 4*A[2,2]*cc[2,4]/315 - 2*A[2,2]*cc[3,3]/315 - A[2,2]*cc[3,4]/90 - A[2,2]*cc[4,4]/63 - A[2,3]*cc[1,1]/630 - A[2,3]*cc[1,2]/63 - A[2,3]*cc[1,3]/630 - A[2,3]*cc[1,4]/630 - 3*A[2,3]*cc[2,2]/70 - A[2,3]*cc[2,3]/63 - A[2,3]*cc[2,4]/63 - A[2,3]*cc[3,3]/630 - A[2,3]*cc[3,4]/630 - A[2,3]*cc[4,4]/630
    M[2,10]=A[1,2]*cc[1,1]/210 - A[1,2]*cc[1,2]/630 + A[1,2]*cc[1,3]/105 + A[1,2]*cc[1,4]/210 - A[1,2]*cc[2,2]/126 - A[1,2]*cc[2,3]/315 - A[1,2]*cc[2,4]/630 + A[1,2]*cc[3,3]/70 + A[1,2]*cc[3,4]/105 + A[1,2]*cc[4,4]/210 + A[2,2]*cc[1,1]/210 - A[2,2]*cc[1,2]/630 + A[2,2]*cc[1,3]/105 + A[2,2]*cc[1,4]/210 - A[2,2]*cc[2,2]/126 - A[2,2]*cc[2,3]/315 - A[2,2]*cc[2,4]/630 + A[2,2]*cc[3,3]/70 + A[2,2]*cc[3,4]/105 + A[2,2]*cc[4,4]/210 + A[2,3]*cc[1,3]/210 - A[2,3]*cc[1,4]/210 - A[2,3]*cc[2,3]/630 + A[2,3]*cc[2,4]/630 + A[2,3]*cc[3,3]/105 - A[2,3]*cc[4,4]/105
    M[3,3]=A[3,3]*cc[1,1]/140 + A[3,3]*cc[1,2]/140 + 13*A[3,3]*cc[1,3]/1260 + A[3,3]*cc[1,4]/140 + A[3,3]*cc[2,2]/140 + 13*A[3,3]*cc[2,3]/1260 + A[3,3]*cc[2,4]/140 + 11*A[3,3]*cc[3,3]/420 + 13*A[3,3]*cc[3,4]/1260 + A[3,3]*cc[4,4]/140
    M[3,4]=-A[1,3]*cc[1,1]/1260 - A[1,3]*cc[1,2]/1260 + A[1,3]*cc[1,3]/252 + A[1,3]*cc[1,4]/252 - A[1,3]*cc[2,2]/1260 + A[1,3]*cc[2,3]/252 + A[1,3]*cc[2,4]/252 + 11*A[1,3]*cc[3,3]/1260 + A[1,3]*cc[3,4]/420 + 11*A[1,3]*cc[4,4]/1260 - A[2,3]*cc[1,1]/1260 - A[2,3]*cc[1,2]/1260 + A[2,3]*cc[1,3]/252 + A[2,3]*cc[1,4]/252 - A[2,3]*cc[2,2]/1260 + A[2,3]*cc[2,3]/252 + A[2,3]*cc[2,4]/252 + 11*A[2,3]*cc[3,3]/1260 + A[2,3]*cc[3,4]/420 + 11*A[2,3]*cc[4,4]/1260 - A[3,3]*cc[1,1]/1260 - A[3,3]*cc[1,2]/1260 + A[3,3]*cc[1,3]/252 + A[3,3]*cc[1,4]/252 - A[3,3]*cc[2,2]/1260 + A[3,3]*cc[2,3]/252 + A[3,3]*cc[2,4]/252 + 11*A[3,3]*cc[3,3]/1260 + A[3,3]*cc[3,4]/420 + 11*A[3,3]*cc[4,4]/1260
    M[3,5]=-A[1,3]*cc[1,1]/210 - A[1,3]*cc[1,2]/105 + A[1,3]*cc[1,3]/630 - A[1,3]*cc[1,4]/210 - A[1,3]*cc[2,2]/70 + A[1,3]*cc[2,3]/315 - A[1,3]*cc[2,4]/105 + A[1,3]*cc[3,3]/126 + A[1,3]*cc[3,4]/630 - A[1,3]*cc[4,4]/210 - A[2,3]*cc[1,1]/70 - A[2,3]*cc[1,2]/105 + A[2,3]*cc[1,3]/315 - A[2,3]*cc[1,4]/105 - A[2,3]*cc[2,2]/210 + A[2,3]*cc[2,3]/630 - A[2,3]*cc[2,4]/210 + A[2,3]*cc[3,3]/126 + A[2,3]*cc[3,4]/630 - A[2,3]*cc[4,4]/210
    M[3,6]=A[1,3]*cc[1,1]/630 + A[1,3]*cc[1,2]/630 + A[1,3]*cc[1,3]/63 + A[1,3]*cc[1,4]/630 + A[1,3]*cc[2,2]/630 + A[1,3]*cc[2,3]/63 + A[1,3]*cc[2,4]/630 + 3*A[1,3]*cc[3,3]/70 + A[1,3]*cc[3,4]/63 + A[1,3]*cc[4,4]/630 - A[3,3]*cc[1,1]/70 - A[3,3]*cc[1,2]/105 + A[3,3]*cc[1,3]/315 - A[3,3]*cc[1,4]/105 - A[3,3]*cc[2,2]/210 + A[3,3]*cc[2,3]/630 - A[3,3]*cc[2,4]/210 + A[3,3]*cc[3,3]/126 + A[3,3]*cc[3,4]/630 - A[3,3]*cc[4,4]/210
    M[3,7]=A[1,3]*cc[1,1]/105 + A[1,3]*cc[1,2]/210 - A[1,3]*cc[1,3]/630 - A[1,3]*cc[2,4]/210 + A[1,3]*cc[3,4]/630 - A[1,3]*cc[4,4]/105 + A[2,3]*cc[1,1]/70 + A[2,3]*cc[1,2]/105 - A[2,3]*cc[1,3]/315 + A[2,3]*cc[1,4]/105 + A[2,3]*cc[2,2]/210 - A[2,3]*cc[2,3]/630 + A[2,3]*cc[2,4]/210 - A[2,3]*cc[3,3]/126 - A[2,3]*cc[3,4]/630 + A[2,3]*cc[4,4]/210 + A[3,3]*cc[1,1]/70 + A[3,3]*cc[1,2]/105 - A[3,3]*cc[1,3]/315 + A[3,3]*cc[1,4]/105 + A[3,3]*cc[2,2]/210 - A[3,3]*cc[2,3]/630 + A[3,3]*cc[2,4]/210 - A[3,3]*cc[3,3]/126 - A[3,3]*cc[3,4]/630 + A[3,3]*cc[4,4]/210
    M[3,8]=A[2,3]*cc[1,1]/630 + A[2,3]*cc[1,2]/630 + A[2,3]*cc[1,3]/63 + A[2,3]*cc[1,4]/630 + A[2,3]*cc[2,2]/630 + A[2,3]*cc[2,3]/63 + A[2,3]*cc[2,4]/630 + 3*A[2,3]*cc[3,3]/70 + A[2,3]*cc[3,4]/63 + A[2,3]*cc[4,4]/630 - A[3,3]*cc[1,1]/210 - A[3,3]*cc[1,2]/105 + A[3,3]*cc[1,3]/630 - A[3,3]*cc[1,4]/210 - A[3,3]*cc[2,2]/70 + A[3,3]*cc[2,3]/315 - A[3,3]*cc[2,4]/105 + A[3,3]*cc[3,3]/126 + A[3,3]*cc[3,4]/630 - A[3,3]*cc[4,4]/210
    M[3,9]=A[1,3]*cc[1,1]/210 + A[1,3]*cc[1,2]/105 - A[1,3]*cc[1,3]/630 + A[1,3]*cc[1,4]/210 + A[1,3]*cc[2,2]/70 - A[1,3]*cc[2,3]/315 + A[1,3]*cc[2,4]/105 - A[1,3]*cc[3,3]/126 - A[1,3]*cc[3,4]/630 + A[1,3]*cc[4,4]/210 + A[2,3]*cc[1,2]/210 - A[2,3]*cc[1,4]/210 + A[2,3]*cc[2,2]/105 - A[2,3]*cc[2,3]/630 + A[2,3]*cc[3,4]/630 - A[2,3]*cc[4,4]/105 + A[3,3]*cc[1,1]/210 + A[3,3]*cc[1,2]/105 - A[3,3]*cc[1,3]/630 + A[3,3]*cc[1,4]/210 + A[3,3]*cc[2,2]/70 - A[3,3]*cc[2,3]/315 + A[3,3]*cc[2,4]/105 - A[3,3]*cc[3,3]/126 - A[3,3]*cc[3,4]/630 + A[3,3]*cc[4,4]/210
    M[3,10]=-A[1,3]*cc[1,1]/630 - A[1,3]*cc[1,2]/630 - A[1,3]*cc[1,3]/63 - A[1,3]*cc[1,4]/630 - A[1,3]*cc[2,2]/630 - A[1,3]*cc[2,3]/63 - A[1,3]*cc[2,4]/630 - 3*A[1,3]*cc[3,3]/70 - A[1,3]*cc[3,4]/63 - A[1,3]*cc[4,4]/630 - A[2,3]*cc[1,1]/630 - A[2,3]*cc[1,2]/630 - A[2,3]*cc[1,3]/63 - A[2,3]*cc[1,4]/630 - A[2,3]*cc[2,2]/630 - A[2,3]*cc[2,3]/63 - A[2,3]*cc[2,4]/630 - 3*A[2,3]*cc[3,3]/70 - A[2,3]*cc[3,4]/63 - A[2,3]*cc[4,4]/630 - 2*A[3,3]*cc[1,1]/315 - 2*A[3,3]*cc[1,2]/315 - A[3,3]*cc[1,3]/70 - A[3,3]*cc[1,4]/90 - 2*A[3,3]*cc[2,2]/315 - A[3,3]*cc[2,3]/70 - A[3,3]*cc[2,4]/90 - 11*A[3,3]*cc[3,3]/315 - 4*A[3,3]*cc[3,4]/315 - A[3,3]*cc[4,4]/63
    M[4,4]=A[1,1]*cc[1,1]/140 + A[1,1]*cc[1,2]/140 + A[1,1]*cc[1,3]/140 + 13*A[1,1]*cc[1,4]/1260 + A[1,1]*cc[2,2]/140 + A[1,1]*cc[2,3]/140 + 13*A[1,1]*cc[2,4]/1260 + A[1,1]*cc[3,3]/140 + 13*A[1,1]*cc[3,4]/1260 + 11*A[1,1]*cc[4,4]/420 + A[1,2]*cc[1,1]/70 + A[1,2]*cc[1,2]/70 + A[1,2]*cc[1,3]/70 + 13*A[1,2]*cc[1,4]/630 + A[1,2]*cc[2,2]/70 + A[1,2]*cc[2,3]/70 + 13*A[1,2]*cc[2,4]/630 + A[1,2]*cc[3,3]/70 + 13*A[1,2]*cc[3,4]/630 + 11*A[1,2]*cc[4,4]/210 + A[1,3]*cc[1,1]/70 + A[1,3]*cc[1,2]/70 + A[1,3]*cc[1,3]/70 + 13*A[1,3]*cc[1,4]/630 + A[1,3]*cc[2,2]/70 + A[1,3]*cc[2,3]/70 + 13*A[1,3]*cc[2,4]/630 + A[1,3]*cc[3,3]/70 + 13*A[1,3]*cc[3,4]/630 + 11*A[1,3]*cc[4,4]/210 + A[2,2]*cc[1,1]/140 + A[2,2]*cc[1,2]/140 + A[2,2]*cc[1,3]/140 + 13*A[2,2]*cc[1,4]/1260 + A[2,2]*cc[2,2]/140 + A[2,2]*cc[2,3]/140 + 13*A[2,2]*cc[2,4]/1260 + A[2,2]*cc[3,3]/140 + 13*A[2,2]*cc[3,4]/1260 + 11*A[2,2]*cc[4,4]/420 + A[2,3]*cc[1,1]/70 + A[2,3]*cc[1,2]/70 + A[2,3]*cc[1,3]/70 + 13*A[2,3]*cc[1,4]/630 + A[2,3]*cc[2,2]/70 + A[2,3]*cc[2,3]/70 + 13*A[2,3]*cc[2,4]/630 + A[2,3]*cc[3,3]/70 + 13*A[2,3]*cc[3,4]/630 + 11*A[2,3]*cc[4,4]/210 + A[3,3]*cc[1,1]/140 + A[3,3]*cc[1,2]/140 + A[3,3]*cc[1,3]/140 + 13*A[3,3]*cc[1,4]/1260 + A[3,3]*cc[2,2]/140 + A[3,3]*cc[2,3]/140 + 13*A[3,3]*cc[2,4]/1260 + A[3,3]*cc[3,3]/140 + 13*A[3,3]*cc[3,4]/1260 + 11*A[3,3]*cc[4,4]/420
    M[4,5]=A[1,1]*cc[1,1]/210 + A[1,1]*cc[1,2]/105 + A[1,1]*cc[1,3]/210 - A[1,1]*cc[1,4]/630 + A[1,1]*cc[2,2]/70 + A[1,1]*cc[2,3]/105 - A[1,1]*cc[2,4]/315 + A[1,1]*cc[3,3]/210 - A[1,1]*cc[3,4]/630 - A[1,1]*cc[4,4]/126 + 2*A[1,2]*cc[1,1]/105 + 2*A[1,2]*cc[1,2]/105 + A[1,2]*cc[1,3]/70 - A[1,2]*cc[1,4]/210 + 2*A[1,2]*cc[2,2]/105 + A[1,2]*cc[2,3]/70 - A[1,2]*cc[2,4]/210 + A[1,2]*cc[3,3]/105 - A[1,2]*cc[3,4]/315 - A[1,2]*cc[4,4]/63 + A[1,3]*cc[1,1]/210 + A[1,3]*cc[1,2]/105 + A[1,3]*cc[1,3]/210 - A[1,3]*cc[1,4]/630 + A[1,3]*cc[2,2]/70 + A[1,3]*cc[2,3]/105 - A[1,3]*cc[2,4]/315 + A[1,3]*cc[3,3]/210 - A[1,3]*cc[3,4]/630 - A[1,3]*cc[4,4]/126 + A[2,2]*cc[1,1]/70 + A[2,2]*cc[1,2]/105 + A[2,2]*cc[1,3]/105 - A[2,2]*cc[1,4]/315 + A[2,2]*cc[2,2]/210 + A[2,2]*cc[2,3]/210 - A[2,2]*cc[2,4]/630 + A[2,2]*cc[3,3]/210 - A[2,2]*cc[3,4]/630 - A[2,2]*cc[4,4]/126 + A[2,3]*cc[1,1]/70 + A[2,3]*cc[1,2]/105 + A[2,3]*cc[1,3]/105 - A[2,3]*cc[1,4]/315 + A[2,3]*cc[2,2]/210 + A[2,3]*cc[2,3]/210 - A[2,3]*cc[2,4]/630 + A[2,3]*cc[3,3]/210 - A[2,3]*cc[3,4]/630 - A[2,3]*cc[4,4]/126
    M[4,6]=A[1,1]*cc[1,1]/210 + A[1,1]*cc[1,2]/210 + A[1,1]*cc[1,3]/105 - A[1,1]*cc[1,4]/630 + A[1,1]*cc[2,2]/210 + A[1,1]*cc[2,3]/105 - A[1,1]*cc[2,4]/630 + A[1,1]*cc[3,3]/70 - A[1,1]*cc[3,4]/315 - A[1,1]*cc[4,4]/126 + A[1,2]*cc[1,1]/210 + A[1,2]*cc[1,2]/210 + A[1,2]*cc[1,3]/105 - A[1,2]*cc[1,4]/630 + A[1,2]*cc[2,2]/210 + A[1,2]*cc[2,3]/105 - A[1,2]*cc[2,4]/630 + A[1,2]*cc[3,3]/70 - A[1,2]*cc[3,4]/315 - A[1,2]*cc[4,4]/126 + 2*A[1,3]*cc[1,1]/105 + A[1,3]*cc[1,2]/70 + 2*A[1,3]*cc[1,3]/105 - A[1,3]*cc[1,4]/210 + A[1,3]*cc[2,2]/105 + A[1,3]*cc[2,3]/70 - A[1,3]*cc[2,4]/315 + 2*A[1,3]*cc[3,3]/105 - A[1,3]*cc[3,4]/210 - A[1,3]*cc[4,4]/63 + A[2,3]*cc[1,1]/70 + A[2,3]*cc[1,2]/105 + A[2,3]*cc[1,3]/105 - A[2,3]*cc[1,4]/315 + A[2,3]*cc[2,2]/210 + A[2,3]*cc[2,3]/210 - A[2,3]*cc[2,4]/630 + A[2,3]*cc[3,3]/210 - A[2,3]*cc[3,4]/630 - A[2,3]*cc[4,4]/126 + A[3,3]*cc[1,1]/70 + A[3,3]*cc[1,2]/105 + A[3,3]*cc[1,3]/105 - A[3,3]*cc[1,4]/315 + A[3,3]*cc[2,2]/210 + A[3,3]*cc[2,3]/210 - A[3,3]*cc[2,4]/630 + A[3,3]*cc[3,3]/210 - A[3,3]*cc[3,4]/630 - A[3,3]*cc[4,4]/126
    M[4,7]=-A[1,1]*cc[1,1]/63 - A[1,1]*cc[1,2]/90 - A[1,1]*cc[1,3]/90 - 4*A[1,1]*cc[1,4]/315 - 2*A[1,1]*cc[2,2]/315 - 2*A[1,1]*cc[2,3]/315 - A[1,1]*cc[2,4]/70 - 2*A[1,1]*cc[3,3]/315 - A[1,1]*cc[3,4]/70 - 11*A[1,1]*cc[4,4]/315 - 19*A[1,2]*cc[1,1]/630 - 13*A[1,2]*cc[1,2]/630 - 13*A[1,2]*cc[1,3]/630 - A[1,2]*cc[1,4]/105 - A[1,2]*cc[2,2]/90 - A[1,2]*cc[2,3]/90 - 4*A[1,2]*cc[2,4]/315 - A[1,2]*cc[3,3]/90 - 4*A[1,2]*cc[3,4]/315 - 17*A[1,2]*cc[4,4]/630 - 19*A[1,3]*cc[1,1]/630 - 13*A[1,3]*cc[1,2]/630 - 13*A[1,3]*cc[1,3]/630 - A[1,3]*cc[1,4]/105 - A[1,3]*cc[2,2]/90 - A[1,3]*cc[2,3]/90 - 4*A[1,3]*cc[2,4]/315 - A[1,3]*cc[3,3]/90 - 4*A[1,3]*cc[3,4]/315 - 17*A[1,3]*cc[4,4]/630 - A[2,2]*cc[1,1]/70 - A[2,2]*cc[1,2]/105 - A[2,2]*cc[1,3]/105 + A[2,2]*cc[1,4]/315 - A[2,2]*cc[2,2]/210 - A[2,2]*cc[2,3]/210 + A[2,2]*cc[2,4]/630 - A[2,2]*cc[3,3]/210 + A[2,2]*cc[3,4]/630 + A[2,2]*cc[4,4]/126 - A[2,3]*cc[1,1]/35 - 2*A[2,3]*cc[1,2]/105 - 2*A[2,3]*cc[1,3]/105 + 2*A[2,3]*cc[1,4]/315 - A[2,3]*cc[2,2]/105 - A[2,3]*cc[2,3]/105 + A[2,3]*cc[2,4]/315 - A[2,3]*cc[3,3]/105 + A[2,3]*cc[3,4]/315 + A[2,3]*cc[4,4]/63 - A[3,3]*cc[1,1]/70 - A[3,3]*cc[1,2]/105 - A[3,3]*cc[1,3]/105 + A[3,3]*cc[1,4]/315 - A[3,3]*cc[2,2]/210 - A[3,3]*cc[2,3]/210 + A[3,3]*cc[2,4]/630 - A[3,3]*cc[3,3]/210 + A[3,3]*cc[3,4]/630 + A[3,3]*cc[4,4]/126
    M[4,8]=A[1,2]*cc[1,1]/210 + A[1,2]*cc[1,2]/210 + A[1,2]*cc[1,3]/105 - A[1,2]*cc[1,4]/630 + A[1,2]*cc[2,2]/210 + A[1,2]*cc[2,3]/105 - A[1,2]*cc[2,4]/630 + A[1,2]*cc[3,3]/70 - A[1,2]*cc[3,4]/315 - A[1,2]*cc[4,4]/126 + A[1,3]*cc[1,1]/210 + A[1,3]*cc[1,2]/105 + A[1,3]*cc[1,3]/210 - A[1,3]*cc[1,4]/630 + A[1,3]*cc[2,2]/70 + A[1,3]*cc[2,3]/105 - A[1,3]*cc[2,4]/315 + A[1,3]*cc[3,3]/210 - A[1,3]*cc[3,4]/630 - A[1,3]*cc[4,4]/126 + A[2,2]*cc[1,1]/210 + A[2,2]*cc[1,2]/210 + A[2,2]*cc[1,3]/105 - A[2,2]*cc[1,4]/630 + A[2,2]*cc[2,2]/210 + A[2,2]*cc[2,3]/105 - A[2,2]*cc[2,4]/630 + A[2,2]*cc[3,3]/70 - A[2,2]*cc[3,4]/315 - A[2,2]*cc[4,4]/126 + A[2,3]*cc[1,1]/105 + A[2,3]*cc[1,2]/70 + A[2,3]*cc[1,3]/70 - A[2,3]*cc[1,4]/315 + 2*A[2,3]*cc[2,2]/105 + 2*A[2,3]*cc[2,3]/105 - A[2,3]*cc[2,4]/210 + 2*A[2,3]*cc[3,3]/105 - A[2,3]*cc[3,4]/210 - A[2,3]*cc[4,4]/63 + A[3,3]*cc[1,1]/210 + A[3,3]*cc[1,2]/105 + A[3,3]*cc[1,3]/210 - A[3,3]*cc[1,4]/630 + A[3,3]*cc[2,2]/70 + A[3,3]*cc[2,3]/105 - A[3,3]*cc[2,4]/315 + A[3,3]*cc[3,3]/210 - A[3,3]*cc[3,4]/630 - A[3,3]*cc[4,4]/126
    M[4,9]=-A[1,1]*cc[1,1]/210 - A[1,1]*cc[1,2]/105 - A[1,1]*cc[1,3]/210 + A[1,1]*cc[1,4]/630 - A[1,1]*cc[2,2]/70 - A[1,1]*cc[2,3]/105 + A[1,1]*cc[2,4]/315 - A[1,1]*cc[3,3]/210 + A[1,1]*cc[3,4]/630 + A[1,1]*cc[4,4]/126 - A[1,2]*cc[1,1]/90 - 13*A[1,2]*cc[1,2]/630 - A[1,2]*cc[1,3]/90 - 4*A[1,2]*cc[1,4]/315 - 19*A[1,2]*cc[2,2]/630 - 13*A[1,2]*cc[2,3]/630 - A[1,2]*cc[2,4]/105 - A[1,2]*cc[3,3]/90 - 4*A[1,2]*cc[3,4]/315 - 17*A[1,2]*cc[4,4]/630 - A[1,3]*cc[1,1]/105 - 2*A[1,3]*cc[1,2]/105 - A[1,3]*cc[1,3]/105 + A[1,3]*cc[1,4]/315 - A[1,3]*cc[2,2]/35 - 2*A[1,3]*cc[2,3]/105 + 2*A[1,3]*cc[2,4]/315 - A[1,3]*cc[3,3]/105 + A[1,3]*cc[3,4]/315 + A[1,3]*cc[4,4]/63 - 2*A[2,2]*cc[1,1]/315 - A[2,2]*cc[1,2]/90 - 2*A[2,2]*cc[1,3]/315 - A[2,2]*cc[1,4]/70 - A[2,2]*cc[2,2]/63 - A[2,2]*cc[2,3]/90 - 4*A[2,2]*cc[2,4]/315 - 2*A[2,2]*cc[3,3]/315 - A[2,2]*cc[3,4]/70 - 11*A[2,2]*cc[4,4]/315 - A[2,3]*cc[1,1]/90 - 13*A[2,3]*cc[1,2]/630 - A[2,3]*cc[1,3]/90 - 4*A[2,3]*cc[1,4]/315 - 19*A[2,3]*cc[2,2]/630 - 13*A[2,3]*cc[2,3]/630 - A[2,3]*cc[2,4]/105 - A[2,3]*cc[3,3]/90 - 4*A[2,3]*cc[3,4]/315 - 17*A[2,3]*cc[4,4]/630 - A[3,3]*cc[1,1]/210 - A[3,3]*cc[1,2]/105 - A[3,3]*cc[1,3]/210 + A[3,3]*cc[1,4]/630 - A[3,3]*cc[2,2]/70 - A[3,3]*cc[2,3]/105 + A[3,3]*cc[2,4]/315 - A[3,3]*cc[3,3]/210 + A[3,3]*cc[3,4]/630 + A[3,3]*cc[4,4]/126
    M[4,10]=-A[1,1]*cc[1,1]/210 - A[1,1]*cc[1,2]/210 - A[1,1]*cc[1,3]/105 + A[1,1]*cc[1,4]/630 - A[1,1]*cc[2,2]/210 - A[1,1]*cc[2,3]/105 + A[1,1]*cc[2,4]/630 - A[1,1]*cc[3,3]/70 + A[1,1]*cc[3,4]/315 + A[1,1]*cc[4,4]/126 - A[1,2]*cc[1,1]/105 - A[1,2]*cc[1,2]/105 - 2*A[1,2]*cc[1,3]/105 + A[1,2]*cc[1,4]/315 - A[1,2]*cc[2,2]/105 - 2*A[1,2]*cc[2,3]/105 + A[1,2]*cc[2,4]/315 - A[1,2]*cc[3,3]/35 + 2*A[1,2]*cc[3,4]/315 + A[1,2]*cc[4,4]/63 - A[1,3]*cc[1,1]/90 - A[1,3]*cc[1,2]/90 - 13*A[1,3]*cc[1,3]/630 - 4*A[1,3]*cc[1,4]/315 - A[1,3]*cc[2,2]/90 - 13*A[1,3]*cc[2,3]/630 - 4*A[1,3]*cc[2,4]/315 - 19*A[1,3]*cc[3,3]/630 - A[1,3]*cc[3,4]/105 - 17*A[1,3]*cc[4,4]/630 - A[2,2]*cc[1,1]/210 - A[2,2]*cc[1,2]/210 - A[2,2]*cc[1,3]/105 + A[2,2]*cc[1,4]/630 - A[2,2]*cc[2,2]/210 - A[2,2]*cc[2,3]/105 + A[2,2]*cc[2,4]/630 - A[2,2]*cc[3,3]/70 + A[2,2]*cc[3,4]/315 + A[2,2]*cc[4,4]/126 - A[2,3]*cc[1,1]/90 - A[2,3]*cc[1,2]/90 - 13*A[2,3]*cc[1,3]/630 - 4*A[2,3]*cc[1,4]/315 - A[2,3]*cc[2,2]/90 - 13*A[2,3]*cc[2,3]/630 - 4*A[2,3]*cc[2,4]/315 - 19*A[2,3]*cc[3,3]/630 - A[2,3]*cc[3,4]/105 - 17*A[2,3]*cc[4,4]/630 - 2*A[3,3]*cc[1,1]/315 - 2*A[3,3]*cc[1,2]/315 - A[3,3]*cc[1,3]/90 - A[3,3]*cc[1,4]/70 - 2*A[3,3]*cc[2,2]/315 - A[3,3]*cc[2,3]/90 - A[3,3]*cc[2,4]/70 - A[3,3]*cc[3,3]/63 - 4*A[3,3]*cc[3,4]/315 - 11*A[3,3]*cc[4,4]/315
    M[5,5]=4*A[1,1]*cc[1,1]/315 + 4*A[1,1]*cc[1,2]/105 + 4*A[1,1]*cc[1,3]/315 + 4*A[1,1]*cc[1,4]/315 + 8*A[1,1]*cc[2,2]/105 + 4*A[1,1]*cc[2,3]/105 + 4*A[1,1]*cc[2,4]/105 + 4*A[1,1]*cc[3,3]/315 + 4*A[1,1]*cc[3,4]/315 + 4*A[1,1]*cc[4,4]/315 + 4*A[1,2]*cc[1,1]/105 + 16*A[1,2]*cc[1,2]/315 + 8*A[1,2]*cc[1,3]/315 + 8*A[1,2]*cc[1,4]/315 + 4*A[1,2]*cc[2,2]/105 + 8*A[1,2]*cc[2,3]/315 + 8*A[1,2]*cc[2,4]/315 + 4*A[1,2]*cc[3,3]/315 + 4*A[1,2]*cc[3,4]/315 + 4*A[1,2]*cc[4,4]/315 + 8*A[2,2]*cc[1,1]/105 + 4*A[2,2]*cc[1,2]/105 + 4*A[2,2]*cc[1,3]/105 + 4*A[2,2]*cc[1,4]/105 + 4*A[2,2]*cc[2,2]/315 + 4*A[2,2]*cc[2,3]/315 + 4*A[2,2]*cc[2,4]/315 + 4*A[2,2]*cc[3,3]/315 + 4*A[2,2]*cc[3,4]/315 + 4*A[2,2]*cc[4,4]/315
    M[5,6]=2*A[1,1]*cc[1,1]/315 + 4*A[1,1]*cc[1,2]/315 + 4*A[1,1]*cc[1,3]/315 + 2*A[1,1]*cc[1,4]/315 + 2*A[1,1]*cc[2,2]/105 + 8*A[1,1]*cc[2,3]/315 + 4*A[1,1]*cc[2,4]/315 + 2*A[1,1]*cc[3,3]/105 + 4*A[1,1]*cc[3,4]/315 + 2*A[1,1]*cc[4,4]/315 + 2*A[1,2]*cc[1,1]/105 + 4*A[1,2]*cc[1,2]/315 + 8*A[1,2]*cc[1,3]/315 + 4*A[1,2]*cc[1,4]/315 + 2*A[1,2]*cc[2,2]/315 + 4*A[1,2]*cc[2,3]/315 + 2*A[1,2]*cc[2,4]/315 + 2*A[1,2]*cc[3,3]/105 + 4*A[1,2]*cc[3,4]/315 + 2*A[1,2]*cc[4,4]/315 + 2*A[1,3]*cc[1,1]/105 + 8*A[1,3]*cc[1,2]/315 + 4*A[1,3]*cc[1,3]/315 + 4*A[1,3]*cc[1,4]/315 + 2*A[1,3]*cc[2,2]/105 + 4*A[1,3]*cc[2,3]/315 + 4*A[1,3]*cc[2,4]/315 + 2*A[1,3]*cc[3,3]/315 + 2*A[1,3]*cc[3,4]/315 + 2*A[1,3]*cc[4,4]/315 + 8*A[2,3]*cc[1,1]/105 + 4*A[2,3]*cc[1,2]/105 + 4*A[2,3]*cc[1,3]/105 + 4*A[2,3]*cc[1,4]/105 + 4*A[2,3]*cc[2,2]/315 + 4*A[2,3]*cc[2,3]/315 + 4*A[2,3]*cc[2,4]/315 + 4*A[2,3]*cc[3,3]/315 + 4*A[2,3]*cc[3,4]/315 + 4*A[2,3]*cc[4,4]/315
    M[5,7]=-4*A[1,1]*cc[1,1]/315 - 4*A[1,1]*cc[1,2]/315 - 2*A[1,1]*cc[1,3]/315 + 4*A[1,1]*cc[2,4]/315 + 2*A[1,1]*cc[3,4]/315 + 4*A[1,1]*cc[4,4]/315 - 8*A[1,2]*cc[1,1]/105 - 16*A[1,2]*cc[1,2]/315 - 4*A[1,2]*cc[1,3]/105 - 8*A[1,2]*cc[1,4]/315 - 8*A[1,2]*cc[2,2]/315 - 2*A[1,2]*cc[2,3]/105 - 4*A[1,2]*cc[2,4]/315 - 4*A[1,2]*cc[3,3]/315 - 2*A[1,2]*cc[3,4]/315 - 2*A[1,3]*cc[1,1]/105 - 8*A[1,3]*cc[1,2]/315 - 4*A[1,3]*cc[1,3]/315 - 4*A[1,3]*cc[1,4]/315 - 2*A[1,3]*cc[2,2]/105 - 4*A[1,3]*cc[2,3]/315 - 4*A[1,3]*cc[2,4]/315 - 2*A[1,3]*cc[3,3]/315 - 2*A[1,3]*cc[3,4]/315 - 2*A[1,3]*cc[4,4]/315 - 8*A[2,2]*cc[1,1]/105 - 4*A[2,2]*cc[1,2]/105 - 4*A[2,2]*cc[1,3]/105 - 4*A[2,2]*cc[1,4]/105 - 4*A[2,2]*cc[2,2]/315 - 4*A[2,2]*cc[2,3]/315 - 4*A[2,2]*cc[2,4]/315 - 4*A[2,2]*cc[3,3]/315 - 4*A[2,2]*cc[3,4]/315 - 4*A[2,2]*cc[4,4]/315 - 8*A[2,3]*cc[1,1]/105 - 4*A[2,3]*cc[1,2]/105 - 4*A[2,3]*cc[1,3]/105 - 4*A[2,3]*cc[1,4]/105 - 4*A[2,3]*cc[2,2]/315 - 4*A[2,3]*cc[2,3]/315 - 4*A[2,3]*cc[2,4]/315 - 4*A[2,3]*cc[3,3]/315 - 4*A[2,3]*cc[3,4]/315 - 4*A[2,3]*cc[4,4]/315
    M[5,8]=2*A[1,2]*cc[1,1]/315 + 4*A[1,2]*cc[1,2]/315 + 4*A[1,2]*cc[1,3]/315 + 2*A[1,2]*cc[1,4]/315 + 2*A[1,2]*cc[2,2]/105 + 8*A[1,2]*cc[2,3]/315 + 4*A[1,2]*cc[2,4]/315 + 2*A[1,2]*cc[3,3]/105 + 4*A[1,2]*cc[3,4]/315 + 2*A[1,2]*cc[4,4]/315 + 4*A[1,3]*cc[1,1]/315 + 4*A[1,3]*cc[1,2]/105 + 4*A[1,3]*cc[1,3]/315 + 4*A[1,3]*cc[1,4]/315 + 8*A[1,3]*cc[2,2]/105 + 4*A[1,3]*cc[2,3]/105 + 4*A[1,3]*cc[2,4]/105 + 4*A[1,3]*cc[3,3]/315 + 4*A[1,3]*cc[3,4]/315 + 4*A[1,3]*cc[4,4]/315 + 2*A[2,2]*cc[1,1]/105 + 4*A[2,2]*cc[1,2]/315 + 8*A[2,2]*cc[1,3]/315 + 4*A[2,2]*cc[1,4]/315 + 2*A[2,2]*cc[2,2]/315 + 4*A[2,2]*cc[2,3]/315 + 2*A[2,2]*cc[2,4]/315 + 2*A[2,2]*cc[3,3]/105 + 4*A[2,2]*cc[3,4]/315 + 2*A[2,2]*cc[4,4]/315 + 2*A[2,3]*cc[1,1]/105 + 8*A[2,3]*cc[1,2]/315 + 4*A[2,3]*cc[1,3]/315 + 4*A[2,3]*cc[1,4]/315 + 2*A[2,3]*cc[2,2]/105 + 4*A[2,3]*cc[2,3]/315 + 4*A[2,3]*cc[2,4]/315 + 2*A[2,3]*cc[3,3]/315 + 2*A[2,3]*cc[3,4]/315 + 2*A[2,3]*cc[4,4]/315
    M[5,9]=-4*A[1,1]*cc[1,1]/315 - 4*A[1,1]*cc[1,2]/105 - 4*A[1,1]*cc[1,3]/315 - 4*A[1,1]*cc[1,4]/315 - 8*A[1,1]*cc[2,2]/105 - 4*A[1,1]*cc[2,3]/105 - 4*A[1,1]*cc[2,4]/105 - 4*A[1,1]*cc[3,3]/315 - 4*A[1,1]*cc[3,4]/315 - 4*A[1,1]*cc[4,4]/315 - 8*A[1,2]*cc[1,1]/315 - 16*A[1,2]*cc[1,2]/315 - 2*A[1,2]*cc[1,3]/105 - 4*A[1,2]*cc[1,4]/315 - 8*A[1,2]*cc[2,2]/105 - 4*A[1,2]*cc[2,3]/105 - 8*A[1,2]*cc[2,4]/315 - 4*A[1,2]*cc[3,3]/315 - 2*A[1,2]*cc[3,4]/315 - 4*A[1,3]*cc[1,1]/315 - 4*A[1,3]*cc[1,2]/105 - 4*A[1,3]*cc[1,3]/315 - 4*A[1,3]*cc[1,4]/315 - 8*A[1,3]*cc[2,2]/105 - 4*A[1,3]*cc[2,3]/105 - 4*A[1,3]*cc[2,4]/105 - 4*A[1,3]*cc[3,3]/315 - 4*A[1,3]*cc[3,4]/315 - 4*A[1,3]*cc[4,4]/315 - 4*A[2,2]*cc[1,2]/315 + 4*A[2,2]*cc[1,4]/315 - 4*A[2,2]*cc[2,2]/315 - 2*A[2,2]*cc[2,3]/315 + 2*A[2,2]*cc[3,4]/315 + 4*A[2,2]*cc[4,4]/315 - 2*A[2,3]*cc[1,1]/105 - 8*A[2,3]*cc[1,2]/315 - 4*A[2,3]*cc[1,3]/315 - 4*A[2,3]*cc[1,4]/315 - 2*A[2,3]*cc[2,2]/105 - 4*A[2,3]*cc[2,3]/315 - 4*A[2,3]*cc[2,4]/315 - 2*A[2,3]*cc[3,3]/315 - 2*A[2,3]*cc[3,4]/315 - 2*A[2,3]*cc[4,4]/315
    M[5,10]=-2*A[1,1]*cc[1,1]/315 - 4*A[1,1]*cc[1,2]/315 - 4*A[1,1]*cc[1,3]/315 - 2*A[1,1]*cc[1,4]/315 - 2*A[1,1]*cc[2,2]/105 - 8*A[1,1]*cc[2,3]/315 - 4*A[1,1]*cc[2,4]/315 - 2*A[1,1]*cc[3,3]/105 - 4*A[1,1]*cc[3,4]/315 - 2*A[1,1]*cc[4,4]/315 - 8*A[1,2]*cc[1,1]/315 - 8*A[1,2]*cc[1,2]/315 - 4*A[1,2]*cc[1,3]/105 - 2*A[1,2]*cc[1,4]/105 - 8*A[1,2]*cc[2,2]/315 - 4*A[1,2]*cc[2,3]/105 - 2*A[1,2]*cc[2,4]/105 - 4*A[1,2]*cc[3,3]/105 - 8*A[1,2]*cc[3,4]/315 - 4*A[1,2]*cc[4,4]/315 - 2*A[1,3]*cc[1,3]/315 + 2*A[1,3]*cc[1,4]/315 - 4*A[1,3]*cc[2,3]/315 + 4*A[1,3]*cc[2,4]/315 - 4*A[1,3]*cc[3,3]/315 + 4*A[1,3]*cc[4,4]/315 - 2*A[2,2]*cc[1,1]/105 - 4*A[2,2]*cc[1,2]/315 - 8*A[2,2]*cc[1,3]/315 - 4*A[2,2]*cc[1,4]/315 - 2*A[2,2]*cc[2,2]/315 - 4*A[2,2]*cc[2,3]/315 - 2*A[2,2]*cc[2,4]/315 - 2*A[2,2]*cc[3,3]/105 - 4*A[2,2]*cc[3,4]/315 - 2*A[2,2]*cc[4,4]/315 - 4*A[2,3]*cc[1,3]/315 + 4*A[2,3]*cc[1,4]/315 - 2*A[2,3]*cc[2,3]/315 + 2*A[2,3]*cc[2,4]/315 - 4*A[2,3]*cc[3,3]/315 + 4*A[2,3]*cc[4,4]/315
    M[6,6]=4*A[1,1]*cc[1,1]/315 + 4*A[1,1]*cc[1,2]/315 + 4*A[1,1]*cc[1,3]/105 + 4*A[1,1]*cc[1,4]/315 + 4*A[1,1]*cc[2,2]/315 + 4*A[1,1]*cc[2,3]/105 + 4*A[1,1]*cc[2,4]/315 + 8*A[1,1]*cc[3,3]/105 + 4*A[1,1]*cc[3,4]/105 + 4*A[1,1]*cc[4,4]/315 + 4*A[1,3]*cc[1,1]/105 + 8*A[1,3]*cc[1,2]/315 + 16*A[1,3]*cc[1,3]/315 + 8*A[1,3]*cc[1,4]/315 + 4*A[1,3]*cc[2,2]/315 + 8*A[1,3]*cc[2,3]/315 + 4*A[1,3]*cc[2,4]/315 + 4*A[1,3]*cc[3,3]/105 + 8*A[1,3]*cc[3,4]/315 + 4*A[1,3]*cc[4,4]/315 + 8*A[3,3]*cc[1,1]/105 + 4*A[3,3]*cc[1,2]/105 + 4*A[3,3]*cc[1,3]/105 + 4*A[3,3]*cc[1,4]/105 + 4*A[3,3]*cc[2,2]/315 + 4*A[3,3]*cc[2,3]/315 + 4*A[3,3]*cc[2,4]/315 + 4*A[3,3]*cc[3,3]/315 + 4*A[3,3]*cc[3,4]/315 + 4*A[3,3]*cc[4,4]/315
    M[6,7]=-4*A[1,1]*cc[1,1]/315 - 2*A[1,1]*cc[1,2]/315 - 4*A[1,1]*cc[1,3]/315 + 2*A[1,1]*cc[2,4]/315 + 4*A[1,1]*cc[3,4]/315 + 4*A[1,1]*cc[4,4]/315 - 2*A[1,2]*cc[1,1]/105 - 4*A[1,2]*cc[1,2]/315 - 8*A[1,2]*cc[1,3]/315 - 4*A[1,2]*cc[1,4]/315 - 2*A[1,2]*cc[2,2]/315 - 4*A[1,2]*cc[2,3]/315 - 2*A[1,2]*cc[2,4]/315 - 2*A[1,2]*cc[3,3]/105 - 4*A[1,2]*cc[3,4]/315 - 2*A[1,2]*cc[4,4]/315 - 8*A[1,3]*cc[1,1]/105 - 4*A[1,3]*cc[1,2]/105 - 16*A[1,3]*cc[1,3]/315 - 8*A[1,3]*cc[1,4]/315 - 4*A[1,3]*cc[2,2]/315 - 2*A[1,3]*cc[2,3]/105 - 2*A[1,3]*cc[2,4]/315 - 8*A[1,3]*cc[3,3]/315 - 4*A[1,3]*cc[3,4]/315 - 8*A[2,3]*cc[1,1]/105 - 4*A[2,3]*cc[1,2]/105 - 4*A[2,3]*cc[1,3]/105 - 4*A[2,3]*cc[1,4]/105 - 4*A[2,3]*cc[2,2]/315 - 4*A[2,3]*cc[2,3]/315 - 4*A[2,3]*cc[2,4]/315 - 4*A[2,3]*cc[3,3]/315 - 4*A[2,3]*cc[3,4]/315 - 4*A[2,3]*cc[4,4]/315 - 8*A[3,3]*cc[1,1]/105 - 4*A[3,3]*cc[1,2]/105 - 4*A[3,3]*cc[1,3]/105 - 4*A[3,3]*cc[1,4]/105 - 4*A[3,3]*cc[2,2]/315 - 4*A[3,3]*cc[2,3]/315 - 4*A[3,3]*cc[2,4]/315 - 4*A[3,3]*cc[3,3]/315 - 4*A[3,3]*cc[3,4]/315 - 4*A[3,3]*cc[4,4]/315
    M[6,8]=4*A[1,2]*cc[1,1]/315 + 4*A[1,2]*cc[1,2]/315 + 4*A[1,2]*cc[1,3]/105 + 4*A[1,2]*cc[1,4]/315 + 4*A[1,2]*cc[2,2]/315 + 4*A[1,2]*cc[2,3]/105 + 4*A[1,2]*cc[2,4]/315 + 8*A[1,2]*cc[3,3]/105 + 4*A[1,2]*cc[3,4]/105 + 4*A[1,2]*cc[4,4]/315 + 2*A[1,3]*cc[1,1]/315 + 4*A[1,3]*cc[1,2]/315 + 4*A[1,3]*cc[1,3]/315 + 2*A[1,3]*cc[1,4]/315 + 2*A[1,3]*cc[2,2]/105 + 8*A[1,3]*cc[2,3]/315 + 4*A[1,3]*cc[2,4]/315 + 2*A[1,3]*cc[3,3]/105 + 4*A[1,3]*cc[3,4]/315 + 2*A[1,3]*cc[4,4]/315 + 2*A[2,3]*cc[1,1]/105 + 4*A[2,3]*cc[1,2]/315 + 8*A[2,3]*cc[1,3]/315 + 4*A[2,3]*cc[1,4]/315 + 2*A[2,3]*cc[2,2]/315 + 4*A[2,3]*cc[2,3]/315 + 2*A[2,3]*cc[2,4]/315 + 2*A[2,3]*cc[3,3]/105 + 4*A[2,3]*cc[3,4]/315 + 2*A[2,3]*cc[4,4]/315 + 2*A[3,3]*cc[1,1]/105 + 8*A[3,3]*cc[1,2]/315 + 4*A[3,3]*cc[1,3]/315 + 4*A[3,3]*cc[1,4]/315 + 2*A[3,3]*cc[2,2]/105 + 4*A[3,3]*cc[2,3]/315 + 4*A[3,3]*cc[2,4]/315 + 2*A[3,3]*cc[3,3]/315 + 2*A[3,3]*cc[3,4]/315 + 2*A[3,3]*cc[4,4]/315
    M[6,9]=-2*A[1,1]*cc[1,1]/315 - 4*A[1,1]*cc[1,2]/315 - 4*A[1,1]*cc[1,3]/315 - 2*A[1,1]*cc[1,4]/315 - 2*A[1,1]*cc[2,2]/105 - 8*A[1,1]*cc[2,3]/315 - 4*A[1,1]*cc[2,4]/315 - 2*A[1,1]*cc[3,3]/105 - 4*A[1,1]*cc[3,4]/315 - 2*A[1,1]*cc[4,4]/315 - 2*A[1,2]*cc[1,2]/315 + 2*A[1,2]*cc[1,4]/315 - 4*A[1,2]*cc[2,2]/315 - 4*A[1,2]*cc[2,3]/315 + 4*A[1,2]*cc[3,4]/315 + 4*A[1,2]*cc[4,4]/315 - 8*A[1,3]*cc[1,1]/315 - 4*A[1,3]*cc[1,2]/105 - 8*A[1,3]*cc[1,3]/315 - 2*A[1,3]*cc[1,4]/105 - 4*A[1,3]*cc[2,2]/105 - 4*A[1,3]*cc[2,3]/105 - 8*A[1,3]*cc[2,4]/315 - 8*A[1,3]*cc[3,3]/315 - 2*A[1,3]*cc[3,4]/105 - 4*A[1,3]*cc[4,4]/315 - 4*A[2,3]*cc[1,2]/315 + 4*A[2,3]*cc[1,4]/315 - 4*A[2,3]*cc[2,2]/315 - 2*A[2,3]*cc[2,3]/315 + 2*A[2,3]*cc[3,4]/315 + 4*A[2,3]*cc[4,4]/315 - 2*A[3,3]*cc[1,1]/105 - 8*A[3,3]*cc[1,2]/315 - 4*A[3,3]*cc[1,3]/315 - 4*A[3,3]*cc[1,4]/315 - 2*A[3,3]*cc[2,2]/105 - 4*A[3,3]*cc[2,3]/315 - 4*A[3,3]*cc[2,4]/315 - 2*A[3,3]*cc[3,3]/315 - 2*A[3,3]*cc[3,4]/315 - 2*A[3,3]*cc[4,4]/315
    M[6,10]=-4*A[1,1]*cc[1,1]/315 - 4*A[1,1]*cc[1,2]/315 - 4*A[1,1]*cc[1,3]/105 - 4*A[1,1]*cc[1,4]/315 - 4*A[1,1]*cc[2,2]/315 - 4*A[1,1]*cc[2,3]/105 - 4*A[1,1]*cc[2,4]/315 - 8*A[1,1]*cc[3,3]/105 - 4*A[1,1]*cc[3,4]/105 - 4*A[1,1]*cc[4,4]/315 - 4*A[1,2]*cc[1,1]/315 - 4*A[1,2]*cc[1,2]/315 - 4*A[1,2]*cc[1,3]/105 - 4*A[1,2]*cc[1,4]/315 - 4*A[1,2]*cc[2,2]/315 - 4*A[1,2]*cc[2,3]/105 - 4*A[1,2]*cc[2,4]/315 - 8*A[1,2]*cc[3,3]/105 - 4*A[1,2]*cc[3,4]/105 - 4*A[1,2]*cc[4,4]/315 - 8*A[1,3]*cc[1,1]/315 - 2*A[1,3]*cc[1,2]/105 - 16*A[1,3]*cc[1,3]/315 - 4*A[1,3]*cc[1,4]/315 - 4*A[1,3]*cc[2,2]/315 - 4*A[1,3]*cc[2,3]/105 - 2*A[1,3]*cc[2,4]/315 - 8*A[1,3]*cc[3,3]/105 - 8*A[1,3]*cc[3,4]/315 - 2*A[2,3]*cc[1,1]/105 - 4*A[2,3]*cc[1,2]/315 - 8*A[2,3]*cc[1,3]/315 - 4*A[2,3]*cc[1,4]/315 - 2*A[2,3]*cc[2,2]/315 - 4*A[2,3]*cc[2,3]/315 - 2*A[2,3]*cc[2,4]/315 - 2*A[2,3]*cc[3,3]/105 - 4*A[2,3]*cc[3,4]/315 - 2*A[2,3]*cc[4,4]/315 - 4*A[3,3]*cc[1,3]/315 + 4*A[3,3]*cc[1,4]/315 - 2*A[3,3]*cc[2,3]/315 + 2*A[3,3]*cc[2,4]/315 - 4*A[3,3]*cc[3,3]/315 + 4*A[3,3]*cc[4,4]/315
    M[7,7]=16*A[1,1]*cc[1,1]/315 + 8*A[1,1]*cc[1,2]/315 + 8*A[1,1]*cc[1,3]/315 + 8*A[1,1]*cc[1,4]/315 + 4*A[1,1]*cc[2,2]/315 + 4*A[1,1]*cc[2,3]/315 + 8*A[1,1]*cc[2,4]/315 + 4*A[1,1]*cc[3,3]/315 + 8*A[1,1]*cc[3,4]/315 + 16*A[1,1]*cc[4,4]/315 + 4*A[1,2]*cc[1,1]/35 + 16*A[1,2]*cc[1,2]/315 + 16*A[1,2]*cc[1,3]/315 + 8*A[1,2]*cc[1,4]/315 + 4*A[1,2]*cc[2,2]/315 + 4*A[1,2]*cc[2,3]/315 + 4*A[1,2]*cc[3,3]/315 - 4*A[1,2]*cc[4,4]/315 + 4*A[1,3]*cc[1,1]/35 + 16*A[1,3]*cc[1,2]/315 + 16*A[1,3]*cc[1,3]/315 + 8*A[1,3]*cc[1,4]/315 + 4*A[1,3]*cc[2,2]/315 + 4*A[1,3]*cc[2,3]/315 + 4*A[1,3]*cc[3,3]/315 - 4*A[1,3]*cc[4,4]/315 + 8*A[2,2]*cc[1,1]/105 + 4*A[2,2]*cc[1,2]/105 + 4*A[2,2]*cc[1,3]/105 + 4*A[2,2]*cc[1,4]/105 + 4*A[2,2]*cc[2,2]/315 + 4*A[2,2]*cc[2,3]/315 + 4*A[2,2]*cc[2,4]/315 + 4*A[2,2]*cc[3,3]/315 + 4*A[2,2]*cc[3,4]/315 + 4*A[2,2]*cc[4,4]/315 + 16*A[2,3]*cc[1,1]/105 + 8*A[2,3]*cc[1,2]/105 + 8*A[2,3]*cc[1,3]/105 + 8*A[2,3]*cc[1,4]/105 + 8*A[2,3]*cc[2,2]/315 + 8*A[2,3]*cc[2,3]/315 + 8*A[2,3]*cc[2,4]/315 + 8*A[2,3]*cc[3,3]/315 + 8*A[2,3]*cc[3,4]/315 + 8*A[2,3]*cc[4,4]/315 + 8*A[3,3]*cc[1,1]/105 + 4*A[3,3]*cc[1,2]/105 + 4*A[3,3]*cc[1,3]/105 + 4*A[3,3]*cc[1,4]/105 + 4*A[3,3]*cc[2,2]/315 + 4*A[3,3]*cc[2,3]/315 + 4*A[3,3]*cc[2,4]/315 + 4*A[3,3]*cc[3,3]/315 + 4*A[3,3]*cc[3,4]/315 + 4*A[3,3]*cc[4,4]/315
    M[7,8]=-4*A[1,2]*cc[1,1]/315 - 2*A[1,2]*cc[1,2]/315 - 4*A[1,2]*cc[1,3]/315 + 2*A[1,2]*cc[2,4]/315 + 4*A[1,2]*cc[3,4]/315 + 4*A[1,2]*cc[4,4]/315 - 4*A[1,3]*cc[1,1]/315 - 4*A[1,3]*cc[1,2]/315 - 2*A[1,3]*cc[1,3]/315 + 4*A[1,3]*cc[2,4]/315 + 2*A[1,3]*cc[3,4]/315 + 4*A[1,3]*cc[4,4]/315 - 2*A[2,2]*cc[1,1]/105 - 4*A[2,2]*cc[1,2]/315 - 8*A[2,2]*cc[1,3]/315 - 4*A[2,2]*cc[1,4]/315 - 2*A[2,2]*cc[2,2]/315 - 4*A[2,2]*cc[2,3]/315 - 2*A[2,2]*cc[2,4]/315 - 2*A[2,2]*cc[3,3]/105 - 4*A[2,2]*cc[3,4]/315 - 2*A[2,2]*cc[4,4]/315 - 4*A[2,3]*cc[1,1]/105 - 4*A[2,3]*cc[1,2]/105 - 4*A[2,3]*cc[1,3]/105 - 8*A[2,3]*cc[1,4]/315 - 8*A[2,3]*cc[2,2]/315 - 8*A[2,3]*cc[2,3]/315 - 2*A[2,3]*cc[2,4]/105 - 8*A[2,3]*cc[3,3]/315 - 2*A[2,3]*cc[3,4]/105 - 4*A[2,3]*cc[4,4]/315 - 2*A[3,3]*cc[1,1]/105 - 8*A[3,3]*cc[1,2]/315 - 4*A[3,3]*cc[1,3]/315 - 4*A[3,3]*cc[1,4]/315 - 2*A[3,3]*cc[2,2]/105 - 4*A[3,3]*cc[2,3]/315 - 4*A[3,3]*cc[2,4]/315 - 2*A[3,3]*cc[3,3]/315 - 2*A[3,3]*cc[3,4]/315 - 2*A[3,3]*cc[4,4]/315
    M[7,9]=4*A[1,1]*cc[1,1]/315 + 4*A[1,1]*cc[1,2]/315 + 2*A[1,1]*cc[1,3]/315 - 4*A[1,1]*cc[2,4]/315 - 2*A[1,1]*cc[3,4]/315 - 4*A[1,1]*cc[4,4]/315 + 8*A[1,2]*cc[1,1]/315 + 4*A[1,2]*cc[1,2]/105 + 2*A[1,2]*cc[1,3]/105 + 8*A[1,2]*cc[1,4]/315 + 8*A[1,2]*cc[2,2]/315 + 2*A[1,2]*cc[2,3]/105 + 8*A[1,2]*cc[2,4]/315 + 4*A[1,2]*cc[3,3]/315 + 8*A[1,2]*cc[3,4]/315 + 16*A[1,2]*cc[4,4]/315 + 2*A[1,3]*cc[1,1]/63 + 4*A[1,3]*cc[1,2]/105 + 2*A[1,3]*cc[1,3]/105 + 4*A[1,3]*cc[1,4]/315 + 2*A[1,3]*cc[2,2]/105 + 4*A[1,3]*cc[2,3]/315 + 2*A[1,3]*cc[3,3]/315 - 2*A[1,3]*cc[4,4]/315 + 4*A[2,2]*cc[1,2]/315 - 4*A[2,2]*cc[1,4]/315 + 4*A[2,2]*cc[2,2]/315 + 2*A[2,2]*cc[2,3]/315 - 2*A[2,2]*cc[3,4]/315 - 4*A[2,2]*cc[4,4]/315 + 2*A[2,3]*cc[1,1]/105 + 4*A[2,3]*cc[1,2]/105 + 4*A[2,3]*cc[1,3]/315 + 2*A[2,3]*cc[2,2]/63 + 2*A[2,3]*cc[2,3]/105 + 4*A[2,3]*cc[2,4]/315 + 2*A[2,3]*cc[3,3]/315 - 2*A[2,3]*cc[4,4]/315 + 2*A[3,3]*cc[1,1]/105 + 8*A[3,3]*cc[1,2]/315 + 4*A[3,3]*cc[1,3]/315 + 4*A[3,3]*cc[1,4]/315 + 2*A[3,3]*cc[2,2]/105 + 4*A[3,3]*cc[2,3]/315 + 4*A[3,3]*cc[2,4]/315 + 2*A[3,3]*cc[3,3]/315 + 2*A[3,3]*cc[3,4]/315 + 2*A[3,3]*cc[4,4]/315
    M[7,10]=4*A[1,1]*cc[1,1]/315 + 2*A[1,1]*cc[1,2]/315 + 4*A[1,1]*cc[1,3]/315 - 2*A[1,1]*cc[2,4]/315 - 4*A[1,1]*cc[3,4]/315 - 4*A[1,1]*cc[4,4]/315 + 2*A[1,2]*cc[1,1]/63 + 2*A[1,2]*cc[1,2]/105 + 4*A[1,2]*cc[1,3]/105 + 4*A[1,2]*cc[1,4]/315 + 2*A[1,2]*cc[2,2]/315 + 4*A[1,2]*cc[2,3]/315 + 2*A[1,2]*cc[3,3]/105 - 2*A[1,2]*cc[4,4]/315 + 8*A[1,3]*cc[1,1]/315 + 2*A[1,3]*cc[1,2]/105 + 4*A[1,3]*cc[1,3]/105 + 8*A[1,3]*cc[1,4]/315 + 4*A[1,3]*cc[2,2]/315 + 2*A[1,3]*cc[2,3]/105 + 8*A[1,3]*cc[2,4]/315 + 8*A[1,3]*cc[3,3]/315 + 8*A[1,3]*cc[3,4]/315 + 16*A[1,3]*cc[4,4]/315 + 2*A[2,2]*cc[1,1]/105 + 4*A[2,2]*cc[1,2]/315 + 8*A[2,2]*cc[1,3]/315 + 4*A[2,2]*cc[1,4]/315 + 2*A[2,2]*cc[2,2]/315 + 4*A[2,2]*cc[2,3]/315 + 2*A[2,2]*cc[2,4]/315 + 2*A[2,2]*cc[3,3]/105 + 4*A[2,2]*cc[3,4]/315 + 2*A[2,2]*cc[4,4]/315 + 2*A[2,3]*cc[1,1]/105 + 4*A[2,3]*cc[1,2]/315 + 4*A[2,3]*cc[1,3]/105 + 2*A[2,3]*cc[2,2]/315 + 2*A[2,3]*cc[2,3]/105 + 2*A[2,3]*cc[3,3]/63 + 4*A[2,3]*cc[3,4]/315 - 2*A[2,3]*cc[4,4]/315 + 4*A[3,3]*cc[1,3]/315 - 4*A[3,3]*cc[1,4]/315 + 2*A[3,3]*cc[2,3]/315 - 2*A[3,3]*cc[2,4]/315 + 4*A[3,3]*cc[3,3]/315 - 4*A[3,3]*cc[4,4]/315
    M[8,8]=4*A[2,2]*cc[1,1]/315 + 4*A[2,2]*cc[1,2]/315 + 4*A[2,2]*cc[1,3]/105 + 4*A[2,2]*cc[1,4]/315 + 4*A[2,2]*cc[2,2]/315 + 4*A[2,2]*cc[2,3]/105 + 4*A[2,2]*cc[2,4]/315 + 8*A[2,2]*cc[3,3]/105 + 4*A[2,2]*cc[3,4]/105 + 4*A[2,2]*cc[4,4]/315 + 4*A[2,3]*cc[1,1]/315 + 8*A[2,3]*cc[1,2]/315 + 8*A[2,3]*cc[1,3]/315 + 4*A[2,3]*cc[1,4]/315 + 4*A[2,3]*cc[2,2]/105 + 16*A[2,3]*cc[2,3]/315 + 8*A[2,3]*cc[2,4]/315 + 4*A[2,3]*cc[3,3]/105 + 8*A[2,3]*cc[3,4]/315 + 4*A[2,3]*cc[4,4]/315 + 4*A[3,3]*cc[1,1]/315 + 4*A[3,3]*cc[1,2]/105 + 4*A[3,3]*cc[1,3]/315 + 4*A[3,3]*cc[1,4]/315 + 8*A[3,3]*cc[2,2]/105 + 4*A[3,3]*cc[2,3]/105 + 4*A[3,3]*cc[2,4]/105 + 4*A[3,3]*cc[3,3]/315 + 4*A[3,3]*cc[3,4]/315 + 4*A[3,3]*cc[4,4]/315
    M[8,9]=-2*A[1,2]*cc[1,1]/315 - 4*A[1,2]*cc[1,2]/315 - 4*A[1,2]*cc[1,3]/315 - 2*A[1,2]*cc[1,4]/315 - 2*A[1,2]*cc[2,2]/105 - 8*A[1,2]*cc[2,3]/315 - 4*A[1,2]*cc[2,4]/315 - 2*A[1,2]*cc[3,3]/105 - 4*A[1,2]*cc[3,4]/315 - 2*A[1,2]*cc[4,4]/315 - 4*A[1,3]*cc[1,1]/315 - 4*A[1,3]*cc[1,2]/105 - 4*A[1,3]*cc[1,3]/315 - 4*A[1,3]*cc[1,4]/315 - 8*A[1,3]*cc[2,2]/105 - 4*A[1,3]*cc[2,3]/105 - 4*A[1,3]*cc[2,4]/105 - 4*A[1,3]*cc[3,3]/315 - 4*A[1,3]*cc[3,4]/315 - 4*A[1,3]*cc[4,4]/315 - 2*A[2,2]*cc[1,2]/315 + 2*A[2,2]*cc[1,4]/315 - 4*A[2,2]*cc[2,2]/315 - 4*A[2,2]*cc[2,3]/315 + 4*A[2,2]*cc[3,4]/315 + 4*A[2,2]*cc[4,4]/315 - 4*A[2,3]*cc[1,1]/315 - 4*A[2,3]*cc[1,2]/105 - 2*A[2,3]*cc[1,3]/105 - 2*A[2,3]*cc[1,4]/315 - 8*A[2,3]*cc[2,2]/105 - 16*A[2,3]*cc[2,3]/315 - 8*A[2,3]*cc[2,4]/315 - 8*A[2,3]*cc[3,3]/315 - 4*A[2,3]*cc[3,4]/315 - 4*A[3,3]*cc[1,1]/315 - 4*A[3,3]*cc[1,2]/105 - 4*A[3,3]*cc[1,3]/315 - 4*A[3,3]*cc[1,4]/315 - 8*A[3,3]*cc[2,2]/105 - 4*A[3,3]*cc[2,3]/105 - 4*A[3,3]*cc[2,4]/105 - 4*A[3,3]*cc[3,3]/315 - 4*A[3,3]*cc[3,4]/315 - 4*A[3,3]*cc[4,4]/315
    M[8,10]=-4*A[1,2]*cc[1,1]/315 - 4*A[1,2]*cc[1,2]/315 - 4*A[1,2]*cc[1,3]/105 - 4*A[1,2]*cc[1,4]/315 - 4*A[1,2]*cc[2,2]/315 - 4*A[1,2]*cc[2,3]/105 - 4*A[1,2]*cc[2,4]/315 - 8*A[1,2]*cc[3,3]/105 - 4*A[1,2]*cc[3,4]/105 - 4*A[1,2]*cc[4,4]/315 - 2*A[1,3]*cc[1,1]/315 - 4*A[1,3]*cc[1,2]/315 - 4*A[1,3]*cc[1,3]/315 - 2*A[1,3]*cc[1,4]/315 - 2*A[1,3]*cc[2,2]/105 - 8*A[1,3]*cc[2,3]/315 - 4*A[1,3]*cc[2,4]/315 - 2*A[1,3]*cc[3,3]/105 - 4*A[1,3]*cc[3,4]/315 - 2*A[1,3]*cc[4,4]/315 - 4*A[2,2]*cc[1,1]/315 - 4*A[2,2]*cc[1,2]/315 - 4*A[2,2]*cc[1,3]/105 - 4*A[2,2]*cc[1,4]/315 - 4*A[2,2]*cc[2,2]/315 - 4*A[2,2]*cc[2,3]/105 - 4*A[2,2]*cc[2,4]/315 - 8*A[2,2]*cc[3,3]/105 - 4*A[2,2]*cc[3,4]/105 - 4*A[2,2]*cc[4,4]/315 - 4*A[2,3]*cc[1,1]/315 - 2*A[2,3]*cc[1,2]/105 - 4*A[2,3]*cc[1,3]/105 - 2*A[2,3]*cc[1,4]/315 - 8*A[2,3]*cc[2,2]/315 - 16*A[2,3]*cc[2,3]/315 - 4*A[2,3]*cc[2,4]/315 - 8*A[2,3]*cc[3,3]/105 - 8*A[2,3]*cc[3,4]/315 - 2*A[3,3]*cc[1,3]/315 + 2*A[3,3]*cc[1,4]/315 - 4*A[3,3]*cc[2,3]/315 + 4*A[3,3]*cc[2,4]/315 - 4*A[3,3]*cc[3,3]/315 + 4*A[3,3]*cc[4,4]/315
    M[9,9]=4*A[1,1]*cc[1,1]/315 + 4*A[1,1]*cc[1,2]/105 + 4*A[1,1]*cc[1,3]/315 + 4*A[1,1]*cc[1,4]/315 + 8*A[1,1]*cc[2,2]/105 + 4*A[1,1]*cc[2,3]/105 + 4*A[1,1]*cc[2,4]/105 + 4*A[1,1]*cc[3,3]/315 + 4*A[1,1]*cc[3,4]/315 + 4*A[1,1]*cc[4,4]/315 + 4*A[1,2]*cc[1,1]/315 + 16*A[1,2]*cc[1,2]/315 + 4*A[1,2]*cc[1,3]/315 + 4*A[1,2]*cc[2,2]/35 + 16*A[1,2]*cc[2,3]/315 + 8*A[1,2]*cc[2,4]/315 + 4*A[1,2]*cc[3,3]/315 - 4*A[1,2]*cc[4,4]/315 + 8*A[1,3]*cc[1,1]/315 + 8*A[1,3]*cc[1,2]/105 + 8*A[1,3]*cc[1,3]/315 + 8*A[1,3]*cc[1,4]/315 + 16*A[1,3]*cc[2,2]/105 + 8*A[1,3]*cc[2,3]/105 + 8*A[1,3]*cc[2,4]/105 + 8*A[1,3]*cc[3,3]/315 + 8*A[1,3]*cc[3,4]/315 + 8*A[1,3]*cc[4,4]/315 + 4*A[2,2]*cc[1,1]/315 + 8*A[2,2]*cc[1,2]/315 + 4*A[2,2]*cc[1,3]/315 + 8*A[2,2]*cc[1,4]/315 + 16*A[2,2]*cc[2,2]/315 + 8*A[2,2]*cc[2,3]/315 + 8*A[2,2]*cc[2,4]/315 + 4*A[2,2]*cc[3,3]/315 + 8*A[2,2]*cc[3,4]/315 + 16*A[2,2]*cc[4,4]/315 + 4*A[2,3]*cc[1,1]/315 + 16*A[2,3]*cc[1,2]/315 + 4*A[2,3]*cc[1,3]/315 + 4*A[2,3]*cc[2,2]/35 + 16*A[2,3]*cc[2,3]/315 + 8*A[2,3]*cc[2,4]/315 + 4*A[2,3]*cc[3,3]/315 - 4*A[2,3]*cc[4,4]/315 + 4*A[3,3]*cc[1,1]/315 + 4*A[3,3]*cc[1,2]/105 + 4*A[3,3]*cc[1,3]/315 + 4*A[3,3]*cc[1,4]/315 + 8*A[3,3]*cc[2,2]/105 + 4*A[3,3]*cc[2,3]/105 + 4*A[3,3]*cc[2,4]/105 + 4*A[3,3]*cc[3,3]/315 + 4*A[3,3]*cc[3,4]/315 + 4*A[3,3]*cc[4,4]/315
    M[9,10]=2*A[1,1]*cc[1,1]/315 + 4*A[1,1]*cc[1,2]/315 + 4*A[1,1]*cc[1,3]/315 + 2*A[1,1]*cc[1,4]/315 + 2*A[1,1]*cc[2,2]/105 + 8*A[1,1]*cc[2,3]/315 + 4*A[1,1]*cc[2,4]/315 + 2*A[1,1]*cc[3,3]/105 + 4*A[1,1]*cc[3,4]/315 + 2*A[1,1]*cc[4,4]/315 + 2*A[1,2]*cc[1,1]/315 + 2*A[1,2]*cc[1,2]/105 + 4*A[1,2]*cc[1,3]/315 + 2*A[1,2]*cc[2,2]/63 + 4*A[1,2]*cc[2,3]/105 + 4*A[1,2]*cc[2,4]/315 + 2*A[1,2]*cc[3,3]/105 - 2*A[1,2]*cc[4,4]/315 + 2*A[1,3]*cc[1,1]/315 + 4*A[1,3]*cc[1,2]/315 + 2*A[1,3]*cc[1,3]/105 + 2*A[1,3]*cc[2,2]/105 + 4*A[1,3]*cc[2,3]/105 + 2*A[1,3]*cc[3,3]/63 + 4*A[1,3]*cc[3,4]/315 - 2*A[1,3]*cc[4,4]/315 + 2*A[2,2]*cc[1,2]/315 - 2*A[2,2]*cc[1,4]/315 + 4*A[2,2]*cc[2,2]/315 + 4*A[2,2]*cc[2,3]/315 - 4*A[2,2]*cc[3,4]/315 - 4*A[2,2]*cc[4,4]/315 + 4*A[2,3]*cc[1,1]/315 + 2*A[2,3]*cc[1,2]/105 + 2*A[2,3]*cc[1,3]/105 + 8*A[2,3]*cc[1,4]/315 + 8*A[2,3]*cc[2,2]/315 + 4*A[2,3]*cc[2,3]/105 + 8*A[2,3]*cc[2,4]/315 + 8*A[2,3]*cc[3,3]/315 + 8*A[2,3]*cc[3,4]/315 + 16*A[2,3]*cc[4,4]/315 + 2*A[3,3]*cc[1,3]/315 - 2*A[3,3]*cc[1,4]/315 + 4*A[3,3]*cc[2,3]/315 - 4*A[3,3]*cc[2,4]/315 + 4*A[3,3]*cc[3,3]/315 - 4*A[3,3]*cc[4,4]/315
    M[10,10]=4*A[1,1]*cc[1,1]/315 + 4*A[1,1]*cc[1,2]/315 + 4*A[1,1]*cc[1,3]/105 + 4*A[1,1]*cc[1,4]/315 + 4*A[1,1]*cc[2,2]/315 + 4*A[1,1]*cc[2,3]/105 + 4*A[1,1]*cc[2,4]/315 + 8*A[1,1]*cc[3,3]/105 + 4*A[1,1]*cc[3,4]/105 + 4*A[1,1]*cc[4,4]/315 + 8*A[1,2]*cc[1,1]/315 + 8*A[1,2]*cc[1,2]/315 + 8*A[1,2]*cc[1,3]/105 + 8*A[1,2]*cc[1,4]/315 + 8*A[1,2]*cc[2,2]/315 + 8*A[1,2]*cc[2,3]/105 + 8*A[1,2]*cc[2,4]/315 + 16*A[1,2]*cc[3,3]/105 + 8*A[1,2]*cc[3,4]/105 + 8*A[1,2]*cc[4,4]/315 + 4*A[1,3]*cc[1,1]/315 + 4*A[1,3]*cc[1,2]/315 + 16*A[1,3]*cc[1,3]/315 + 4*A[1,3]*cc[2,2]/315 + 16*A[1,3]*cc[2,3]/315 + 4*A[1,3]*cc[3,3]/35 + 8*A[1,3]*cc[3,4]/315 - 4*A[1,3]*cc[4,4]/315 + 4*A[2,2]*cc[1,1]/315 + 4*A[2,2]*cc[1,2]/315 + 4*A[2,2]*cc[1,3]/105 + 4*A[2,2]*cc[1,4]/315 + 4*A[2,2]*cc[2,2]/315 + 4*A[2,2]*cc[2,3]/105 + 4*A[2,2]*cc[2,4]/315 + 8*A[2,2]*cc[3,3]/105 + 4*A[2,2]*cc[3,4]/105 + 4*A[2,2]*cc[4,4]/315 + 4*A[2,3]*cc[1,1]/315 + 4*A[2,3]*cc[1,2]/315 + 16*A[2,3]*cc[1,3]/315 + 4*A[2,3]*cc[2,2]/315 + 16*A[2,3]*cc[2,3]/315 + 4*A[2,3]*cc[3,3]/35 + 8*A[2,3]*cc[3,4]/315 - 4*A[2,3]*cc[4,4]/315 + 4*A[3,3]*cc[1,1]/315 + 4*A[3,3]*cc[1,2]/315 + 8*A[3,3]*cc[1,3]/315 + 8*A[3,3]*cc[1,4]/315 + 4*A[3,3]*cc[2,2]/315 + 8*A[3,3]*cc[2,3]/315 + 8*A[3,3]*cc[2,4]/315 + 16*A[3,3]*cc[3,3]/315 + 8*A[3,3]*cc[3,4]/315 + 16*A[3,3]*cc[4,4]/315
    M[2,1]=M[1,2]
    M[3,1]=M[1,3]
    M[4,1]=M[1,4]
    M[5,1]=M[1,5]
    M[6,1]=M[1,6]
    M[7,1]=M[1,7]
    M[8,1]=M[1,8]
    M[9,1]=M[1,9]
    M[10,1]=M[1,10]
    M[3,2]=M[2,3]
    M[4,2]=M[2,4]
    M[5,2]=M[2,5]
    M[6,2]=M[2,6]
    M[7,2]=M[2,7]
    M[8,2]=M[2,8]
    M[9,2]=M[2,9]
    M[10,2]=M[2,10]
    M[4,3]=M[3,4]
    M[5,3]=M[3,5]
    M[6,3]=M[3,6]
    M[7,3]=M[3,7]
    M[8,3]=M[3,8]
    M[9,3]=M[3,9]
    M[10,3]=M[3,10]
    M[5,4]=M[4,5]
    M[6,4]=M[4,6]
    M[7,4]=M[4,7]
    M[8,4]=M[4,8]
    M[9,4]=M[4,9]
    M[10,4]=M[4,10]
    M[6,5]=M[5,6]
    M[7,5]=M[5,7]
    M[8,5]=M[5,8]
    M[9,5]=M[5,9]
    M[10,5]=M[5,10]
    M[7,6]=M[6,7]
    M[8,6]=M[6,8]
    M[9,6]=M[6,9]
    M[10,6]=M[6,10]
    M[8,7]=M[7,8]
    M[9,7]=M[7,9]
    M[10,7]=M[7,10]
    M[9,8]=M[8,9]
    M[10,8]=M[8,10]
    M[10,9]=M[9,10]

    return M*abs(J.det)
end

include("./s43nvhnuhcc1.jl")

## source vectors
function s43v1(J::CooTrafo)
        return [1/24 1/24 1/24 1/24].*abs(J.det)
end

function s43v2(J::CooTrafo)
        return [-1/120 -1/120 -1/120 -1/120 1/30 1/30 1/30 1/30 1/30 1/30].*abs(J.det)
end

function s43vh(J::CooTrafo)
        # no recombine necessary because derivative dof map to 0
        return [1/240 1/240 1/240 1/240 0 0 0 0 0 0 0 0 0 0 0 0 3/80 3/80 3/80 3/80].*abs(J.det)
end

function s43nv1rx(J::CooTrafo,n_ref, x_ref)
        M=[1 0 0;
        0 1 0;
        0 0 1;
        -1 -1 -1]
         return M*J.inv*n_ref
end

function s43nv2rx(J::CooTrafo,n_ref, x_ref)
        M=Array{ComplexF64}(undef,10,3)
        x,y,z=J.inv*(x_ref.-J.orig)
        M[1,1]=4*x - 1
        M[1,2]=0
        M[1,3]=0
        M[2,1]=0
        M[2,2]=4*y - 1
        M[2,3]=0
        M[3,1]=0
        M[3,2]=0
        M[3,3]=4*z - 1
        M[4,1]=4*x + 4*y + 4*z - 3
        M[4,2]=4*x + 4*y + 4*z - 3
        M[4,3]=4*x + 4*y + 4*z - 3
        M[5,1]=4*y
        M[5,2]=4*x
        M[5,3]=0
        M[6,1]=4*z
        M[6,2]=0
        M[6,3]=4*x
        M[7,1]=-8*x - 4*y - 4*z + 4
        M[7,2]=-4*x
        M[7,3]=-4*x
        M[8,1]=0
        M[8,2]=4*z
        M[8,3]=4*y
        M[9,1]=-4*y
        M[9,2]=-4*x - 8*y - 4*z + 4
        M[9,3]=-4*y
        M[10,1]=-4*z
        M[10,2]=-4*z
        M[10,3]=-4*x - 4*y - 8*z + 4
        return M*J.inv*n_ref
end

function s43nvhrx(J::CooTrafo, n_ref, x_ref)
        M=Array{ComplexF64}(undef,20,3)
        x,y,z=J.inv*(x_ref.-J.orig)
        M[1,1]=-6*x - 13*y^2 - 33*y*z + 13*y*(2*x + 2*y + 2*z - 2) + 7*y - 13*z^2 + 13*z*(2*x + 2*y + 2*z - 2) + 7*z - 6*(-x - y - z + 1)^2 + 6
        M[1,2]=7*x - 7*y^2 - 7*y*z + 26*y*(-x - y - z + 1) + 13*y*(2*x + 2*y + 2*z - 2) + 14*y + 33*z*(-x - y - z + 1) + 13*z*(2*x + 2*y + 2*z - 2) + 7*z + 7*(-x - y - z + 1)^2 - 7
        M[1,3]=7*x - 7*y*z + 33*y*(-x - y - z + 1) + 13*y*(2*x + 2*y + 2*z - 2) + 7*y - 7*z^2 + 26*z*(-x - y - z + 1) + 13*z*(2*x + 2*y + 2*z - 2) + 14*z + 7*(-x - y - z + 1)^2 - 7
        M[2,1]=-7*x^2 - 7*x*z + 26*x*(-x - y - z + 1) + 13*x*(2*x + 2*y + 2*z - 2) + 14*x + 7*y + 33*z*(-x - y - z + 1) + 13*z*(2*x + 2*y + 2*z - 2) + 7*z + 7*(-x - y - z + 1)^2 - 7
        M[2,2]=-13*x^2 - 33*x*z + 13*x*(2*x + 2*y + 2*z - 2) + 7*x - 6*y - 13*z^2 + 13*z*(2*x + 2*y + 2*z - 2) + 7*z - 6*(-x - y - z + 1)^2 + 6
        M[2,3]=-7*x*z + 33*x*(-x - y - z + 1) + 13*x*(2*x + 2*y + 2*z - 2) + 7*x + 7*y - 7*z^2 + 26*z*(-x - y - z + 1) + 13*z*(2*x + 2*y + 2*z - 2) + 14*z + 7*(-x - y - z + 1)^2 - 7
        M[3,1]=-7*x^2 - 7*x*y + 26*x*(-x - y - z + 1) + 13*x*(2*x + 2*y + 2*z - 2) + 14*x + 33*y*(-x - y - z + 1) + 13*y*(2*x + 2*y + 2*z - 2) + 7*y + 7*z + 7*(-x - y - z + 1)^2 - 7
        M[3,2]=-7*x*y + 33*x*(-x - y - z + 1) + 13*x*(2*x + 2*y + 2*z - 2) + 7*x - 7*y^2 + 26*y*(-x - y - z + 1) + 13*y*(2*x + 2*y + 2*z - 2) + 14*y + 7*z + 7*(-x - y - z + 1)^2 - 7
        M[3,3]=-13*x^2 - 33*x*y + 13*x*(2*x + 2*y + 2*z - 2) + 7*x - 13*y^2 + 13*y*(2*x + 2*y + 2*z - 2) + 7*y - 6*z - 6*(-x - y - z + 1)^2 + 6
        M[4,1]=6*x^2 + 26*x*y + 26*x*z - 6*x + 13*y^2 + 33*y*z - 13*y + 13*z^2 - 13*z
        M[4,2]=13*x^2 + 26*x*y + 33*x*z - 13*x + 6*y^2 + 26*y*z - 6*y + 13*z^2 - 13*z
        M[4,3]=13*x^2 + 33*x*y + 26*x*z - 13*x + 13*y^2 + 26*y*z - 13*y + 6*z^2 - 6*z
        M[5,1]=3*x^2 - 4*x*y - 4*x*z - 2*x - 2*y^2 - 2*y*z + 2*y - 2*z^2 + 2*z
        M[5,2]=-2*x^2 - 4*x*y - 2*x*z + 2*x
        M[5,3]=-2*x^2 - 2*x*y - 4*x*z + 2*x
        M[6,1]=2*x*y + 2*y^2 - y
        M[6,2]=x^2 + 4*x*y - x
        M[6,3]=0
        M[7,1]=2*x*z + 2*z^2 - z
        M[7,2]=0
        M[7,3]=x^2 + 4*x*z - x
        M[8,1]=3*x^2 + 6*x*y + 6*x*z - 4*x + 2*y^2 + 4*y*z - 3*y + 2*z^2 - 3*z + 1
        M[8,2]=3*x^2 + 4*x*y + 4*x*z - 3*x
        M[8,3]=3*x^2 + 4*x*y + 4*x*z - 3*x
        M[9,1]=4*x*y + y^2 - y
        M[9,2]=2*x^2 + 2*x*y - x
        M[9,3]=0
        M[10,1]=-4*x*y - 2*y^2 - 2*y*z + 2*y
        M[10,2]=-2*x^2 - 4*x*y - 2*x*z + 2*x + 3*y^2 - 4*y*z - 2*y - 2*z^2 + 2*z
        M[10,3]=-2*x*y - 2*y^2 - 4*y*z + 2*y
        M[11,1]=0
        M[11,2]=2*y*z + 2*z^2 - z
        M[11,3]=y^2 + 4*y*z - y
        M[12,1]=4*x*y + 3*y^2 + 4*y*z - 3*y
        M[12,2]=2*x^2 + 6*x*y + 4*x*z - 3*x + 3*y^2 + 6*y*z - 4*y + 2*z^2 - 3*z + 1
        M[12,3]=4*x*y + 3*y^2 + 4*y*z - 3*y
        M[13,1]=4*x*z + z^2 - z
        M[13,2]=0
        M[13,3]=2*x^2 + 2*x*z - x
        M[14,1]=0
        M[14,2]=4*y*z + z^2 - z
        M[14,3]=2*y^2 + 2*y*z - y
        M[15,1]=-4*x*z - 2*y*z - 2*z^2 + 2*z
        M[15,2]=-2*x*z - 4*y*z - 2*z^2 + 2*z
        M[15,3]=-2*x^2 - 2*x*y - 4*x*z + 2*x - 2*y^2 - 4*y*z + 2*y + 3*z^2 - 2*z
        M[16,1]=4*x*z + 4*y*z + 3*z^2 - 3*z
        M[16,2]=4*x*z + 4*y*z + 3*z^2 - 3*z
        M[16,3]=2*x^2 + 4*x*y + 6*x*z - 3*x + 2*y^2 + 6*y*z - 3*y + 3*z^2 - 4*z + 1
        M[17,1]=-27*y*z
        M[17,2]=-27*y*z + 27*z*(-x - y - z + 1)
        M[17,3]=-27*y*z + 27*y*(-x - y - z + 1)
        M[18,1]=-27*x*z + 27*z*(-x - y - z + 1)
        M[18,2]=-27*x*z
        M[18,3]=-27*x*z + 27*x*(-x - y - z + 1)
        M[19,1]=-27*x*y + 27*y*(-x - y - z + 1)
        M[19,2]=-27*x*y + 27*x*(-x - y - z + 1)
        M[19,3]=-27*x*y
        M[20,1]=27*y*z
        M[20,2]=27*x*z
        M[20,3]=27*x*y
        for i=1:3
                M[:,i]=recombine_hermite(J,M[:,i])
        end
        return M*J.inv*n_ref
end



function s33v1(J::CooTrafo)
        return [1/6 1/6 1/6]*abs(J.det)
end

function s33v2(J::CooTrafo)
        return [0 0 0 1/6 1/6 1/6]*abs(J.det)
end

function s33vh(J::CooTrafo)
        return  recombine_hermite(J,[11/120  11/120  11/120  -1/60  1/120  1/120  1/120  -1/60  1/120  0 0 0 9/40])*abs(J.det)
end

function s33v1c1(J::CooTrafo,c)
    c1,c2,c4=c
    M=Array{ComplexF64}(undef,3)
    M[1]=c1/12 + c2/24 + c4/24
    M[2]=c1/24 + c2/12 + c4/24
    M[3]=c1/24 + c2/24 + c4/12
    return M*abs(J.det)
end


function s33v2c1(J::CooTrafo,c)
    c1,c2,c4=c
    M=Array{ComplexF64}(undef,6)
    M[1]=c1/60 - c2/120 - c4/120
    M[2]=-c1/120 + c2/60 - c4/120
    M[3]=-c1/120 - c2/120 + c4/60
    M[4]=c1/15 + c2/15 + c4/30
    M[5]=c1/15 + c2/30 + c4/15
    M[6]=c1/30 + c2/15 + c4/15
    return M*abs(J.det)
end

function s33vhc1(J::CooTrafo,c)
    c1,c2,c4=c
    M=Array{ComplexF64}(undef,13)
    M[1]=23*c1/360 + c2/72 + c4/72
    M[2]=c1/72 + 23*c2/360 + c4/72
    M[3]=c1/72 + c2/72 + 23*c4/360
    M[4]=-c1/90 - c2/360 - c4/360
    M[5]=c1/360 + c2/180
    M[6]=c1/360 + c4/180
    M[7]=c1/180 + c2/360
    M[8]=-c1/360 - c2/90 - c4/360
    M[9]=c2/360 + c4/180
    M[10]=0
    M[11]=0
    M[12]=0
    M[13]=3*c1/40 + 3*c2/40 + 3*c4/40
    return recombine_hermite(J,M)*abs(J.det)
end

## shape functions
function f1(J,p)
    x,y,z=J.inv*(p.-J.orig)
    a=1-x-y-z
    vals=[x,y,z,a]
    return vals
end

function f2(J,p)
    x,y,z=J.inv*(p.-J.orig)
    a=1-x-y-z
    vals=[(2*x-1)*x,
    (2*y-1)*y,
    (2*z-1)*z,
    (2*a-1)*a,
    4*x*y,
    4*x*z,
    4*x*a,
    4*y*z,
    4*y*a,
    4*z*a,
    ]
    return vals
end
function fh(J,p)
    x,y,z=J.inv*(p.-J.orig)
    a=1-x-y-z
    #hermite shape functions (third order polynomial)
    fh_vtx(x,y,z)=1-3*x^2-13*x*y-13*x*z-3*y^2-13*y*z-3*z^2+2*x^3+13*x^2*y+13*x^2*z+13*x*y^2+33*x*y*z+13*x*z^2+2*y^3+13*y^2*z+13*y*z^2+2*z^3
    fh_dvtx(x,y,z)=x-2*x^2-3*x*y-3*x*z+x^3+3*x^2*y+3*x^2*z+2*x*y^2+4*x*y*z+2*x*z^2
    fh_dvtxx(x,y,z)=-x^2+2*x*y+2x*z+x^3-2*x^2*y-2*x^2*z-2*x*y^2-2x*y*z-2*x*z^2
    fh_fc(x,y,z)=27*x*y*z
    ##
    vals=[fh_vtx(y,z,a), #fh01
        fh_vtx(x,z,a), #fh02
        fh_vtx(x,y,a), #fh03
        fh_vtx(x,y,z), #fh04
    #partial derivatives (arguement order matters)
    # wrt x
        fh_dvtxx(x,y,z), #fh05
        fh_dvtx(x,a,z), #fh06
        fh_dvtx(x,y,a), #fh07
        fh_dvtx(x,y,z), #fh08
    # wrt y
        fh_dvtx(y,z,a), #fh09
        fh_dvtxx(y,x,z), #fh10
        fh_dvtx(y,x,a), #fh11
        fh_dvtx(y,x,z), #fh12

    #wrt z
        fh_dvtx(z,y,a), #fh13
        fh_dvtx(z,x,a), #fh14
        fh_dvtxx(z,x,y), #fh15
        fh_dvtx(z,x,y), #fh16
    #
        fh_fc(y,z,a), #fh17
        fh_fc(x,z,a), #fh18
        fh_fc(x,y,a), #fh19
        fh_fc(x,y,z), #fh20
    ]
    return recombine_hermite(CT,vals)
end
