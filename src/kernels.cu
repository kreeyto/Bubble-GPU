#include "kernels.cuh"
#include "var.cuh"
#include <math.h>

#include "precision.cuh"

__global__ void phiCalc(
    dfloat *phi, dfloat *g, 
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    #define IDX3D(i,j,k) ((k) * (nx * ny) + (j) * (nx) + (i))
    #define IDX4D(i,j,k,l) ((l) * (nx * ny * nz) + (k) * (nx * ny) + (j) * (nx) + (i))

    if (i > 0 && i < nx-1 && j > 0 && j < ny-1 && k > 0 && k < nz-1) {
        #ifdef PD3Q15
            phi[IDX3D(i,j,k)] = g[IDX4D(i,j,k,0)] + g[IDX4D(i,j,k,1)] + g[IDX4D(i,j,k,2)] +
                                g[IDX4D(i,j,k,3)] + g[IDX4D(i,j,k,4)] + g[IDX4D(i,j,k,5)] +
                                g[IDX4D(i,j,k,6)] + g[IDX4D(i,j,k,7)] + g[IDX4D(i,j,k,8)] +
                                g[IDX4D(i,j,k,9)] + g[IDX4D(i,j,k,10)] + g[IDX4D(i,j,k,11)] +
                                g[IDX4D(i,j,k,12)] + g[IDX4D(i,j,k,13)] + g[IDX4D(i,j,k,14)];
        #elif defined(PD3Q19)
            phi[IDX3D(i,j,k)] = g[IDX4D(i,j,k,0)] + g[IDX4D(i,j,k,1)] + g[IDX4D(i,j,k,2)] +
                                g[IDX4D(i,j,k,3)] + g[IDX4D(i,j,k,4)] + g[IDX4D(i,j,k,5)] +
                                g[IDX4D(i,j,k,6)] + g[IDX4D(i,j,k,7)] + g[IDX4D(i,j,k,8)] +
                                g[IDX4D(i,j,k,9)] + g[IDX4D(i,j,k,10)] + g[IDX4D(i,j,k,11)] +
                                g[IDX4D(i,j,k,12)] + g[IDX4D(i,j,k,13)] + g[IDX4D(i,j,k,14)] +
                                g[IDX4D(i,j,k,15)] + g[IDX4D(i,j,k,16)] + g[IDX4D(i,j,k,17)] +
                                g[IDX4D(i,j,k,18)];
        #elif defined(PD3Q27)
            phi[IDX3D(i,j,k)] = g[IDX4D(i,j,k,0)] + g[IDX4D(i,j,k,1)] + g[IDX4D(i,j,k,2)] +
                                g[IDX4D(i,j,k,3)] + g[IDX4D(i,j,k,4)] + g[IDX4D(i,j,k,5)] +
                                g[IDX4D(i,j,k,6)] + g[IDX4D(i,j,k,7)] + g[IDX4D(i,j,k,8)] +
                                g[IDX4D(i,j,k,9)] + g[IDX4D(i,j,k,10)] + g[IDX4D(i,j,k,11)] +
                                g[IDX4D(i,j,k,12)] + g[IDX4D(i,j,k,13)] + g[IDX4D(i,j,k,14)] +
                                g[IDX4D(i,j,k,15)] + g[IDX4D(i,j,k,16)] + g[IDX4D(i,j,k,17)] +
                                g[IDX4D(i,j,k,18)] + g[IDX4D(i,j,k,19)] + g[IDX4D(i,j,k,20)] +
                                g[IDX4D(i,j,k,21)] + g[IDX4D(i,j,k,22)] + g[IDX4D(i,j,k,23)] +
                                g[IDX4D(i,j,k,24)] + g[IDX4D(i,j,k,25)] + g[IDX4D(i,j,k,26)];
        #endif                
    }
}

__global__ void gradCalc(
    dfloat *phi, dfloat *mod_grad, dfloat *normx, dfloat *normy,
    dfloat *normz, dfloat *indicator, dfloat *w, const dfloat *cix,
    const dfloat *ciy, const dfloat *ciz, int fpoints,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    #define IDX3D(i,j,k) ((k) * (nx * ny) + (j) * (nx) + (i))

    if (i > 0 && i < nx-1 && j > 0 && j < ny-1 && k > 0 && k < nz-1) {
        dfloat grad_fix = 0.0, grad_fiy = 0.0, grad_fiz = 0.0;
        for (int l = 0; l < fpoints; ++l) {
            grad_fix = grad_fix  + 3.0 * w[l] * cix[l] * phi[IDX3D(i + static_cast<int>(cix[l]),
                                                                   j + static_cast<int>(ciy[l]),
                                                                   k + static_cast<int>(ciz[l]))];
            grad_fiy = grad_fiy  + 3.0 * w[l] * ciy[l] * phi[IDX3D(i + static_cast<int>(cix[l]),
                                                                   j + static_cast<int>(ciy[l]),
                                                                   k + static_cast<int>(ciz[l]))];
            grad_fiz = grad_fiz + 3.0 * w[l] * ciz[l] * phi[IDX3D(i + static_cast<int>(cix[l]),
                                                                  j + static_cast<int>(ciy[l]),
                                                                  k + static_cast<int>(ciz[l]))];
        }
        mod_grad[IDX3D(i,j,k)] = sqrt(grad_fix*grad_fix + grad_fiy*grad_fiy + grad_fiz*grad_fiz);
        normx[IDX3D(i,j,k)] = grad_fix / (mod_grad[IDX3D(i,j,k)] + 1e-9);
        normy[IDX3D(i,j,k)] = grad_fiy / (mod_grad[IDX3D(i,j,k)] + 1e-9);
        normz[IDX3D(i,j,k)] = grad_fiz / (mod_grad[IDX3D(i,j,k)] + 1e-9);
        indicator[IDX3D(i,j,k)] = sqrt(grad_fix*grad_fix + grad_fiy*grad_fiy + grad_fiz*grad_fiz);
    }
}

__global__ void curvatureCalc(
    dfloat *curvature, dfloat *indicator, dfloat *w,
    const dfloat *cix, const dfloat *ciy, const dfloat *ciz,
    dfloat *normx, dfloat *normy, dfloat *normz,
    dfloat *ffx, dfloat *ffy, dfloat *ffz, dfloat sigma,
    int fpoints, int nx, int ny, int nz

) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    #define IDX3D(i,j,k) ((k) * (nx * ny) + (j) * (nx) + (i))

    if (i > 0 && i < nx-1 && j > 0 && j < ny-1 && k > 0 && k < nz-1) {
        curvature[IDX3D(i,j,k)] = 0.0;
        for (int l = 0; l < fpoints; ++l) {
            curvature[IDX3D(i,j,k)] = curvature[IDX3D(i,j,k)] - 3.0 * w[l] *
               (cix[l] * normx[IDX3D(i + static_cast<int>(cix[l]),
                                    j + static_cast<int>(ciy[l]),
                                    k + static_cast<int>(ciz[l]))] +
                ciy[l] * normy[IDX3D(i + static_cast<int>(cix[l]),
                                    j + static_cast<int>(ciy[l]),
                                    k + static_cast<int>(ciz[l]))] +
                ciz[l] * normz[IDX3D(i + static_cast<int>(cix[l]),
                                    j + static_cast<int>(ciy[l]),
                                    k + static_cast<int>(ciz[l]))]
            );
        }
        ffx[IDX3D(i,j,k)] = sigma * curvature[IDX3D(i,j,k)] * normx[IDX3D(i,j,k)] * indicator[IDX3D(i,j,k)];
        ffy[IDX3D(i,j,k)] = sigma * curvature[IDX3D(i,j,k)] * normy[IDX3D(i,j,k)] * indicator[IDX3D(i,j,k)];
        ffz[IDX3D(i,j,k)] = sigma * curvature[IDX3D(i,j,k)] * normz[IDX3D(i,j,k)] * indicator[IDX3D(i,j,k)];
    }
}

__global__ void momentiCalc(
    dfloat *ux, dfloat *uy, dfloat *uz, dfloat *rho,
    dfloat *ffx, dfloat *ffy, dfloat *ffz, dfloat *w, dfloat *f,
    const dfloat *cix, const dfloat *ciy, const dfloat *ciz,
    dfloat *pxx, dfloat *pyy, dfloat *pzz,
    dfloat *pxy, dfloat *pxz, dfloat *pyz,
    dfloat cssq, int nx, int ny, int nz,
    int fpoints
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    #define IDX3D(i,j,k) ((k) * (nx * ny) + (j) * (nx) + (i))
    #define IDX4D(i,j,k,l) ((l) * (nx * ny * nz) + (k) * (nx * ny) + (j) * (nx) + (i))

    dfloat fneq[19];
    
    if (i > 0 && i < nx-1 && j > 0 && j < ny-1 && k > 0 && k < nz-1) {
        #ifdef FD3Q19 
            ux[IDX3D(i,j,k)] = (
                f[IDX4D(i,j,k,1)] - f[IDX4D(i,j,k,2)] + f[IDX4D(i,j,k,7)] - f[IDX4D(i,j,k,8)] + f[IDX4D(i,j,k,9)] - 
                f[IDX4D(i,j,k,10)] + f[IDX4D(i,j,k,13)] - f[IDX4D(i,j,k,14)] + f[IDX4D(i,j,k,15)] - f[IDX4D(i,j,k,16)] 
            ) / rho[IDX3D(i,j,k)] + ffx[IDX3D(i,j,k)] * 0.5 / rho[IDX3D(i,j,k)];
            uy[IDX3D(i,j,k)] = (
                f[IDX4D(i,j,k,3)] - f[IDX4D(i,j,k,4)] + f[IDX4D(i,j,k,7)] - f[IDX4D(i,j,k,8)] + f[IDX4D(i,j,k,11)] - 
                f[IDX4D(i,j,k,12)] - f[IDX4D(i,j,k,13)] + f[IDX4D(i,j,k,14)] + f[IDX4D(i,j,k,17)] - f[IDX4D(i,j,k,18)] 
            ) / rho[IDX3D(i,j,k)] + ffy[IDX3D(i,j,k)] * 0.5 / rho[IDX3D(i,j,k)];
            uz[IDX3D(i,j,k)] = (
                f[IDX4D(i,j,k,5)] - f[IDX4D(i,j,k,6)] + f[IDX4D(i,j,k,9)] - f[IDX4D(i,j,k,10)] + f[IDX4D(i,j,k,11)] - 
                f[IDX4D(i,j,k,12)] - f[IDX4D(i,j,k,15)] + f[IDX4D(i,j,k,16)] - f[IDX4D(i,j,k,17)] + f[IDX4D(i,j,k,18)]
            ) / rho[IDX3D(i,j,k)] + ffz[IDX3D(i,j,k)] * 0.5 / rho[IDX3D(i,j,k)];
        #elif defined(FD3Q27)
            ux[IDX3D(i,j,k)] = (
                f[IDX4D(i,j,k,1)] - f[IDX4D(i,j,k,2)] + f[IDX4D(i,j,k,7)] - f[IDX4D(i,j,k,8)] + f[IDX4D(i,j,k,9)] - 
                f[IDX4D(i,j,k,10)] + f[IDX4D(i,j,k,13)] - f[IDX4D(i,j,k,14)] + f[IDX4D(i,j,k,15)] - f[IDX4D(i,j,k,16)] + 
                f[IDX4D(i,j,k,19)] - f[IDX4D(i,j,k,20)] + f[IDX4D(i,j,k,21)] - f[IDX4D(i,j,k,22)] + f[IDX4D(i,j,k,23)] - 
                f[IDX4D(i,j,k,24)] + f[IDX4D(i,j,k,25)] - f[IDX4D(i,j,k,26)]
            ) / rho[IDX3D(i,j,k)] + ffx[IDX3D(i,j,k)] * 0.5 / rho[IDX3D(i,j,k)];
            uy[IDX3D(i,j,k)] = (
                f[IDX4D(i,j,k,3)] - f[IDX4D(i,j,k,4)] + f[IDX4D(i,j,k,7)] - f[IDX4D(i,j,k,8)] + f[IDX4D(i,j,k,11)] - 
                f[IDX4D(i,j,k,12)] - f[IDX4D(i,j,k,13)] + f[IDX4D(i,j,k,14)] + f[IDX4D(i,j,k,17)] - f[IDX4D(i,j,k,18)] + 
                f[IDX4D(i,j,k,19)] - f[IDX4D(i,j,k,20)] - f[IDX4D(i,j,k,21)] + f[IDX4D(i,j,k,22)] + f[IDX4D(i,j,k,23)] - 
                f[IDX4D(i,j,k,24)] - f[IDX4D(i,j,k,25)] + f[IDX4D(i,j,k,26)]
            ) / rho[IDX3D(i,j,k)] + ffy[IDX3D(i,j,k)] * 0.5 / rho[IDX3D(i,j,k)];
            uz[IDX3D(i,j,k)] = (
                f[IDX4D(i,j,k,5)] - f[IDX4D(i,j,k,6)] + f[IDX4D(i,j,k,9)] - f[IDX4D(i,j,k,10)] + f[IDX4D(i,j,k,11)] - 
                f[IDX4D(i,j,k,12)] - f[IDX4D(i,j,k,15)] + f[IDX4D(i,j,k,16)] - f[IDX4D(i,j,k,17)] + f[IDX4D(i,j,k,18)] + 
                f[IDX4D(i,j,k,19)] - f[IDX4D(i,j,k,20)] - f[IDX4D(i,j,k,21)] + f[IDX4D(i,j,k,22)] + f[IDX4D(i,j,k,23)] + 
                f[IDX4D(i,j,k,24)] - f[IDX4D(i,j,k,25)] - f[IDX4D(i,j,k,26)]
            ) / rho[IDX3D(i,j,k)] + ffz[IDX3D(i,j,k)] * 0.5 / rho[IDX3D(i,j,k)];
        #endif        
        dfloat uu = 0.5 * (ux[IDX3D(i,j,k)]*ux[IDX3D(i,j,k)] + uy[IDX3D(i,j,k)]*uy[IDX3D(i,j,k)] + uz[IDX3D(i,j,k)]*uz[IDX3D(i,j,k)]) / cssq;
        #ifdef FD3Q19
            rho[IDX3D(i,j,k)] = f[IDX4D(i,j,k,0)] + f[IDX4D(i,j,k,1)] + f[IDX4D(i,j,k,2)] +
                                f[IDX4D(i,j,k,3)] + f[IDX4D(i,j,k,4)] + f[IDX4D(i,j,k,5)] +
                                f[IDX4D(i,j,k,6)] + f[IDX4D(i,j,k,7)] + f[IDX4D(i,j,k,8)] +
                                f[IDX4D(i,j,k,9)] + f[IDX4D(i,j,k,10)] + f[IDX4D(i,j,k,11)] +
                                f[IDX4D(i,j,k,12)] + f[IDX4D(i,j,k,13)] + f[IDX4D(i,j,k,14)] +
                                f[IDX4D(i,j,k,15)] + f[IDX4D(i,j,k,16)] + f[IDX4D(i,j,k,17)] +
                                f[IDX4D(i,j,k,18)];
        #elif defined(FD3Q27)
            rho[IDX3D(i,j,k)] = f[IDX4D(i,j,k,0)] + f[IDX4D(i,j,k,1)] + f[IDX4D(i,j,k,2)] +
                                f[IDX4D(i,j,k,3)] + f[IDX4D(i,j,k,4)] + f[IDX4D(i,j,k,5)] +
                                f[IDX4D(i,j,k,6)] + f[IDX4D(i,j,k,7)] + f[IDX4D(i,j,k,8)] +
                                f[IDX4D(i,j,k,9)] + f[IDX4D(i,j,k,10)] + f[IDX4D(i,j,k,11)] +
                                f[IDX4D(i,j,k,12)] + f[IDX4D(i,j,k,13)] + f[IDX4D(i,j,k,14)] +
                                f[IDX4D(i,j,k,15)] + f[IDX4D(i,j,k,16)] + f[IDX4D(i,j,k,17)] +
                                f[IDX4D(i,j,k,18)] + f[IDX4D(i,j,k,19)] + f[IDX4D(i,j,k,20)] +
                                f[IDX4D(i,j,k,21)] + f[IDX4D(i,j,k,22)] + f[IDX4D(i,j,k,23)] +
                                f[IDX4D(i,j,k,24)] + f[IDX4D(i,j,k,25)] + f[IDX4D(i,j,k,26)];
        #endif
        for (int l = 0; l < fpoints; ++l) {
            dfloat udotc = (ux[IDX3D(i,j,k)] * cix[l] + uy[IDX3D(i,j,k)] * ciy[l] + uz[IDX3D(i,j,k)] * ciz[l]) / cssq;
            dfloat HeF = (w[l] * (rho[IDX3D(i,j,k)] + rho[IDX3D(i,j,k)] * (udotc + 0.5 * (udotc*udotc) - uu)))
                    * ((cix[l] - ux[IDX3D(i,j,k)]) * ffx[IDX3D(i,j,k)] +
                        (ciy[l] - uy[IDX3D(i,j,k)]) * ffy[IDX3D(i,j,k)] +
                        (ciz[l] - uz[IDX3D(i,j,k)]) * ffz[IDX3D(i,j,k)]
                    ) / (rho[IDX3D(i,j,k)] * cssq);
            dfloat feq = w[l] * (rho[IDX3D(i,j,k)] + rho[IDX3D(i,j,k)] * (udotc + 0.5 * (udotc*udotc) - uu)) - 0.5 * HeF;
            fneq[l] = f[IDX4D(i,j,k,l)] - feq;
        }
        #ifdef FD3Q19 
            pxx[IDX3D(i,j,k)] = fneq[1] + fneq[2] + fneq[7] + fneq[8] + fneq[9] + fneq[10] + fneq[13] + fneq[14] + fneq[15] + fneq[16];
            pyy[IDX3D(i,j,k)] = fneq[3] + fneq[4] + fneq[7] + fneq[8] + fneq[11] + fneq[12] + fneq[13] + fneq[14] + fneq[17] + fneq[18];
            pzz[IDX3D(i,j,k)] = fneq[5] + fneq[6] + fneq[9] + fneq[10] + fneq[11] + fneq[12] + fneq[15] + fneq[16] + fneq[17] + fneq[18];
            pxy[IDX3D(i,j,k)] = fneq[7] + fneq[8] - fneq[13] - fneq[14];
            pxz[IDX3D(i,j,k)] = fneq[9] + fneq[10] - fneq[15] - fneq[16];
            pyz[IDX3D(i,j,k)] = fneq[11] + fneq[12] - fneq[17] - fneq[18];
        #elif defined(FD3Q27)
            pxx[IDX3D(i,j,k)] = fneq[1] + fneq[2] + fneq[7] + fneq[8] + fneq[9] + fneq[10] + fneq[13] + fneq[14] + fneq[15] + fneq[16] + fneq[19] + 
                                fneq[20] + fneq[21] + fneq[22] + fneq[23] + fneq[24] + fneq[25] + fneq[26];
            pyy[IDX3D(i,j,k)] = fneq[3] + fneq[4] + fneq[7] + fneq[8] + fneq[11] + fneq[12] + fneq[13] + fneq[14] + fneq[17] + fneq[18] + fneq[19] + 
                                fneq[20] + fneq[21] + fneq[22] + fneq[23] + fneq[24] + fneq[25] + fneq[26];
            pzz[IDX3D(i,j,k)] = fneq[5] + fneq[6] + fneq[9] + fneq[10] + fneq[11] + fneq[12] + fneq[15] + fneq[16] + fneq[17] + fneq[18] + fneq[19] + 
                                fneq[20] + fneq[21] + fneq[22] + fneq[23] + fneq[24] + fneq[25] + fneq[26]; 
            pxy[IDX3D(i,j,k)] = fneq[7] + fneq[8] - fneq[13] - fneq[14] + fneq[19] + fneq[20] + fneq[21] + fneq[22] - fneq[23] - fneq[24] - fneq[25] - fneq[26];
            pxz[IDX3D(i,j,k)] = fneq[9] + fneq[10] - fneq[15] - fneq[16] + fneq[19] + fneq[20] - fneq[21] - fneq[22] + fneq[23] + fneq[24] - fneq[25] - fneq[26];
            pyz[IDX3D(i,j,k)] = fneq[11] + fneq[12] - fneq[17] - fneq[18] + fneq[19] + fneq[20] - fneq[21] - fneq[22] - fneq[23] - fneq[24] + fneq[25] + fneq[26];
        #endif
    }
}

__global__ void collisionCalc(
    dfloat *ux, dfloat *uy, dfloat *uz, dfloat *w, dfloat *w_g,
    const dfloat *cix, const dfloat *ciy, const dfloat *ciz,
    dfloat *normx, dfloat *normy, dfloat *normz,
    dfloat *ffx, dfloat *ffy, dfloat *ffz,
    dfloat *rho, dfloat *phi, dfloat *f, dfloat *g,
    dfloat *pxx, dfloat *pyy, dfloat *pzz, dfloat *pxy, dfloat *pxz, dfloat *pyz,
    dfloat cssq, dfloat omega, dfloat sharp_c, int fpoints, int gpoints,
    int nx, int ny, int nz, dfloat *f_coll // saída: f pós-colisão
) {     
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    #define IDX3D(i,j,k) ((k) * (nx * ny) + (j) * (nx) + (i))
    #define IDX4D(i,j,k,l) ((l) * (nx * ny * nz) + (k) * (nx * ny) + (j) * (nx) + (i))

    if (i > 0 && i < nx-1 && j > 0 && j < ny-1 && k > 0 && k < nz-1) {
        dfloat uu = 0.5 * (ux[IDX3D(i,j,k)]*ux[IDX3D(i,j,k)] + uy[IDX3D(i,j,k)]*uy[IDX3D(i,j,k)] + uz[IDX3D(i,j,k)]*uz[IDX3D(i,j,k)]) / cssq;
        for (int l = 0; l < fpoints; ++l) {
            dfloat udotc = (ux[IDX3D(i,j,k)] * cix[l] + uy[IDX3D(i,j,k)] * ciy[l] + uz[IDX3D(i,j,k)] * ciz[l]) / cssq;
            dfloat feq = w[l] * (rho[IDX3D(i,j,k)] + rho[IDX3D(i,j,k)] * (udotc + 0.5 * (udotc*udotc) - uu));
            dfloat HeF = 0.5 * (w[l] * (rho[IDX3D(i,j,k)] + rho[IDX3D(i,j,k)] * (udotc + 0.5 * (udotc*udotc) - uu)))
                    * ((cix[l] - ux[IDX3D(i,j,k)]) * ffx[IDX3D(i,j,k)] +
                        (ciy[l] - uy[IDX3D(i,j,k)]) * ffy[IDX3D(i,j,k)] +
                        (ciz[l] - uz[IDX3D(i,j,k)]) * ffz[IDX3D(i,j,k)]
                    ) / (rho[IDX3D(i,j,k)] * cssq);
            dfloat fneq = (cix[l] * cix[l] - cssq) * pxx[IDX3D(i,j,k)] +
                        (ciy[l] * ciy[l] - cssq) * pyy[IDX3D(i,j,k)] +
                        (ciz[l] * ciz[l] - cssq) * pzz[IDX3D(i,j,k)] +
                        2 * cix[l] * ciy[l] * pxy[IDX3D(i,j,k)] +
                        2 * cix[l] * ciz[l] * pxz[IDX3D(i,j,k)] +
                        2 * ciy[l] * ciz[l] * pyz[IDX3D(i,j,k)];
            f_coll[IDX4D(i,j,k,l)] = feq + (1.0 - omega) * (w[l] / (2.0*cssq*cssq)) * fneq + HeF;
        }
        for (int l = 0; l < gpoints; ++l) {
            dfloat udotc = (ux[IDX3D(i,j,k)] * cix[l] + uy[IDX3D(i,j,k)] * ciy[l] + uz[IDX3D(i,j,k)] * ciz[l]) / cssq;
            dfloat feq = w_g[l] * phi[IDX3D(i,j,k)] * (1 + udotc);
            dfloat Hi = sharp_c * phi[IDX3D(i,j,k)] * (1 - phi[IDX3D(i,j,k)]) *
                (cix[l] * normx[IDX3D(i,j,k)] +
                 ciy[l] * normy[IDX3D(i,j,k)] + 
                 ciz[l] * normz[IDX3D(i,j,k)]);
            g[IDX4D(i,j,k,l)] = feq + w_g[l] * Hi;
        }
    }
}

__global__ void streamingCalcNew(
    const dfloat *f_coll,
    const dfloat *cix, const dfloat *ciy, const dfloat *ciz,
    int nx, int ny, int nz, int fpoints,
    dfloat *f // saída: f final após streaming
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;
    
    #define IDX3D(i,j,k) ((k)*(nx*ny)+(j)*nx+(i))
    #define IDX4D(i,j,k,l) ((l)*(nx*ny*nz)+(k)*(nx*ny)+(j)*nx+(i))
    
    // Cada thread puxa os dados da célula vizinha oposta à direção l
    for (int l = 0; l < fpoints; ++l) {
        int src_i = (i - (int)cix[l] + nx) % nx;
        int src_j = (j - (int)ciy[l] + ny) % ny;
        int src_k = (k - (int)ciz[l] + nz) % nz;
        f[IDX4D(i,j,k,l)] = f_coll[IDX4D(src_i, src_j, src_k, l)];
    }
}

__global__ void streamingCalc(
    const dfloat *g_in, dfloat *g_out, 
    const dfloat *cix, const dfloat *ciy, const dfloat *ciz,
    int nx, int ny, int nz, int gpoints
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;
    
    if (i >= nx || j >= ny || k >= nz) return;

    #define IDX4D(i,j,k,l) ((l) * (nx * ny * nz) + (k) * (nx * ny) + (j) * (nx) + (i))
    
    for (int l = 0; l < gpoints; ++l) {
        int shifted_i = (i - static_cast<int>(cix[l]) + nx) % nx;
        int shifted_j = (j - static_cast<int>(ciy[l]) + ny) % ny;
        int shifted_k = (k - static_cast<int>(ciz[l]) + nz) % nz;
        g_out[IDX4D(i,j,k,l)] = g_in[IDX4D(shifted_i,shifted_j,shifted_k,l)];
    }
}

__global__ void fgBoundary(
    dfloat *f, dfloat *g, dfloat *rho, dfloat *phi,
    dfloat *w, dfloat *w_g,
    const dfloat *cix, const dfloat *ciy, const dfloat *ciz,
    int fpoints, int gpoints, int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    #define IDX3D(i,j,k) ((k) * (nx * ny) + (j) * (nx) + (i))
    #define IDX4D(i,j,k,l) ((l) * (nx * ny * nz) + (k) * (nx * ny) + (j) * (nx) + (i))

    if (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) {
        for (int l = 0; l < fpoints; ++l) {
            int nb_i = i + static_cast<int>(cix[l]);
            int nb_j = j + static_cast<int>(ciy[l]);
            int nb_k = k + static_cast<int>(ciz[l]);
            if (nb_i >= 0 && nb_i < nx &&
                nb_j >= 0 && nb_j < ny &&
                nb_k >= 0 && nb_k < nz)
            {
                f[IDX4D(nb_i, nb_j, nb_k, l)] = rho[IDX3D(i,j,k)] * w[l];
            }
        }
        for (int l = 0; l < gpoints; ++l) {
            int nb_i = i + static_cast<int>(cix[l]);
            int nb_j = j + static_cast<int>(ciy[l]);
            int nb_k = k + static_cast<int>(ciz[l]);
            if (nb_i >= 0 && nb_i < nx &&
                nb_j >= 0 && nb_j < ny &&
                nb_k >= 0 && nb_k < nz)
            {
                g[IDX4D(nb_i, nb_j, nb_k, l)] = phi[IDX3D(i,j,k)] * w_g[l];
            }
        }
    }
}

__global__ void boundaryConditions(dfloat *phi, int nx, int ny, int nz)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    #define IDX3D(i,j,k) ((k) * (nx * ny) + (j) * nx + (i))

    if (k == 0 && j < ny && i < nx) {
        phi[IDX3D(i,j,0)] = phi[IDX3D(i,j,1)];
    }
    if (k == nz-1 && j < ny && i < nx && nz > 1) {
        phi[IDX3D(i,j,nz-1)] = phi[IDX3D(i,j,nz-2)];
    }

    if (j == 0 && k < nz && i < nx) {
        phi[IDX3D(i,0,k)] = phi[IDX3D(i,1,k)];
    }
    if (j == ny-1 && k < nz && i < nx && ny > 1) {
        phi[IDX3D(i,ny-1,k)] = phi[IDX3D(i,ny-2,k)];
    }

    if (i == 0 && j < ny && k < nz) {
        phi[IDX3D(0,j,k)] = phi[IDX3D(1,j,k)];
    }
    if (i == nx-1 && j < ny && k < nz && nx > 1) {
        phi[IDX3D(nx-1,j,k)] = phi[IDX3D(nx-2,j,k)];
    }
}
