#include "var.cuh"
#include <cuda_runtime.h>
#include <iostream>
#include <vector>

#include "precision.cuh"

dfloat res = 1.0f;
int mesh = static_cast<int>(std::round(150 * res));

int nx = mesh;
int ny = mesh;
int nz = mesh;
int fpoints = 19;
int gpoints = 15;

dfloat tau = 1.0f;
dfloat cssq = 1.0f / 3.0f;
dfloat omega = 1.0f / tau;
dfloat sharp_c = 0.15f * 3.0f;
dfloat sigma = 0.024f;

dfloat *d_f, *d_g, *d_w, *d_w_g, *d_cix, *d_ciy, *d_ciz;
dfloat *d_normx, *d_normy, *d_normz, *d_indicator, *d_mod_grad;
dfloat *d_curvature, *d_ffx, *d_ffy, *d_ffz;
dfloat *d_ux, *d_uy, *d_uz, *d_pxx, *d_pyy, *d_pzz;
dfloat *d_pxy, *d_pxz, *d_pyz, *d_rho, *d_phi;
dfloat *d_fneq;

dfloat *h_pxx = (dfloat *)malloc(nx * ny * nz * sizeof(dfloat));
dfloat *h_pyy = (dfloat *)malloc(nx * ny * nz * sizeof(dfloat));
dfloat *h_pzz = (dfloat *)malloc(nx * ny * nz * sizeof(dfloat));
dfloat *h_pxy = (dfloat *)malloc(nx * ny * nz * sizeof(dfloat));
dfloat *h_pxz = (dfloat *)malloc(nx * ny * nz * sizeof(dfloat));
dfloat *h_pyz = (dfloat *)malloc(nx * ny * nz * sizeof(dfloat));

const dfloat cix[19] = { 0, 1, -1, 0, 0, 0, 0, 1, -1, 1, -1, 0, 0, 1, -1, 1, -1, 0, 0 };
const dfloat ciy[19] = { 0, 0, 0, 1, -1, 0, 0, 1, -1, 0, 0, 1, -1, -1, 1, 0, 0, 1, -1 };
const dfloat ciz[19] = { 0, 0, 0, 0, 0, 1, -1, 0, 0, 1, -1, 1, -1, 0, 0, -1, 1, -1, 1 };

void initializeVars() {
    size_t size = nx * ny * nz * sizeof(dfloat);            
    size_t f_size = nx * ny * nz * fpoints * sizeof(dfloat); 
    size_t g_size = nx * ny * nz * gpoints * sizeof(dfloat); 
    size_t vs_size = fpoints * sizeof(dfloat);
    size_t pf_size = gpoints * sizeof(dfloat);

    auto IDX3D = [&](int i, int j, int k) {
        return ((i) + nx * ((j) + ny * (k)));
    };

    for (int k = 0; k < nz; ++k) {
        for (int j = 0; j < ny; ++j) {
            for (int i = 0; i < nx; ++i) {
                h_pxx[IDX3D(i,j,k)] = 1.0f;
                h_pyy[IDX3D(i,j,k)] = 1.0f;
                h_pzz[IDX3D(i,j,k)] = 1.0f;
                h_pxy[IDX3D(i,j,k)] = 1.0f;
                h_pxz[IDX3D(i,j,k)] = 1.0f;
                h_pyz[IDX3D(i,j,k)] = 1.0f;
            }
        }
    }

    cudaMalloc((void **)&d_rho, size);
    cudaMalloc((void **)&d_phi, size);
    cudaMalloc((void **)&d_ux, size);
    cudaMalloc((void **)&d_uy, size);
    cudaMalloc((void **)&d_uz, size);
    cudaMalloc((void **)&d_normx, size);
    cudaMalloc((void **)&d_normy, size);
    cudaMalloc((void **)&d_normz, size);
    cudaMalloc((void **)&d_curvature, size);
    cudaMalloc((void **)&d_indicator, size);
    cudaMalloc((void **)&d_ffx, size);
    cudaMalloc((void **)&d_ffy, size);
    cudaMalloc((void **)&d_ffz, size);
    cudaMalloc((void **)&d_mod_grad, size);
    cudaMalloc((void **)&d_pxx, size);
    cudaMalloc((void **)&d_pyy, size);
    cudaMalloc((void **)&d_pzz, size);
    cudaMalloc((void **)&d_pxy, size);
    cudaMalloc((void **)&d_pxz, size);
    cudaMalloc((void **)&d_pyz, size);

    cudaMalloc((void **)&d_f, f_size);
    cudaMalloc((void **)&d_g, g_size);
    cudaMalloc((void **)&d_w, vs_size);
    cudaMalloc((void **)&d_w_g, pf_size);
    cudaMalloc((void **)&d_cix, vs_size);
    cudaMalloc((void **)&d_ciy, vs_size);
    cudaMalloc((void **)&d_ciz, vs_size);
    cudaMalloc((void **)&d_fneq, vs_size);

    cudaMemset(d_ux, 0, size);
    cudaMemset(d_uy, 0, size);
    cudaMemset(d_uz, 0, size);
    cudaMemset(d_normx, 0, size);
    cudaMemset(d_normy, 0, size);
    cudaMemset(d_normz, 0, size);
    cudaMemset(d_curvature, 0, size);
    cudaMemset(d_indicator, 0, size);
    cudaMemset(d_ffx, 0, size);
    cudaMemset(d_ffy, 0, size);
    cudaMemset(d_ffz, 0, size);
    cudaMemset(d_mod_grad, 0, size);
    cudaMemset(d_fneq, 0, vs_size);

    cudaMemcpy(d_pxx, h_pxx, size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_pyy, h_pyy, size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_pzz, h_pzz, size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_pxy, h_pxy, size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_pxz, h_pxz, size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_pyz, h_pyz, size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_cix, cix, vs_size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_ciy, ciy, vs_size, cudaMemcpyHostToDevice);
    cudaMemcpy(d_ciz, ciz, vs_size, cudaMemcpyHostToDevice);

    free(h_pxx);
    free(h_pyy);
    free(h_pzz);
    free(h_pxy);
    free(h_pxz);
    free(h_pyz);

}

