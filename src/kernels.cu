#include "kernels.cuh"
#include "var.cuh"
#include <math.h>

#include "precision.cuh"

#define IDX3D(i,j,k)  ((i) + (j) * nx + (k) * nx * ny)
#define IDX4D(i,j,k,l) ((i) + (j) * nx + (k) * nx * ny + (l) * nx * ny * nz)

__global__ void initPhase(
    dfloat * __restrict__ phi, 
    int res, int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;
    if (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    dfloat dx = i - nx * 0.5;
    dfloat dy = j - ny * 0.5;
    dfloat dz = k - nz * 0.5;

    dfloat Ri = sqrt((dx * dx) / 4.0 + dy * dy + dz * dz);
    dfloat phi_val = 0.5 + 0.5 * tanh(2.0 * (20 - Ri) / (3.0 * res));

    phi[IDX3D(i,j,k)] = phi_val;
}


__global__ void initDist(
    const dfloat * __restrict__ rho, 
    const dfloat * __restrict__ phi, 
    dfloat * __restrict__ f,
    dfloat * __restrict__ g,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    dfloat rho_val = rho[IDX3D(i,j,k)];
    dfloat phi_val = phi[IDX3D(i,j,k)];

    #pragma unroll
    for (int l = 0; l < FPOINTS; ++l) {
        f[IDX4D(i,j,k,l)] = W[l] * rho_val;
    }

    #pragma unroll
    for (int l = 0; l < GPOINTS; ++l) {
        g[IDX4D(i,j,k,l)] = W_G[l] * phi_val;
    }
}


// ============================================================================================== //

__global__ void phiCalc(
    dfloat * __restrict__ phi,
    const dfloat * __restrict__ g,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;
    if (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    dfloat sum = 0.0;

    #pragma unroll
    for (int l = 0; l < GPOINTS; ++l) {
        sum += g[IDX4D(i,j,k,l)];
    }

    phi[IDX3D(i,j,k)] = sum;
}

__global__ void gradCalc(
    const dfloat * __restrict__ phi,
    dfloat * __restrict__ mod_grad,
    dfloat * __restrict__ normx,
    dfloat * __restrict__ normy,
    dfloat * __restrict__ normz,
    dfloat * __restrict__ indicator,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;
    if (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    dfloat grad_fix = 0.0, grad_fiy = 0.0, grad_fiz = 0.0;

    #pragma unroll
    for (int l = 0; l < FPOINTS; ++l) {
        int cix_l = CIX[l], ciy_l = CIY[l], ciz_l = CIZ[l];
        dfloat w_l = W[l];
        int ii = i + cix_l;
        int jj = j + ciy_l;
        int kk = k + ciz_l;
        int offset = ii + jj * nx + kk * nx * ny;
        dfloat val = phi[offset];
        dfloat coef = 3.0 * w_l;
        grad_fix += coef * cix_l * val;
        grad_fiy += coef * ciy_l * val;
        grad_fiz += coef * ciz_l * val;
    }

    dfloat gmag_sq = grad_fix * grad_fix + grad_fiy * grad_fiy + grad_fiz * grad_fiz;
    dfloat inv_gmag = rsqrtf(gmag_sq + 1e-9);
    dfloat gmag = 1.0 / inv_gmag;  

    mod_grad[IDX3D(i,j,k)] = gmag;
    normx[IDX3D(i,j,k)] = grad_fix * inv_gmag;
    normy[IDX3D(i,j,k)] = grad_fiy * inv_gmag;
    normz[IDX3D(i,j,k)] = grad_fiz * inv_gmag;
    indicator[IDX3D(i,j,k)] = gmag;
}

__global__ void curvatureCalc(
    dfloat * __restrict__ curvature,
    const dfloat * __restrict__ indicator,
    const dfloat * __restrict__ normx,
    const dfloat * __restrict__ normy,
    const dfloat * __restrict__ normz,
    dfloat * __restrict__ ffx,
    dfloat * __restrict__ ffy,
    dfloat * __restrict__ ffz,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;
    if (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    int offset = IDX3D(i,j,k);

    dfloat normx_ = normx[offset];
    dfloat normy_ = normy[offset];
    dfloat normz_ = normz[offset];
    dfloat ind_ = indicator[offset];
    dfloat curv = 0.0;

    int baseIdx = i + j * nx + k * nx * ny;

    #pragma unroll
    for (int l = 0; l < FPOINTS; ++l) {
        int cix_l = CIX[l], ciy_l = CIY[l], ciz_l = CIZ[l];
        dfloat w_l = W[l];
        int offsetN = baseIdx + cix_l + ciy_l * nx + ciz_l * nx * ny;
        dfloat normxN = normx[offsetN];
        dfloat normyN = normy[offsetN];
        dfloat normzN = normz[offsetN];
        dfloat coef = 3.0 * w_l;
        curv -= coef * (cix_l * normxN + ciy_l * normyN + ciz_l * normzN);
    }

    dfloat mult = SIGMA * curv * ind_;
    curvature[offset] = curv;
    ffx[offset] = mult * normx_;
    ffy[offset] = mult * normy_;
    ffz[offset] = mult * normz_;
}

__global__ void momentiCalc(
    dfloat * __restrict__ ux,
    dfloat * __restrict__ uy,
    dfloat * __restrict__ uz,
    dfloat * __restrict__ rho,
    dfloat * __restrict__ ffx,
    dfloat * __restrict__ ffy,
    dfloat * __restrict__ ffz,
    const dfloat * __restrict__ f,
    dfloat * __restrict__ pxx,
    dfloat * __restrict__ pyy,
    dfloat * __restrict__ pzz,
    dfloat * __restrict__ pxy,
    dfloat * __restrict__ pxz,
    dfloat * __restrict__ pyz,
    int nx, int ny, int nz
) {
    const int i = blockIdx.x * blockDim.x + threadIdx.x;
    const int j = blockIdx.y * blockDim.y + threadIdx.y;
    const int k = blockIdx.z * blockDim.z + threadIdx.z;
    
    if (i >= nx || j >= ny || k >= nz) return;
    if (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;
    
    const int idx = IDX3D(i,j,k);

    dfloat fVal[FPOINTS];
    #pragma unroll
    for (int l = 0; l < FPOINTS; ++l)
        fVal[l] = __ldg(&f[IDX4D(i,j,k,l)]);
    
    const dfloat rhoOld  = rho[idx];
    const dfloat ffx_val = ffx[idx];
    const dfloat ffy_val = ffy[idx];
    const dfloat ffz_val = ffz[idx];

    #ifdef FD3Q19
        const dfloat sumUx = fVal[1] - fVal[2] + fVal[7] - fVal[8] +
                            fVal[9] - fVal[10] + fVal[13] - fVal[14] +
                            fVal[15] - fVal[16];
        const dfloat sumUy = fVal[3] - fVal[4] + fVal[7] - fVal[8] +
                            fVal[11] - fVal[12] - fVal[13] + fVal[14] +
                            fVal[17] - fVal[18];
        const dfloat sumUz = fVal[5] - fVal[6] + fVal[9] - fVal[10] +
                            fVal[11] - fVal[12] - fVal[15] + fVal[16] -
                            fVal[17] + fVal[18];
    #endif

    const dfloat invRhoOld = 1.0 / rhoOld;
    const dfloat halfFx = 0.5 * ffx_val * invRhoOld;
    const dfloat halfFy = 0.5 * ffy_val * invRhoOld;
    const dfloat halfFz = 0.5 * ffz_val * invRhoOld;

#ifdef FD3Q19
    const dfloat uxVal = sumUx * invRhoOld + halfFx;
    const dfloat uyVal = sumUy * invRhoOld + halfFy;
    const dfloat uzVal = sumUz * invRhoOld + halfFz;
#endif

    dfloat rhoNew = 0.0;
    #pragma unroll
    for (int l = 0; l < FPOINTS; ++l)
        rhoNew += fVal[l];
    rho[idx] = rhoNew;

    const dfloat invCssq        = 1.0 / CSSQ;
    const dfloat uu             = 0.5 * (uxVal*uxVal + uyVal*uyVal + uzVal*uzVal) * invCssq;
    const dfloat invRhoNewCssq  = 1.0 / (rhoNew * CSSQ);

    #ifdef FD3Q19
        dfloat sumXX = 0.0, sumYY = 0.0, sumZZ = 0.0;
        dfloat sumXY = 0.0, sumXZ = 0.0, sumYZ = 0.0;
        #pragma unroll
        for (int l = 0; l < FPOINTS; ++l) {
            const int cix_l = CIX[l], ciy_l = CIY[l], ciz_l = CIZ[l];
            const dfloat w_l = W[l];
            const dfloat udotc = (uxVal * cix_l + uyVal * ciy_l + uzVal * ciz_l) * invCssq;
            const dfloat udotc2 = udotc * udotc;
            const dfloat eqBase = rhoNew * (udotc + 0.5 * udotc2 - uu);
            const dfloat common = w_l * (rhoNew + eqBase);
            dfloat feq = common;
            const dfloat HeF = common * ((cix_l - uxVal) * ffx_val +
                                        (ciy_l - uyVal) * ffy_val +
                                        (ciz_l - uzVal) * ffz_val) * invRhoNewCssq;
            feq -= 0.5 * HeF;
            const dfloat fneq = fVal[l] - feq;
            
            if (l == 1 || l == 2 || l == 7 || l == 8 ||
                l == 9 || l == 10 || l == 13 || l == 14 ||
                l == 15 || l == 16)
                sumXX += fneq;
            if (l == 3 || l == 4 || l == 7 || l == 8 ||
                l == 11 || l == 12 || l == 13 || l == 14 ||
                l == 17 || l == 18)
                sumYY += fneq;
            if (l == 5 || l == 6 || l == 9 || l == 10 ||
                l == 11 || l == 12 || l == 15 || l == 16 ||
                l == 17 || l == 18)
                sumZZ += fneq;
            if (l == 7 || l == 8)
                sumXY += fneq;
            if (l == 13 || l == 14)
                sumXY -= fneq;
            if (l == 9 || l == 10)
                sumXZ += fneq;
            if (l == 15 || l == 16)
                sumXZ -= fneq;
            if (l == 11 || l == 12)
                sumYZ += fneq;
            if (l == 17 || l == 18)
                sumYZ -= fneq;
        }
        
        pxx[idx] = sumXX;
        pyy[idx] = sumYY;
        pzz[idx] = sumZZ;
        pxy[idx] = sumXY;
        pxz[idx] = sumXZ;
        pyz[idx] = sumYZ;
    #endif

    ux[idx] = uxVal;
    uy[idx] = uyVal;
    uz[idx] = uzVal;
}

__global__ void collisionCalc(
    const dfloat * __restrict__ ux,
    const dfloat * __restrict__ uy,
    const dfloat * __restrict__ uz,
    const dfloat * __restrict__ normx,
    const dfloat * __restrict__ normy,
    const dfloat * __restrict__ normz,
    const dfloat * __restrict__ ffx,
    const dfloat * __restrict__ ffy,
    const dfloat * __restrict__ ffz,
    const dfloat * __restrict__ rho,
    const dfloat * __restrict__ phi,
    const dfloat * __restrict__ f,
    dfloat * __restrict__ g,
    const dfloat * __restrict__ pxx,
    const dfloat * __restrict__ pyy,
    const dfloat * __restrict__ pzz,
    const dfloat * __restrict__ pxy,
    const dfloat * __restrict__ pxz,
    const dfloat * __restrict__ pyz,
    int nx, int ny, int nz,
    dfloat * __restrict__ f_coll
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;
    if (i == 0 || i == nx - 1 || j == 0 || j == ny - 1 || k == 0 || k == nz - 1) return;

    int idx3D = IDX3D(i,j,k);
    int nxyz = nx * ny * nz;

    dfloat ux_val = ux[idx3D];
    dfloat uy_val = uy[idx3D];
    dfloat uz_val = uz[idx3D];
    dfloat rho_val = rho[idx3D];
    dfloat phi_val = phi[idx3D];
    dfloat ffx_val = ffx[idx3D];
    dfloat ffy_val = ffy[idx3D];
    dfloat ffz_val = ffz[idx3D];
    dfloat pxx_val = pxx[idx3D];
    dfloat pyy_val = pyy[idx3D];
    dfloat pzz_val = pzz[idx3D];
    dfloat pxy_val = pxy[idx3D];
    dfloat pxz_val = pxz[idx3D];
    dfloat pyz_val = pyz[idx3D];
    dfloat normx_val = normx[idx3D];
    dfloat normy_val = normy[idx3D];
    dfloat normz_val = normz[idx3D];

    dfloat uu = 0.5 * (ux_val * ux_val + uy_val * uy_val + uz_val * uz_val) / CSSQ;
    dfloat one_minus_omega = 1.0 - OMEGA;

    #pragma unroll
    for (int l = 0; l < FPOINTS; ++l) {
        int cix_l = CIX[l], ciy_l = CIY[l], ciz_l = CIZ[l];
        dfloat w_l = W[l];
        dfloat udotc = (ux_val * cix_l + uy_val * ciy_l + uz_val * ciz_l) / CSSQ;
        dfloat feq = w_l * (rho_val + rho_val * (udotc + 0.5 * udotc * udotc - uu));
        dfloat HeF = 0.5 * feq *
                        ((cix_l - ux_val) * ffx_val +
                         (ciy_l - uy_val) * ffy_val +
                         (ciz_l - uz_val) * ffz_val) / (rho_val * CSSQ);
        dfloat fneq = (cix_l * cix_l - CSSQ) * pxx_val +
                        (ciy_l * ciy_l - CSSQ) * pyy_val +
                        (ciz_l * ciz_l - CSSQ) * pzz_val +
                        2 * cix_l * ciy_l * pxy_val +
                        2 * cix_l * ciz_l * pxz_val +
                        2 * ciy_l * ciz_l * pyz_val;
        f_coll[idx3D + l * nxyz] = feq + one_minus_omega * (w_l / (2.0 * CSSQ * CSSQ)) * fneq + HeF;
    }
    
    #pragma unroll
    for (int l = 0; l < GPOINTS; ++l) {
        int cix_l = CIX[l], ciy_l = CIY[l], ciz_l = CIZ[l];
        dfloat w_g_l = W_G[l];
        dfloat udotc = (ux_val * cix_l + uy_val * ciy_l + uz_val * ciz_l) / CSSQ;
        dfloat feq = w_g_l * phi_val * (1 + udotc);
        dfloat Hi = SHARP_C * phi_val * (1 - phi_val) *
                        (cix_l * normx_val + ciy_l * normy_val + ciz_l * normz_val);
        g[idx3D + l * nxyz] = feq + w_g_l * Hi;
    }
}

__global__ void streamingCalcNew(
    const dfloat * __restrict__ f_coll,
    int nx, int ny, int nz,
    dfloat * __restrict__ f 
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    int NxNy = nx * ny;
    int NxNyNz = NxNy * nz;
    int dstBase = i + j * nx + k * NxNy;

    #pragma unroll
    for (int l = 0; l < FPOINTS; ++l) {
        int src_i = (i - CIX[l] + nx) % nx;
        int src_j = (j - CIY[l] + ny) % ny;
        int src_k = (k - CIZ[l] + nz) % nz;
        int srcBase = src_i + src_j * nx + src_k * NxNy;
        int dstIdx = l * NxNyNz + dstBase;
        int srcIdx = l * NxNyNz + srcBase;
        f[dstIdx] = f_coll[srcIdx];
    }
}

__global__ void streamingCalc(
    const dfloat * __restrict__ g_in,
    dfloat * __restrict__ g_out,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    int NxNy = nx * ny;
    int NxNyNz = NxNy * nz;
    int dstBase = i + j * nx + k * NxNy;

    #pragma unroll
    for (int l = 0; l < GPOINTS; ++l) {
        int src_i = (i - CIX[l] + nx) % nx;
        int src_j = (j - CIY[l] + ny) % ny;
        int src_k = (k - CIZ[l] + nz) % nz;
        int srcBase = src_i + src_j * nx + src_k * NxNy;
        int dstIdx = l * NxNyNz + dstBase;
        int srcIdx = l * NxNyNz + srcBase;
        g_out[dstIdx] = g_in[srcIdx];
    }
}

__global__ void fgBoundary(
    dfloat * __restrict__ f,
    dfloat * __restrict__ g,
    const dfloat * __restrict__ rho,
    const dfloat * __restrict__ phi,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z; 

    if (i >= nx || j >= ny || k >= nz) return;

    int idx = IDX3D(i,j,k);

    if (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) {
        #pragma unroll
        for (int l = 0; l < FPOINTS; ++l) {
            int nb_i = i + CIX[l];
            int nb_j = j + CIY[l];
            int nb_k = k + CIZ[l];
            if (nb_i >= 0 && nb_i < nx && nb_j >= 0 && nb_j < ny && nb_k >= 0 && nb_k < nz) {
                f[IDX4D(nb_i,nb_j,nb_k,l)] = rho[idx] * W[l];
            }
        }
        #pragma unroll
        for (int l = 0; l < GPOINTS; ++l) {
            int nb_i = i + CIX[l];
            int nb_j = j + CIY[l];
            int nb_k = k + CIZ[l];

            if (nb_i >= 0 && nb_i < nx && nb_j >= 0 && nb_j < ny && nb_k >= 0 && nb_k < nz) {
                g[IDX4D(nb_i,nb_j,nb_k,l)] = phi[idx] * W_G[l];
            }
        }
    }
}

__global__ void boundaryConditions(
    dfloat * __restrict__ phi, 
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    if (k == 0) phi[IDX3D(i,j,0)] = phi[IDX3D(i,j,1)];
    if (k == nz-1 && nz > 1) phi[IDX3D(i,j,nz-1)] = phi[IDX3D(i,j,nz-2)];

    if (j == 0) phi[IDX3D(i,0,k)] = phi[IDX3D(i,1,k)];
    if (j == ny-1 && ny > 1) phi[IDX3D(i,ny-1,k)] = phi[IDX3D(i,ny-2,k)];

    if (i == 0) phi[IDX3D(0,j,k)] = phi[IDX3D(1,j,k)];
    if (i == nx-1 && nx > 1) phi[IDX3D(nx-1,j,k)] = phi[IDX3D(nx-2,j,k)];
}
