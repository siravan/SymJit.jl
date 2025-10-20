_sin(x::Float64)::Float64 = sin(x)
_cos(x::Float64)::Float64 = cos(x)
_tan(x::Float64)::Float64 = tan(x)
_csc(x::Float64)::Float64 = csc(x)
_sec(x::Float64)::Float64 = sec(x)
_cot(x::Float64)::Float64 = cot(x)

_asin(x::Float64)::Float64 = asin(x)
_acos(x::Float64)::Float64 = acos(x)
_atan(x::Float64)::Float64 = atan(x)
_acsc(x::Float64)::Float64 = acsc(x)
_asec(x::Float64)::Float64 = asec(x)
_acot(x::Float64)::Float64 = acot(x)

_sinh(x::Float64)::Float64 = sinh(x)
_cosh(x::Float64)::Float64 = cosh(x)
_tanh(x::Float64)::Float64 = tanh(x)
_csch(x::Float64)::Float64 = csch(x)
_sech(x::Float64)::Float64 = sech(x)
_coth(x::Float64)::Float64 = coth(x)

_asinh(x::Float64)::Float64 = asinh(x)
_acosh(x::Float64)::Float64 = acosh(x)
_atanh(x::Float64)::Float64 = atanh(x)
_acsch(x::Float64)::Float64 = acsch(x)
_asech(x::Float64)::Float64 = asech(x)
_acoth(x::Float64)::Float64 = acoth(x)

_log(x::Float64)::Float64 = log(x)
_log2(x::Float64)::Float64 = log2(x)
_log10(x::Float64)::Float64 = log10(x)

_exp(x::Float64)::Float64 = exp(x)
_exp2(x::Float64)::Float64 = exp2(x)
_exp10(x::Float64)::Float64 = exp10(x)

_sqrt(x::Float64)::Float64 = sqrt(x)
_cbrt(x::Float64)::Float64 = cbrt(x)

_power(x::Float64, y::Float64)::Float64 = x ^ y

func_ptr = Dict{Symbol, Any}(
    :sin => @cfunction(_sin, Cdouble, (Cdouble,)),
    :cos => @cfunction(_cos, Cdouble, (Cdouble,)),
    :tan => @cfunction(_tan, Cdouble, (Cdouble,)),
    :csc => @cfunction(_csc, Cdouble, (Cdouble,)),
    :sec => @cfunction(_sec, Cdouble, (Cdouble,)),
    :cot => @cfunction(_cot, Cdouble, (Cdouble,)),

    :asin => @cfunction(_asin, Cdouble, (Cdouble,)),
    :acos => @cfunction(_acos, Cdouble, (Cdouble,)),
    :atan => @cfunction(_atan, Cdouble, (Cdouble,)),
    :acsc => @cfunction(_acsc, Cdouble, (Cdouble,)),
    :asec => @cfunction(_asec, Cdouble, (Cdouble,)),
    :acot => @cfunction(_acot, Cdouble, (Cdouble,)),

    :sinh => @cfunction(_sinh, Cdouble, (Cdouble,)),
    :cosh => @cfunction(_cosh, Cdouble, (Cdouble,)),
    :tanh => @cfunction(_tanh, Cdouble, (Cdouble,)),
    :csch => @cfunction(_csch, Cdouble, (Cdouble,)),
    :sech => @cfunction(_sech, Cdouble, (Cdouble,)),
    :coth => @cfunction(_coth, Cdouble, (Cdouble,)),

    :asinh => @cfunction(_asinh, Cdouble, (Cdouble,)),
    :acosh => @cfunction(_acosh, Cdouble, (Cdouble,)),
    :atanh => @cfunction(_atanh, Cdouble, (Cdouble,)),
    :acsch => @cfunction(_acsch, Cdouble, (Cdouble,)),
    :asech => @cfunction(_asech, Cdouble, (Cdouble,)),
    :acoth => @cfunction(_acoth, Cdouble, (Cdouble,)),

    :log => @cfunction(_log, Cdouble, (Cdouble,)),
    :log2 => @cfunction(_log2, Cdouble, (Cdouble,)),
    :log10 => @cfunction(_log10, Cdouble, (Cdouble,)),

    :exp => @cfunction(_exp, Cdouble, (Cdouble,)),
    :exp2 => @cfunction(_exp2, Cdouble, (Cdouble,)),
    :exp10 => @cfunction(_exp10, Cdouble, (Cdouble,)),

    :sqrt => @cfunction(_sqrt, Cdouble, (Cdouble,)),
    :cbrt => @cfunction(_cbrt, Cdouble, (Cdouble,)),

    :power => @cfunction(_power, Cdouble, (Cdouble, Cdouble)),
)
