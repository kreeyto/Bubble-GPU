#include "kernels.cuh"
#include "var.cuh"
#include <math.h>

#include "precision.cuh"

#define IDX3D(i,j,k) ((i) + (j) * nx + (k) * nx * ny)
#define IDX4D(i,j,k,l) ((i) + (j) * nx + (k) * nx * ny + (l) * nx * ny * nz)

// ============================================================================================== //

__global__ void initPhase(
    dfloat * __restrict__ phi, 
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;
    if (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    int idx3D = i + j * nx + k * nx * ny;

    dfloat bubble_radius = 20.0 * nx / 150.0;

    dfloat dx = i - nx * 0.5;
    dfloat dy = j - ny * 0.5;
    dfloat dz = k - nz * 0.5;
    dfloat Ri = sqrt((dx * dx) / 4.0 + dy * dy + dz * dz);

    dfloat phi_val = 0.5 + 0.5 * tanh(2.0 * (bubble_radius - Ri) / 3.0);

    phi[idx3D] = phi_val;
}

// =================================================================================================== //



// =================================================================================================== //

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

    int idx3D = i + j * nx + k * nx * ny;

    dfloat rho_val = rho[idx3D];
    dfloat phi_val = phi[idx3D];

    for (int l = 0; l < FPOINTS; ++l) {
        int idx4D = idx3D + l * nx * ny * nz;
        f[idx4D] = W[l] * rho_val;
    }

    for (int l = 0; l < GPOINTS; ++l) {
        int idx4D = idx3D + l * nx * ny * nz;
        g[idx4D] = W_G[l] * phi_val;
    }
}

// =================================================================================================== //



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

    int idx3D = i + j * nx + k * nx * ny;

    dfloat sum = 0.0;       
    for (int l = 0; l < GPOINTS; ++l) {
        int idx4D = idx3D + l * nx * ny * nz;
        sum += g[idx4D];
    }

    phi[idx3D] = sum;
}

// =================================================================================================== //



// =================================================================================================== //

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

    int idx3D = i + j * nx + k * nx * ny;

    dfloat grad_fix = 0.0, grad_fiy = 0.0, grad_fiz = 0.0;
    for (int l = 0; l < FPOINTS; ++l) {
        int ii = i + CIX[l];
        int jj = j + CIY[l];
        int kk = k + CIZ[l];
        int offset = ii + jj * nx + kk * nx * ny;
        dfloat val = phi[offset];
        dfloat coef = 3.0 * W[l];
        grad_fix += coef * CIX[l] * val;
        grad_fiy += coef * CIY[l] * val;
        grad_fiz += coef * CIZ[l] * val;
    }

    dfloat gmag_sq = grad_fix * grad_fix + grad_fiy * grad_fiy + grad_fiz * grad_fiz;
    dfloat gmag = sqrt(gmag_sq);

    mod_grad[idx3D] = gmag;
    dfloat factor = 1.0 / (gmag + 1e-9);  
    normx[idx3D] = grad_fix * factor;
    normy[idx3D] = grad_fiy * factor;
    normz[idx3D] = grad_fiz * factor;
    indicator[idx3D] = gmag;
}

// =================================================================================================== //



// =================================================================================================== //

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

    int idx3D = i + j * nx + k * nx * ny;

    dfloat normx_ = normx[idx3D];
    dfloat normy_ = normy[idx3D];
    dfloat normz_ = normz[idx3D];
    dfloat ind_ = indicator[idx3D];
    dfloat curv = 0.0;

    for (int l = 0; l < FPOINTS; ++l) {
        int ii = i + CIX[l];
        int jj = j + CIY[l];
        int kk = k + CIZ[l];
        int offset = ii + jj * nx + kk * nx * ny;
        dfloat normxN = normx[offset];
        dfloat normyN = normy[offset];
        dfloat normzN = normz[offset];
        dfloat coef = 3.0 * W[l];
        curv -= coef * (CIX[l] * normxN + CIY[l] * normyN + CIZ[l] * normzN);
    }

    dfloat mult = SIGMA * curv;

    curvature[idx3D] = curv;
    ffx[idx3D] = mult * normx_ * ind_;
    ffy[idx3D] = mult * normy_ * ind_;
    ffz[idx3D] = mult * normz_ * ind_;
}

// =================================================================================================== //



// =================================================================================================== //

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
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;
    
    if (i >= nx || j >= ny || k >= nz) return;
    if (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    int idx3D = i + j * nx + k * nx * ny;
    
    dfloat fneq[FPOINTS];
    dfloat fVal[FPOINTS];

    for (int l = 0; l < FPOINTS; ++l) {
        int idx4D = idx3D + l * nx * ny * nz;
        fVal[l] = f[idx4D];
    }
    
    dfloat rhoOld = rho[idx3D];
    dfloat ffx_val = ffx[idx3D];
    dfloat ffy_val = ffy[idx3D];
    dfloat ffz_val = ffz[idx3D];

    #ifdef FD3Q19
        dfloat sumUx = fVal[1] - fVal[2] + fVal[7] - fVal[8] +
                       fVal[9] - fVal[10] + fVal[13] - fVal[14] +
                       fVal[15] - fVal[16];
        dfloat sumUy = fVal[3] - fVal[4] + fVal[7] - fVal[8] +
                       fVal[11] - fVal[12] - fVal[13] + fVal[14] +
                       fVal[17] - fVal[18];
        dfloat sumUz = fVal[5] - fVal[6] + fVal[9] - fVal[10] +
                       fVal[11] - fVal[12] - fVal[15] + fVal[16] -
                       fVal[17] + fVal[18];
    #elif defined(FD3Q27)
        dfloat sumUx = fVal[1] - fVal[2] + fVal[7] - fVal[8] + fVal[9] - 
                       fVal[10] + fVal[13] - fVal[14] + fVal[15] - 
                       fVal[16] + fVal[19] - fVal[20] + fVal[21] - 
                       fVal[22] + fVal[23] - fVal[24] - fVal[25] + 
                       fVal[26];
        dfloat sumUy = fVal[3] - fVal[4] + fVal[7] - fVal[8] + fVal[11] - 
                       fVal[12] - fVal[13] + fVal[14] + fVal[17] - 
                       fVal[18] + fVal[19] - fVal[20] + fVal[21] - 
                       fVal[22] - fVal[23] + fVal[24] + fVal[25] - 
                       fVal[26];
        dfloat sumUz = fVal[5] - fVal[6] + fVal[9] - fVal[10] + fVal[11] - 
                       fVal[12] - fVal[15] + fVal[16] - fVal[17] + 
                       fVal[18] + fVal[19] - fVal[20] - fVal[21] + 
                       fVal[22] + fVal[23] - fVal[24] + fVal[25] - 
                       fVal[26];
    #endif

    dfloat invRhoOld = 1.0 / rhoOld;
    dfloat halfFx = ffx_val * 0.5 * invRhoOld;
    dfloat halfFy = ffy_val * 0.5 * invRhoOld;
    dfloat halfFz = ffz_val * 0.5 * invRhoOld;

    dfloat uxVal = sumUx * invRhoOld + halfFx;
    dfloat uyVal = sumUy * invRhoOld + halfFy;
    dfloat uzVal = sumUz * invRhoOld + halfFz;

    dfloat rhoNew = 0.0;
    for (int l = 0; l < FPOINTS; ++l)
        rhoNew += fVal[l];
    rho[idx3D] = rhoNew;

    dfloat invCssq = 1.0 / CSSQ;
    dfloat uu = 0.5 * (uxVal * uxVal + uyVal * uyVal + uzVal * uzVal) * invCssq;
    dfloat invRhoNewCssq = 1.0 / (rhoNew * CSSQ);

    dfloat sumXX = 0.0, sumYY = 0.0, sumZZ = 0.0;
    dfloat sumXY = 0.0, sumXZ = 0.0, sumYZ = 0.0;

    for (int l = 0; l < FPOINTS; ++l) {
        dfloat udotc = (uxVal * CIX[l] + uyVal * CIY[l] + uzVal * CIZ[l]) * invCssq;
        dfloat udotc2 = udotc * udotc;
        dfloat eqBase = rhoNew * (udotc + 0.5 * udotc2 - uu);
        dfloat common = W[l] * (rhoNew + eqBase);
        dfloat HeF = common * ((CIX[l] - uxVal) * ffx_val +
                               (CIY[l] - uyVal) * ffy_val +
                               (CIZ[l] - uzVal) * ffz_val) * invRhoNewCssq;
        dfloat feq = common - 0.5 * HeF; 
        fneq[l] = fVal[l] - feq;
    }

    #ifdef FD3Q19
        sumXX = fneq[1] + fneq[2] + fneq[7] + fneq[8] +
                fneq[9] + fneq[10] + fneq[13] + fneq[14] +
                fneq[15] + fneq[16];
        sumYY = fneq[3] + fneq[4] + fneq[7] + fneq[8] +
                fneq[11] + fneq[12] + fneq[13] + fneq[14] +
                fneq[17] + fneq[18];
        sumZZ = fneq[5] + fneq[6] + fneq[9] + fneq[10] +
                fneq[11] + fneq[12] + fneq[15] + fneq[16] +
                fneq[17] + fneq[18];
        sumXY = fneq[7] + fneq[8] - fneq[13] - fneq[14];
        sumXZ = fneq[9] + fneq[10] - fneq[15] - fneq[16];
        sumYZ = fneq[11] + fneq[12] - fneq[17] - fneq[18];
    #elif defined(FD3Q27)
        sumXX = fneq[1] + fneq[2] + fneq[7] + fneq[8] + fneq[9] + 
                fneq[10] + fneq[13] + fneq[14] + fneq[15] + fneq[16] + 
                fneq[19] + fneq[20] + fneq[21] + fneq[22] + fneq[23] + 
                fneq[24] + fneq[25] + fneq[26];
        sumYY = fneq[3] + fneq[4] + fneq[7] + fneq[8] + fneq[11] + 
                fneq[12] + fneq[13] + fneq[14] + fneq[17] + fneq[18] + 
                fneq[19] + fneq[20] + fneq[21] + fneq[22] + fneq[23] + 
                fneq[24] + fneq[25] + fneq[26];
        sumZZ = fneq[5] + fneq[6] + fneq[9] + fneq[10] + fneq[11] + 
                fneq[12] + fneq[13] + fneq[14] + fneq[17] + fneq[18] + 
                fneq[19] + fneq[20] + fneq[21] + fneq[22] + fneq[23] + 
                fneq[24] + fneq[25] + fneq[26];
        sumXY = fneq[7] + fneq[8] + fneq[19] + fneq[20] + fneq[21] + 
                fneq[22] - fneq[13] - fneq[14] - fneq[23] - fneq[24] - 
                fneq[25] - fneq[26];
        sumXZ = fneq[9] + fneq[10] + fneq[19] + fneq[20] + fneq[23] + 
                fneq[24] - fneq[15] - fneq[16] - fneq[21] - fneq[22] - 
                fneq[25] - fneq[26];
        sumYZ = fneq[11] + fneq[12] + fneq[19] + fneq[20] + fneq[25] + 
                fneq[26] - fneq[17] - fneq[18] - fneq[21] - fneq[22] - 
                fneq[23] - fneq[24];
    #endif

    pxx[idx3D] = sumXX;
    pyy[idx3D] = sumYY;
    pzz[idx3D] = sumZZ;
    pxy[idx3D] = sumXY;
    pxz[idx3D] = sumXZ;
    pyz[idx3D] = sumYZ;

    ux[idx3D] = uxVal;
    uy[idx3D] = uyVal;
    uz[idx3D] = uzVal;
}

// =================================================================================================== //



// =================================================================================================== //

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
    if (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    int idx3D = i + j * nx + k * nx * ny;
    int nxyz  = nx * ny * nz;

    dfloat ux_val = ux[idx3D], uy_val = uy[idx3D], uz_val = uz[idx3D];
    dfloat rho_val = rho[idx3D], phi_val = phi[idx3D];
    dfloat ffx_val = ffx[idx3D], ffy_val = ffy[idx3D], ffz_val = ffz[idx3D];
    dfloat pxx_val = pxx[idx3D], pyy_val = pyy[idx3D], pzz_val = pzz[idx3D];
    dfloat pxy_val = pxy[idx3D], pxz_val = pxz[idx3D], pyz_val = pyz[idx3D];
    dfloat normx_val = normx[idx3D], normy_val = normy[idx3D], normz_val = normz[idx3D];

    dfloat u_sq = ux_val*ux_val + uy_val*uy_val + uz_val*uz_val;
    dfloat uu = 0.5 * u_sq / CSSQ;
    dfloat inv_rho_CSSQ = 1.0 / (rho_val * CSSQ);
    dfloat omc = 1.0 - OMEGA;
    dfloat invCSSQ = 1.0 / CSSQ;

    for (int l = 0; l < FPOINTS; ++l) {
        dfloat udotc = (ux_val * CIX[l] + uy_val * CIY[l] + uz_val * CIZ[l]) * invCSSQ;
        dfloat udotc2 = udotc * udotc;
        dfloat feq = W[l] * (rho_val + rho_val * (udotc + 0.5 * udotc2 - uu));
        dfloat HeF = 0.5 * feq * ( (CIX[l] - ux_val) * ffx_val +
                                   (CIY[l] - uy_val) * ffy_val +
                                   (CIZ[l] - uz_val) * ffz_val ) * inv_rho_CSSQ;
        dfloat fneq = (W[l] / (2.0 * CSSQ * CSSQ)) * ((CIX[l]*CIX[l] - CSSQ) * pxx_val +
                                                      (CIY[l]*CIY[l] - CSSQ) * pyy_val +
                                                      (CIZ[l]*CIZ[l] - CSSQ) * pzz_val +
                                                       2.0 * CIX[l] * CIY[l] * pxy_val +
                                                       2.0 * CIX[l] * CIZ[l] * pxz_val +
                                                       2.0 * CIY[l] * CIZ[l] * pyz_val
                                                     );
        f_coll[idx3D + l * nxyz] = feq + omc * fneq + HeF; 
    }

    for (int l = 0; l < GPOINTS; ++l) {
        dfloat udotc = (ux_val * CIX[l] + uy_val * CIY[l] + uz_val * CIZ[l]) * invCSSQ;
        dfloat geq = W_G[l] * phi_val * (1.0 + udotc);
        dfloat Hi = W_G[l] * SHARP_C * phi_val * (1.0 - phi_val) *
                    (CIX[l] * normx_val + CIY[l] * normy_val + CIZ[l] * normz_val);
        g[idx3D + l * nxyz] = geq + Hi;
    }
}

__global__ void streamingColl(
    dfloat * __restrict__ f,
    const dfloat * __restrict__ f_coll,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;
    if (i == 0 || i == nx-1 || j == 0 || j == ny-1 || k == 0 || k == nz-1) return;

    int NxNy = nx * ny;
    int NxNyNz = NxNy * nz;
    int srcBase = i + j * nx + k * NxNy;

    for (int l = 0; l < FPOINTS; ++l) {
        int dst_i = i + CIX[l]; 
        int dst_j = j + CIY[l];
        int dst_k = k + CIZ[l];
        if (dst_i >= 0 && dst_i < nx && dst_j >= 0 && dst_j < ny && dst_k >= 0 && dst_k < nz) {
            int dstBase = dst_i + dst_j * nx + dst_k * NxNy;
            int srcIdx = l * NxNyNz + srcBase;
            int dstIdx = l * NxNyNz + dstBase;
            f[dstIdx] = f_coll[srcIdx];  
        }
    }
}

// =================================================================================================== //



// =================================================================================================== //

__global__ void streamingCalc(
    const dfloat * __restrict__ g,
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

    for (int l = 0; l < GPOINTS; ++l) {
        int src_i = (i - CIX[l] + nx) & (nx-1);
        int src_j = (j - CIY[l] + ny) & (ny-1);
        int src_k = (k - CIZ[l] + nz) & (nz-1);
        int srcBase = src_i + src_j * nx + src_k * NxNy;
        int dstIdx = l * NxNyNz + dstBase;
        int srcIdx = l * NxNyNz + srcBase;
        g_out[dstIdx] = g[srcIdx];
    }
}

// =================================================================================================== //



// =================================================================================================== //

__global__ void fgBoundary_f(
    dfloat * __restrict__ f,
    const dfloat * __restrict__ rho,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    if (i == 0 || i == nx - 1 || j == 0 || j == ny - 1 || k == 0 || k == nz - 1) {
        for (int l = 0; l < FPOINTS; ++l) {
            int ni = i + CIX[l];
            int nj = j + CIY[l];
            int nk = k + CIZ[l];
            if (ni >= 0 && ni < nx && nj >= 0 && nj < ny && nk >= 0 && nk < nz) {
                f[IDX4D(ni,nj,nk,l)] = rho[IDX3D(i,j,k)] * W[l];
            }
        }
    }
}

__global__ void fgBoundary_g(
    dfloat * __restrict__ g,
    const dfloat * __restrict__ phi,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    int k = blockIdx.z * blockDim.z + threadIdx.z;

    if (i >= nx || j >= ny || k >= nz) return;

    if (i == 0 || i == nx - 1 || j == 0 || j == ny - 1 || k == 0 || k == nz - 1) {
        for (int l = 0; l < GPOINTS; ++l) {
            int ni = i + CIX[l];
            int nj = j + CIY[l];
            int nk = k + CIZ[l];
            if (ni >= 0 && ni < nx && nj >= 0 && nj < ny && nk >= 0 && nk < nz) {
                g[IDX4D(ni,nj,nk,l)] = phi[IDX3D(i,j,k)] * W_G[l];
            }
        }
    }
}

__global__ void boundaryConditionsZ(
    dfloat * __restrict__ phi,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;
    if(i < nx && j < ny) {
         phi[IDX3D(i,j,0)] = phi[IDX3D(i,j,1)];
         phi[IDX3D(i,j,nz-1)] = phi[IDX3D(i,j,nz-2)];
    }
}

__global__ void boundaryConditionsY(
    dfloat * __restrict__ phi,
    int nx, int ny, int nz
) {
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int k = blockIdx.y * blockDim.y + threadIdx.y;
    if(i < nx && k < nz) {
         phi[IDX3D(i,0,k)] = phi[IDX3D(i,1,k)];
         phi[IDX3D(i,ny-1,k)] = phi[IDX3D(i,ny-2,k)];
    }
}

__global__ void boundaryConditionsX(
    dfloat * __restrict__ phi,
    int nx, int ny, int nz
) {
    int j = blockIdx.x * blockDim.x + threadIdx.x;
    int k = blockIdx.y * blockDim.y + threadIdx.y;
    if(j < ny && k < nz) {
         phi[IDX3D(0,j,k)] = phi[IDX3D(1,j,k)];
         phi[IDX3D(nx-1,j,k)] = phi[IDX3D(nx-2,j,k)];
    }
}


// =================================================================================================== //
