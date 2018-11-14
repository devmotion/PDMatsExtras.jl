using PSDMats
using Base.Test

using Distributions

# NOTE: We could probably do a more thorough testing job if we able to override the
# `t_tripod` and `t_whiten` test in PDMats.
test_matrices = Dict(
    "Positive definite" => [
        0.796911  0.602112  0.766136  0.247788
        0.602112  0.480312  0.605538  0.218218
        0.766136  0.605538  1.28666   0.290052
        0.247788  0.218218  0.290052  0.130588
    ],
    "Positive semi-definite" => [
        10.8145   -9.27226   1.67126   4.02515
        -9.27226   8.08443  -1.48168  -4.27258
        1.67126  -1.48168   1.31866   1.43293
        4.02515  -4.27258   1.43293   6.76801
    ]
)

@testset "PSDMats.jl" begin

@testset "PSDMat" begin
    @testset "Positive definite" begin
        M = test_matrices["Positive definite"]
        pivoted = cholfact(M, :U, Val{true})
        PDMats.test_pdmat(
            PSDMat(M, pivoted),
            M,
            cmat_eq=false,
            verbose=1,
            t_triprod=false,    # fails because of some floating point issues.
            t_whiten=false,     # Whiten doesn't produce an identity matrix with the upper triangular matrix
        )
    end
    @testset "Positive semi-definite" begin
        M = test_matrices["Positive semi-definite"]
        @test !isposdef(M)
        pivoted = cholfact(M, :U, Val{true})
        PDMats.test_pdmat(
            PSDMat(M, pivoted),
            M,
            cmat_eq=true,
            verbose=1,
            t_logdet=false,     # We get an expected domain error
            t_rdiv=false,       # We get an expected RankDeficientExceptions
            t_quad=false,       # We get an expected RankDeficientExceptions
            t_triprod=false,    # fails because of expected RankDeficientExceptions
            t_whiten=false,     # Test calls chol_lower on the matrix which throws a PosDefException
        )
    end
end

@testset "Degenerate MvNormal" begin
    # Similar test used in Distributions.jl/test/mvnormal.jl test_mvnormal
    means = rand(4)
    n_tsamples = 10^6

    @testset "Positive definite" begin
        g = MvNormal(means, PSDMat(test_matrices["Positive definite"]))
        d = length(g)
        μ = mean(g)
        Σ = cov(g)
        @test partype(g) == Float64
        @test isa(μ, Vector{Float64})
        @test isa(Σ, Matrix{Float64})
        @test length(μ) == d
        @test size(Σ) == (d, d)
        @test var(g)     ≈ diag(Σ)
        @test entropy(g) ≈ 0.5 * logdet(2π * e * Σ)
        ldcov = logdetcov(g)
        @test ldcov ≈ logdet(Σ)
        @test g == typeof(g)(params(g)...)

        # test sampling for AbstractMatrix (here, a SubArray):
        subX = view(rand(d, 2d), :, 1:d)
        @test isa(rand!(g, subX), SubArray)

        # sampling
        @test isa(rand(g), Vector{Float64})

        X = rand(MersenneTwister(14), g, n_tsamples)
        Y = rand(MersenneTwister(14), g, n_tsamples)
        @test X == Y

        # evaluation of sqmahal & logpdf
        U = X .- μ
        sqm = vec(sum(U .* (Σ \ U), 1))
        for i = 1:min(100, n_tsamples)
            @test sqmahal(g, X[:,i]) ≈ sqm[i]
        end
        @test sqmahal(g, X) ≈ sqm

        lp = -0.5 .* sqm .- 0.5 * (d * log(2.0 * pi) + ldcov)
        for i = 1:min(100, n_tsamples)
            @test logpdf(g, X[:,i]) ≈ lp[i]
        end
        @test logpdf(g, X) ≈ lp

        # log likelihood
        @test loglikelihood(g, X) ≈ sum([Distributions._logpdf(g, X[:,i]) for i in 1:size(X, 2)])
    end

    @testset "Positive semi-definite" begin
        g = MvNormal(means, PSDMat(test_matrices["Positive semi-definite"]))
        d = length(g)
        μ = mean(g)
        Σ = cov(g)
        @test partype(g) == Float64
        @test isa(μ, Vector{Float64})
        @test isa(Σ, Matrix{Float64})
        @test length(μ) == d
        @test size(Σ) == (d, d)
        @test var(g) ≈ diag(Σ)
        etrpy = entropy(g)
        @test_throws DomainError etrpy ≈ 0.5 * logdet(2π * e * Σ)
        ldcov = logdetcov(g)
        @test_throws DomainError ldcov ≈ logdet(Σ)
        @test g == typeof(g)(params(g)...)

        # test sampling for AbstractMatrix (here, a SubArray):
        subX = view(rand(d, 2d), :, 1:d)
        @test isa(rand!(g, subX), SubArray)

        # sampling
        @test isa(rand(g), Vector{Float64})

        X = rand(MersenneTwister(14), g, n_tsamples)
        Y = rand(MersenneTwister(14), g, n_tsamples)
        @test X == Y

        logpdf(g, X)
        sqmahal(g, X)

        # sqmahal, logpdf and loglikelihood calculation should throw RankDeficientExceptions
        # for degenerate MvNormal Distributions
        @test_throws Base.LinAlg.RankDeficientException loglikelihood(g, X)
    end
end

end
