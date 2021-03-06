Algebra = MPO #this is really a vector space (ish)

function element(v :: Array{Complex{Float64}}, A :: Algebra)
    el = deepcopy(A)

    assert(A.χ[0] == length(v))

    v = reshape(v, (1, length(v)))
    W1 = el.W[1]
    W1p = zeros(Complex{Float64}, (el.d,el.d, 1, el.χ[1]))
    @tensor W1p[s,sp, al, ar] = v[al, g]*W1[s,sp,g,ar]
    
    el.W[1] = W1p
    el.χ[0] = 1
    return el
end

function ⊕(A :: Algebra, B:: MPO)
    # almost total overlap with cApdB
    # should be able to re-write
    
    assert(A.L == B.L)
    assert(A.d == B.d)
    L = A.L
    d = A.d 
    
    C = mpo(L,d)
    for j in 1:L
        C.χ[j-1] = A.χ[j-1] + B.χ[j-1]
        C.χ[j]   = A.χ[j]   + B.χ[j]
        
        W = zeros(Complex{Float64},(d,d,C.χ[j-1],C.χ[j],))

        W[:,:,1:A.χ[j-1],1:A.χ[j]] = A.W[j]
        W[:,:,A.χ[j-1]+1:end,A.χ[j] + 1:end] = B.W[j]
        AWj = A.W[j]
        BWj = B.W[j]
        C.W[j] = W
    end
    
    rbc = reshape([1 1],2,1)
    
    WL = C.W[L]
    WLp = zeros(Complex{Float64},(d,d,C.χ[L-1],1))
    @tensor WLp[s,sp,al,ar] = WL[s,sp,al,g]*rbc[g,ar]
    C.W[L] = WLp

    C.χ[0] = 1 + A.χ[0]
    C.χ[L] = 1
    return C
end


# To check:
#
# 1. Take rf heis length 10
# 2. compute spectrum
# 3. compute chebyshev_space (call this function)
# 4. compute spectra
# 5. check that spectra(chebyshev(H)) = chebyshev(spectra(H))
#

function chebyshev_space(H :: MPO, n :: Int, χmax = 0, verbose :: Bool = false)
    assert(n > 2)

    L = H.L
    d = H.d
    
    Trec = [mpoeye(L, d),H]
    T = mpoeye(L,d)⊕H
    
    for j = 1:(n-2)
        @show j
        Tnext = canonical_form(2*H*Trec[end],       preserve_mag = true, χmax = χmax)
        Tnext = canonical_form(Tnext - Trec[end-1], preserve_mag = true, χmax = χmax)
        sanity_check(Tnext)
        T = T⊕Tnext
        T     = canonical_form(T,     preserve_mag = true, χmax = χmax, runtime_check = false)
        Tnext = canonical_form(Tnext, preserve_mag = true, χmax = χmax, runtime_check = false)
        Trec[1] = Trec[2]
        Trec[2] = Tnext
        if verbose
            @show T.χ
            @show Tnext.χ
        end
    end

    return T
end

function trace(A :: Algebra)
    I = eye(A.d)
    C = ones(Complex{Float64},1)
    for j in A.L:-1:1
        Cp = zeros(Complex{Float64}, A.χ[j-1])
        Wj = A.W[j]
        @tensor Cp[al] = I[s,sp] * Wj[s,sp,al,ar] * C[ar]
        C = Cp
    end
    return C
end

function chebyshev_space(H :: MPO, n :: Int, χmax = 0, verbose :: Bool = false)
    assert(n > 2)

    L = H.L
    d = H.d
    
    Trec = [mpoeye(L, d),H]
    T = mpoeye(L,d)⊕H
    
    for j = 1:(n-2)
        @show j
        Tnext = canonical_form(2*H*Trec[end],       preserve_mag = true, χmax = χmax)
        Tnext = canonical_form(Tnext - Trec[end-1], preserve_mag = true, χmax = χmax)
        sanity_check(Tnext)
        T = T⊕Tnext
        T     = canonical_form(T,     preserve_mag = true, χmax = χmax, runtime_check = false)
        Tnext = canonical_form(Tnext, preserve_mag = true, χmax = χmax, runtime_check = false)
        Trec[1] = Trec[2]
        Trec[2] = Tnext
        if verbose
            @show T.χ
            @show Tnext.χ
        end
    end

    return T
end

#will add "operator" as an argument: trace against this operator (list of operators?)
function chebyshev_traces(H :: MPO, n :: Int; prog_per = 0, χmax = 0, verbose :: Bool = false)
    assert(n > 2)

    L = H.L
    d = H.d
    
    Trec = [mpoeye(L, d),H]
    
    traces = zeros(Complex{Float64}, n)
    traces[1] = mpoeye(L,d) |> trace |> ssqueeze
    traces[2] = H |> trace |> ssqueeze

    if prog_per != 0
        tic()
    end
    for j = 1:(n-2)
        Tnext = canonical_form(2*H*Trec[end],       preserve_mag = true, χmax = χmax)
        Tnext = canonical_form(Tnext - Trec[end-1], preserve_mag = true, χmax = χmax)
        sanity_check(Tnext)
        trace(Tnext)
        traces[j+2] = Tnext |> trace |> ssqueeze
        Trec[1] = Trec[2]
        Trec[2] = Tnext
        if prog_per != 0 && j % prog_per == 0
            @show j, toq()
            tic()
        end
        if verbose
            @show T.χ
            @show Tnext.χ
        end
    end

    return traces
end
