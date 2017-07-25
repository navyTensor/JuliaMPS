import Base.dot
import Base.conj

type MPS
    W :: Array{Array{Complex{Float64},3}, 1}
    χ :: OffsetArrays.OffsetArray{Int64,1,Array{Int64,1}}
    d :: Int
    L :: Int
    s :: Array{Array{Float64,1},1}
end

function mps(Ws :: Array{Array{Complex{Float64},3}, 1})
    L = length(Ws)
    χ = OffsetArray(zeros(Int64, L+1), 0:L)
    χ[0]   = 1
    χ[1:L] = [size(W,3) for W in Ws]
    d = size(Ws[1], 1)
    for W = Ws
        assert(size(W,1) == d)
    end
    s = Array(Array{Float64,1}, L)
    return MPS(Ws,χ,d,L,s)
end

function conj(ψ :: MPS)
    ψ = deepcopy(ψ)
    for j = 1:ψ.L
        W[j] = conj(W[j])
    end
    return ψ
end


function dot(φ :: MPS, ψ :: MPS)
    C = zeros(Complex{Float64},(ψ.χ[1], φ.χ[1]))
    ψW1 = squeeze(ψ.W[1],2)
    φW1 = squeeze(ψ.W[1],2)
    @tensor C[a,ap] = ( ψW1[s,a]
                      * φW1[s,ap])
    for j in 2:L
        D = zeros(Complex{Float64}, (ψ.χ[j], φ.χ[j]))
        
        ψWj = ψ.W[j]
        φWjc = conj(φ.W[j])
        @tensor D[ar,arp] = (C[al,alp] * ψWj[ s,al ,ar]
                                       * φWjc[s,alp,arp])
        C = D
    end
    return squeeze(C)
end

function site_expectation_value{T}(A :: Array{T,2}, ψ :: MPS, j :: Int)
     ψ  = copy(ψ)
     ψc = conj(ψ)
     Z = dot(ψc, ψ)
     @tensor ψ.W[j][s, al, ar] = A[s,sp] * ψ[sp, al,ar]
     return dot(ψp, ψ)/Z
end

function canonical_form!(A :: MPS; preserve_mag :: Bool = false,  χmax :: Int = 0, runtime_check = false)
    L = A.L
    χ = A.χ
    d = A.d
    
    f = 1.0
    for j in 1:L-1
        if χmax == 0 && runtime_check
            twosite = zeros(d,d,χ[j-1],χ[j+1])
            Wj = A.W[j]
            Wjp1 = A.W[j+1]
            @tensor twosite[sj, sjp1, al, ar] = Wj[sj, al, g] * Wjp1[sjp1, g, ar]
        end

                                                                   
        W = reshape(A.W[j], (d*χ[j-1], χ[j]))

        U, s, V = svd(W, thin=true)
        V = V'
        snorm = sqrt(sum(s.^2))
        s = s/snorm
        f *= snorm
        
        keep = s .> maximum(s)*1e-15

        s = s[keep]
        χ[j] = size(s)[1]
        
        U = reshape(U[:,keep],(d,χ[j-1],χ[j]))
        V = diagm(s)*V[keep,:]
        A.W[j] = U
        Wjp1 = A.W[j+1]
        Wjp1p = zeros(Complex{Float64},(d, χ[j], χ[j+1]))
        @tensor Wjp1p[s,al,ar] = V[al,g]*Wjp1[s,g,ar]
        A.W[j+1] = Wjp1p

        if χmax == 0 && runtime_check
            twosite_after = zeros(d,d,χ[j-1],χ[j+1])
            Wj = A.W[j]
            Wjp1 = A.W[j+1]
            @tensor twosite_after[sj, sjp1, al, ar] = Wj[sj, al, g] * Wjp1[sjp1, g, ar]
            assert(maximum(abs(twosite_after*snorm - twosite)) < 1e-10)
        end
    end

    for j in L:-1:2
        if χmax == 0 && runtime_check
            twosite = zeros(Complex{Float64}, d,d,χ[j-2],χ[j])
            Wj = A.W[j]
            Wjm1 = A.W[j-1]
            @tensor twosite[sj, sjp1, al, ar] = Wjm1[sj, al, g] * Wj[sjp1, g, ar]
        end
        W = permutedims(A.W[j], [2,1,3])
        W = reshape(W, (χ[j-1], d*χ[j]))
        U,s,V = svd(W,thin=true)
        V = V'

        if runtime_check
            assert(maximum(abs(U*diagm(s)*V - W)) < 1e-10)
        end
        
        if χmax == 0 && runtime_check
            tempV = reshape(V, (χ[j-1], d, χ[j]))
            tempU = U*diagm(s)
            Wj_mid = zeros(Complex{Float64}, d, χ[j-1], χ[j])
            @tensor Wj_mid[sj, al, ar] = tempU[al,gp]*tempV[gp,sj,ar]
            assert(maximum(abs(Wj_mid - A.W[j])) < 1e-10)
            
            twosite_mid = zeros(Complex{Float64}, d,d,χ[j-2],χ[j])
            Wjm1 = A.W[j-1]
            @tensor twosite_mid[sj, sjp1, al, ar] = Wjm1[sj, al, g] * tempU[g,gp]*tempV[gp,sjp1,ar]
            assert(maximum(abs(twosite_mid - twosite)) < 1e-10)
        end
        
        snorm = sqrt(sum(s.^2))
        s = s/snorm
        f *=snorm
        keep = s .> maximum(s)*1e-14
        if χmax > 0
            keep[χmax + 1:end] = false
        end
        s = s[keep]
        A.s[j-1] = s
        χ[j-1] = size(s,1)       
        
        # B-form
        # here is where I would do ν
        U = U[:,keep]
        U = U*diagm(s)
        V = V[keep,:]
        V = reshape(V, (χ[j-1], d, χ[j]))
        V = permutedims(V, [2,1,3])
        A.W[j] = V
        
        Wjm1 = A.W[j-1]
        Wjm1p = zeros(Complex{Float64}, (d,χ[j-2], χ[j-1]))
        @tensor Wjm1p[s,al,ar] = Wjm1[s,al,g]*U[g,ar]
        A.W[j-1] = Wjm1p
        
        if χmax == 0 && runtime_check
            twosite_after = zeros(Complex{Float64}, d,d,χ[j-2],χ[j])
            Wj = A.W[j]
            Wjm1 = A.W[j-1]
            @tensor twosite_after[sj, sjp1, al, ar] = Wjm1[sj, al, g] * Wj[sjp1, g, ar]
            assert(maximum(abs(twosite_after*snorm - twosite)) < 1e-10)
        end
    end
    
    A.χ = χ
    if preserve_mag
        for j in 1:L
            A.W[j] = A.W[j]*f^(1/L)
        end
    end
    return A
end
