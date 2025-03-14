#pragma once

#include "header.cuh"

extern int nx, ny, nz;

extern __constant__ float TAU, CSSQ, OMEGA, SHARP_C, SIGMA;
extern __constant__ float W[FPOINTS], W_G[GPOINTS];
extern __constant__ int CIX[FPOINTS], CIY[FPOINTS], CIZ[FPOINTS];
 
extern float *d_f, *d_g;
extern float *d_normx, *d_normy, *d_normz, *d_indicator;
extern float *d_curvature, *d_ffx, *d_ffy, *d_ffz;
extern float *d_ux, *d_uy, *d_uz, *d_pxx, *d_pyy, *d_pzz;
extern float *d_pxy, *d_pxz, *d_pyz, *d_rho, *d_phi;
extern float *d_g_out; 

void initializeVars();
