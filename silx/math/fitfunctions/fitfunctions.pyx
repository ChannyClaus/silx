# coding: utf-8
#/*##########################################################################
# Copyright (C) 2016 European Synchrotron Radiation Facility
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
#############################################################################*/
"""This module provides multi-peak fit functions, background extraction
functions, smoothing functions and peak search functions.

Index of fit functions:
-----------------------

    - :func:`sum_gauss`
    - :func:`sum_agauss`
    - :func:`sum_splitgauss`
    - :func:`sum_fastagauss`

    - :func:`sum_apvoigt`
    - :func:`sum_pvoigt`
    - :func:`sum_splitpvoigt`

    - :func:`sum_lorentz`
    - :func:`sum_alorentz`
    - :func:`sum_splitlorentz`

    - :func:`sum_downstep`
    - :func:`sum_upstep`
    - :func:`sum_slit`

    - :func:`sum_ahypermet`
    - :func:`sum_fastahypermet`

Index of background extraction functions:
------------------------------------------

    - :func:`strip`
    - :func:`snip1d`
    - :func:`snip2d`
    - :func:`snip3d`

Smoothing function:
-------------------

    - :func:`savitsky_golay`

Peak search function:
---------------------

    - :func:`peak_search`

Full documentation:
-------------------

"""

__authors__ = ["P. Knobel"]
__license__ = "MIT"
__date__ = "17/06/2016"

import logging
import numpy

logging.basicConfig()
_logger = logging.getLogger(__name__)

cimport cython

# Rename C functions to reuse the same names for their python wrappers
from fitfunctions cimport erf_array as _erf
from fitfunctions cimport erfc_array as _erfc
from fitfunctions cimport snip1d as _snip1d
from fitfunctions cimport snip2d as _snip2d
from fitfunctions cimport snip3d as _snip3d
from fitfunctions cimport sum_gauss as _sum_gauss
from fitfunctions cimport sum_agauss as _sum_agauss
from fitfunctions cimport sum_fastagauss as _sum_fastagauss
from fitfunctions cimport sum_splitgauss as _sum_splitgauss
from fitfunctions cimport sum_apvoigt as _sum_apvoigt
from fitfunctions cimport sum_pvoigt as _sum_pvoigt
from fitfunctions cimport sum_splitpvoigt as _sum_splitpvoigt
from fitfunctions cimport sum_lorentz as _sum_lorentz
from fitfunctions cimport sum_alorentz as _sum_alorentz
from fitfunctions cimport sum_splitlorentz as _sum_splitlorentz
from fitfunctions cimport sum_downstep as _sum_downstep
from fitfunctions cimport sum_upstep as _sum_upstep
from fitfunctions cimport sum_slit as _sum_slit
from fitfunctions cimport sum_ahypermet as _sum_ahypermet
from fitfunctions cimport sum_fastahypermet as _sum_fastahypermet
from fitfunctions cimport seek
from fitfunctions cimport strip as _strip
from fitfunctions cimport snip1d as _snip1d
from fitfunctions cimport snip2d as _snip2d
from fitfunctions cimport snip3d as _snip3d


def erf(x):
    """erf(x) -> numpy.ndarray
    Return the gaussian error function

    :param x: Independant variable where the gaussian error function is
        calculated
    :return: Gaussian error function ``y=erf(x)``
    """
    cdef:
        double[::1] x_c
        double[::1] y_c

    x_c = numpy.array(x, copy=False, dtype=numpy.float64, order='C').reshape(-1)
    y_c = numpy.empty(shape=(x_c.size,), dtype=numpy.float64)

    status = _erf(&x_c[0], x_c.size, &y_c[0])

    return numpy.asarray(y_c).reshape(x.shape)


def erfc(x):
    """erfc(x) -> numpy.ndarray
    Return the gaussian complementary error function

    :param x: Independant variable where the gaussian complementary error
        function is calculated
    :type x: numpy.ndarray
    :return: Gaussian complementary error function ``y=erfc(x)``
    :type rtype: numpy.ndarray
    """
    cdef:
        double[::1] x_c
        double[::1] y_c

    x_c = numpy.array(x, copy=False, dtype=numpy.float64, order='C').reshape(-1)
    y_c = numpy.empty(shape=(x_c.size,), dtype=numpy.float64)

    status = _erfc(&x_c[0], x_c.size, &y_c[0])

    return numpy.asarray(y_c).reshape(x.shape)


def strip(data, w, niterations, factor=1.0, anchors=None):
    """Extract background from data using the strip algorithm, as explained at
    http://pymca.sourceforge.net/stripbackground.html.

    In its simplest implementation it is just as an iterative procedure
    depending on two parameters. These parameters are the strip background
    width `` w``, and the number of iterations. At each iteration, if the
    contents of channel ``i``, ``y(i)``, is above the average of the contents
    of the channels at `` w`` channels of distance, ``y(i-w)`` and
    ``y(i+w)``,  ``y(i)`` is replaced by the average.
    At the end of the process we are left with something that resembles a spectrum
    in which the peaks have been stripped.

    :param data: Data array
    :type data: numpy.ndarray
    :param w: Strip width
    :param niterations: number of iterations
    :param factor: scaling factor applied to the average of ``y(i-w)`` and
        ``y(i+w)`` before comparing to ``y(i)``
    :param anchors: Array of anchors, indices of points that will not be
          modified during the stripping procedure.
    :return: Data with peaks stripped away
    """
    cdef:
        double[::1] input_c
        double[::1] output
        long[::1] anchors_c

    if not isinstance(data, numpy.ndarray):
        if not hasattr(data, "__len__"):
            raise TypeError("data must be a sequence (list, tuple) " +
                            "or a numpy array")
        data_shape = (len(data), )
    else:
        data_shape = data.shape

    input_c = numpy.array(data,
                          copy=True,
                          dtype=numpy.float64,
                          order='C').reshape(-1)

    output = numpy.empty(shape=(input_c.size,),
                         dtype=numpy.float64)

    if anchors is not None:
        # numpy.int_ is the same as C long (http://docs.scipy.org/doc/numpy/user/basics.types.html)
        anchors_c = numpy.array(anchors,
                                copy=False,
                                dtype=numpy.int_,
                                order='C')
        len_anchors = anchors_c.size
    else:
        # Make a dummy lenght-1 array, because if I use shape=(0,) I get the error
        # IndexError: Out of bounds on buffer access (axis 0)
        anchors_c = numpy.empty(shape=(1,),
                                dtype=numpy.int_)
        len_anchors = 0


    status = _strip(&input_c[0], input_c.size, factor, niterations, w,
                    &anchors_c[0], len_anchors, &output[0])

    return numpy.asarray(output).reshape(data_shape)


def snip1d(data, int width):
    """snip1d(data, width) -> numpy.ndarray
    Estimate the baseline (background) of a 1D data vector by clipping peaks.

    The implementation of the algorithm SNIP in 1D is described in *Miroslav
    Morhac et al. Nucl. Instruments and Methods in Physics Research A401
    (1997) 113-132*.

    The original idea for 1D and the low-statistics-digital-filter (lsdf) come
    from *C.G. Ryan et al. Nucl. Instruments and Methods in Physics Research
    B34 (1988) 396-402*.

    :param data: Data array, preferably 1D and of type *numpy.float64*.
        Else, the data array will be flattened and converted to
        *dtype=numpy.float64* prior to applying the snip filter.
    :type data: numpy.ndarray
    :param width: Width of the snip operator, in number of samples. A wider
        snip operator will result in a smoother result (lower frequency peaks
        will be clipped), and a longer computation time.
    :type width: int
    :return: Baseline of the input array, as an array of the same shape.
    :rtype: numpy.ndarray
    """
    cdef double[::1] data_c

    # Ensure we are dealing with a 1D array in contiguous memory
    data_c = numpy.array(data, copy=True, dtype=numpy.float64, order='C').reshape(-1)

    _snip1d(&data_c[0], data.size, width)

    return numpy.asarray(data_c).reshape(data.shape)


def snip2d(data, int width, nrows=None, ncolumns=None):
    """snip2d(data, width, nrows=None, ncolumns=None) -> numpy.ndarray
    Estimate the baseline (background) of a 2D data signal by clipping peaks.

    Implementation of the algorithm SNIP in 2D described in
    *Miroslav Morhac et al. Nucl. Instruments and Methods in Physics Research
    A401 (1997) 113-132.*

    :param data: Data array, preferably 1D and of type *numpy.float64*.
        Else, the data array will be flattened and converted to
        *dtype=numpy.float64* prior to applying the snip filter.
        If the data is a 2D array, ``nrows`` and ``ncolumns`` don't
        need to be specified.
    :type data: numpy.ndarray
    :param width: Width of the snip operator, in number of samples. A wider
        snip operator will result in a smoother result (lower frequency peaks
        will be clipped), and a longer computation time.
    :type width: int
    :param nrows: Number of rows (second dimension) in array.
        If ``None``, it will be inferred from the shape of the data if it
        is a 2D array.
    :type nrows: int or None
    :param ncolumns: Number of columns (first dimension) in array
        If ``None``, it will be inferred from the shape of the data if it
        is a 2D array.
    :type ncolumns: int or None
    :return: Baseline of the input array, as an array of the same shape.
    :rtype: numpy.ndarray
    """
    cdef double[::1] data_c


    if nrows is None or ncolumns is None:
        if len(data.shape) == 2:
            nrows, ncolumns = data.shape
        else:
            raise TypeError("nrows and ncolumns must both be specified " +
                            "if the data array is not 2D.")

    # Convert data to a 1D array in contiguous memory
    data_c = numpy.array(data, copy=True, dtype=numpy.float64, order='C').reshape(-1)

    _snip2d(&data_c[0], nrows, ncolumns, width)

    return numpy.asarray(data_c).reshape(data.shape)


def snip3d(data, int width, nx=None, ny=None, nz=None):
    """snip3d(data, width, nx=None, ny=None, nz=None) -> numpy.ndarray
    Estimate the baseline (background) of a 3D data signal by clipping peaks.

    Implementation of the algorithm SNIP in 2D described in
    *Miroslav Morhac et al. Nucl. Instruments and Methods in Physics Research
    A401 (1997) 113-132.*

    :param data: Data array, preferably 1D and of type *numpy.float64*.
        Else, the data array will be flattened and converted to
        *dtype=numpy.float64* prior to applying the snip filter.
        If the data is a 3D array, arguments ``nx``, ``ny`` and ``nz`` can
        be omitted.
    :type data: numpy.ndarray
    :param width: Width of the snip operator, in number of samples. A wider
        snip operator will result in a smoother result (lower frequency peaks
        will be clipped), and a longer computation time.
    :type width: int
    :param nx: Size of first dimension in array.
        If ``None``, it can be inferred from the shape of the data if it
        is a 3D array.
    :type nx: int or None
    :param ny: Size of second dimension in array.
        If ``None``, it can be inferred from the shape of the data if it
        is a 3D array.
    :type ny: int or None
    :param nz: Size of third dimension in array.
        If ``None``, it can be inferred from the shape of the data if it
        is a 3D array.
    :type ny: int or None
    :return: Baseline of the input array, as an array of the same shape.
    :rtype: numpy.ndarray
    """
    cdef double[::1] data_c


    if nx is None or ny is None or nz is None:
        if len(data.shape) == 3:
            nx, ny, nz = data.shape
        else:
            raise TypeError("nx, ny and nz must all be specified " +
                            "if the data array is not 3D.")

    # Convert data to a 1D array in contiguous memory
    data_c = numpy.array(data, copy=True, dtype=numpy.float64, order='C').reshape(-1)

    _snip3d(&data_c[0], nx, ny, nz, width)

    return numpy.asarray(data_c).reshape(data.shape)


def sum_gauss(x, *params):
    """sum_gauss(x, *params) -> numpy.ndarray

    Return a sum of gaussian functions defined by *(height, centroid, fwhm)*,
    where:

        - *height* is the peak amplitude
        - *centroid* is the peak x-coordinate
        - *fwhm* is the full-width at half maximum

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of gaussian parameters (length must be a multiple
        of 3):
        *(height1, centroid1, fwhm1, height2, centroid2, fwhm2,...)*
    :return: Array of sum of gaussian functions at each ``x`` coordinate.
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    # ensure float64 (double) type and 1D contiguous data layout in memory
    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_gauss(&x_c[0], x.size, &params_c[0], params_c.size, &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    # reshape y_c to match original, possibly unusual, data shape
    return numpy.asarray(y_c).reshape(x.shape)


def sum_agauss(x, *params):
    """sum_agauss(x, *params) -> numpy.ndarray

    Return a sum of gaussian functions defined by *(area, centroid, fwhm)*,
    where:

        - *area* is the area underneath the peak
        - *centroid* is the peak x-coordinate
        - *fwhm* is the full-width at half maximum

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of gaussian parameters (length must be a multiple
        of 3):
        *(area1, centroid1, fwhm1, area2, centroid2, fwhm2,...)*
    :return: Array of sum of gaussian functions at each ``x`` coordinate.
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_agauss(&x_c[0], x.size, &params_c[0], params_c.size, &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_fastagauss(x, *params):
    """sum_fastagauss(x, *params) -> numpy.ndarray

    Return a sum of gaussian functions defined by *(area, centroid, fwhm)*,
    where:

        - *area* is the area underneath the peak
        - *centroid* is the peak x-coordinate
        - *fwhm* is the full-width at half maximum

    This implementation differs from :func:`sum_agauss` by the usage of a
    lookup table with precalculated exponential values. This might speed up
    the computation for large numbers of individual gaussian functions.

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of gaussian parameters (length must be a multiple
        of 3):
        *(area1, centroid1, fwhm1, area2, centroid2, fwhm2,...)*
    :return: Array of sum of gaussian functions at each ``x`` coordinate.
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_fastagauss(&x_c[0], x.size, &params_c[0], params_c.size, &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_splitgauss(x, *params):
    """sum_splitgauss(x, *params) -> numpy.ndarray

    Return a sum of gaussian functions defined by *(area, centroid, fwhm)*,
    where:

        - *height* is the peak amplitude
        - *centroid* is the peak x-coordinate
        - *fwhm1* is the full-width at half maximum for the distribution
          when ``x < centroid``
        - *fwhm2* is the full-width at half maximum for the distribution
          when  ``x > centroid``

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of gaussian parameters (length must be a multiple
        of 4):
        *(height1, centroid1, fwhm11, fwhm21, height2, centroid2, fwhm12, fwhm22,...)*
    :return: Array of sum of split gaussian functions at each ``x`` coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_splitgauss(&x_c[0], x.size, &params_c[0], params_c.size, &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_apvoigt(x, *params):
    """sum_apvoigt(x, *params) -> numpy.ndarray

    Return a sum of pseudo-Voigt functions, defined by *(area, centroid, fwhm,
    eta)*.

    The pseudo-Voigt profile ``PV(x)`` is an approximation of the Voigt
    profile using a linear combination of a Gaussian curve ``G(x)`` and a
    Lorentzian curve ``L(x)`` instead of their convolution.

        - *area* is the area underneath both G(x) and L(x)
        - *centroid* is the peak x-coordinate for both functions
        - *fwhm* is the full-width at half maximum of both functions
        - *eta* is the Lorentz factor: PV(x) = eta * L(x) + (1 - eta) * G(x)

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of pseudo-Voigt parameters (length must be a multiple
        of 4):
        *(area1, centroid1, fwhm1, eta1, area2, centroid2, fwhm2, eta2,...)*
    :return: Array of sum of pseudo-Voigt functions at each ``x`` coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_apvoigt(&x_c[0], x.size, &params_c[0], params_c.size, &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_pvoigt(x, *params):
    """sum_pvoigt(x, *params) -> numpy.ndarray

    Return a sum of pseudo-Voigt functions, defined by *(height, centroid,
    fwhm, eta)*.

    The pseudo-Voigt profile ``PV(x)`` is an approximation of the Voigt
    profile using a linear combination of a Gaussian curve ``G(x)`` and a
    Lorentzian curve ``L(x)`` instead of their convolution.

        - *height* is the peak amplitude of G(x) and L(x)
        - *centroid* is the peak x-coordinate for both functions
        - *fwhm* is the full-width at half maximum of both functions
        - *eta* is the Lorentz factor: PV(x) = eta * L(x) + (1 - eta) * G(x)

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of pseudo-Voigt parameters (length must be a multiple
        of 4):
        *(height1, centroid1, fwhm1, eta1, height2, centroid2, fwhm2, eta2,...)*
    :return: Array of sum of pseudo-Voigt functions at each ``x`` coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_pvoigt(&x_c[0], x.size, &params_c[0], params_c.size, &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_splitpvoigt(x, *params):
    """sum_splitpvoigt(x, *params) -> numpy.ndarray

    Return a sum of split pseudo-Voigt functions, defined by *(height,
    centroid, fwhm1, fwhm2, eta)*.

    The pseudo-Voigt profile ``PV(x)`` is an approximation of the Voigt
    profile using a linear combination of a Gaussian curve ``G(x)`` and a
    Lorentzian curve ``L(x)`` instead of their convolution.

        - *height* is the peak amplitudefor G(x) and L(x)
        - *centroid* is the peak x-coordinate for both functions
        - *fwhm1* is the full-width at half maximum of both functions
          when ``x < centroid``
        - *fwhm2* is the full-width at half maximum of both functions
          when ``x > centroid``
        - *eta* is the Lorentz factor: PV(x) = eta * L(x) + (1 - eta) * G(x)

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of pseudo-Voigt parameters (length must be a multiple
        of 5):
        *(height1, centroid1, fwhm11, fwhm21, eta1,...)*
    :return: Array of sum of split pseudo-Voigt functions at each ``x``
        coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_splitpvoigt(&x_c[0], x.size, &params_c[0], params_c.size, &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_lorentz(x, *params):
    """sum_lorentz(x, *params) -> numpy.ndarray

    Return a sum of Lorentz distributions, also known as Cauchy distribution,
    defined by *(height, centroid, fwhm)*.

        - *height* is the peak amplitude
        - *centroid* is the peak x-coordinate
        - *fwhm* is the full-width at half maximum

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of Lorentz parameters (length must be a multiple
        of 3):
        *(height1, centroid1, fwhm1,...)*
    :return: Array of sum Lorentz functions at each ``x``
        coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_lorentz(&x_c[0], x.size, &params_c[0], params_c.size, &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_alorentz(x, *params):
    """sum_alorentz(x, *params) -> numpy.ndarray

    Return a sum of Lorentz distributions, also known as Cauchy distribution,
    defined by *(area, centroid, fwhm)*.

        - *area* is the area underneath the peak
        - *centroid* is the peak x-coordinate for both functions
        - *fwhm* is the full-width at half maximum

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of Lorentz parameters (length must be a multiple
        of 3):
        *(area1, centroid1, fwhm1,...)*
    :return: Array of sum of Lorentz functions at each ``x``
        coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_alorentz(&x_c[0],
                           x.size,
                           &params_c[0],
                           params_c.size,
                           &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_splitlorentz(x, *params):
    """sum_splitlorentz(x, *params) -> numpy.ndarray

    Return a sum of split Lorentz distributions,
    defined by *(height, centroid, fwhm1, fwhm2)*.

        - *height* is the peak amplitude
        - *centroid* is the peak x-coordinate for both functions
        - *fwhm1* is the full-width at half maximum for ``x < centroid``
        - *fwhm2* is the full-width at half maximum for ``x > centroid``

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of Lorentz parameters (length must be a multiple
        of 4):
        *(height1, centroid1, fwhm11, fwhm21...)*
    :return: Array of sum of Lorentz functions at each ``x``
        coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_splitlorentz(&x_c[0],
                               x.size,
                               &params_c[0],
                               params_c.size,
                               &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_downstep(x, *params):
    """sum_downstep(x, *params) -> numpy.ndarray

    Return a sum of downstep functions.
    defined by *(height, centroid, fwhm)*.

        - *height* is the step's amplitude
        - *centroid* is the step's x-coordinate
        - *fwhm* is the full-width at half maximum for the derivative,
          which is a measure of the *sharpness* of the step-down's edge

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of downstep parameters (length must be a multiple
        of 3):
        *(height1, centroid1, fwhm1,...)*
    :return: Array of sum of downstep functions at each ``x``
        coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_downstep(&x_c[0],
                           x.size,
                           &params_c[0],
                           params_c.size,
                           &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_upstep(x, *params):
    """sum_upstep(x, *params) -> numpy.ndarray

    Return a sum of upstep functions.
    defined by *(height, centroid, fwhm)*.

        - *height* is the step's amplitude
        - *centroid* is the step's x-coordinate
        - *fwhm* is the full-width at half maximum for the derivative,
          which is a measure of the *sharpness* of the step-up's edge

    :param x: Independant variable where the gaussians are calculated
    :type x: numpy.ndarray
    :param params: Array of upstep parameters (length must be a multiple
        of 3):
        *(height1, centroid1, fwhm1,...)*
    :return: Array of sum of upstep functions at each ``x``
        coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_upstep(&x_c[0],
                         x.size,
                         &params_c[0],
                         params_c.size,
                         &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_slit(x, *params):
    """sum_slit(x, *params) -> numpy.ndarray

    Return a sum of slit functions.
    defined by *(height, position, fwhm, beamfwhm)*.

        - *height* is the slit's amplitude
        - *position* is the center of the slit's x-coordinate
        - *fwhm* is the full-width at half maximum of the slit
        - *beamfwhm* is the full-width at half maximum of the
          derivative, which is a measure of the *sharpness*
          of the edges of the slit

    :param x: Independant variable where the slits are calculated
    :type x: numpy.ndarray
    :param params: Array of slit parameters (length must be a multiple
        of 4):
        *(height1, centroid1, fwhm1, beamfwhm1,...)*
    :return: Array of sum of slit functions at each ``x``
        coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_slit(&x_c[0],
                       x.size,
                       &params_c[0],
                       params_c.size,
                       &y_c[0])

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_ahypermet(x, *params,
                  gaussian_term=True, st_term=True, lt_term=True, step_term=True):
    """sum_ahypermet(x, *params) -> numpy.ndarray

    Return a sum of ahypermet functions.
    defined by *(area, position, fwhm, st_area_r, st_slope_r, lt_area_r,
    lt_slope_r, step_height_r)*.

        - *area* is the area underneath the gaussian peak
        - *position* is the center of the various peaks and the position of
          the step down
        - *fwhm* is the full-width at half maximum of the terms
        - *st_area_r* is factor between the gaussian area and the area of the
          short tail term
        - *st_slope_r* is a parameter related to the slope of the short tail
          in the low ``x`` values (the lower, the steeper)
        - *lt_area_r* is factor between the gaussian area and the area of the
          long tail term
        - *lt_slope_r* is a parameter related to the slope of the long tail
          in the low ``x`` values  (the lower, the steeper)
        - *step_height_r* is the factor between the height of the step down
          and the gaussian height

    A hypermet function is a sum of four functions (terms):

        - a gaussian term
        - a long tail term
        - a short tail term
        - a step down term

    :param x: Independant variable where the hypermets are calculated
    :type x: numpy.ndarray
    :param params: Array of hypermet parameters (length must be a multiple
        of 8):
        *(area1, position1, fwhm1, st_area_r1, st_slope_r1, lt_area_r1,
        lt_slope_r1, step_height_r1...)*
    :param gaussian_term: If ``True``, enable gaussian term. Default ``True``
    :param st_term: If ``True``, enable gaussian term. Default ``True``
    :param lt_term: If ``True``, enable gaussian term. Default ``True``
    :param step_term: If ``True``, enable gaussian term. Default ``True``
    :return: Array of sum of hypermet functions at each ``x`` coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    # Sum binary flags to activate various terms of the equation
    tail_flags = 1 if gaussian_term else 0
    if st_term:
        tail_flags += 2
    if lt_term:
        tail_flags += 4
    if step_term:
        tail_flags += 8

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_ahypermet(&x_c[0],
                            x.size,
                            &params_c[0],
                            params_c.size,
                            &y_c[0],
                            tail_flags)

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def sum_fastahypermet(x, *params,
                      gaussian_term=True, st_term=True,
                      lt_term=True, step_term=True):
    """sum_fastahypermet(x, *params) -> numpy.ndarray

    Return a sum of hypermet functions defined by *(area, position, fwhm,
    st_area_r, st_slope_r, lt_area_r, lt_slope_r, step_height_r)*.

        - *area* is the area underneath the gaussian peak
        - *position* is the center of the various peaks and the position of
          the step down
        - *fwhm* is the full-width at half maximum of the terms
        - *st_area_r* is factor between the gaussian area and the area of the
          short tail term
        - *st_slope_r* is a parameter related to the slope of the short tail
          in the low ``x`` values (the lower, the steeper)
        - *lt_area_r* is factor between the gaussian area and the area of the
          long tail term
        - *lt_slope_r* is a parameter related to the slope of the long tail
          in the low ``x`` values  (the lower, the steeper)
        - *step_height_r* is the factor between the height of the step down
          and the gaussian height

    A hypermet function is a sum of four functions (terms):

        - a gaussian term
        - a long tail term
        - a short tail term
        - a step down term

    This function differs from :func:`sum_ahypermet` by the use of a lookup
    table for calculating exponentials. This offers better performance when
    calculating many functions for large ``x`` arrays.

    :param x: Independant variable where the hypermets are calculated
    :type x: numpy.ndarray
    :param params: Array of hypermet parameters (length must be a multiple
        of 8):
        *(area1, position1, fwhm1, st_area_r1, st_slope_r1, lt_area_r1,
        lt_slope_r1, step_height_r1...)*
    :param gaussian_term: If ``True``, enable gaussian term. Default ``True``
    :param st_term: If ``True``, enable gaussian term. Default ``True``
    :param lt_term: If ``True``, enable gaussian term. Default ``True``
    :param step_term: If ``True``, enable gaussian term. Default ``True``
    :return: Array of sum of hypermet functions at each ``x`` coordinate
    """
    cdef:
        double[::1] x_c
        double[::1] params_c
        double[::1] y_c

    # Sum binary flags to activate various terms of the equation
    tail_flags = 1 if gaussian_term else 0
    if st_term:
        tail_flags += 2
    if lt_term:
        tail_flags += 4
    if step_term:
        tail_flags += 8

    # TODO (maybe):
    # Set flags according to params, to move conditional
    # branches out of the C code.
    # E.g., set st_term = False if any of the st_slope_r params
    # (params[8*i + 4]) is 0, to prevent division by 0. Same thing for
    # lt_slope_r (params[8*i + 6]) and lt_term.

    x_c = numpy.array(x,
                      copy=False,
                      dtype=numpy.float64,
                      order='C').reshape(-1)
    params_c = numpy.array(params,
                           copy=False,
                           dtype=numpy.float64,
                           order='C').reshape(-1)
    y_c = numpy.empty(shape=(x.size,),
                      dtype=numpy.float64)

    status = _sum_fastahypermet(&x_c[0],
                               x.size,
                               &params_c[0],
                               params_c.size,
                               &y_c[0],
                               tail_flags)

    if status:
        raise IndexError("Wrong number of parameters for function")

    return numpy.asarray(y_c).reshape(x.shape)


def peak_search(y, fwhm, sensitivity=3.5, max_number_of_peaks=500,
                begin_index=None, end_index=None,
                debug=False, relevance_info=False):
    """Find peaks in the data.

    :param y: Data array
    :type y: numpy.ndarray
    :param fwhm: Estimated full width at half maximum of the peaks we are
        interested in
    :param sensitivity: Threshold factor used for peak search
    :param max_number_of_peaks: Maximum number of peaks in the data.
        This parameter is used to allocate memory for the output array.
        If it is too small, this function wiff fail.
    :param begin_index: Index of the first sample of the region of interest
         in the ``y`` array
    :param end_index: Index of the last sample of the region of interest in
        the ``y`` array
    :param debug: If ``True``, print debug messages. Default: ``False``
    :param relevance_info: If ``True``, add a second dimension with relevance
        information to the output array. Default: ``False``
    :return: 1D sequence with indexes of peaks in the data
        if ``relevance_info`` is ``False``.
        Else, sequence of  ``(peak_index, peak_relevance)`` tuples (one tuple
        per peak).
    :raise: ``IndexError`` if the number of peaks is too large to fit in the
        output array.
    """
    cdef:
        double[::1] y_c
        double[::1] peaks
        double[::1] relevances

    y_c = numpy.array(y,
                      copy=True,
                      dtype=numpy.float64,
                      order='C').reshape(-1)

    peaks = numpy.empty(shape=(max_number_of_peaks,),
                        dtype=numpy.float64)

    relevances = numpy.empty(shape=(max_number_of_peaks,),
                             dtype=numpy.float64)

    if debug:
        debug = 1
    else:
        debug = 0

    if begin_index is None:
        begin_index = 0
    if end_index is None:
        end_index = y_c.size - 1

    n_peaks = seek(begin_index, end_index, y_c.size,
                   fwhm, sensitivity, debug, max_number_of_peaks,
                   &y_c[0], &peaks[0], &relevances[0])

    if n_peaks < 0:
        raise IndexError("Too many peaks found for size of output array")

    if not relevance_info:
        return numpy.asarray(peaks)[0:n_peaks]
    else:
        # FIXME: maybe don't zip, return tuple (peaks, relevances)?
        return zip(numpy.asarray(peaks), numpy.asarray(relevances))[0:n_peaks]

def snip1d(data, snip_width):
    """
    Implementation of the background extraction algorithm SNIP described in
    *Miroslav Morhac et al. Nucl. Instruments and Methods in
    Physics Research A401 (1997) 113-132*.

    The original idea for 1D and the low-statistics-digital-filter (lsdf) come
    from *C.G. Ryan et al. Nucl. Instruments and Methods in Physics Research
    B34 (1988) 396-402*.


    :param data: Data array
    :type data: numpy.ndarray
    :param snip_width: Width of snip operator, in number of samples.
        A sample will be iteratively compared to it's neighbors up to a
        distance of ``snip_width`` samples. This parameters has a direct
        influence on the speed of the algorithm.
    """
    cdef:
        double[::1] data_c

    if not isinstance(data, numpy.ndarray):
        if not hasattr(data, "__len__"):
            raise TypeError("data must be a sequence (list, tuple) " +
                            "or a numpy array")
        data_shape = (len(data), )
    else:
        data_shape = data.shape

    data_c =  numpy.array(data,
                          copy=True,
                          dtype=numpy.float64,
                          order='C').reshape(-1)

    _snip1d(&data_c[0], data_c.size, snip_width)

    return numpy.asarray(data_c).reshape(data_shape)

def snip2d(data, snip_width):
    """
    Implementation of the background extraction algorithm SNIP described in
    *Miroslav Morhac et al. Nucl. Instruments and Methods in
    Physics Research A401 (1997) 113-132*.

    The original idea for 1D and the low-statistics-digital-filter (lsdf) come
    from *C.G. Ryan et al. Nucl. Instruments and Methods in Physics Research
    B34 (1988) 396-402*.


    :param data: Data array
    :type data: numpy.ndarray
    :param snip_width: Width of snip operator, in number of samples.
        A sample will be iteratively compared to it's neighbors up to a
        distance of ``snip_width`` samples. This parameters has a direct
        influence on the speed of the algorithm.
    """
    cdef:
        double[::1] data_c

    if not isinstance(data, numpy.ndarray):
        if not hasattr(data, "__len__"):
            raise TypeError("data must be a 2D sequence (list, tuple) " +
                            "or a 2D numpy array")
        if not hasattr(data[0], "__len__"):
            raise TypeError("data must be a 2D sequence (list, tuple) " +
                            "or a 2D numpy array")
        nrows = len(data)
        ncolumns = len(data[0])
        data_shape = (len(data), len(data[0]))

    else:
        data_shape = data.shape
        nrows =  data_shape[0]
        if len(data_shape) == 2:
            ncolumns = data_shape[1]
        else:
            raise TypeError("data array must be 2-dimensional")

    data_c =  numpy.array(data,
                          copy=True,
                          dtype=numpy.float64,
                          order='C').reshape(-1)

    _snip2d(&data_c[0], nrows, ncolumns, snip_width)

    return numpy.asarray(data_c).reshape(data_shape)

def snip3d(data, snip_width):
    """
    Implementation of the background extraction algorithm SNIP described in
    *Miroslav Morhac et al. Nucl. Instruments and Methods in
    Physics Research A401 (1997) 113-132*.

    The original idea for 1D and the low-statistics-digital-filter (lsdf) come
    from *C.G. Ryan et al. Nucl. Instruments and Methods in Physics Research
    B34 (1988) 396-402*.


    :param data: Data array
    :type data: numpy.ndarray
    :param snip_width: Width of snip operator, in number of samples.
        A sample will be iteratively compared to it's neighbors up to a
        distance of ``snip_width`` samples. This parameters has a direct
        influence on the speed of the algorithm.
    """
    cdef:
        double[::1] data_c

    if not isinstance(data, numpy.ndarray):
        if not hasattr(data, "__len__") or not hasattr(data[0], "__len__") or\
                not hasattr(data[0][0], "__len__"):
            raise TypeError("data must be a 3D sequence (list, tuple) " +
                            "or a 3D numpy array")
        nx = len(data)
        ny = len(data[0])
        nz = len(data[0][0])
        data_shape = (len(data), len(data[0]),  len(data[0][0]))
    else:
        data_shape = data.shape
        nrows =  data_shape[0]
        if len(data_shape) == 3:
            nx =  data_shape[0]
            ny = data_shape[1]
            nz = data_shape[2]
        else:
            raise TypeError("data array must be 3-dimensional")

    data_c =  numpy.array(data,
                          copy=True,
                          dtype=numpy.float64,
                          order='C').reshape(-1)

    _snip3d(&data_c[0], nx, ny, nz, snip_width)


    return numpy.asarray(data_c).reshape(data_shape)


def savitsky_golay(data, npoints=5):
    """Smooth a curve using a Savitsky-Golay filter.

    :param data: Input data
    :type data: 1D numpy array
    :param npoints: Size of the smoothing operator in number of samples
        Must be between 3 and 100.
    :return: Smoothed data
    """
    cdef:
        double[::1] data_c
        double[::1] output

    data_c =  numpy.array(data,
                          dtype=numpy.float64,
                          order='C').reshape(-1)

    output = numpy.empty(shape=(data_c.size,),
                         dtype=numpy.float64)

    status = SavitskyGolay(&data_c[0], data_c.size, npoints, &output[0])

    if status:
        _logger.error("Smoothing failed. Check that npoints is greater " +
                      "than 3 and smaller than 100.")

    return numpy.asarray(output).reshape(data.shape)
