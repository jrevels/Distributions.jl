doc"""
    Normal(μ,σ)

The *Normal distribution* with mean `μ` and standard deviation `σ` has probability density function

$f(x; \mu, \sigma) = \frac{1}{\sqrt{2 \pi \sigma^2}}
\exp \left( - \frac{(x - \mu)^2}{2 \sigma^2} \right)$

```julia
Normal()          # standard Normal distribution with zero mean and unit variance
Normal(mu)        # Normal distribution with mean mu and unit variance
Normal(mu, sig)   # Normal distribution with mean mu and variance sig^2

params(d)         # Get the parameters, i.e. (mu, sig)
mean(d)           # Get the mean, i.e. mu
std(d)            # Get the standard deviation, i.e. sig
```

External links

* [Normal distribution on Wikipedia](http://en.wikipedia.org/wiki/Normal_distribution)

"""
immutable Normal{T<:Real} <: ContinuousUnivariateDistribution
    μ::T
    σ::T

    (::Type{Normal{T}}){T}(μ, σ) = (@check_args(Normal, σ > zero(σ)); new{T}(μ, σ))
end

#### Outer constructors
Normal{T<:Real}(μ::T, σ::T) = Normal{T}(μ, σ)
Normal(μ::Real, σ::Real) = Normal(promote(μ, σ)...)
Normal(μ::Integer, σ::Integer) = Normal(Float64(μ), Float64(σ))
Normal(μ::Real) = Normal(μ, 1.0)
Normal() = Normal(0.0, 1.0)

const Gaussian = Normal

# #### Conversions
convert{T <: Real, S <: Real}(::Type{Normal{T}}, μ::S, σ::S) = Normal(T(μ), T(σ))
convert{T <: Real, S <: Real}(::Type{Normal{T}}, d::Normal{S}) = Normal(T(d.μ), T(d.σ))

@distr_support Normal -Inf Inf


#### Parameters

params(d::Normal) = (d.μ, d.σ)
@inline partype{T<:Real}(d::Normal{T}) = T

location(d::Normal) = d.μ
scale(d::Normal) = d.σ

#### Statistics

mean(d::Normal) = d.μ
median(d::Normal) = d.μ
mode(d::Normal) = d.μ

var(d::Normal) = abs2(d.σ)
std(d::Normal) = d.σ
skewness{T<:Real}(d::Normal{T}) = zero(T)
kurtosis{T<:Real}(d::Normal{T}) = zero(T)

entropy(d::Normal) = (log2π + 1)/2 + log(d.σ)


#### Evaluation

@_delegate_statsfuns Normal norm μ σ

gradlogpdf(d::Normal, x::Real) = (d.μ - x) / d.σ^2

mgf(d::Normal, t::Real) = exp(t * d.μ + d.σ^2/2 * t^2)
cf(d::Normal, t::Real) = exp(im * t * d.μ - d.σ^2/2 * t^2)


#### Sampling

rand(d::Normal) = d.μ + d.σ * randn()


#### Fitting

immutable NormalStats <: SufficientStats
    s::Float64    # (weighted) sum of x
    m::Float64    # (weighted) mean of x
    s2::Float64   # (weighted) sum of (x - μ)^2
    tw::Float64    # total sample weight
end

function suffstats{T<:Real}(::Type{Normal}, x::AbstractArray{T})
    n = length(x)

    # compute s
    s = x[1]
    for i = 2:n
        @inbounds s += x[i]
    end
    m = s / n

    # compute s2
    s2 = abs2(x[1] - m)
    for i = 2:n
        @inbounds s2 += abs2(x[i] - m)
    end

    NormalStats(s, m, s2, n)
end

function suffstats{T<:Real}(::Type{Normal}, x::AbstractArray{T}, w::AbstractArray{Float64})
    n = length(x)

    # compute s
    tw = w[1]
    s = w[1] * x[1]
    for i = 2:n
        @inbounds wi = w[i]
        @inbounds s += wi * x[i]
        tw += wi
    end
    m = s / tw

    # compute s2
    s2 = w[1] * abs2(x[1] - m)
    for i = 2:n
        @inbounds s2 += w[i] * abs2(x[i] - m)
    end

    NormalStats(s, m, s2, tw)
end

# Cases where μ or σ is known

immutable NormalKnownMu <: IncompleteDistribution
    μ::Float64
end

immutable NormalKnownMuStats <: SufficientStats
    μ::Float64      # known mean
    s2::Float64     # (weighted) sum of (x - μ)^2
    tw::Float64     # total sample weight
end

function suffstats{T<:Real}(g::NormalKnownMu, x::AbstractArray{T})
    μ = g.μ
    s2 = abs2(x[1] - μ)
    for i = 2:length(x)
        @inbounds s2 += abs2(x[i] - μ)
    end
    NormalKnownMuStats(g.μ, s2, length(x))
end

function suffstats{T<:Real}(g::NormalKnownMu, x::AbstractArray{T}, w::AbstractArray{Float64})
    μ = g.μ
    s2 = abs2(x[1] - μ) * w[1]
    tw = w[1]
    for i = 2:length(x)
        @inbounds wi = w[i]
        @inbounds s2 += abs2(x[i] - μ) * wi
        tw += wi
    end
    NormalKnownMuStats(g.μ, s2, tw)
end


immutable NormalKnownSigma <: IncompleteDistribution
    σ::Float64

    function NormalKnownSigma(σ::Float64)
        σ > 0 || throw(ArgumentError("σ must be a positive value."))
        new(σ)
    end
end

immutable NormalKnownSigmaStats <: SufficientStats
    σ::Float64      # known std.dev
    sx::Float64      # (weighted) sum of x
    tw::Float64     # total sample weight
end

function suffstats{T<:Real}(g::NormalKnownSigma, x::AbstractArray{T})
    NormalKnownSigmaStats(g.σ, sum(x), Float64(length(x)))
end

function suffstats{T<:Real}(g::NormalKnownSigma, x::AbstractArray{T}, w::AbstractArray{T})
    NormalKnownSigmaStats(g.σ, dot(x, w), sum(w))
end

# fit_mle based on sufficient statistics

fit_mle(::Type{Normal}, ss::NormalStats) = Normal(ss.m, sqrt(ss.s2 / ss.tw))
fit_mle(g::NormalKnownMu, ss::NormalKnownMuStats) = Normal(g.μ, sqrt(ss.s2 / ss.tw))
fit_mle(g::NormalKnownSigma, ss::NormalKnownSigmaStats) = Normal(ss.sx / ss.tw, g.σ)

# generic fit_mle methods

function fit_mle{T<:Real}(::Type{Normal}, x::AbstractArray{T}; mu::Float64=NaN, sigma::Float64=NaN)
    if isnan(mu)
        if isnan(sigma)
            fit_mle(Normal, suffstats(Normal, x))
        else
            g = NormalKnownSigma(sigma)
            fit_mle(g, suffstats(g, x))
        end
    else
        if isnan(sigma)
            g = NormalKnownMu(mu)
            fit_mle(g, suffstats(g, x))
        else
            Normal(mu, sigma)
        end
    end
end

function fit_mle{T<:Real}(::Type{Normal}, x::AbstractArray{T}, w::AbstractArray{Float64}; mu::Float64=NaN, sigma::Float64=NaN)
    if isnan(mu)
        if isnan(sigma)
            fit_mle(Normal, suffstats(Normal, x, w))
        else
            g = NormalKnownSigma(sigma)
            fit_mle(g, suffstats(g, x, w))
        end
    else
        if isnan(sigma)
            g = NormalKnownMu(mu)
            fit_mle(g, suffstats(g, x, w))
        else
            Normal(mu, sigma)
        end
    end
end
